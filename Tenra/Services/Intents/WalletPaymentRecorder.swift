//
//  WalletPaymentRecorder.swift
//  Tenra
//
//  Records an Apple Pay payment from LogWalletPaymentIntent, or an expense or an income
//  from a bank's notification (LogBankNotificationIntent), without a single question
//  (docs/plan-auto-capture.md §4):
//
//  1. no amount (a transit gate, a payload the trigger lost) → nothing to record;
//  2. the same payment within 90 seconds → the terminal fired twice; the same expense
//     from the other source (Apple Pay, the bank's notification) within 5 minutes;
//  3. account and category through WalletPaymentResolver, guesses noted;
//  4. a subscription's charge the series recorded ahead → the planned charge takes the real
//     amount, date and account, nothing new (SubscriptionChargeMatcher; a same-amount charge
//     with no shared word is only a suggestion in To review);
//  5. another currency: the cached rate (refreshed first when stale), else one network
//     request (the only one an intent makes, owner's decision 2026-10-19), else the
//     payment waits in WalletCaptureStore.pending for a rate; a payment drained from the
//     queue on a later day takes its own day's rate;
//  6. saved through TransactionDraftService.commit, journaled in WalletCaptureStore; a bank
//     notification's transfer that is half of a transfer between the person's own banks is
//     paired with the other half (OwnTransferPairing) and merged into one transfer.
//
//  Runs in whatever process the intent got: a cold one has only the fast path
//  loaded, so the merchant's history comes from a bounded CoreData fetch, never
//  from the store's array.
//

import Foundation
import CoreData

@MainActor
enum WalletPaymentRecorder {

    enum Outcome: Equatable {
        case saved(amount: Double, currency: String, categoryName: String)
        case noAmount
        case duplicate
        /// The charge of a subscription whose series recorded it ahead: merged into it.
        case subscription(name: String)
        /// Waits in WalletCaptureStore.pending for an exchange rate.
        case queued
        case noAccount
    }

    /// Payments the history fetch reads for one merchant. The newest are enough for
    /// "which category did this merchant get", and the bound keeps the fetch cheap.
    private static let historyLimit = 200

    /// Guards against two drains in one process (an intent and the app coming to
    /// the front) running at once.
    private static var isDraining = false

    /// Payments being saved right now. The intent and a drain both run on the main actor
    /// and interleave at every await: a drain skips these, they wait in `pending` meanwhile.
    private static var inFlight: Set<String> = []

    /// Records one payment from the automation. The payment goes into the queue before the
    /// first await and leaves it only once saved: a second run of the same tap then sees it
    /// as a duplicate, and a run the system ends mid-save (a slow rate request) leaves it
    /// queued, never lost.
    static func record(
        _ payment: WalletPayment,
        services: IntentServices,
        captures: WalletCaptureStore = .shared
    ) async throws -> Outcome {
        guard payment.amount.isFinite, payment.amount > 0 else { return .noAmount }
        if captures.isDuplicate(payment) { return .duplicate }

        inFlight.insert(payment.id)
        captures.enqueue(payment)
        defer { inFlight.remove(payment.id) }

        // A thrown save stays queued: the next drain tries it again.
        let outcome = try await save(payment, services: services, captures: captures)
        if outcome != .queued {
            captures.removePending(id: payment.id)
        }
        return outcome
    }

    /// Records the payments that waited for an exchange rate, oldest first, each with
    /// its own date. Called before every new payment and when the app comes to the front.
    /// A payment leaves the queue only once saved.
    static func recordPending(services: IntentServices, captures: WalletCaptureStore = .shared) async {
        guard !isDraining, !captures.pending.isEmpty else { return }
        isDraining = true
        defer { isDraining = false }

        for payment in captures.pending where !inFlight.contains(payment.id) {
            // Saved by a run that ended before it took the payment off the queue.
            if captures.isRecorded(paymentId: payment.id) {
                captures.removePending(id: payment.id)
                continue
            }
            inFlight.insert(payment.id)
            let outcome = try? await save(payment, services: services, captures: captures)
            inFlight.remove(payment.id)
            if let outcome, outcome != .queued {
                captures.removePending(id: payment.id)
            }
        }
    }

    // MARK: - Saving

