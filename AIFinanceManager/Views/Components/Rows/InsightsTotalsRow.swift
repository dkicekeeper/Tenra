//
//  InsightsTotalsRow.swift
//  AIFinanceManager
//
//  Three-column income / expenses / net-flow summary row.
//  Extracted from InsightsSummaryHeader (summaryItem) and
//  InsightsSummaryDetailView (totalItem) — Phase 26.
//

import SwiftUI

/// Horizontal row with three labeled financial totals: income, expenses, net flow.
/// Used inside glass cards in the Insights summary header and summary detail view.
struct InsightsTotalsRow: View {
    let income: Double
    let expenses: Double
    let netFlow: Double
    let currency: String
    /// Font for the amount values (default .bodySmall matches both callers).
    var amountFont: Font = AppTypography.body

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            totalItem(
                title: String(localized: "insights.income"),
                amount: income,
                color: AppColors.success
            )
            Spacer()
            totalItem(
                title: String(localized: "insights.expenses"),
                amount: expenses,
                color: AppColors.destructive
            )
            Spacer()
            totalItem(
                title: String(localized: "insights.netFlow"),
                amount: netFlow,
                color: netFlow >= 0 ? AppColors.textPrimary : AppColors.destructive
            )
        }
    }

    private func totalItem(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .center, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: amountFont,
                fontWeight: .semibold,
                color: color
            )
        }
    }
}

// MARK: - Previews

#Preview("Positive") {
    InsightsTotalsRow(income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT")
        .cardStyle(radius: AppRadius.xl)
        .screenPadding()
        .padding(.vertical)
}

#Preview("Negative net flow") {
    InsightsTotalsRow(income: 280_000, expenses: 340_000, netFlow: -60_000, currency: "KZT")
        .cardStyle(radius: AppRadius.xl)
        .screenPadding()
        .padding(.vertical)
}
