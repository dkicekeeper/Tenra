//
//  SummaryCalculator.swift
//  Tenra
//
//  Pure off-thread summary computation.
//  Called from ContentView via Task.detached to keep MainActor free.
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
            // Convert tx.amount → baseCurrency via the live FX cache. `convertedAmount`
            // is in the *account*'s currency, so it must NOT be preferred over
            // `convertSync` — only used as a last-resort fallback when rates are
            // unavailable.
            let amountInBase: Double
            if tx.currency == baseCurrency {
                amountInBase = tx.amount
            } else if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) {
                amountInBase = fx
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

    // MARK: - Category Gradient Background

    /// Compute the top expense categories and their proportional weights for the
    /// Apple Card-style gradient background in `TransactionsSummaryCard`.
    ///
    /// Runs identically on any thread (no @MainActor services required).
    /// Returns at most `maxCount` items, sorted by spend descending, with
    /// weights normalised to 0.0–1.0 relative to the largest category.
    ///
    /// - Parameters:
    ///   - transactions: Full array captured on MainActor before dispatch.
    ///   - filterStart: Inclusive lower bound of the active time window.
    ///   - filterEnd: Exclusive upper bound of the active time window.
    ///   - baseCurrency: The app base currency used for amount conversion.
    ///   - maxCount: Maximum number of categories to return (default 5).
    /// - Returns: Sorted `[CategoryColorWeight]`, empty when no expense data.
    nonisolated static func computeTopExpenseWeights(
        transactions: [Transaction],
        filterStart: Date,
        filterEnd: Date,
        baseCurrency: String,
        maxCount: Int = 5
    ) -> [CategoryColorWeight] {
        let dateFormatter = makeDateFormatter()
        let today = Calendar.current.startOfDay(for: Date())

        // Single O(N) pass: filter by date range + accumulate per-category totals.
        var categoryTotals: [String: Double] = [:]

        for tx in transactions {
            // Only past (non-future) expense-like transactions count.
            guard tx.type == .expense || tx.type == .loanPayment else { continue }
            guard let txDate = dateFormatter.date(from: tx.date) else { continue }
            guard txDate >= filterStart && txDate < filterEnd else { continue }
            guard txDate <= today else { continue }

            let amountInBase: Double
            if tx.currency == baseCurrency {
                amountInBase = tx.amount
            } else if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) {
                amountInBase = fx
            } else {
                amountInBase = tx.convertedAmount ?? tx.amount
            }

            categoryTotals[tx.category, default: 0] += amountInBase
        }

        guard !categoryTotals.isEmpty else { return [] }

        // Sort descending by spend and keep the top N categories.
        let sorted = categoryTotals
            .sorted { $0.value > $1.value }
            .prefix(maxCount)

        // Normalise weights relative to the largest category (not total sum),
        // so the dominant category always gets weight 1.0 and the others scale
        // proportionally. This makes orb-size differences clearly visible.
        let maxAmount = sorted.first?.value ?? 1.0
        guard maxAmount > 0 else { return [] }

        return sorted.map { CategoryColorWeight(category: $0.key, weight: $0.value / maxAmount) }
    }
}
