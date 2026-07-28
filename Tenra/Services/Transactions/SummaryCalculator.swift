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

    // MARK: - Date Parsing
    //
    // Dates go through `FastDateParser`, not `DateFormatter`. This type is the single
    // most frequently re-run O(N) walk in the app: `ContentView.task(id: summaryTrigger)`
    // fires it on every transaction mutation, every period switch, every FX refresh and
    // every base-currency change, and it used to parse the full 19k set ~3 times per run
    // (~635 ms measured). FastDateParser is ~53× faster and has no thread-safety caveat,
    // so the per-task formatter instance is gone too.

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
        let today = Calendar.current.startOfDay(for: Date())
        // One frozen rate table for the whole walk: avoids ~38k NSLock acquisitions and
        // guarantees every transaction is converted at the same rates even if a prewarm
        // response lands mid-loop. See RateSnapshot.
        let rates = RateSnapshot()

        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0
        var plannedExpenses: Double = 0
        var minDate: String?
        var maxDate: String?

        // ONE pass. Previously this was a `.filter` that parsed every tx.date, followed by
        // a loop over the result that parsed the SAME strings a second time, followed by a
        // `filtered.map { $0.date }.sorted()` purely to read the first/last element.
        // Three walks and two parses per transaction; now one of each.
        for tx in transactions {
            guard let txDate = FastDateParser.date(from: tx.date) else { continue }
            guard txDate >= filterStart, txDate < filterEnd else { continue }

            // Convert tx.amount → baseCurrency via the live FX cache. `convertedAmount`
            // is in the *account*'s currency, so it must NOT be preferred over
            // `convertSync` — only used as a last-resort fallback when rates are
            // unavailable.
            let amountInBase: Double
            if tx.currency == baseCurrency {
                amountInBase = tx.amount
            } else if let fx = rates.convert(tx.amount, from: tx.currency, to: baseCurrency) {
                amountInBase = fx
            } else {
                amountInBase = tx.convertedAmount ?? tx.amount
            }

            // Single shared classification rule — see SummaryContribution.
            switch tx.type.summaryContribution(isFuture: txDate > today) {
            case .income:          totalIncome += amountInBase
            case .expense:         totalExpenses += amountInBase
            case .internalTransfer: totalInternal += amountInBase
            case .plannedExpense:  plannedExpenses += amountInBase
            case .ignored:         break
            }

            // Period bounds tracked inline. `yyyy-MM-dd` sorts lexicographically in
            // chronological order, so string min/max is exact — and avoids allocating
            // an N-element array plus an O(n log n) sort to read two values.
            if minDate == nil || tx.date < minDate! { minDate = tx.date }
            if maxDate == nil || tx.date > maxDate! { maxDate = tx.date }
        }

        return Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: baseCurrency,
            startDate: minDate ?? "",
            endDate: maxDate ?? "",
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
        let today = Calendar.current.startOfDay(for: Date())
        let rates = RateSnapshot()

        // Single O(N) pass: filter by date range + accumulate per-category totals.
        var categoryTotals: [String: Double] = [:]

        for tx in transactions {
            // Type check first — it is far cheaper than parsing, and most transactions
            // fail it, so this skips the parse entirely for the majority of the set.
            guard tx.type == .expense || tx.type == .loanPayment else { continue }
            guard let txDate = FastDateParser.date(from: tx.date) else { continue }
            guard txDate >= filterStart && txDate < filterEnd else { continue }
            guard txDate <= today else { continue }

            let amountInBase: Double
            if tx.currency == baseCurrency {
                amountInBase = tx.amount
            } else if let fx = rates.convert(tx.amount, from: tx.currency, to: baseCurrency) {
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
