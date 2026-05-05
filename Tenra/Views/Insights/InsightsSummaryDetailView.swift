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
        granularity: InsightGranularity
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
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Single totals card for the current bucket — no period label and
                // no delta badges (the granularity title and the chart provide context).
                InsightsTotalsCard(
                    income: currentBucketIncome,
                    expenses: currentBucketExpenses,
                    netFlow: currentBucketNetFlow,
                    currency: currency
                )
                .screenPadding()

                // Full-size income/expense chart
                if periodDataPoints.count >= 2 {
                    chartSection
                }

                // Period breakdown list
                if !periodDataPoints.isEmpty {
                    periodListSection
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(bucketLabel.isEmpty ? granularity.displayName : bucketLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "insights.cashFlowTrend"), style: .large)
                .padding(.top, AppSpacing.lg)

            // Chart bleeds edge-to-edge so the scrollable plot area aligns
            // with the screen edges. Apple Charts with chartScrollableAxes
            // looks clipped if a horizontal padding is applied to the parent.
            PeriodChartSwitcher(
                dataPoints: periodDataPoints,
                currency: currency,
                granularity: granularity
            )
        }
    }

    // MARK: - Period List

    private var periodListSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeaderView(String(localized: "insights.monthlyBreakdown"), style: .large)

            ForEach(periodDataPoints.reversed()) { point in
                PeriodBreakdownRow(
                    label: point.label,
                    income: point.income,
                    expenses: point.expenses,
                    netFlow: point.netFlow,
                    currency: currency,
                    showDivider: true,
                    labelMinWidth: 80
                )
            }
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
