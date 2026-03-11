//
//  PeriodBreakdownRow.swift
//  AIFinanceManager
//
//  Single period row showing net flow + income/expenses breakdown.
//  Extracted from InsightDetailView and InsightsSummaryDetailView (Phase 26).
//

import SwiftUI

/// One row in a period breakdown list (week / month / quarter / year).
/// Shows label on the left, netFlow + income/expenses on the right.
/// - Parameter showDivider: adds a `Divider` at the bottom (InsightsSummaryDetailView)
/// - Parameter labelMinWidth: optional min width for the label column (InsightsSummaryDetailView)
struct PeriodBreakdownRow: View {
    let label: String
    let income: Double
    let expenses: Double
    let netFlow: Double
    let currency: String
    var showDivider: Bool = false
    var labelMinWidth: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
//                    .frame(minWidth: labelMinWidth, alignment: .leading)

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    FormattedAmountText(
                        amount: netFlow,
                        currency: currency,
                        fontSize: AppTypography.body,
                        fontWeight: .semibold,
                        color: netFlow >= 0 ? AppColors.textPrimary : AppColors.destructive
                    )
                    HStack(spacing: AppSpacing.md) {
                        FormattedAmountText(
                            amount: income,
                            currency: currency,
                            prefix: "+",
                            fontSize: AppTypography.caption,
                            fontWeight: .regular,
                            color: AppColors.success
                        )
                        FormattedAmountText(
                            amount: expenses,
                            currency: currency,
                            prefix: "-",
                            fontSize: AppTypography.caption,
                            fontWeight: .regular,
                            color: AppColors.destructive
                        )
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
            .screenPadding()

            if showDivider {
                Divider()
                    .padding(.horizontal, AppSpacing.lg)
            }
        }
    }
}

// MARK: - Previews

#Preview("Without divider") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Jan 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT")
        PeriodBreakdownRow(label: "Dec 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT")
        PeriodBreakdownRow(label: "Nov 2025", income: 510_000, expenses: 540_000, netFlow: -30_000, currency: "KZT")
    }
}

#Preview("With divider + minWidth") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Jan 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT", showDivider: true, labelMinWidth: 80)
        PeriodBreakdownRow(label: "Dec 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT", showDivider: true, labelMinWidth: 80)
    }
}
