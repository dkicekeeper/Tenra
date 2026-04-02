//
//  InsightPeriodDataPoint.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights — Universal period data point
//  Replaces MonthlyDataPoint for insight charts. Supports any granularity
//  (week / month / quarter / year / allTime).
//
//  Migration note:
//  MonthlyDataPoint is kept in InsightModels.swift for backward-compatibility
//  with existing chart components until they are fully migrated.
//  New code should use PeriodDataPoint.
//

import Foundation

// MARK: - PeriodDataPoint

/// A single bucketed data point for any InsightGranularity.
/// `period` describes the exact date interval this bucket covers.
struct PeriodDataPoint: Identifiable, Hashable {
    /// Stable identifier — same as `groupingKey` used to build the bucket.
    let id: String

    /// The granularity this point was generated for (week/month/quarter/year/allTime).
    let granularity: InsightGranularity

    /// The grouping key used to build this bucket (e.g. "2024-02", "2024-W07", "2024-Q1").
    let key: String

    /// Start of the bucket (inclusive).
    let periodStart: Date

    /// End of the bucket (exclusive).
    let periodEnd: Date

    /// Human-readable label shown on charts and in breakdown lists.
    let label: String

    // MARK: - Financial Aggregates

    /// Total income (converted to base currency) within this bucket.
    let income: Double

    /// Total expenses (converted to base currency) within this bucket.
    let expenses: Double

    /// `income - expenses` for the bucket.
    nonisolated var netFlow: Double { income - expenses }

    // MARK: - Optional: Cumulative Balance

    /// Running cumulative balance at the END of this bucket.
    /// Populated only for wealth/balance charts; `nil` otherwise.
    let cumulativeBalance: Double?
}

// MARK: - PeriodDataPoint convenience

extension PeriodDataPoint {
    /// Creates a zero-value data point for a given key (placeholder for empty periods).
    static func empty(
        key: String,
        granularity: InsightGranularity,
        cumulativeBalance: Double? = nil
    ) -> PeriodDataPoint {
        let start = granularity.periodStart(for: key)
        return PeriodDataPoint(
            id: key,
            granularity: granularity,
            key: key,
            periodStart: start,
            periodEnd: start, // will be corrected by the service
            label: granularity.periodLabel(for: key),
            income: 0,
            expenses: 0,
            cumulativeBalance: cumulativeBalance
        )
    }
}


// MARK: - Mock data for previews

extension PeriodDataPoint {
    static func mockMonthly() -> [PeriodDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<6).reversed().map { offset in
            let start = calendar.date(byAdding: .month, value: -offset, to: calendar.startOfMonth(for: now))!
            let key = InsightGranularity.month.groupingKey(for: start)
            let income = Double.random(in: 200_000...500_000)
            let expenses = Double.random(in: 100_000...300_000)
            return PeriodDataPoint(
                id: key,
                granularity: .month,
                key: key,
                periodStart: start,
                periodEnd: calendar.date(byAdding: .month, value: 1, to: start)!,
                label: InsightGranularity.month.periodLabel(for: key),
                income: income,
                expenses: expenses,
                cumulativeBalance: nil
            )
        }
    }
}

// MARK: - Calendar helpers (internal)

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
