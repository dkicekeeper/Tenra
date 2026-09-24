//
//  TransactionStore+Recategorize.swift
//  Tenra
//
//  Bulk category change for the "apply to similar" prompt in
//  TransactionEditCoordinator. Goes through the canonical `update` path one row
//  at a time, so state, indexes, balances, caches and persistence stay in step.
//

import Foundation

extension TransactionStore {
    /// Moves the given transactions from `from` to `to`. Every row is re-checked
    /// against the live store first: rows that disappeared, or whose category is
    /// no longer `from` (edited meanwhile), are skipped. Returns the number updated.
    func recategorize(ids: [String], from: String, to: String) async -> Int {
        var updated = 0
        for id in ids {
            guard let current = transactionById[id], current.category == from else { continue }
            do {
                try await update(current.withCategory(to))
                updated += 1
            } catch {
                continue
            }
        }
        return updated
    }
}
