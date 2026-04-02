//
//  ChartAxisHelpers.swift
//  AIFinanceManager
//
//  Phase 28: Chart Consistency Refactor
//  Single source of truth for chart axis formatting logic.
//  Previously duplicated across 6 chart structs in 3 files.
//

import Foundation

// MARK: - ChartAxisHelpers

/// Shared axis formatting utilities for all Insights chart components.
///
/// Eliminates duplicated axis formatting code across:
/// - `PeriodBarChart`
/// - `PeriodLineChart`
nonisolated enum ChartAxisHelpers {

    // MARK: - Y-axis value formatter (all charts)

    /// Formats a Double to a compact human-readable string.
    /// Uses `abs()` to correctly handle negative values (CashFlow, WealthChart).
    ///
    /// Examples: 1_500_000 → "1.5M" · 75_000 → "75K" · 500 → "500" · -30_000 → "-30K"
    static func formatCompact(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if abs >= 1_000     { return String(format: "%.0fK", value / 1_000) }
        return String(format: "%.0f", value)
    }

    // MARK: - Legacy X-axis formatter (MonthlyDataPoint — Date-based)

    /// Cached `DateFormatter` for legacy month-based X-axis labels.
    /// Locale is updated at each call site to stay current.
    static let axisMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    /// Formats a `Date` for the legacy X-axis.
    /// Returns 3-char uppercase month (locale-aware) + short year suffix when not current year.
    ///
    /// Examples: "ЯНВ" (current year) · "ЯНВ'24" (other year)
    static func formatAxisDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let dateYear = calendar.component(.year, from: date)
        axisMonthFormatter.locale = .current
        let month = String(axisMonthFormatter.string(from: date).uppercased().prefix(3))
        return dateYear == currentYear
            ? month
            : "\(month)'\(String(format: "%02d", dateYear % 100))"
    }

    // MARK: - Period X-axis formatters (PeriodDataPoint — String label-based)

    /// Builds a `[fullLabel: compactLabel]` dictionary for all data points in one pass.
    /// Creates `Calendar` and `DateFormatter` once — O(n) with minimal overhead.
    static func axisLabelMap(for points: [PeriodDataPoint]) -> [String: String] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM"
        // Use uniquingKeysWith to gracefully handle rare label collisions (e.g. allTime,
        // or two weeks in different years that start on the same calendar date).
        return Dictionary(
            points.map { point in
                (point.label, compactPeriodLabel(
                    for: point,
                    calendar: calendar,
                    currentYear: currentYear,
                    formatter: formatter
                ))
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Compact period label per granularity:
    /// - `.month`   → "ЯНВ" / "ЯНВ'25"
    /// - `.week`    → "W07" / "W07'25"
    /// - `.quarter` → "Q1"  / "Q1'25"
    /// - `.year`    → "2025"
    /// - `.allTime` → original label
    static func compactPeriodLabel(
        for point: PeriodDataPoint,
        calendar: Calendar,
        currentYear: Int,
        formatter: DateFormatter
    ) -> String {
        let pointYear = calendar.component(.year, from: point.periodStart)
        let shortYear = String(format: "%02d", pointYear % 100)

        switch point.granularity {
        case .month:
            let month = String(formatter.string(from: point.periodStart).uppercased().prefix(3))
            return pointYear == currentYear ? month : "\(month)'\(shortYear)"

        case .week:
            let weekNum = calendar.component(.weekOfYear, from: point.periodStart)
            return pointYear == currentYear
                ? String(format: "W%02d", weekNum)
                : String(format: "W%02d'\(shortYear)", weekNum)

        case .quarter:
            let month = calendar.component(.month, from: point.periodStart)
            let quarter = (month - 1) / 3 + 1
            return pointYear == currentYear ? "Q\(quarter)" : "Q\(quarter)'\(shortYear)"

        case .year:
            return "\(pointYear)"

        case .allTime:
            return point.label
        }
    }
}
