//
//  SummaryCalculator.swift
//  AIFinanceManager
//
//  Phase 31 Fix B: Pure off-thread summary computation.
//  Called from ContentView via Task.detached to keep MainActor free during
//  the skeleton→content transition (~275ms eliminated).
//

import Foundation

/// Pure, nonisolated summary calculator.
///
/// All parameters are value types (Transaction is a struct, TimeFilter is a struct)
/// so this can safely run on any thread — no @MainActor services required.
///
/// Currency conversion mirrors TransactionCurrencyService:
/// uses `tx.convertedAmount` when the stored currency differs from baseCurrency,
/// falls back to `tx.amount` when no pre-computed conversion is available.
enum SummaryCalculator {

    // MARK: - Date Formatter

    /// Thread-local DateFormatter. DateFormatter is not thread-safe, so each
    /// detached task gets its own instance rather than sharing DateFormatters.dateFormatter.
    private nonisolated static func makeDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }

    // MARK: - Public API

    /// Compute a Summary from a snapshot of transactions filtered by the given TimeFilter.
    ///
    /// - Parameters:
    ///   - transactions: Full transaction array captured on MainActor before dispatch.
    ///   - filter: The active TimeFilter (value type — safe to capture across threads).
    ///   - baseCurrency: The app base currency string captured on MainActor.
    /// - Returns: A fully computed Summary value.
    nonisolated static func compute(
        transactions: [Transaction],
        filterStart: Date,
        filterEnd: Date,
        baseCurrency: String
    ) -> Summary {
        let dateFormatter = makeDateFormatter()
        let today = Calendar.current.startOfDay(for: Date())

        // Filter by the time range
        let filtered = transactions.filter { tx in
            guard let txDate = dateFormatter.date(from: tx.date) else { return false }
            return txDate >= filterStart && txDate < filterEnd
        }

        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0
        var plannedExpenses: Double = 0

        for tx in filtered {
            // Mirror TransactionCurrencyService logic:
            // if the transaction currency matches baseCurrency, use amount directly;
            // otherwise use the pre-computed convertedAmount (stored at creation time),
            // falling back to the raw amount if no conversion was stored.
            let amountInBase: Double
            if tx.currency == baseCurrency {
                amountInBase = tx.amount
            } else {
                amountInBase = tx.convertedAmount ?? tx.amount
            }

            guard let txDate = dateFormatter.date(from: tx.date) else { continue }
            let isFuture = txDate > today

            if !isFuture {
                switch tx.type {
                case .income:
                    totalIncome += amountInBase
                case .expense:
                    totalExpenses += amountInBase
                case .internalTransfer:
                    totalInternal += amountInBase
                case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                    break
                case .loanPayment, .loanEarlyRepayment:
                    totalExpenses += amountInBase
                }
            } else {
                if tx.type == .expense || tx.type == .loanPayment {
                    plannedExpenses += amountInBase
                }
            }
        }

        let dates = filtered.map { $0.date }.sorted()

        return Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: baseCurrency,
            startDate: dates.first ?? "",
            endDate: dates.last ?? "",
            plannedAmount: plannedExpenses
        )
    }
}
