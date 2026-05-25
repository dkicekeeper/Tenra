//
//  AccountAggregates.swift
//  Tenra
//
//  Pure value-type aggregates for AccountDetailView.
//
//  Read path: O(1) lookup against `TransactionStore.accountAggregatesByAccountId`,
//  which is maintained incrementally by `TransactionStore+AccountAggregates`
//  (the single definition of the per-type income/expense sign table).
//

import Foundation

struct AccountAggregates: Equatable, Sendable {
    let totalTransactions: Int
    let totalIncome: Double      // in account currency
    let totalExpense: Double     // in account currency
}

@MainActor
enum AccountAggregatesCalculator {

    /// O(1) read from the pre-maintained store index.
    /// Returns zeros for an unknown account id (or an account with no transactions).
    static func compute(accountId: String, store: TransactionStore) -> AccountAggregates {
        store.accountAggregatesByAccountId[accountId]
            ?? AccountAggregates(totalTransactions: 0, totalIncome: 0, totalExpense: 0)
    }
}
