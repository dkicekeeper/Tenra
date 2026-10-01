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
//    banner title (`granularity.bannerLabel`), period start for the Today marker
//  - `PeriodChartSeries` → `ChartSeries<PeriodDataPoint>` (value, colouring, baseline)
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
        switch self {
        case .spending:
            return ChartSeries(id: "spending", name: String(localized: "insights.expenses"),
                               coloring: .solid(AppColors.destructive)) { PeriodChartSeries.spending.value(for: $0) }
        case .income:
            return ChartSeries(id: "income", name: String(localized: "insights.income"),
                               coloring: .solid(AppColors.success)) { PeriodChartSeries.income.value(for: $0) }
        case .avgDailyExpenses:
            return ChartSeries(id: "avgDaily", name: String(localized: "insights.avgDailySpending"),
                               coloring: .solid(AppColors.destructive)) { PeriodChartSeries.avgDailyExpenses.value(for: $0) }
        case .cashFlow:
            return ChartSeries(id: "cashFlow", name: String(localized: "insights.cashFlow"),
                               coloring: .signed(positive: AppColors.success, negative: AppColors.destructive),
                               baseline: .signed) { PeriodChartSeries.cashFlow.value(for: $0) }
        case .wealth:
            return ChartSeries(id: "wealth", name: String(localized: "insights.wealth"),
                               coloring: .solid(AppColors.accent),
                               baseline: .signed,
                               lineWidth: 2.5) { PeriodChartSeries.wealth.value(for: $0) }
        }
    }
}

// MARK: - Points

extension PeriodDataPoint: ChartPoint {
    nonisolated var chartLabel: String { label }
    nonisolated var chartAxisLabel: String { PeriodAxisLabel.compact(for: self) }
    nonisolated var chartTitle: String { granularity.bannerLabel(for: key) }
    nonisolated var chartDate: Date? { periodStart }
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
            series: series.map(\.chart),
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
            series: series.map(\.chart),
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
            series: series.map(\.chart),
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
