//
//  PeriodChartAdapters.swift
//  Tenra
//
//  Insight charts are DesignKit's trend charts (0.5.0): LineChart, BarChart,
//  ChartSwitcher, HeroSparkline and Sparkline (the former MiniSparkline) — the same
//  drawing code that used to live here, with the finance model taken out. This file
//  maps Tenra's model onto them and keeps the call sites' signatures
//  (`granularity:`, `currency:`):
//
//  - `PeriodDataPoint: ChartPoint` — axis label per granularity ("ЯНВ", "W07", "Q1"),
//    banner title (`granularity.bannerLabel`), period start for the Today marker, the
//    current period as not over (DesignKit 8.3.0: a fading bar, a dashed line, "so far")
//  - `PeriodChartSeries` → `ChartSeries<PeriodDataPoint>` (value, colouring, baseline,
//    which way is better, what a picked stretch sums up to); over a dataset it adds the same
//    period a year back and, for spending, where the current period is heading
//  - Today / empty-state texts from the insights strings
//

import SwiftUI

// MARK: - Series

/// Which value of a `PeriodDataPoint` an insight chart plots, and how it is coloured.
enum PeriodChartSeries {
    /// Spending trend: `expenses`, Y from 0, destructive.
    case spending
    /// Income trend: `income`, Y from 0, success.
    case income
    /// Average daily spending: `expenses / days-in-period`, Y from 0, destructive.
    case avgDailyExpenses
    /// Cash flow: `netFlow`, ± Y, green above zero / red below, dashed zero rule.
    case cashFlow
    /// Wealth: `cumulativeBalance` (falls back to `netFlow`), ± Y, accent, line 2.5.
    case wealth

    nonisolated func value(for point: PeriodDataPoint) -> Double {
        switch self {
        case .spending: return point.expenses
        case .income:   return point.income
        case .avgDailyExpenses:
            let days = Swift.max(1, Calendar.current.dateComponents([.day], from: point.periodStart, to: point.periodEnd).day ?? 1)
            return point.expenses / Double(days)
        case .cashFlow: return point.netFlow
        case .wealth:   return point.cumulativeBalance ?? point.netFlow
        }
    }

    /// The DesignKit series for this case. The name is what VoiceOver reads when a chart
    /// shows several series ("Income: …. Expenses: ….").
    var chart: ChartSeries<PeriodDataPoint> {
        series(projected: nil, comparison: nil)
    }

    /// The series over the points it is drawn with: the same period a year back (weeks,
    /// months, quarters) and, for spending, where the current period is heading. The person
    /// turns both on and off in the chart's options menu (`ChartOptionsHost`).
    func chart(in points: [PeriodDataPoint]) -> ChartSeries<PeriodDataPoint> {
        let history = PeriodChartHistory(points: points, series: self)
        return series(
            projected: self == .spending ? history.forecast : nil,
            comparison: history.hasYearAgo ? history.yearAgo : nil
        )
    }

    /// Which way the series is better: its change in the banner reads green that way, and
    /// its best finished period is a record.
    private var better: ChartBetter {
        switch self {
        case .spending, .avgDailyExpenses: return .lower
        case .income, .cashFlow, .wealth:  return .higher
        }
    }

    /// What a stretch picked with a long press sums up to: a total of the flows; the last
    /// value of a level (wealth) and of a daily average.
    private var rangeSummary: ChartRangeSummary {
        switch self {
        case .spending, .income, .cashFlow: return .total
        case .avgDailyExpenses, .wealth:    return .change
        }
    }

    private func series(
        projected: ((PeriodDataPoint) -> Double?)?,
        comparison: ((PeriodDataPoint) -> Double?)?
    ) -> ChartSeries<PeriodDataPoint> {
        let id: String
        let name: String
        let coloring: ChartColoring
        var baseline = ChartBaseline.zero
        var lineWidth: CGFloat = 2
        switch self {
        case .spending:
            id = "spending"
            name = String(localized: "insights.expenses")
            coloring = .solid(AppColors.destructive)
        case .income:
            id = "income"
            name = String(localized: "insights.income")
            coloring = .solid(AppColors.success)
        case .avgDailyExpenses:
            id = "avgDaily"
            name = String(localized: "insights.avgDailySpending")
            coloring = .solid(AppColors.destructive)
        case .cashFlow:
            id = "cashFlow"
            name = String(localized: "insights.cashFlow")
            coloring = .signed(positive: AppColors.success, negative: AppColors.destructive)
            baseline = .signed
        case .wealth:
            id = "wealth"
            name = String(localized: "insights.wealth")
            coloring = .solid(AppColors.accent)
            baseline = .signed
            lineWidth = 2.5
        }
        let series = self
        return ChartSeries(
            id: id, name: name, coloring: coloring, baseline: baseline, lineWidth: lineWidth,
            better: better, rangeSummary: rangeSummary,
            value: { series.value(for: $0) },
            projected: projected,
            comparison: comparison
        )
    }
}