    private static func save(
        _ payment: WalletPayment,
        services: IntentServices,
        captures: WalletCaptureStore
    ) async throws -> Outcome {
        let accounts = services.accounts.accounts
        let categories = services.categories.customCategories
        let context = CoreDataStack.shared.viewContext
        let memory = MerchantCategoryMemory.shared
        let type: TransactionType = payment.isExpense ? .expense : .income

        // Category first: the account ranking is keyed on it. The merchant memory holds
        // expense categories: an income's comes from the sender's history.
        let remembered = payment.isExpense ? memory.category(forMerchant: payment.merchant, in: categories) : nil
        let category = WalletPaymentResolver.category(
            remembered: remembered,
            rememberedSubcategoryIds: remembered == nil ? nil : memory.subcategoryIds(forMerchant: payment.merchant),
            suggestion: remembered == nil
                ? suggestedCategory(for: payment.merchant, type: type, categories: categories, services: services, context: context)
                : nil,
            categories: categories,
            type: type
        )

        guard let account = WalletPaymentResolver.account(
            fixedId: payment.accountId,
            cardAccountId: CardAccountMemory.shared.accountId(forCard: payment.card),
            accounts: accounts,
            suggested: {
                IntentAccountSuggester.suggestedAccountId(
                    forCategory: category.name,
                    accounts: accounts,
                    amount: payment.amount,
                    context: context
                )
            }
        ) else { return .noAccount }

        // A subscription's charge: its series recorded it ahead (SubscriptionChargeMatcher). Only
        // a planned charge no earlier payment was taken for: a second payment at the same gym
        // that week (a friend's pass) is a payment of its own.
        let currency = payment.currencyCode
            ?? accounts.first { $0.id == account.accountId }?.currency
            ?? ""
        var subscription: SubscriptionChargeMatcher.Match?
        if payment.isExpense,
           let day = ImportDuplicateDetector.dayNumber(DateFormatters.dateFormatter.string(from: payment.date)) {
            let memory = SubscriptionMerchantMemory.shared
            subscription = SubscriptionChargeMatcher.match(
                SubscriptionChargeMatcher.Charge(amount: payment.amount, currency: currency, day: day, merchant: payment.merchant),
                occurrences: subscriptionOccurrences(around: payment.date, context: context).filter {
                    $0.recurringOccurrenceId != nil && !captures.isMatched(occurrenceId: $0.id)
                },
                rememberedSeriesId: memory.seriesId(forMerchant: payment.merchant),
                dismissedSeriesIds: memory.dismissedSeriesIds(forMerchant: payment.merchant),
                suggests: payment.isTransferLike != true,
                accountId: account.isGuess ? nil : account.accountId,
                accountCurrency: { id in accounts.first { $0.id == id }?.currency },
                convert: { amount, from, to in CurrencyConverter.convertSync(amount: amount, from: from, to: to) }
            )
        }
        let planned = subscription?.isConfident == true ? subscription?.occurrence : nil
        // The charge goes where the money left. When the card's account is only a guess, the
        // subscription's own account is the better one.
        var accountId = account.accountId
        if account.isGuess, let plannedAccount = planned?.accountId,
           accounts.contains(where: { $0.id == plannedAccount && !$0.isLoan }) {
            accountId = plannedAccount
        }

        let operation = ParsedOperation(
            type: type,
            amount: Decimal(payment.amount),
            currencyCode: payment.currencyCode,
            date: payment.date,
            accountId: accountId,
            categoryName: category.name,
            subcategoryNames: [],
            note: payment.merchant
        )
        func draft(_ conversion: ConversionPolicy) -> Result<TransactionDraft, DraftIssue> {
            TransactionDraftService.makeDraft(
                from: operation,
                accounts: accounts,
                categories: categories,
                learned: .shared,
                conversion: conversion,
                note: payment.merchant
            )
        }
        // Today's payment takes the cached rate, refreshed first when it is stale (the stale
        // one stays if that fails). A payment of another day (it waited in the queue, drained
        // in the app) takes that day's rate. One request at most in the intent.
        let isToday = Calendar.current.isDateInToday(payment.date)
        let accountCurrency = accounts.first { $0.id == accountId }?.currency
        var askedNetwork = false
        if isToday, !CurrencyRateStore.shared.hasFreshRates,
           let from = payment.currencyCode, let to = accountCurrency, from != to {
            askedNetwork = true
            _ = await CurrencyConverter.getExchangeRate(for: from)
            _ = await CurrencyConverter.getExchangeRate(for: to)
        }
        var result = draft(.cachedOnly)
        if !isToday, case .success(let resolved) = result, resolved.convertedAmount != nil,
           let to = accountCurrency,
           let converted = await CurrencyConverter.convert(
               amount: resolved.amount, from: resolved.currency, to: to, on: payment.date
           ) {
            result = draft(.provided(converted))
        }
        if case .failure(.needsFXConversion(let amount, let from, let to)) = result {
            var converted: Double?
            if !askedNetwork {
                converted = await CurrencyConverter.convert(amount: amount, from: from, to: to, on: isToday ? nil : payment.date)
            }
            result = draft(.provided(converted))
        }

        var transactionDraft: TransactionDraft
        switch result {
        case .failure(.needsFXConversion): return .queued
        case .failure(.noEligibleAccount): return .noAccount
        case .failure(.missingAmount): return .noAmount
        case .success(let resolved): transactionDraft = resolved
        }

        if let planned {
            return await mergeIntoPlanned(planned, draft: transactionDraft, payment: payment, services: services, captures: captures)
        }

        // Only remembered subcategories still linked to the category apply. Read from
        // CoreData: a cold intent process has none in memory.
        if let ids = category.subcategoryIds, !ids.isEmpty, let categoryId = remembered?.id {
            let current = Set(
                IntentSubcategoryStore
                    .subcategories(ofCategoryIds: [categoryId], context: context)
                    .map(\.id)
            )
            transactionDraft.subcategoryIds = ids.filter { current.contains($0) }
        }

        // A guessed account must not teach VoiceLearningStore: two such saves would make
        // the guess outrank the history ranking for every later voice entry.
        var hooks = CommitHooks.production
        if account.isGuess {
            hooks.recordLearning = { _, _ in }
        }
        let saved = try await TransactionDraftService.commit(
            transactionDraft,
            store: services.store,
            categoriesViewModel: services.categories,
            hooks: hooks
        )
        IntentUsageCounters.shared.record(.intentAdd)

        var guesses: Set<WalletCaptureStore.Guess> = []
        if category.isGuess { guesses.insert(.category) }
        if account.isGuess { guesses.insert(.account) }
        // One "check a payment" notification per merchant until the user looks at it. A
        // payment deleted meanwhile no longer waits (the store's index, once it is loaded).
        let merchantKey = CategorySuggestionService.normalizedMerchant(payment.merchant)
        let store = services.store
        let merchantAlreadyWaiting = captures.toReview.contains {
            CategorySuggestionService.normalizedMerchant($0.payment.merchant) == merchantKey
                && (!store.hasCompletedInitialLoad || store.transactionById[$0.id] != nil)
        }
        let suggestion = subscription.flatMap { $0.isConfident ? nil : $0.occurrence }
        captures.record(
            transactionId: saved.id,
            payment: payment,
            guesses: guesses,
            accountId: saved.accountId ?? accountId,
            subscriptionSuggestion: suggestion?.recurringSeriesId
        )

        // Half of a transfer between the person's own banks: the other bank's side may be here.
        let pair = pairWithOtherBank(saved: saved, payment: payment, accountId: saved.accountId ?? accountId, captures: captures)
        if let pair {
            let otherId = pair.outgoingId == saved.id ? pair.incomingId : pair.outgoingId
            let accountGuessed = guesses.contains(.account)
                || captures.capture(forTransactionId: otherId).map { !$0.isReviewed && $0.guesses.contains(.account) } == true
            if !pair.isConfident || accountGuessed {
                await WalletReviewNotifier.notifyOwnTransfer(
                    transactionId: saved.id,
                    from: pair.outgoingId == saved.id ? payment.bankApp ?? "" : otherBankApp(of: pair, besides: saved.id, captures: captures),
                    to: pair.incomingId == saved.id ? payment.bankApp ?? "" : otherBankApp(of: pair, besides: saved.id, captures: captures)
                )
            }
            WalletReviewNotifier.removeDelivered(transactionId: otherId)
            await OwnTransferMerger.mergePending(store: services.store, captures: captures)
        } else if (!guesses.isEmpty || suggestion != nil), !merchantAlreadyWaiting {
            await WalletReviewNotifier.notify(
                transactionId: saved.id,
                payment: payment,
                guesses: guesses,
                categoryName: saved.category,
                accountName: accounts.first { $0.id == accountId }?.name ?? "",
                subscriptionName: suggestion?.description
            )
        }

        // An account fixed in the automation is the user's choice for this card.
        if let fixed = payment.accountId, fixed == account.accountId {
            CardAccountMemory.shared.remember(accountId: fixed, forCard: payment.card)
        }

        return .saved(amount: saved.amount, currency: saved.currency, categoryName: saved.category)
    }

