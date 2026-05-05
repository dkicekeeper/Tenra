//
//  InsightsTotalsCard.swift
//  Tenra
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
    /// Localised label for the period being shown ("May 2026", "Q2 2026", "Last 7 days", "All time").
    /// When `nil` the period row is hidden.
    var periodLabel: String? = nil
    /// Optional previous-bucket totals for delta indicators. Pass `nil` to hide deltas.
    var previousIncome: Double? = nil
    var previousExpenses: Double? = nil
    var previousNetFlow: Double? = nil
    /// Font for the amount values (default .body matches both callers).
    var amountFont: Font = AppTypography.body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let label = periodLabel {
                Text(label)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.textSecondary)
//                    .textCase(.uppercase)
            }

            HStack(alignment: .top, spacing: AppSpacing.xs) {
                totalItem(
                    title: String(localized: "insights.income"),
                    amount: income,
                    previous: previousIncome,
                    color: AppColors.success,
                    upIsGood: true
                )
                Spacer()
                totalItem(
                    title: String(localized: "insights.expenses"),
                    amount: expenses,
                    previous: previousExpenses,
                    color: AppColors.destructive,
                    upIsGood: false
                )
                Spacer()
                totalItem(
                    title: String(localized: "insights.netFlow"),
                    amount: netFlow,
                    previous: previousNetFlow,
                    color: netFlow >= 0 ? AppColors.textPrimary : AppColors.destructive,
                    upIsGood: true
                )
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func totalItem(
        title: String,
        amount: Double,
        previous: Double?,
        color: Color,
        upIsGood: Bool
    ) -> some View {
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

            if let prev = previous {
                Self.deltaBadge(current: amount, previous: prev, upIsGood: upIsGood)
            }
        }
    }

    /// Builds a tiny delta badge ("+12%" / "−4%") coloured by direction.
    /// Returns EmptyView when previous is zero (delta undefined) or values are equal.
    @ViewBuilder
    private static func deltaBadge(current: Double, previous: Double, upIsGood: Bool) -> some View {
        if abs(previous) > 0.01 {
            let delta = ((current - previous) / abs(previous)) * 100
            if abs(delta) >= 0.5 {
                let isUp = delta > 0
                let color: Color = (isUp == upIsGood) ? AppColors.success : AppColors.destructive
                HStack(spacing: 2) {
                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.0f%%", abs(delta)))
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(color)
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

#Preview("Positive — with deltas") {
    InsightsTotalsCard(
        income: 530_000, expenses: 320_000, netFlow: 210_000,
        currency: "KZT",
        periodLabel: "May 2026",
        previousIncome: 480_000, previousExpenses: 350_000, previousNetFlow: 130_000
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("All-time — no deltas") {
    InsightsTotalsCard(
        income: 12_400_000, expenses: 8_900_000, netFlow: 3_500_000,
        currency: "KZT",
        periodLabel: "All time"
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Negative net flow") {
    InsightsTotalsCard(
        income: 280_000, expenses: 340_000, netFlow: -60_000,
        currency: "KZT",
        periodLabel: "Q2 2026",
        previousIncome: 290_000, previousExpenses: 300_000, previousNetFlow: -10_000
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
