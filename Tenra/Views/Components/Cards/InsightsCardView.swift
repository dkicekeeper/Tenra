//
//  InsightsCardView.swift
//  Tenra
//
//  Phase 17: Financial Insights Feature
//  Insight card of the insights feed. Adapter over DesignKit's `MetricCard`: the insight
//  model and the choice of mini chart for each kind of insight stay here.
//

import SwiftUI

struct InsightsCardView<BottomChart: View>: View {
    let insight: Insight

    @ViewBuilder private let bottomChartContent: () -> BottomChart

    // MARK: - Init (backward compatible — no embedded chart)
    init(insight: Insight) where BottomChart == EmptyView {
        self.insight = insight
        self.bottomChartContent = { EmptyView() }
    }

    // MARK: - Init (with embedded full-size chart)
    init(insight: Insight, @ViewBuilder bottomChart: @escaping () -> BottomChart) {
        self.insight = insight
        self.bottomChartContent = bottomChart
    }

    private var hasBottomChart: Bool {
        BottomChart.self != EmptyView.self
    }

    /// Whether the trailing mini-chart overlay actually renders content for this
    /// insight. Must mirror the `miniChart` switch: when it resolves to EmptyView
    /// (formula breakdowns, lists, empty data), the text column takes the full
    /// card width instead of reserving a blank 120pt gutter.
    private var hasMiniChart: Bool {
        // Purpose-built visual wins over the detailData-derived fallback.
        if let visual = insight.cardVisual {
            switch visual {
            case .donut(let slices):            return !slices.isEmpty
            case .budgetBars(let bars):         return !bars.isEmpty
            case .sparkline(let points, _, _, _): return points.count >= 2
            case .proportionBar(let segments):  return !segments.isEmpty
            default:                            return true
            }
        }
        switch insight.detailData {
        case .categoryBreakdown(let items):
            return !items.isEmpty
        case .categoryBreakdownPaged(let pages):
            let current = pages.periods.indices.contains(pages.currentIndex)
                ? pages.periods[pages.currentIndex].items : []
            return !current.isEmpty
        case .budgetProgressList(let items):
            return !items.isEmpty
        case .periodTrend(let points):
            return !points.isEmpty
        case .recurringList, .accountComparison, .wealthBreakdown, .formulaBreakdown, nil:
            return false
        }
    }

    private var value: MetricCardValue {
        if let currency = insight.metric.currency {
            return .amount(insight.metric.value, currency: currency)
        }
        return .text(insight.metric.formattedValue)
    }

    private var trend: MetricCardTrend? {
        insight.trend.map { trend in
            MetricCardTrend(
                direction: trend.direction.badgeDirection,
                changePercent: trend.changePercent,
                color: insight.trendBadgeColorOverride ?? trend.trendColor
            )
        }
    }

    var body: some View {
        if hasBottomChart {
            // Full-size chart, injected via init(insight:bottomChart:), replaces the mini chart.
            MetricCard(
                title: insight.title,
                subtitle: insight.subtitle,
                value: value,
                unit: insight.metric.unit,
                trend: trend,
                chartPlacement: .bottom,
                chart: bottomChartContent
            )
        } else if hasMiniChart {
            MetricCard(
                title: insight.title,
                subtitle: insight.subtitle,
                value: value,
                unit: insight.metric.unit,
                trend: trend
            ) {
                miniChart
            }
        } else {
            // No mini chart for this insight: the text takes the full card width.
            MetricCard(
                title: insight.title,
                subtitle: insight.subtitle,
                value: value,
                unit: insight.metric.unit,
                trend: trend
            )
        }
    }

    // MARK: - Mini Chart

    @ViewBuilder
    private var miniChart: some View {
        // Purpose-built visual set by the generator (2026-07 visual refresh).
        // Falls back to the legacy detailData-derived chart when nil.
        if let visual = insight.cardVisual {
            cardVisualView(visual)
        } else {
            legacyMiniChart
        }
    }

    @ViewBuilder
    private func cardVisualView(_ visual: InsightCardVisual) -> some View {
        switch visual {
        case .barPair(let previous, let current, let color, let isProjection):
            MiniBarPair(previous: previous, current: current, color: color, isProjection: isProjection)
        case .halfGauge(let value, let norm, let color):
            MiniHalfGauge(value: value, norm: norm, color: color)
        case .ring(let progress, let isOverBudget):
            ProgressRing(
                progress: progress,
                size: 48,
                lineWidth: 5,
                isOverBudget: isOverBudget,
                animatesOnAppear: false, // LazyVStack feed — onAppear re-fires on scroll
                showsTrack: true
            )
        case .donut(let slices):
            MiniDonut(slices: slices)
        case .budgetBars(let bars):
            VStack(spacing: AppSpacing.sm) {
                ForEach(bars.prefix(3), id: \.id) { bar in
                    LinearProgressBar(
                        percentage: bar.percentage,
                        isOverBudget: bar.isOverBudget,
                        color: bar.color,
                        height: 5,
                        animatesOnAppear: false, // LazyVStack feed
                        projectedPercentage: bar.projectedPercentage
                    )
                }
            }
        case .milestoneGauge(let value, let target, let maxValue, let color):
            MiniMilestoneGauge(value: value, target: target, maxValue: maxValue, color: color)
        case .sparkline(let points, let series, let projectedValue, let markExtremes):
            MiniSparkline(
                dataPoints: points, // generator-shaped — no sparklineTail slice here
                series: series,
                projectedValue: projectedValue,
                markExtremes: markExtremes
            )
        case .proportionBar(let segments):
            MiniProportionBar(segments: segments)
        }
    }

