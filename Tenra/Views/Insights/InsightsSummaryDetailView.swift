//
//  InsightsSummaryDetailView.swift
//  Tenra
//
//  Phase 18: Financial Insights Feature
//  Full-screen detail view shown when the InsightsSummaryHeader is tapped.
//  Displays income, expenses, net flow for the current bucket (with MoM delta)
//  AND the all-time chart-window totals, plus the period-by-period income/expense
//  trend chart with a breakdown list.
//

import SwiftUI

/// Which metric the summary detail opens on. Each stat card in the Insights grid
/// drills into the same screen but focused on the number the card promised, instead
/// of every card landing on the same generic overview.
enum SummaryDetailFocus {
    case overview
    case expenses
    case income
    case netFlow

    var title: String {
        switch self {
        case .overview: return ""
        case .expenses: return String(localized: "insights.expenses")
        case .income:   return String(localized: "insights.income")
        case .netFlow:  return String(localized: "insights.netFlow")
        }
    }

    /// Series drawn in the trend chart.
    var chartSeries: [PeriodChartSeries] {
        switch self {
        case .overview: return [.income, .spending]
        case .expenses: return [.spending]
        case .income:   return [.income]
        case .netFlow:  return [.cashFlow]
        }
    }

    /// Value each period row surfaces. `.cashFlow` keeps the income/expense/net triple.
    var listMetric: PeriodListMetric {
        switch self {
        case .overview, .netFlow: return .cashFlow
        case .expenses:           return .expenses
        case .income:             return .income
        }
    }

    /// Reuses existing section titles — no new localization keys.
    /// (`insights.incomeGrowth` already reads "Income Trend" / "Тренд доходов".)
    var chartHeader: String {
        switch self {
        case .overview, .netFlow: return String(localized: "insights.cashFlowTrend")
        case .expenses:           return String(localized: "insights.spendingTrend")
        case .income:             return String(localized: "insights.incomeGrowth")
        }
    }

    var accentColor: Color {
        switch self {
        case .overview: return AppColors.textPrimary
        case .expenses: return AppColors.destructive
        case .income:   return AppColors.success
        case .netFlow:  return AppColors.textPrimary
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.bar"
        case .expenses: return "arrow.up.circle"
        case .income:   return "arrow.down.circle"
        case .netFlow:  return "arrow.left.arrow.right.circle"
        }
    }
}

struct InsightsSummaryDetailView: View {
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let currentBucketIncome: Double
    let currentBucketExpenses: Double
    let currentBucketNetFlow: Double
    let previousBucketIncome: Double
    let previousBucketExpenses: Double
    let previousBucketNetFlow: Double
    let bucketLabel: String
    let currency: String
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity
    /// Metric the screen opens on (set by the tapped stat card). `.overview` keeps the
    /// original all-three-totals behaviour used by the header tap.
    let focus: SummaryDetailFocus

    init(
        totalIncome: Double,
        totalExpenses: Double,
        netFlow: Double,
        currentBucketIncome: Double,
        currentBucketExpenses: Double,
        currentBucketNetFlow: Double,
        previousBucketIncome: Double,
        previousBucketExpenses: Double,
        previousBucketNetFlow: Double,
        bucketLabel: String,
        currency: String,
        periodDataPoints: [PeriodDataPoint],
        granularity: InsightGranularity,
        focus: SummaryDetailFocus = .overview
    ) {
        self.totalIncome = totalIncome
        self.totalExpenses = totalExpenses
        self.netFlow = netFlow
        self.currentBucketIncome = currentBucketIncome
        self.currentBucketExpenses = currentBucketExpenses
        self.currentBucketNetFlow = currentBucketNetFlow
        self.previousBucketIncome = previousBucketIncome
        self.previousBucketExpenses = previousBucketExpenses
        self.previousBucketNetFlow = previousBucketNetFlow
        self.bucketLabel = bucketLabel
        self.currency = currency
        self.periodDataPoints = periodDataPoints
        self.granularity = granularity
        self.focus = focus
    }

    /// Bucket value the focused metric shows in its hero.
    private var focusedAmount: Double {
        switch focus {
        case .overview: return currentBucketNetFlow
        case .expenses: return currentBucketExpenses
        case .income:   return currentBucketIncome
        case .netFlow:  return currentBucketNetFlow
        }
    }

