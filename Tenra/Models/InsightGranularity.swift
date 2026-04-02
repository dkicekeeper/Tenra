//
//  InsightGranularity.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights — Granularity-based time filter
//  Replaces TimeFilter in the Insights module.
//  Data is always computed for ALL TIME; only the grouping changes.
//

import Foundation

// MARK: - InsightGranularity

/// Controls how insight data is grouped and displayed.
/// The underlying data always spans ALL transactions; granularity
/// determines the bucket size used for charts and comparisons.
enum InsightGranularity: String, CaseIterable, Identifiable {
    case week       // Last 52 weeks (rolling 1 year)
    case month      // All months from first transaction
    case quarter    // All quarters from first transaction
    case year       // All years from first transaction
    case allTime    // Single summary bucket

    nonisolated var id: String { rawValue }

    // MARK: - Display

    /// Localised display name shown in the picker
    nonisolated var displayName: String {
        switch self {
        case .week:    return String(localized: "insights.granularity.week")
        case .month:   return String(localized: "insights.granularity.month")
        case .quarter: return String(localized: "insights.granularity.quarter")
        case .year:    return String(localized: "insights.granularity.year")
        case .allTime: return String(localized: "insights.granularity.allTime")
        }
    }

    /// Short label used in compact UI contexts
    nonisolated var shortName: String {
        switch self {
        case .week:    return String(localized: "insights.granularity.week.short")
        case .month:   return String(localized: "insights.granularity.month.short")
        case .quarter: return String(localized: "insights.granularity.quarter.short")
        case .year:    return String(localized: "insights.granularity.year.short")
        case .allTime: return String(localized: "insights.granularity.allTime.short")
        }
    }

    // MARK: - Chart Layout

    /// Preferred width per data point in the scrollable chart.
    nonisolated var pointWidth: CGFloat {
        switch self {
        case .week:    return 28
        case .month:   return 50
        case .quarter: return 80
        case .year:    return 100
        case .allTime: return 160
        }
    }

    // MARK: - Comparison Period Name

    /// Label used in MoM/YoY comparison strings ("vs prev. month", etc.)
    nonisolated var comparisonPeriodName: String {
        switch self {
        case .week:    return String(localized: "insights.granularity.prev.week")
        case .month:   return String(localized: "insights.granularity.prev.month")
        case .quarter: return String(localized: "insights.granularity.prev.quarter")
        case .year:    return String(localized: "insights.granularity.prev.year")
        case .allTime: return ""
        }
    }

    // MARK: - Date Range