    @ViewBuilder
    private var legacyMiniChart: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            // Canvas-based replacement for `DonutChart(mode: .compact)`. With
            // 25+ cards visible during scroll, instantiating Apple Charts per
            // mini-card dominated frame time when LazyVStack materialised a
            // section. See MiniDonut.swift header for the rationale.
            MiniDonut(slices: DonutSlice.from(items))
        case .categoryBreakdownPaged(let pages):
            // Mini donut reflects the current period (the page the detail view opens on).
            let current = pages.periods.indices.contains(pages.currentIndex)
                ? pages.periods[pages.currentIndex].items : []
            MiniDonut(slices: DonutSlice.from(current))
        case .budgetProgressList(let items):
            if let first = items.first {
                budgetProgressBar(first)
            }
        case .recurringList:
            EmptyView()
        case .accountComparison:
            EmptyView()
        case .periodTrend(let points):
            // Canvas-based replacement for `LineChart(mode: .compact)`.
            // Series matches the insight metric so the sparkline tracks the same
            // data the detail chart and list show. See MiniSparkline.swift header.
            MiniSparkline(
                dataPoints: sparklineTail(points),
                series: miniSparklineSeries
            )
        case .wealthBreakdown:
            // No mini chart for wealth breakdown (account list)
            EmptyView()
        case .formulaBreakdown:
            // No mini chart for formula breakdown — the hero metric is already in the card header
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    /// Recent tail of the period series for the 120×60pt sparkline. `.periodTrend`
    /// deliberately carries the FULL series for the detail view (domain contract —
    /// see docs/domains/insights.md), but at card scale dozens of points render as
    /// noise, and a historical outlier stretches the y-domain until the recent
    /// dynamics the trend badge describes go flat. Slicing here keeps the detail
    /// view untouched; the y-domain follows the visible slice automatically.
    private func sparklineTail(_ points: [PeriodDataPoint]) -> [PeriodDataPoint] {
        guard let granularity = points.first?.granularity else { return points }
        let limit: Int
        switch granularity {
        case .week:    limit = 12
        case .month:   limit = 12
        case .quarter: limit = 8
        case .year, .allTime: return points // few buckets by nature
        }
        return Array(points.suffix(limit))
    }

    /// Sparkline series matching the insight metric (mirrors InsightDetailView).
    private var miniSparklineSeries: PeriodChartSeries {
        switch insight.type {
        case .averageDailySpending: return .avgDailyExpenses
        case .monthOverMonthChange: return .spending
        case .incomeGrowth:         return .income
        default:                    return insight.category == .wealth ? .wealth : .cashFlow
        }
    }

    private func budgetProgressBar(_ item: BudgetInsightItem) -> some View {
        LinearProgressBar(
            percentage: item.percentage,
            isOverBudget: item.isOverBudget,
            color: item.color,
            height: 6,
            animatesOnAppear: false // insights feed is a LazyVStack — onAppear re-fires on scroll
        )
    }
}

// MARK: - Previews

#Preview("Spending — Top Category") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockTopSpending())
            InsightsCardView(insight: .mockMoM())
            InsightsCardView(insight: .mockAvgDaily())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("Income & Cash Flow") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockIncomeGrowth())
            InsightsCardView(insight: .mockCashFlow())
            InsightsCardView(insight: .mockProjectedBalance())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("Budget & Recurring") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockBudgetOver())
            InsightsCardView(insight: .mockRecurring())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("Savings & Forecasting") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockSavingsRate())
            InsightsCardView(insight: .mockForecasting())
            InsightsCardView(insight: .mockWealthBreakdown())
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}

#Preview("With Embedded Chart") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            InsightsCardView(insight: .mockCashFlow()) {
                LineChart(
                    dataPoints: PeriodDataPoint.mockMonthly(),
                    series: .cashFlow,
                    granularity: .month
                )
            }
            InsightsCardView(insight: .mockPeriodTrend()) {
                LineChart(
                    dataPoints: PeriodDataPoint.mockMonthly(),
                    series: .cashFlow,
                    granularity: .month
                )
            }
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}