    private var focusedPreviousAmount: Double {
        switch focus {
        case .overview: return previousBucketNetFlow
        case .expenses: return previousBucketExpenses
        case .income:   return previousBucketIncome
        case .netFlow:  return previousBucketNetFlow
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if focus == .overview {
                    // Single totals card for the current bucket — no period label and
                    // no delta badges (the granularity title and the chart provide context).
                    InsightsTotalsCard(
                        income: currentBucketIncome,
                        expenses: currentBucketExpenses,
                        netFlow: currentBucketNetFlow,
                        currency: currency
                    )
                    .screenPadding()
                } else {
                    focusedHero
                }

                // Full-size trend chart, scoped to the focused metric
                if periodDataPoints.count >= 2 {
                    chartSection
                }

                // Period breakdown list — same card shell as the other insight
                // detail lists (header outside, rows inside a .cardStyle() card).
                if !periodDataPoints.isEmpty {
                    InsightPeriodBreakdownList(
                        points: periodDataPoints,
                        granularity: granularity,
                        metric: focus.listMetric,
                        currency: currency
                    )
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitleText: String {
        if focus == .overview {
            return bucketLabel.isEmpty ? granularity.displayName : bucketLabel
        }
        return focus.title
    }

    // MARK: - Focused hero

    /// Hero for a single-metric drill-down: the metric's own amount for the bucket,
    /// then a comparison card against the previous bucket (the same card the category
    /// deep dive uses, so period-over-period reads identically across the feature).
    private var focusedHero: some View {
        VStack(spacing: AppSpacing.lg) {
            HeroSection(
                icon: .sfSymbol(focus.icon),
                title: focus.title,
                iconTint: .monochrome(focus.accentColor),
                primaryAmount: focusedAmount,
                primaryCurrency: currency,
                primaryAmountColor: focus == .netFlow && focusedAmount < 0
                    ? AppColors.destructive
                    : focus.accentColor,
                subtitle: bucketLabel.isEmpty ? granularity.displayName : bucketLabel
            )

            if focusedPreviousAmount != 0 {
                PeriodComparisonCard(
                    currentLabel: bucketLabel.isEmpty ? granularity.displayName : bucketLabel,
                    currentAmount: focusedAmount,
                    previousLabel: granularity.headingLabel(for: granularity.previousPeriodKey),
                    previousAmount: focusedPreviousAmount,
                    currency: currency,
                    isExpenseContext: focus == .expenses
                )
                .screenPadding()
            }
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(focus.chartHeader, style: .large)
                .padding(.top, AppSpacing.lg)

            // Chart bleeds edge-to-edge so the scrollable plot area aligns
            // with the screen edges. Apple Charts with chartScrollableAxes
            // looks clipped if a horizontal padding is applied to the parent.
            ChartSwitcher(
                dataPoints: periodDataPoints,
                series: focus.chartSeries,
                granularity: granularity,
                currency: currency,
                initialStyle: .bar
            )
        }
    }
}

// MARK: - Previews

#Preview("Monthly") {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 5_450_387,
            totalExpenses: 1_904_618,
            netFlow: 3_545_769,
            currentBucketIncome: 530_000,
            currentBucketExpenses: 320_000,
            currentBucketNetFlow: 210_000,
            previousBucketIncome: 480_000,
            previousBucketExpenses: 350_000,
            previousBucketNetFlow: 130_000,
            bucketLabel: "May 2026",
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockMonthly(),
            granularity: .month
        )
    }
}

#Preview("Focused — expenses") {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 5_450_387,
            totalExpenses: 1_904_618,
            netFlow: 3_545_769,
            currentBucketIncome: 530_000,
            currentBucketExpenses: 320_000,
            currentBucketNetFlow: 210_000,
            previousBucketIncome: 480_000,
            previousBucketExpenses: 350_000,
            previousBucketNetFlow: 130_000,
            bucketLabel: "May 2026",
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockMonthly(),
            granularity: .month,
            focus: .expenses
        )
    }
}

#Preview("Weekly") {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 1_200_000,
            totalExpenses: 840_000,
            netFlow: 360_000,
            currentBucketIncome: 100_000,
            currentBucketExpenses: 78_000,
            currentBucketNetFlow: 22_000,
            previousBucketIncome: 95_000,
            previousBucketExpenses: 80_000,
            previousBucketNetFlow: 15_000,
            bucketLabel: "Last 7 days",
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockWeekly(),
            granularity: .week
        )
    }
}

#Preview("All time") {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 12_400_000,
            totalExpenses: 8_900_000,
            netFlow: 3_500_000,
            currentBucketIncome: 12_400_000,
            currentBucketExpenses: 8_900_000,
            currentBucketNetFlow: 3_500_000,
            previousBucketIncome: 12_400_000,
            previousBucketExpenses: 8_900_000,
            previousBucketNetFlow: 3_500_000,
            bucketLabel: "All time",
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockMonthly(),
            granularity: .allTime
        )
    }
}
