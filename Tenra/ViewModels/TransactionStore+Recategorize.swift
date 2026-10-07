//
//  TransactionStore+Recategorize.swift
//  Tenra
//
//  Bulk category change for the "apply to similar" prompt in
//  TransactionEditCoordinator. One `.bulkUpdated` event through `updateBatch`, so
//  state, indexes, balances, caches and persistence move together, once for all rows.
//

import Foundation

extension TransactionStore {
    /// Moves the given transactions from `from` to `to`. Every row is re-checked
    /// against the live store first: rows that disappeared, or whose category is
    /// no longer `from` (edited meanwhile), are skipped, and so is a row `update(_:)`
    /// would reject. Returns the number updated.
    func recategorize(ids: [String], from: String, to: String) async -> Int {
        var seen = Set<String>()
        var rows: [Transaction] = []
        for id in ids where seen.insert(id).inserted {
            guard let current = transactionById[id], current.category == from else { continue }
            rows.append(current.withCategory(to))
        }
        guard !rows.isEmpty else { return 0 }
        return await updateBatch(rows).count
    }
}
