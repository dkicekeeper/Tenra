//
//  InsightsStatCard.swift
//  Tenra
//
//  Single-metric stat card used in the Insights summary 2×2 grid
//  (Available balance / Expenses / Income / Net flow). Split out of the
//  former 3-column InsightsTotalsCard so each metric gets its own card.
//

import SwiftUI

/// A compact card showing one labeled financial metric with an optional
/// previous-period delta badge. Designed to tile in a 2-column grid.
struct InsightsStatCard: View {
    let title: String
    let amount: Double
    let currency: String
    /// Value color (e.g. green income, red expenses, contextual net flow).
    var color: Color = AppColors.textPrimary
    /// Optional previous-bucket value for the delta badge. `nil` hides the badge.
    var previous: Double? = nil
    /// Whether an increase is good (income, net flow) or bad (expenses) — colours the delta.
    var upIsGood: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: AppTypography.h3,
                fontWeight: .semibold,
                color: color
            )
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            if let previous {
                Self.deltaBadge(current: amount, previous: previous, upIsGood: upIsGood)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    /// Tiny "+12%" / "−4%" badge coloured by direction. EmptyView when the delta
    /// is undefined (previous ≈ 0) or negligible.
    @ViewBuilder
    private static func deltaBadge(current: Double, previous: Double, upIsGood: Bool) -> some View {
        if abs(previous) > 0.01 {
            let delta = ((current - previous) / abs(previous)) * 100
            if abs(delta) >= 0.5 {
                let isUp = delta > 0
                let color: Color = (isUp == upIsGood) ? AppColors.success : AppColors.destructive
                HStack(spacing: 2) {
                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: AppIconSize.sm, weight: .bold))
                    Text(String(format: "%.0f%%", abs(delta)))
                        .font(AppTypography.bodyEmphasis)
                }
                .foregroundStyle(color)
            }
        }
    }
}

// MARK: - Previews

#Preview("2×2 grid") {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md),
                        GridItem(.flexible(), spacing: AppSpacing.md)],
              spacing: AppSpacing.md) {
        InsightsStatCard(title: "Доступный баланс", amount: 1_240_000, currency: "KZT")
        InsightsStatCard(title: "Чистый поток", amount: 210_000, currency: "KZT",
                         previous: 130_000, upIsGood: true)
        InsightsStatCard(title: "Расходы", amount: 320_000, currency: "KZT",
                         color: AppColors.destructive, previous: 350_000, upIsGood: false)
        InsightsStatCard(title: "Доходы", amount: 530_000, currency: "KZT",
                         color: AppColors.success, previous: 480_000, upIsGood: true)
    }
    .screenPadding()
}
