//
//  SpentBudgetText.swift
//  Tenra
//
//  "spent / budget" amount pair shared by CategoryRow and BudgetProgressRow.
//

import SwiftUI

/// Renders `spent / budget` as two `FormattedAmountText` values around a slash.
/// Font, weight and colors are configurable so both the management-list style
/// (bodySmall, over-budget tinting) and the insights card style (caption,
/// tertiary separator) route through one implementation.
struct SpentBudgetText: View {
    let spent: Double
    let budget: Double
    let currency: String
    var font: Font = AppTypography.bodySmall
    var fontWeight: Font.Weight = .regular
    var amountColor: Color = AppColors.textSecondary
    var separatorColor: Color = AppColors.textSecondary

    var body: some View {
        HStack(spacing: 0) {
            FormattedAmountText(
                amount: spent,
                currency: currency,
                fontSize: font,
                fontWeight: fontWeight,
                color: amountColor
            )
            Text(" / ")
                .font(font)
                .foregroundStyle(separatorColor)
            FormattedAmountText(
                amount: budget,
                currency: currency,
                fontSize: font,
                fontWeight: fontWeight,
                color: amountColor
            )
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
        SpentBudgetText(spent: 42_000, budget: 60_000, currency: "KZT")
        SpentBudgetText(
            spent: 72_000, budget: 60_000, currency: "KZT",
            amountColor: AppColors.destructive, separatorColor: AppColors.destructive
        )
        SpentBudgetText(
            spent: 42_000, budget: 60_000, currency: "KZT",
            font: AppTypography.caption, separatorColor: AppColors.textTertiary
        )
    }
    .padding()
}
