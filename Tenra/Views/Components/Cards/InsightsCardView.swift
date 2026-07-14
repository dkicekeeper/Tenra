//
//  InsightsCardView.swift
//  Tenra
//
//  Phase 17: Financial Insights Feature
//  Reusable insight card with mini-chart, metric, and trend indicator
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

    // Mini-chart footprint. The chart is overlaid (not a layout sibling) so it can
    // bleed to the card's trailing edge; the text column reserves matching room so
    // titles/amounts/badges never run underneath it. Keep these in sync.
    private static var miniChartWidth: CGFloat { 120 }
    private static var miniChartHeight: CGFloat { 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Text column. Reserves trailing room for the mini-chart overlay below
            // so the title and amount+badge row can't collide with it.
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(insight.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
//                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.subtitle)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(3)

                metricRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep clear of the full-bleed mini-chart; full width when a bottom chart
            // replaces it OR when this insight renders no mini-chart at all.
            .padding(.trailing, (hasBottomChart || !hasMiniChart) ? 0 : Self.miniChartWidth + AppSpacing.sm)

            // Full-size chart — shown only when injected via init(insight:bottomChart:)
            if hasBottomChart {
                bottomChartContent()
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        // Mini chart overlaid OUTSIDE the clip region so it can bleed to the trailing edge.
        // Hidden when a full-size bottom chart is injected.
        .overlay(alignment: .trailing) {
            if !hasBottomChart && hasMiniChart {
                miniChart
                    .frame(width: Self.miniChartWidth, height: Self.miniChartHeight)
//                    .padding(.top, AppSpacing.lg)
                    .padding(.trailing, AppSpacing.lg)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Metric Row

    /// Amount (+ optional unit) with the trend badge. Keeps both on one line when they
    /// fit the reserved width, otherwise drops the badge to a second line.
    @ViewBuilder
    private var metricRow: some View {
        if insight.trend != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    amountWithUnit
                    trendBadge
                }
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    amountWithUnit
                    trendBadge
                }
            }
        } else {
            amountWithUnit
        }
    }

    @ViewBuilder
    private var amountWithUnit: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            // Large metric — use FormattedAmountText for currency amounts
            if let currency = insight.metric.currency {
                FormattedAmountText(
                    amount: insight.metric.value,
                    currency: currency,
                    fontSize: AppTypography.h2,
                    fontWeight: .bold,
                    color: AppColors.textPrimary
                )
            } else {
                Text(insight.metric.formattedValue)
                    .font(AppTypography.h2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.textPrimary)
            }

            if let unit = insight.metric.unit {
                Text(unit)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var trendBadge: some View {
        if let trend = insight.trend {
            InsightTrendBadge(trend: trend, style: .pill, colorOverride: insight.trendBadgeColorOverride)
        }
    }

    // MARK: - Mini Chart

    @ViewBuilder
    private var miniChart: some View {
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
                dataPoints: points,
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
