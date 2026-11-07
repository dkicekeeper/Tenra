//
//  SubscriptionChargeLinker.swift
//  Tenra
//
//  Merges a real subscription charge into the planned one (SubscriptionChargeMatcher), so one
//  charge stays one transaction:
//
//  • by hand: "This is a subscription…" in the edit screen, Link payments on the subscription's
//    screen, "Merge" in To review. The nearest planned charge within half the period takes the
//    expense's amount, currency, conversion, date and account, and the expense is deleted. With
//    no planned charge near, the expense is linked to the series as it is. The merchant is
//    remembered for the subscription (SubscriptionMerchantMemory), so its next charge merges on
//    its own.
//  • queued: an intent matched a charge while only the fast path was loaded (no history to
//    update); `applyPending` merges it once the full load lands.
//
//  Never touches the series itself (CLAUDE.md red flag 10). docs/domains/recurring.md §Real charges.
//

import Foundation

@MainActor
enum SubscriptionChargeLinker {

    private static var isApplying = false

    enum Outcome: Equatable {
        /// The planned charge took the expense's values; the expense is gone.
        case merged(occurrenceId: String)
        /// No planned charge near: the expense is linked to the series as it is.
        case linked
    }

    /// Links an expense to a subscription, merging it into the planned charge it stands for.
    /// - Parameter merchant: the merchant the bank wrote (a capture's), else the description.
    @discardableResult
    static func link(
        _ charge: Transaction,
        to series: RecurringSeries,
        merchant: String? = nil,
        store: TransactionStore,
        captures: WalletCaptureStore = .shared,
        memory: SubscriptionMerchantMemory = .shared
    ) async throws -> Outcome {
        // Which planned charges already hold a real one is known for `WalletCaptureStore.retention`
        // only: an older one may hold a real charge, so an older expense is linked, never merged.
        let horizon = DateFormatters.dateFormatter.string(from: Date().addingTimeInterval(-WalletCaptureStore.retention))
        let outcome: Outcome
        if let occurrence = SubscriptionChargeMatcher.plannedOccurrence(
            for: charge,
            among: (store.transactionsBySeriesId[series.id] ?? []).filter { $0.date >= horizon },
            frequency: series.frequency,
            isTaken: captures.isMatched(occurrenceId:)
        ) {
            try await store.update(SubscriptionChargeMatcher.merged(
                occurrence,
                amount: charge.amount,
                currency: charge.currency,
                convertedAmount: charge.convertedAmount,
                targetCurrency: charge.targetCurrency,
                targetAmount: charge.targetAmount,
                accountId: charge.accountId,
                date: charge.date
            ))
            try await store.delete(charge)
            captures.noteMatched(occurrenceId: occurrence.id)
            outcome = .merged(occurrenceId: occurrence.id)
        } else {
            try await store.linkTransactionsToSubscription(seriesId: series.id, transactions: [charge])
            outcome = .linked
        }
        let capture = captures.capture(forTransactionId: charge.id)
        memory.remember(seriesId: series.id, forMerchant: merchant ?? capture?.payment.merchant ?? charge.description)
        if case .merged(let occurrenceId) = outcome {
            captures.removeCapture(transactionId: charge.id)
            // Kept under the planned charge: the other source's report of the same payment
            // (Apple Pay and the bank) stays a duplicate of it.
            if let capture {
                var moved = WalletCaptureStore.Capture(
                    id: occurrenceId, payment: capture.payment, guesses: [], isReviewed: true, accountId: charge.accountId
                )
                moved.pairingDismissed = true
                captures.insert(moved)
            }
            WalletReviewNotifier.removeDelivered(transactionId: charge.id)
        } else {
            captures.clearSubscriptionSuggestion(transactionId: charge.id)
        }
        return outcome
    }

    /// Links several expenses (Link payments), oldest first, each to its own planned charge.
    static func linkAll(
        _ charges: [Transaction],
        to series: RecurringSeries,
        store: TransactionStore
    ) async throws {
        for charge in charges.sorted(by: { $0.date < $1.date }) {
            try await link(charge, to: series, store: store)
        }
    }

    /// The charges intents matched before the full load, merged into their planned charges in
    /// one batch. The intent saved nothing else for them, so a charge is never dropped: one whose
    /// planned charge is gone (deleted meanwhile) or could not be updated is saved as an expense
    /// of its own; one that fails that too stays queued for the next pass.
    static func applyPending(store: TransactionStore, captures: WalletCaptureStore = .shared) async {
        // One pass at a time: the intent and the foreground both call it, and a second pass
        // over the same queue would save a gone planned charge's expense twice.
        guard store.hasCompletedInitialLoad, !captures.chargeMerges.isEmpty, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        // Merges an intent queued while this pass awaited are taken in the same pass.
        var attempted = Set<String>()
        while true {
            let merges = captures.chargeMerges.filter { !attempted.contains($0.occurrenceId) }
            guard !merges.isEmpty else { break }
            attempted.formUnion(merges.map(\.occurrenceId))
            await apply(merges, store: store, captures: captures)
        }
    }

    private static func apply(_ merges: [WalletCaptureStore.ChargeMerge], store: TransactionStore, captures: WalletCaptureStore) async {
        var done = Set<String>()
        let rows = merges.compactMap { merge -> Transaction? in
            guard let occurrence = store.transactionById[merge.occurrenceId] else { return nil }
            return SubscriptionChargeMatcher.merged(
                occurrence,
                amount: merge.amount,
                currency: merge.currency,
                convertedAmount: merge.convertedAmount,
                targetCurrency: merge.targetCurrency,
                targetAmount: merge.targetAmount,
                accountId: merge.accountId,
                date: merge.date
            )
        }
        if !rows.isEmpty {
            done.formUnion(await store.updateBatch(rows).map(\.id))
        }
        for merge in merges where !done.contains(merge.occurrenceId) {
            let expense = Transaction(
                id: "",
                date: merge.date,
                description: merge.note,
                amount: merge.amount,
                currency: merge.currency,
                convertedAmount: merge.convertedAmount,
                type: .expense,
                category: merge.categoryName,
                accountId: merge.accountId,
                targetCurrency: merge.targetCurrency,
                targetAmount: merge.targetAmount
            )
            if (try? await store.add(expense)) != nil {
                done.insert(merge.occurrenceId)
            }
        }
        captures.removeChargeMerges(occurrenceIds: done)
    }
}