    /// Returns `(start, end)` covering the data window for this granularity.
    /// `end` is always exclusive (the first instant AFTER the window).
    ///
    /// - Parameter firstTransactionDate: earliest transaction date in the store.
    ///   Used to determine how far back to go for month/quarter/year.
    ///   Pass `nil` to fall back to a sensible default.
    nonisolated func dateRange(firstTransactionDate: Date?) -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)

        switch self {
        case .week:
            // Last 52 weeks (rolling ~1 year)
            let start = calendar.date(byAdding: .weekOfYear, value: -52, to: calendar.startOfWeek(for: now))!
            return (start, end)

        case .month:
            let earliest = firstTransactionDate ?? calendar.date(byAdding: .month, value: -12, to: now)!
            let start = calendar.startOfMonth(for: earliest)
            return (start, end)

        case .quarter:
            let earliest = firstTransactionDate ?? calendar.date(byAdding: .month, value: -12, to: now)!
            let start = calendar.startOfQuarter(for: earliest)
            return (start, end)

        case .year:
            let earliest = firstTransactionDate ?? calendar.date(byAdding: .year, value: -3, to: now)!
            var comps = calendar.dateComponents([.year], from: earliest)
            comps.month = 1; comps.day = 1
            let start = calendar.date(from: comps) ?? earliest
            return (start, end)

        case .allTime:
            let earliest = firstTransactionDate ?? now
            return (earliest, end)
        }
    }

    // MARK: - Grouping Key

    /// Returns a stable string key for bucketing a date into this granularity's period.
    nonisolated func groupingKey(for date: Date) -> String {
        let calendar = Calendar.current
        switch self {
        case .week:
            // ISO week: "yyyy-Www" e.g. "2024-W03"
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return String(format: "%04d-W%02d", year, weekOfYear)

        case .month:
            let y = calendar.component(.year, from: date)
            let m = calendar.component(.month, from: date)
            return String(format: "%04d-%02d", y, m)

        case .quarter:
            let y = calendar.component(.year, from: date)
            let m = calendar.component(.month, from: date)
            let q = (m - 1) / 3 + 1
            return String(format: "%04d-Q%d", y, q)

        case .year:
            let y = calendar.component(.year, from: date)
            return String(format: "%04d", y)

        case .allTime:
            return "all"
        }
    }

    // MARK: - Period Start Date for a Key

    /// Returns the start `Date` of the period represented by `key`.
    nonisolated func periodStart(for key: String) -> Date {
        let calendar = Calendar.current
        switch self {
        case .week:
            // "2024-W03"
            let parts = key.split(separator: "-W")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let week = Int(parts[1]) else { return Date() }
            var comps = DateComponents()
            comps.yearForWeekOfYear = year
            comps.weekOfYear = week
            comps.weekday = calendar.firstWeekday
            return calendar.date(from: comps) ?? Date()

        case .month:
            // "2024-02"
            let parts = key.split(separator: "-")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]) else { return Date() }
            let comps = DateComponents(year: year, month: month, day: 1)
            return calendar.date(from: comps) ?? Date()

        case .quarter:
            // "2024-Q1"
            let parts = key.split(separator: "-Q")
            guard parts.count == 2,
                  let year = Int(parts[0]),
                  let quarter = Int(parts[1]) else { return Date() }
            let month = (quarter - 1) * 3 + 1
            let comps = DateComponents(year: year, month: month, day: 1)
            return calendar.date(from: comps) ?? Date()

        case .year:
            // "2024"
            guard let year = Int(key) else { return Date() }
            let comps = DateComponents(year: year, month: 1, day: 1)
            return calendar.date(from: comps) ?? Date()

        case .allTime:
            return Date.distantPast
        }
    }

    // MARK: - Period Label for a Key

    /// Human-readable label shown on charts / breakdown list.
    nonisolated func periodLabel(for key: String, locale: Locale = .current) -> String {
        let date = periodStart(for: key)
        let calendar = Calendar.current
        switch self {
        case .week:
            // "3 Jan" (current year) or "3 Jan'25" (other year)
            // Year suffix is required to keep labels unique across the 52-week window which
            // spans two calendar years, e.g. Jan 2025 and Jan 2026 overlap.
            let df = DateFormatter()
            df.locale = locale
            df.dateFormat = DateFormatter.dateFormat(fromTemplate: "dMMM", options: 0, locale: locale)
            let weekYear = calendar.component(.yearForWeekOfYear, from: date)
            let currentYear = calendar.component(.yearForWeekOfYear, from: Date())
            let dayMonth = df.string(from: date)
            return weekYear == currentYear
                ? dayMonth
                : "\(dayMonth)'\(String(format: "%02d", weekYear % 100))"

        case .month:
            // "Jan 2024"
            let df = DateFormatter()
            df.locale = locale
            df.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMMyyyy", options: 0, locale: locale)
            return df.string(from: date)

        case .quarter:
            // "Q1 2024"
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let quarter = (month - 1) / 3 + 1
            return "Q\(quarter) \(year)"

        case .year:
            // "2024"
            let year = calendar.component(.year, from: date)
            return "\(year)"

        case .allTime:
            return String(localized: "insights.granularity.allTime")
        }
    }

    // MARK: - SF Symbol icon

    /// SF Symbol name representing this granularity in pickers and menus.
    nonisolated var icon: String {
        switch self {
        case .week:    return "calendar.badge.clock"
        case .month:   return "calendar"
        case .quarter: return "calendar.badge.plus"
        case .year:    return "chart.line.uptrend.xyaxis"
        case .allTime: return "infinity"
        }
    }

    // MARK: - Granularity-Aware Insight Titles

    /// Card title for the period-over-period spending change insight.
    /// "Monthly Spending Change" for month, "Weekly Spending" for week, etc.
    nonisolated var monthOverMonthTitle: String {
        switch self {
        case .week:    return String(localized: "insights.monthOverMonth.week")
        case .month:   return String(localized: "insights.monthOverMonth.month")
        case .quarter: return String(localized: "insights.monthOverMonth.quarter")
        case .year:    return String(localized: "insights.monthOverMonth.year")
        case .allTime: return String(localized: "insights.monthOverMonth.month")
        }
    }

    /// Card title for the best-period cashflow insight.
    nonisolated var bestPeriodTitle: String {
        switch self {
        case .week:    return String(localized: "insights.bestPeriod.week")
        case .month:   return String(localized: "insights.bestPeriod.month")
        case .quarter: return String(localized: "insights.bestPeriod.quarter")
        case .year:    return String(localized: "insights.bestPeriod.year")
        case .allTime: return String(localized: "insights.bestPeriod.allTime")
        }
    }

    /// Card title for the worst-period cashflow insight.
    nonisolated var worstPeriodTitle: String {
        switch self {
        case .week:    return String(localized: "insights.worstPeriod.week")
        case .month:   return String(localized: "insights.worstPeriod.month")
        case .quarter: return String(localized: "insights.worstPeriod.quarter")
        case .year:    return String(localized: "insights.worstPeriod.year")
        case .allTime: return String(localized: "insights.worstPeriod.allTime")
        }
    }

    /// Card title for the total recurring cost insight.
    nonisolated var totalRecurringTitle: String {
        switch self {
        case .week:    return String(localized: "insights.totalRecurring.week")
        case .month:   return String(localized: "insights.totalRecurring.month")
        case .quarter: return String(localized: "insights.totalRecurring.quarter")
        case .year:    return String(localized: "insights.totalRecurring.year")
        case .allTime: return String(localized: "insights.totalRecurring.month")
        }
    }

    // MARK: - Period End Date for a Key

    /// Returns the exclusive end `Date` for the period identified by `key`.
    /// Exclusive end is the first instant after the period completes (same convention as `dateRange()`).
    nonisolated func periodEnd(for key: String) -> Date {
        let start = periodStart(for: key)
        let calendar = Calendar.current
        switch self {
        case .week:    return calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        case .month:   return calendar.date(byAdding: .month,      value: 1, to: start) ?? start
        case .quarter: return calendar.date(byAdding: .month,      value: 3, to: start) ?? start
        case .year:    return calendar.date(byAdding: .year,       value: 1, to: start) ?? start
        case .allTime: return Date()
        }
    }

    // MARK: - Current Period Key

    /// Returns the grouping key for the current (today's) period.
    nonisolated var currentPeriodKey: String { groupingKey(for: Date()) }

    /// Returns the grouping key for the previous period (used for MoP comparison).
    nonisolated var previousPeriodKey: String {
        let calendar = Calendar.current
        let now = Date()
        let prev: Date
        switch self {
        case .week:    prev = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        case .month:   prev = calendar.date(byAdding: .month, value: -1, to: now)!
        case .quarter: prev = calendar.date(byAdding: .month, value: -3, to: now)!
        case .year:    prev = calendar.date(byAdding: .year, value: -1, to: now)!
        case .allTime: prev = now
        }
        return groupingKey(for: prev)
    }
}

// MARK: - Calendar helpers

private extension Calendar {
    nonisolated func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? date
    }

    nonisolated func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }

    nonisolated func startOfQuarter(for date: Date) -> Date {
        let m = component(.month, from: date)
        let qStartMonth = ((m - 1) / 3) * 3 + 1
        var comps = dateComponents([.year], from: date)
        comps.month = qStartMonth
        comps.day = 1
        return self.date(from: comps) ?? date
    }
}
