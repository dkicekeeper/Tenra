//
//  CategoryAggregates.swift
//  Tenra
//
//  Pure value-type aggregates for CategoryDetailView.
//  Lives in a `nonisolated enum` so the computation can run off MainActor if needed.
//

import Foundation

struct CategoryAggregates: Equatable, Sendable {
    let amountInPeriod: Double      // in base currency
    let amountAllTime: Double       // in base currency
    let avgMonthlyLast6: Double     // in base currency
    let totalTransactions: Int
}

nonisolated enum CategoryAggregatesCalculator {
    /// Computes period-scoped / all-time / last-6-month-avg totals and total tx count for a
    /// named category. Amounts are converted into `baseCurrency` when the tx currency differs.
    ///
    /// - `periodStart`/`periodEnd` define the half-open window used for `amountInPeriod`.
    ///    We treat the window as `[periodStart, periodEnd)` on the tx's parsed date — matching
    ///    `TimeFilter.dateRange()` convention (end = midnight of first day after the window).
    /// - `avgMonthlyLast6` divides the last-6-month total by the number of distinct
    ///    (year, month) buckets we observed — so one tx in October only divides by 1, not 6.
    static func compute(
        categoryName: String,
        periodStart: Date,
        periodEnd: Date,
        baseCurrency: String,
        transactions: [Transaction]
    ) -> CategoryAggregates {
        let cal = Calendar.current
        let now = Date()
        let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: now) ?? now

        var amountPeriod = 0.0
        var amountAll = 0.0
        var amountLast6 = 0.0
        var count = 0
        var monthsSeenLast6 = Set<String>()

        for tx in transactions where tx.category == categoryName {
            count += 1
            let amount = convertIfNeeded(
                amount: tx.amount,
                from: tx.currency,
                to: baseCurrency,
                stored: tx.convertedAmount
            )
            amountAll += amount

            guard let date = DateFormatters.dateFormatter.date(from: tx.date) else { continue }
            if date >= periodStart && date < periodEnd {
                amountPeriod += amount
            }
            if date >= sixMonthsAgo {
                amountLast6 += amount
                let ym = "\(cal.component(.year, from: date))-\(cal.component(.month, from: date))"
                monthsSeenLast6.insert(ym)
            }
        }

        let months = max(monthsSeenLast6.count, 1)
        let avg = amountLast6 / Double(months)

        return CategoryAggregates(
            amountInPeriod: amountPeriod,
            amountAllTime: amountAll,
            avgMonthlyLast6: avg,
            totalTransactions: count
        )
    }

    private static func convertIfNeeded(
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