/// What a series reads from the other points of its chart: the same period a year back, and
/// the forecast of the current period at the pace of the periods before it.
private struct PeriodChartHistory {
    private let points: [PeriodDataPoint]
    private let series: PeriodChartSeries

    init(points: [PeriodDataPoint], series: PeriodChartSeries) {
        self.points = points
        self.series = series
    }

    /// Weeks, months and quarters have a year ago; a year's is simply the period before.
    var hasYearAgo: Bool {
        switch points.first?.granularity {
        case .week, .month, .quarter: return true
        case .year, .allTime, nil:    return false
        }
    }

    /// The value of the period that held this period's start a year earlier, when the points
    /// reach back that far. The points are in time order: a binary search.
    func yearAgo(_ point: PeriodDataPoint) -> Double? {
        guard let target = Calendar.current.date(byAdding: .year, value: -1, to: point.periodStart),
              let first = points.first, target >= first.periodStart else { return nil }
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if points[mid].periodStart <= target { low = mid } else { high = mid - 1 }
        }
        let match = points[low]
        return target < match.periodEnd ? series.value(for: match) : nil
    }

    /// The current period's value so far plus the rest of it at the average of the last
    /// three finished periods. `nil` before a finished period, or with nothing spent in them.
    /// (The spending forecast insight also adds the subscriptions still due this month, so the
    /// two can differ by those.)
    func forecast(_ point: PeriodDataPoint) -> Double? {
        guard let index = points.firstIndex(where: { $0.id == point.id }), index > 0 else { return nil }
        let finished = points[max(0, index - 3)..<index].map { series.value(for: $0) }
        let typical = finished.reduce(0, +) / Double(finished.count)
        let length = point.periodEnd.timeIntervalSince(point.periodStart)
        guard typical > 0, length > 0 else { return nil }
        let elapsed = min(max(Date().timeIntervalSince(point.periodStart) / length, 0), 1)
        return series.value(for: point) + typical * (1 - elapsed)
    }
}

// MARK: - Points

extension PeriodDataPoint: ChartPoint {
    nonisolated var chartLabel: String { label }
    nonisolated var chartAxisLabel: String { PeriodAxisLabel.compact(for: self) }
    nonisolated var chartTitle: String { granularity.bannerLabel(for: key) }
    nonisolated var chartDate: Date? { periodStart }
    /// The current week, month, quarter or year is not over. All time is one period, never
    /// "so far".
    nonisolated var chartIsPartial: Bool {
        if case .allTime = granularity { return false }
        return periodEnd > Date()
    }
}

/// Compact X-axis label per granularity:
/// `.month` → "ЯНВ" / "ЯНВ'25", `.week` → "W07" / "W07'25", `.quarter` → "Q1" / "Q1'25",
/// `.year` → "2025", `.allTime` → the point's label. The year suffix appears only for
/// periods outside the current year.
nonisolated enum PeriodAxisLabel {
    /// Shared formatter: charts build their axis labels once per dataset, on the main actor.
    nonisolated(unsafe) private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    /// A month's start as the month charts label it: "ЯНВ", "ЯНВ'25" outside the current year
    /// (the merchant's and the category's 12 months).
    static func month(_ start: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: start)
        monthFormatter.locale = .current
        let month = String(monthFormatter.string(from: start).uppercased().prefix(3))
        return year == calendar.component(.year, from: Date()) ? month : "\(month)'\(String(format: "%02d", year % 100))"
    }

    static func compact(for point: PeriodDataPoint) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let pointYear = calendar.component(.year, from: point.periodStart)
        let shortYear = String(format: "%02d", pointYear % 100)

        switch point.granularity {
        case .month:
            monthFormatter.locale = .current
            let month = String(monthFormatter.string(from: point.periodStart).uppercased().prefix(3))
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

// MARK: - Texts and value format

private enum InsightChartText {
    static var today: String { String(localized: "insights.today") }
    static var emptyTitle: String { String(localized: "insights.empty.title") }
    static var emptyMessage: String { String(localized: "insights.empty.subtitle") }

    /// Banner / VoiceOver amounts: the currency when there is one, compact otherwise.
    static func valueFormat(_ currency: String) -> ChartValueFormat {
        currency.isEmpty ? .compact : .currency(currency)
    }
}

// MARK: - Call-site signatures

extension LineChart where Point == PeriodDataPoint {
    /// `granularity` is kept for call-site compatibility; titles come from each point.
    init(
        dataPoints: [PeriodDataPoint],
        series: [PeriodChartSeries],
        granularity: InsightGranularity,
        currency: String = "",
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.init(
            dataPoints: dataPoints,
            series: series.map { $0.chart(in: dataPoints) },
            valueFormat: InsightChartText.valueFormat(currency),
            todayText: InsightChartText.today,
            emptyTitle: InsightChartText.emptyTitle,
            emptyMessage: InsightChartText.emptyMessage,
            zoomScale: zoomScale
        )
    }

    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        granularity: InsightGranularity,
        currency: String = "",
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.init(dataPoints: dataPoints, series: [series], granularity: granularity,
                  currency: currency, zoomScale: zoomScale)
    }
}

