//
//  InsightsTotalsCard.swift
//  AIFinanceManager
//
//  Three-column income / expenses / net-flow summary card.
//  Extracted from InsightsSummaryHeader (summaryItem) and
//  InsightsSummaryDetailView (totalItem) — Phase 26.
//

import SwiftUI

/// Horizontal card with three labeled financial totals: income, expenses, net flow.
/// Used inside glass cards in the Insights summary header and summary detail view.
struct InsightsTotalsCard: View {
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
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func totalItem(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .center, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)

            if abs(amount) >= 1_000_000 {
                let symbol = Formatting.currencySymbol(for: currency)
                Text(Self.compactAmount(amount) + " " + symbol)
                    .font(amountFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .animation(AppAnimation.gentleSpring, value: amount)
            } else {
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

    /// Compact formatting for millions: 1M, 2.34M, -12.5M
    private static func compactAmount(_ value: Double) -> String {
        let absValue = abs(value)
        let millions = absValue / 1_000_000
        let sign = value < 0 ? "-" : ""

        if millions == millions.rounded(.down) {
            return "\(sign)\(Int(millions))M"
        } else {
            let formatted = String(format: "%.2f", millions)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
            return "\(sign)\(formatted)M"
        }
    }
}

// MARK: - Previews

#Preview("Positive") {
    InsightsTotalsCard(income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT")
        .screenPadding()
        .padding(.vertical)
}

#Preview("Millions") {
    InsightsTotalsCard(income: 2_340_000, expenses: 1_500_000, netFlow: 840_000, currency: "KZT")
        .screenPadding()
        .padding(.vertical)
}

#Preview("Negative net flow") {
    InsightsTotalsCard(income: 280_000, expenses: 340_000, netFlow: -60_000, currency: "KZT")
        .screenPadding()
        .padding(.vertical)
}
