//
//  AccountAggregates.swift
//  Tenra
//
//  Pure value-type aggregates for AccountDetailView.
//
//  Read path: O(1) lookup against `TransactionStore.accountAggregatesByAccountId`,
//  which is maintained incrementally by `TransactionStore+AccountAggregates`.
//  Legacy O(N_tx) full-scan path stays as a `nonisolated static` helper for
//  background actors (Insights) that cannot read MainActor-isolated store indexes.
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

    // MARK: - Legacy array-based API
    //
    // For consumers that work on a `[Transaction]` snapshot (background services,
    // Insights, tests). Same byte-for-byte output as the original implementation.

    nonisolated static func compute(
        accountId: String,
        accountCurrency: String,
        transactions: [Transaction]
    ) -> AccountAggregates {
        var count = 0
        var income = 0.0
        var expense = 0.0
        for tx in transactions {
            let isSource = tx.accountId == accountId
            let isTarget = tx.targetAccountId == accountId
            guard isSource || isTarget else { continue }
            count += 1

            let amount: Double
            if tx.type == .internalTransfer, isTarget,
               let targetAmount = tx.targetAmount,
               let targetCurrency = tx.targetCurrency {
                amount = convertIfNeeded(
                    amount: targetAmount,
                    from: targetCurrency,
                    to: accountCurrency,
                    stored: nil
                )
            } else {
                amount = convertIfNeeded(
                    amount: tx.amount,
                    from: tx.currency,
                    to: accountCurrency,
                    stored: tx.convertedAmount
                )
            }

            switch tx.type {
            case .income:
                if isSource { income += amount }
            case .expense:
                if isSource { expense += amount }
            case .internalTransfer:
                if isTarget { income += amount }
                if isSource { expense += amount }
            case .depositTopUp:
                if isSource { expense += amount }
                if isTarget { income += amount }
            case .depositWithdrawal:
                if isSource { expense += amount }
                if isTarget { income += amount }
            case .depositInterestAccrual:
                if isSource { income += amount }
                if isTarget { income += amount }
            case .loanPayment, .loanEarlyRepayment:
                if isSource { expense += amount }
                if isTarget { expense += amount }
            }
        }
        return AccountAggregates(
            totalTransactions: count,
            totalIncome: income,
            totalExpense: expense
        )
    }

    private nonisolated static func convertIfNeeded(
        amount: Double,
        from: String,
        to: String,
        stored: Double?
    ) -> Double {
        if from == to { return amount }
        if let converted = CurrencyConverter.convertSync(amount: amount, from: from, to: to) {
            return converted
        }
        return stored ?? amount
    }
}
