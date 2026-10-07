//
//  TransactionStore+BulkMutations.swift
//  Tenra
//
//  Bulk edits and deletes: `TransactionEvent.bulkUpdated` / `.bulkDeleted`.
//
//  "Apply to similar", deleting an account or a category with its transactions, and
//  deleting / detaching / (un)linking a series' transactions used to apply one `.updated`
//  or `.deleted` event per row. Each row paid an O(N) `firstIndex` scan of `transactions`,
//  a blocking `performAndWait` fetch + save on a fresh background context, a detached
//  balance save, and a merge into the view context (a history-list rebuild): 200 similar
//  transactions took 1–2 s, deleting a 5k-transaction account hung for 25–50 s.
//
//  A bulk event runs the same pipeline once for all rows (`apply`):
//  • state: one pass over `transactions`, each index bucket filtered once, aggregate
//    deltas per row in row order, one debounced persist per aggregate map
//    (`updateStateForBulkDelete` / `updateStateForBulkUpdate` in TransactionStore.swift);
//  • balances: one exact recalculation of the touched accounts
//    (`recalculateBalancesAfterBulkChange`);
//  • cache: full invalidation, as for `.bulkAdded`;
//  • persistence: one awaited background save (`persistBulkChange` →
//    `deleteTransactions(ids:)` / `updateTransactionsFields(_:)`);
//  • view models: the same debounced `syncTransactionStoreToViewModels` as any event.
//
//  Results match the per-row path (pinned by BulkTransactionMutationTests).
//

import Foundation

extension TransactionStore {

    // MARK: - Entry points

    /// Deletes `rows` (current values from the store, in the order a per-row loop would
    /// take them) with as few events as the loan rule allows: payments to a loan that still
    /// exists go one at a time through `.deleted`, everything else in ONE `.bulkDeleted`.
    ///
    /// Why the split: `.deleted` takes a payment off its loan, and that rollback reads the
    /// loan's other payments (the principal owed after a payment is worked out from the
    /// payments after it). Deleted one at a time, in order, each rollback sees exactly the
    /// payments the per-row path left in place — the payments of one loan are few. Rows of
    /// other kinds don't affect a rollback, so deleting them together afterwards changes
    /// nothing it reads.
    internal func deleteTransactionsInBulk(_ rows: [Transaction]) async throws {
        var bulk: [Transaction] = []
        bulk.reserveCapacity(rows.count)
        for row in rows {
            if isPaymentToLiveLoan(row) {
                try await apply(.deleted(row))
            } else {
                bulk.append(row)
            }
        }
        guard !bulk.isEmpty else { return }
        try await apply(.bulkDeleted(bulk))
    }

    /// A `.loanPayment` / `.loanEarlyRepayment` whose loan (`targetAccountId`, the
    /// orientation contract) still exists: deleting it must roll that loan back.
    internal func isPaymentToLiveLoan(_ transaction: Transaction) -> Bool {
        guard transaction.type == .loanPayment || transaction.type == .loanEarlyRepayment,
              let loanId = transaction.targetAccountId else { return false }
        return accountById[loanId]?.loanInfo != nil
    }

    // MARK: - Bucket maintenance

    /// Removes `ids` from the given buckets of a grouping index, one filter per bucket,
    /// dropping buckets left empty (what the per-row removals did one id at a time).
    nonisolated static func removeIds(
        _ ids: Set<String>,
        fromBuckets keys: Set<String>,
        of index: inout [String: [String]]
    ) {
        guard !ids.isEmpty else { return }
        for key in keys {
            index[key]?.removeAll { ids.contains($0) }
            if index[key]?.isEmpty == true {
                index.removeValue(forKey: key)
            }
        }
    }
}