extension BarChart where Point == PeriodDataPoint {
    /// `granularity` is kept for call-site compatibility; titles come from each point.
    init(
        dataPoints: [PeriodDataPoint],
        series: [PeriodChartSeries],
        granularity: InsightGranularity,
        currency: String = "",
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.init(
            dataPoints: dataPoints,
            series: series.map { $0.chart(in: dataPoints) },
            valueFormat: InsightChartText.valueFormat(currency),
            todayText: InsightChartText.today,
            emptyTitle: InsightChartText.emptyTitle,
            emptyMessage: InsightChartText.emptyMessage,
            zoomScale: zoomScale
        )
    }

    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        granularity: InsightGranularity,
        currency: String = "",
        zoomScale: Binding<CGFloat> = .constant(1.0)
    ) {
        self.init(dataPoints: dataPoints, series: [series], granularity: granularity,
                  currency: currency, zoomScale: zoomScale)
    }
}

extension ChartSwitcher where Point == PeriodDataPoint {
    /// `granularity` is kept for call-site compatibility; titles come from each point.
    init(
        dataPoints: [PeriodDataPoint],
        series: [PeriodChartSeries],
        granularity: InsightGranularity,
        currency: String = "",
        initialStyle: ChartStyle = .line
    ) {
        self.init(
            dataPoints: dataPoints,
            series: series.map { $0.chart(in: dataPoints) },
            valueFormat: InsightChartText.valueFormat(currency),
            todayText: InsightChartText.today,
            emptyTitle: InsightChartText.emptyTitle,
            emptyMessage: InsightChartText.emptyMessage,
            initialStyle: initialStyle
        )
    }

    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        granularity: InsightGranularity,
        currency: String = "",
        initialStyle: ChartStyle = .line
    ) {
        self.init(dataPoints: dataPoints, series: [series], granularity: granularity,
                  currency: currency, initialStyle: initialStyle)
    }
}

extension HeroSparkline where Point == PeriodDataPoint {
    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        projectedValue: Double? = nil,
        markExtremes: Bool = false,
        currency: String = "",
        entranceDelay: Double = 0
    ) {
        self.init(
            dataPoints: dataPoints,
            series: series.chart,
            projectedValue: projectedValue,
            markExtremes: markExtremes,
            valueFormat: InsightChartText.valueFormat(currency),
            entranceDelay: entranceDelay
        )
    }
}

// MARK: - Chart options

/// The person's chart options (DesignKit's `ChartDisplayOptions`: the average line, highs and
/// lows, the forecast, a year ago, a ruler the chart scrolls under), kept in `UserDefaults` and
/// handed to every chart of the app: the menu by a chart's zoom changes them for all of them.
/// Applied once, on `MainTabView`.
private struct ChartOptionsHost: ViewModifier {
    @AppStorage("charts.displayOptions") private var options = ChartDisplayOptions.standard

    func body(content: Content) -> some View {
        content.chartDisplayOptions($options)
    }
}

extension View {
    /// Every chart below follows the person's chart options (`ChartOptionsHost`).
    func chartOptionsHost() -> some View {
        modifier(ChartOptionsHost())
    }
}

/// The feed's Canvas sparkline is DesignKit's `Sparkline`.
typealias MiniSparkline = Sparkline

extension Sparkline {
    init(
        dataPoints: [PeriodDataPoint],
        series: PeriodChartSeries,
        lineWidth: CGFloat = 1.5,
        height: CGFloat = 60,
        endDotRadius: CGFloat = 3,
        projectedValue: Double? = nil,
        markExtremes: Bool = false
    ) {
        self.init(
            dataPoints: dataPoints,
            series: series.chart,
            lineWidth: lineWidth,
            height: height,
            endDotRadius: endDotRadius,
            projectedValue: projectedValue,
            markExtremes: markExtremes
        )
    }
}