    // MARK: - Subscription charges and own transfers

    /// The real charge of a subscription: the planned charge takes its amount, currency,
    /// conversion, date and account, now when the history is loaded, else once it is
    /// (SubscriptionChargeLinker.applyPending). A reviewed capture under the planned charge's id
    /// makes the other source's report of the same payment (Apple Pay and the bank) a duplicate.
    private static func mergeIntoPlanned(
        _ planned: Transaction,
        draft: TransactionDraft,
        payment: WalletPayment,
        services: IntentServices,
        captures: WalletCaptureStore
    ) async -> Outcome {
        captures.noteMatched(occurrenceId: planned.id)
        let accountCurrency = services.accounts.accounts.first { $0.id == draft.accountId }?.currency
        captures.enqueueChargeMerge(WalletCaptureStore.ChargeMerge(
            occurrenceId: planned.id,
            amount: draft.amount,
            currency: draft.currency,
            convertedAmount: draft.convertedAmount,
            targetCurrency: draft.convertedAmount == nil ? nil : accountCurrency,
            targetAmount: draft.convertedAmount,
            accountId: draft.accountId,
            date: DateFormatters.dateFormatter.string(from: draft.date),
            categoryName: draft.categoryName,
            note: draft.note
        ))
        captures.insert(WalletCaptureStore.Capture(
            id: planned.id,
            payment: payment,
            guesses: [],
            isReviewed: true,
            accountId: draft.accountId
        ))
        await SubscriptionChargeLinker.applyPending(store: services.store, captures: captures)
        return .subscription(name: planned.description)
    }

