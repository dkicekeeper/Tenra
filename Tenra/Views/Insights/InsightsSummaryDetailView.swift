//
//  InsightsSummaryDetailView.swift
//  AIFinanceManager
//
//  Phase 18: Financial Insights Feature
//  Full-screen detail view shown when the InsightsSummaryHeader is tapped.
//  Displays income, expenses, net flow for all time and the
//  period-by-period income/expense trend chart with a breakdown list.
//

import SwiftUI

struct InsightsSummaryDetailView: View {
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let currency: String
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity

    init(
        totalIncome: Double,
        totalExpenses: Double,
        netFlow: Double,
        currency: String,
        periodDataPoints: [PeriodDataPoint],
        granularity: InsightGranularity
    ) {
        self.totalIncome = totalIncome
        self.totalExpenses = totalExpenses
        self.netFlow = netFlow
        self.currency = currency
        self.periodDataPoints = periodDataPoints
        self.granularity = granularity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // Period totals
                periodTotalsSection

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
        .navigationTitle(granularity.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Period Totals

    private var periodTotalsSection: some View {
        InsightsTotalsCard(
            income: totalIncome,
            expenses: totalExpenses,
            netFlow: netFlow,
            currency: currency
        )
        .cardStyle(radius: AppRadius.xl)
        .screenPadding()
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeaderView(String(localized: "insights.cashFlowTrend"), style: .large)
                .padding(.top, AppSpacing.lg)

            PeriodBarChart(
                dataPoints: periodDataPoints,
                currency: currency,
                granularity: granularity,
                mode: .full
            )
        }
//        .cardBackground(radius: AppRadius.xl)
//        .screenPadding()
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
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockWeekly(),
            granularity: .week
        )
    }
}

#Preview("Quarterly") {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 5_450_387,
            totalExpenses: 1_904_618,
            netFlow: 3_545_769,
            currency: "KZT",
            periodDataPoints: PeriodDataPoint.mockQuarterly(),
            granularity: .quarter
        )
    }
}
