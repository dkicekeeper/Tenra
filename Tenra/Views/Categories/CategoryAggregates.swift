//
//  CategoryAggregates.swift
//  Tenra
//
//  Pure value-type aggregates for CategoryDetailView.
//
//  Read-time API. All work happens via O(1) hashmap lookups against
//  `TransactionStore.categoryAggregatesByKey`, which is maintained
//  incrementally by `TransactionStore+CategoryIndex`. Never scans the
//  transactions array.
//

import Foundation

struct CategoryAggregates: Equatable, Sendable {
    let amountInPeriod: Double      // in base currency
    let amountAllTime: Double       // in base currency
    let avgMonthlyLast6: Double     // in base currency
    let totalTransactions: Int
}

@MainActor
enum CategoryAggregatesCalculator {

    /// Compute period-scoped, all-time, last-6-month-average totals and total tx count
    /// for a named category.
    ///
    /// Complexity:
    /// • all-time / period-month / month-by-month: O(1) hashmap lookup each.
    /// • period spanning multiple days: bounded ≤days_in_period daily-bucket lookups,
    ///   capped naturally at 366. For the common cases (`thisMonth`, `lastMonth`,
    ///   `thisWeek`, `thisYear`) we use a single bucket lookup at the matching
    ///   granularity.
    /// • avg-monthly-last-6: 6 lookups.
    ///
    /// Returns zeroed aggregates when `store` has no rows for the category yet —
    /// safer than falling back to an O(N_tx) scan.
    static func compute(
        categoryName: String,
        periodStart: Date,
        periodEnd: Date,
        baseCurrency _: String,
        store: TransactionStore
    ) -> CategoryAggregates {
        // All-time bucket — O(1)
        let allKey = CategoryAggregate.makeId(category: categoryName, year: 0, month: 0, day: 0)
        let allTime = store.categoryAggregatesByKey[allKey]
        let amountAllTime = allTime?.totalAmount ?? 0
        let totalCount = Int(allTime?.transactionCount ?? 0)

        // Period total — try to short-circuit when the user's filter matches a
        // granularity bucket exactly, else fall back to daily-bucket summation.
        let amountInPeriod = computePeriodTotal(
            category: categoryName,
            start: periodStart,
            end: periodEnd,
            store: store
        )

        // Average monthly over the last 6 months — 6 hashmap lookups.
        let avg = computeAvgMonthlyLast6(category: categoryName, now: Date(), store: store)

        return CategoryAggregates(
            amountInPeriod: amountInPeriod,
            amountAllTime: amountAllTime,
            avgMonthlyLast6: avg,
            totalTransactions: totalCount
        )
    }

    // MARK: - Period total

    private static func computePeriodTotal(
        category: String,
        start: Date,
        end: Date,
        store: TransactionStore
    ) -> Double {
        let cal = Calendar.current

        // Fast path 1: exact-month window
        if let monthInterval = cal.dateInterval(of: .month, for: start),
           monthInterval.start == start && monthInterval.end == end {
            let y = Int16(cal.component(.year, from: start))
            let m = Int16(cal.component(.month, from: start))
            return readBucket(category: category, y: y, m: m, d: 0, store: store)
        }

        // Fast path 2: exact-year window
        if let yearInterval = cal.dateInterval(of: .year, for: start),
           yearInterval.start == start && yearInterval.end == end {
            let y = Int16(cal.component(.year, from: start))
            return readBucket(category: category, y: y, m: 0, d: 0, store: store)
        }

        // Generic path: sum daily buckets.
        return sumDailyBuckets(category: category, range: DateInterval(start: start, end: end), store: store)
    }

    private static func sumDailyBuckets(
        category: String,
        range: DateInterval,
        store: TransactionStore
    ) -> Double {
        let cal = Calendar.current
        var total = 0.0
        var cursor = cal.startOfDay(for: range.start)
        let limit = range.end
        // Cap defensively to keep this strictly bounded regardless of the input range.
        var safety = 400
        while cursor < limit && safety > 0 {
            let comps = cal.dateComponents([.year, .month, .day], from: cursor)
            total += readBucket(
                category: category,
                y: Int16(comps.year ?? 0),
                m: Int16(comps.month ?? 0),
                d: Int16(comps.day ?? 0),
                store: store
            )
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            safety -= 1
        }
        return total
    }

    // MARK: - Avg monthly last 6

    private static func computeAvgMonthlyLast6(category: String, now: Date, store: TransactionStore) -> Double {
        let cal = Calendar.current
        var sum = 0.0
        var observed = 0
        for offset in 0..<6 {
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { continue }
            let y = Int16(cal.component(.year, from: d))
            let m = Int16(cal.component(.month, from: d))
            let amt = readBucket(category: category, y: y, m: m, d: 0, store: store)
            if amt != 0 {
                sum += amt
                observed += 1
            }
        }
        return observed > 0 ? sum / Double(observed) : 0
    }

    // MARK: - Primitive

    private static func readBucket(
        category: String,
        y: Int16, m: Int16, d: Int16,
        store: TransactionStore
    ) -> Double {
        let key = CategoryAggregate.makeId(category: category, year: y, month: m, day: d)
        return store.categoryAggregatesByKey[key]?.totalAmount ?? 0
    }
}