    /// The pair a bank notification's transfer or top-up makes with the other bank's side,
    /// recorded earlier (OwnTransferPairing), queued for OwnTransferMerger.
    private static func pairWithOtherBank(
        saved: Transaction,
        payment: WalletPayment,
        accountId: String,
        captures: WalletCaptureStore
    ) -> OwnTransferPairing.Pair? {
        guard payment.bankApp != nil, payment.isTransferLike == true else { return nil }
        let side = OwnTransferPairing.Side(transactionId: saved.id, payment: payment, accountId: accountId)
        guard let pair = OwnTransferPairing.pair(
            for: side,
            among: captures.unpairedBankSides(around: payment.date),
            ownNames: captures.ownNames
        ) else { return nil }
        captures.addOwnTransferPair(pair)
        return pair
    }

    private static func otherBankApp(of pair: OwnTransferPairing.Pair, besides id: String, captures: WalletCaptureStore) -> String {
        let other = pair.outgoingId == id ? pair.incomingId : pair.outgoingId
        return captures.capture(forTransactionId: other)?.payment.bankApp ?? ""
    }

    // MARK: - Review

    /// The user looked at a captured payment and kept or fixed it, so what it is saved
    /// with now is their choice: the category and subcategories for its merchant, the
    /// account for its card. A transaction the Wallet action did not record is left alone.
    ///
    /// From To review ("Correct", "All correct", `editedFrom` nil) everything shown is
    /// confirmed. From the edit screen (`editedFrom` the transaction as it was) only what
    /// the user changed, plus a category Tenra guessed that they had not reviewed yet: a
    /// later edit of an old payment (its note) must not undo what they set since for the
    /// merchant or the card, and a guessed account kept as it was stays a guess.
    static func confirm(
        _ transaction: Transaction,
        subcategoryIds: [String],
        categories: [CustomCategory],
        editedFrom previous: Transaction? = nil,
        previousSubcategoryIds: Set<String>? = nil,
        captures: WalletCaptureStore = .shared,
        merchants: MerchantCategoryMemory = .shared,
        cards: CardAccountMemory = .shared
    ) {
        guard let capture = captures.capture(forTransactionId: transaction.id) else { return }
        let isEdit = previous != nil
        let categoryChanged = previous.map { $0.category != transaction.category } ?? false
        let subcategoriesChanged = previousSubcategoryIds.map { $0 != Set(subcategoryIds) } ?? false
        let accountChanged = previous.map { $0.accountId != transaction.accountId } ?? false
        let unreviewedCategoryGuess = !capture.isReviewed && capture.guesses.contains(.category)
        let teachesCategory = !isEdit || categoryChanged || subcategoriesChanged || unreviewedCategoryGuess
        let teachesAccount = !isEdit || accountChanged

        if teachesCategory, transaction.type == .expense,
           let categoryId = categories
               .first(where: { $0.type == .expense && $0.name == transaction.category })?.id {
            merchants.remember(
                categoryId: categoryId,
                subcategoryIds: subcategoryIds,
                forMerchant: capture.payment.merchant
            )
        }
        if teachesAccount, let accountId = transaction.accountId {
            cards.remember(accountId: accountId, forCard: capture.payment.card)
        }
        // A transfer merged from two banks' notifications: the receiving card's account, and the
        // names on both sides are the person's own (OwnTransferPairing).
        if let record = capture.ownTransfer {
            if teachesAccount, let targetId = transaction.targetAccountId {
                cards.remember(accountId: targetId, forCard: record.incoming.card)
            }
            if !capture.isReviewed {
                captures.rememberOwnNames([capture.payment.merchant, record.incoming.merchant])
            }
            record.originals.forEach { WalletReviewNotifier.removeDelivered(transactionId: $0.id) }
        }
        captures.markReviewed(transactionId: transaction.id)
        WalletReviewNotifier.removeDelivered(transactionId: transaction.id)
    }

