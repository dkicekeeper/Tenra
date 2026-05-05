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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header: title + conditional mini-chart overlay
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Text(insight.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()
            }
            // Mini chart rendered OUTSIDE clip region to avoid being clipped.
            // Hidden when a full-size bottom chart is injected.
            .overlay(alignment: .topTrailing) {
                if !hasBottomChart {
                    miniChart
                        .frame(width: 120, height: 100)
                }
            }

            Text(insight.subtitle)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: AppSpacing.sm) {
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

                // Trend indicator
                if let trend = insight.trend {
                    InsightTrendBadge(trend: trend, style: .pill, colorOverride: insight.trendBadgeColorOverride)
                }
                if let unit = insight.metric.unit {
                    Text(unit)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Full-size chart — shown only when injected via init(insight:bottomChart:)
            if hasBottomChart {
                bottomChartContent()
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
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
        case .budgetProgressList(let items):
            if let first = items.first {
                budgetProgressBar(first)
            }
        case .recurringList:
            EmptyView()
        case .accountComparison:
            EmptyView()
        case .periodTrend(let points):
            // Canvas-based replacement for `PeriodLineChart(mode: .compact)`.
            // See MiniSparkline.swift header for the rationale.
            MiniSparkline(
                dataPoints: points,
                series: insight.category == .wealth ? .wealth : .cashFlow
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

    private func budgetProgressBar(_ item: BudgetInsightItem) -> some View {
        BudgetProgressBar(
            percentage: item.percentage,
            isOverBudget: item.isOverBudget,
            color: item.color,
            height: 6
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
                PeriodLineChart(
                    dataPoints: PeriodDataPoint.mockMonthly(),
                    series: .cashFlow,
                    granularity: .month,
                    mode: .full
                )
            }
            InsightsCardView(insight: .mockPeriodTrend()) {
                PeriodLineChart(
                    dataPoints: PeriodDataPoint.mockMonthly(),
                    series: .cashFlow,
                    granularity: .month,
                    mode: .full
                )
            }
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}
