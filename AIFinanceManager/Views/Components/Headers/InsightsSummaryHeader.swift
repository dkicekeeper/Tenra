//
//  InsightsSummaryHeader.swift
//  AIFinanceManager
//
//  Phase 23: P7 — switched from MonthlyDataPoint to PeriodDataPoint.
//  Eliminates per-render .map { $0.asMonthlyDataPoint() } allocation in InsightsView.body.
//

import SwiftUI
import os

struct InsightsSummaryHeader: View {
    let totalIncome: Double
    let totalExpenses: Double
    let netFlow: Double
    let currency: String
    /// Phase 23 P7: PeriodDataPoint instead of MonthlyDataPoint — no conversion needed.
    let periodDataPoints: [PeriodDataPoint]
    /// Phase 24: optional financial health score shown as a compact badge.
    var healthScore: FinancialHealthScore? = nil

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "InsightsSummaryHeader")

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            InsightsTotalsRow(
                income: totalIncome,
                expenses: totalExpenses,
                netFlow: netFlow,
                currency: currency
            )

            // Phase 24 — Health score badge (shown only when score is available)
            if let hs = healthScore {
                HealthScoreBadge(score: hs)
            }

            // Mini trend chart.
            // Using cardBackground (not cardStyle) so clipShape doesn't cut Charts layers.
//            if periodDataPoints.count >= 2 {
//                PeriodIncomeExpenseChart(
//                    dataPoints: periodDataPoints,
//                    currency: currency,
//                    granularity: periodDataPoints.first?.granularity ?? .month,
//                    mode: .compact
//                )
//            }
        }
        .cardStyle(radius: AppRadius.xl)
        .onAppear {
            Self.logger.debug("📊 [SummaryHeader] RENDER — income=\(String(format: "%.0f", totalIncome), privacy: .public), expenses=\(String(format: "%.0f", totalExpenses), privacy: .public), net=\(String(format: "%.0f", netFlow), privacy: .public) \(currency, privacy: .public), pts=\(periodDataPoints.count)")
        }
    }

}

// MARK: - Previews

#Preview("With trend chart") {
    InsightsSummaryHeader(
        totalIncome: 530_000,
        totalExpenses: 320_000,
        netFlow: 210_000,
        currency: "KZT",
        periodDataPoints: PeriodDataPoint.mockMonthly()
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Negative net flow") {
    InsightsSummaryHeader(
        totalIncome: 280_000,
        totalExpenses: 340_000,
        netFlow: -60_000,
        currency: "KZT",
        periodDataPoints: PeriodDataPoint.mockMonthly()
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("No trend data") {
    InsightsSummaryHeader(
        totalIncome: 450_000,
        totalExpenses: 310_000,
        netFlow: 140_000,
        currency: "USD",
        periodDataPoints: []
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("With health score") {
    InsightsSummaryHeader(
        totalIncome: 530_000,
        totalExpenses: 320_000,
        netFlow: 210_000,
        currency: "KZT",
        periodDataPoints: PeriodDataPoint.mockMonthly(),
        healthScore: .mockGood()
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