    // MARK: - Category suggestion

    /// History, brand and keyword tiers for a merchant the user has not chosen a
    /// category for (CategorySuggestionProvider), resolved to one of their categories.
    private static func suggestedCategory(
        for merchant: String,
        type: TransactionType,
        categories: [CustomCategory],
        services: IntentServices,
        context: NSManagedObjectContext
    ) -> String? {
        guard MerchantCategoryMemory.key(forMerchant: merchant) != nil else { return nil }
        let index = CategorySuggestionService.buildHistoryIndex(from: history(of: merchant, type: type, context: context))
        let parser = services.makeParser()
        return CategorySuggestionProvider.suggestion(
            for: merchant,
            type: type,
            index: index,
            categories: categories,
            keywordMatcher: { parser.keywordCategory(in: $0) }
        )
    }

    /// Expenses of recurring series dated around a payment: a handful of rows, whatever
    /// the size of the history.
    static func subscriptionOccurrences(around date: Date, context: NSManagedObjectContext) -> [Transaction] {
        let window = TimeInterval(ImportDuplicateDetector.subscriptionDayWindow + 1) * 86_400
        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "recurringSeriesId != nil AND type == %@ AND date >= %@ AND date <= %@",
            TransactionType.expense.rawValue,
            date.addingTimeInterval(-window) as NSDate,
            date.addingTimeInterval(window) as NSDate
        )
        return ((try? context.fetch(request)) ?? []).map { $0.toTransaction() }
    }

    /// Recent expenses (or incomes) whose description contains the merchant's first word. Broad on
    /// purpose ("MAGNUM CASH&CARRY 123" and "... 456" share it): the history index then
    /// compares normalized merchants exactly. The word of its clean name (MerchantName), so
    /// a legal form in front ("ИП", "ТОО") is not the word searched.
    static func history(
        of merchant: String,
        type: TransactionType = .expense,
        context: NSManagedObjectContext
    ) -> [Transaction] {
        guard let firstWord = CategorySuggestionService.normalizedMerchant(MerchantName.displayName(merchant))
            .split(separator: " ")
            .first,
            firstWord.count >= CategorySuggestionService.minimumMerchantLength else { return [] }

        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "type == %@ AND descriptionText CONTAINS[cd] %@",
            type.rawValue,
            String(firstWord)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = historyLimit
        return ((try? context.fetch(request)) ?? []).map { $0.toTransaction() }
    }
}
