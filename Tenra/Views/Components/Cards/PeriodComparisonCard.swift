//
//  PeriodComparisonCard.swift
//  Tenra
//
//  Period-over-period comparison card (current vs previous).
//  Extracted from InsightDeepDiveView.comparisonSection — Phase 26.
//

import SwiftUI

/// Glass card comparing two adjacent time periods.
/// Shows: current amount | direction arrow + change% | previous amount.
///
/// - Parameter isExpenseContext: if true, an increase is shown in red (costs more = bad).
///   If false (income), an increase is shown in green (earns more = good).
struct PeriodComparisonCard: View {
    let currentLabel: String
    let currentAmount: Double
    let previousLabel: String
    let previousAmount: Double
    let currency: String
    var isExpenseContext: Bool = true

    private var change: Double {
        guard previousAmount > 0 else { return 0 }
        return ((currentAmount - previousAmount) / previousAmount) * 100
    }

    private var direction: TrendDirection {
        change > 2 ? .up : (change < -2 ? .down : .flat)
    }

    private var changeColor: Color {
        switch direction {
        case .up: return isExpenseContext ? AppColors.destructive : AppColors.success
        case .down: return isExpenseContext ? AppColors.success : AppColors.destructive
        case .flat: return AppColors.textSecondary
        }
    }

    var body: some View {
        HStack {
            // Previous period
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(previousLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                FormattedAmountText(
                    amount: previousAmount,
                    currency: currency,
                    fontSize: AppTypography.h3,
                    fontWeight: .semibold,
                    color: AppColors.textSecondaryAccessible
                )
            }

            Spacer()

            // Change indicator
            InsightTrendBadge(
                trend: InsightTrend(
                    direction: direction,
                    changePercent: change,
                    changeAbsolute: nil,
                    comparisonPeriod: ""
                ),
                style: .changeIndicator,
                colorOverride: changeColor
            )

            Spacer()

            // Current period
            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(currentLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                FormattedAmountText(
                    amount: currentAmount,
                    currency: currency,
                    fontSize: AppTypography.h3,
                    fontWeight: .bold,
                    color: AppColors.textPrimary
                )
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

// MARK: - Previews

#Preview("Expense increase (bad)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 120_000,
        previousLabel: "Jan 2026", previousAmount: 95_000,
        currency: "KZT", isExpenseContext: true
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Expense decrease (good)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 75_000,
        previousLabel: "Jan 2026", previousAmount: 95_000,
        currency: "KZT", isExpenseContext: true
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Income increase (good)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 620_000,
        previousLabel: "Jan 2026", previousAmount: 530_000,
        currency: "KZT", isExpenseContext: false
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
