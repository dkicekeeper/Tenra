//
//  WalletPaymentRecorder.swift
//  Tenra
//
//  Records an Apple Pay payment from LogWalletPaymentIntent without a single
//  question (docs/plan-auto-capture.md §4):
//
//  1. no amount (a transit gate, a payload the trigger lost) → nothing to record;
//  2. the same payment within 90 seconds → the terminal fired twice;
//  3. account and category through WalletPaymentResolver, guesses noted;
//  4. another currency: the cached rate, else one network request (the only one an
//     intent makes, owner's decision 2026-10-19), else the payment waits in
//     WalletCaptureStore.pending for a rate;
//  5. saved through TransactionDraftService.commit, journaled in WalletCaptureStore.
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
        /// Waits in WalletCaptureStore.pending for an exchange rate.
        case queued
        case noAccount
    }

    /// Payments the history fetch reads for one merchant. The newest are enough for
    /// "which category did this merchant get", and the bound keeps the fetch cheap.
    private static let historyLimit = 200

    /// Guards against two drains in one process (an intent and the app coming to
    /// the front) recording the same queued payment twice.
    private static var isDraining = false

    /// Records one payment from the automation. A payment that cannot be converted
    /// yet is queued, not lost.
    static func record(
        _ payment: WalletPayment,
        services: IntentServices,
        captures: WalletCaptureStore = .shared
    ) async throws -> Outcome {
        guard payment.amount.isFinite, payment.amount > 0 else { return .noAmount }
        if captures.isDuplicate(payment) { return .duplicate }

        let outcome = try await save(payment, services: services, captures: captures)
        if outcome == .queued {
            captures.enqueue(payment)
        }
        return outcome
    }

    /// Records the payments that waited for an exchange rate, oldest first, each with
    /// its own date. Called before every new payment and when the app comes to the front.
    static func recordPending(services: IntentServices, captures: WalletCaptureStore = .shared) async {
        guard !isDraining, !captures.pending.isEmpty else { return }
        isDraining = true
        defer { isDraining = false }

        for payment in captures.pending {
            // Taken off the queue first, so nothing else records it meanwhile.
            captures.removePending(id: payment.id)
            let outcome = try? await save(payment, services: services, captures: captures)
            if outcome == nil || outcome == .queued {
                captures.enqueue(payment)
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

        // Category first: the account ranking is keyed on it.
        let remembered = memory.category(forMerchant: payment.merchant, in: categories)
        let category = WalletPaymentResolver.category(
            remembered: remembered,
            rememberedSubcategoryIds: remembered == nil ? nil : memory.subcategoryIds(forMerchant: payment.merchant),
            suggestion: remembered == nil
                ? suggestedCategory(for: payment.merchant, categories: categories, services: services, context: context)
                : nil,
            categories: categories
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

        let operation = ParsedOperation(
            type: .expense,
            amount: Decimal(payment.amount),
            currencyCode: payment.currencyCode,
            date: payment.date,
            accountId: account.accountId,
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
        var result = draft(.cachedOnly)
        if case .failure(.needsFXConversion(let amount, let from, let to)) = result {
            result = draft(.provided(await CurrencyConverter.convert(amount: amount, from: from, to: to)))
        }

        var transactionDraft: TransactionDraft
        switch result {
        case .failure(.needsFXConversion): return .queued
        case .failure(.noEligibleAccount): return .noAccount
        case .failure(.missingAmount): return .noAmount
        case .success(let resolved): transactionDraft = resolved
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
        // One "check a payment" notification per merchant until the user looks at it.
        let merchantKey = CategorySuggestionService.normalizedMerchant(payment.merchant)
        let merchantAlreadyWaiting = captures.toReview.contains {
            CategorySuggestionService.normalizedMerchant($0.payment.merchant) == merchantKey
        }
        captures.record(transactionId: saved.id, payment: payment, guesses: guesses)
        if !guesses.isEmpty, !merchantAlreadyWaiting {
            await WalletReviewNotifier.notify(
                transactionId: saved.id,
                payment: payment,
                guesses: guesses,
                categoryName: saved.category,
                accountName: accounts.first { $0.id == account.accountId }?.name ?? ""
            )
        }

        // An account fixed in the automation is the user's choice for this card.
        if let fixed = payment.accountId, fixed == account.accountId {
            CardAccountMemory.shared.remember(accountId: fixed, forCard: payment.card)
        }

        return .saved(amount: saved.amount, currency: saved.currency, categoryName: saved.category)
    }

    // MARK: - Review

    /// The user looked at a captured payment and kept or fixed it, so what it is saved
    /// with now is their choice: the category and subcategories for its merchant, the
    /// account for its card. Called by the edit screen and the To review list. A
    /// transaction the Wallet action did not record is left alone.
    static func confirm(
        _ transaction: Transaction,
        subcategoryIds: [String],
        categories: [CustomCategory],
        captures: WalletCaptureStore = .shared,
        merchants: MerchantCategoryMemory = .shared,
        cards: CardAccountMemory = .shared
    ) {
        guard let capture = captures.capture(forTransactionId: transaction.id) else { return }
        if transaction.type == .expense,
           let categoryId = categories
               .first(where: { $0.type == .expense && $0.name == transaction.category })?.id {
            merchants.remember(
                categoryId: categoryId,
                subcategoryIds: subcategoryIds,
                forMerchant: capture.payment.merchant
            )
        }
        if let accountId = transaction.accountId {
            cards.remember(accountId: accountId, forCard: capture.payment.card)
        }
        captures.markReviewed(transactionId: transaction.id)
    }

    // MARK: - Category suggestion

    /// History, brand and keyword tiers for a merchant the user has not chosen a
    /// category for (CategorySuggestionProvider), resolved to one of their categories.
    private static func suggestedCategory(
        for merchant: String,
        categories: [CustomCategory],
        services: IntentServices,
        context: NSManagedObjectContext
    ) -> String? {
        guard MerchantCategoryMemory.key(forMerchant: merchant) != nil else { return nil }
        let index = CategorySuggestionService.buildHistoryIndex(from: history(of: merchant, context: context))
        let parser = services.makeParser()
        return CategorySuggestionProvider.suggestion(
            for: merchant,
            type: .expense,
            index: index,
            categories: categories,
            keywordMatcher: { parser.keywordCategory(in: $0) }
        )
    }

    /// Recent expenses whose description contains the merchant's first word. Broad on
    /// purpose ("MAGNUM CASH&CARRY 123" and "... 456" share it): the history index then
    /// compares normalized merchants exactly.
    static func history(of merchant: String, context: NSManagedObjectContext) -> [Transaction] {
        guard let firstWord = CategorySuggestionService.normalizedMerchant(merchant)
            .split(separator: " ")
            .first,
            firstWord.count >= CategorySuggestionService.minimumMerchantLength else { return [] }

        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "type == %@ AND descriptionText CONTAINS[cd] %@",
            TransactionType.expense.rawValue,
            String(firstWord)
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = historyLimit
        return ((try? context.fetch(request)) ?? []).map { $0.toTransaction() }
    }
}
