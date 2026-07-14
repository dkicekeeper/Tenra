//
//  AmountComparisonBar.swift
//  Tenra
//
//  Two amounts compared as a proportion bar with the values underneath
//  (e.g. expenses vs income on the home summary card). The bar itself is
//  a ProportionBar — this component only adds the amount labels.
//

import SwiftUI

struct AmountComparisonBar: View {
    let expenseAmount: Double
    let incomeAmount: Double
    let currency: String
    /// Sweep-from-zero entrance (see ProportionBar). Disable in lazy lists.
    var animatesOnAppear: Bool = true

    private var total: Double {
        expenseAmount + incomeAmount
    }

    private var expensePercent: Double {
        total > 0 ? max(0, min(1, expenseAmount / total)) : 0.0
    }

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            if total > 0 {
                ProportionBar(
                    ratio: expensePercent,
                    leftColor: AppColors.destructive,
                    rightColor: AppColors.income,
                    height: AppSpacing.md,
                    animatesOnAppear: animatesOnAppear
                )
            } else {
                // No data yet — keep the slot height stable with a muted track.
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .fill(AppColors.bgMuted)
                    .frame(height: AppSpacing.md)
            }

            // Amounts below the bar
            HStack {
                FormattedAmountText(
                    amount: expenseAmount,
                    currency: currency,
                    fontSize: AppTypography.h4,
                    fontWeight: .semibold,
                    color: AppColors.textPrimary
                )

                Spacer()

                FormattedAmountText(
                    amount: incomeAmount,
                    currency: currency,
                    fontSize: AppTypography.h4,
                    fontWeight: .semibold,
                    color: AppColors.income
                )
            }
        }
    }
}

#Preview {
    VStack(spacing: AppSpacing.lg) {
        AmountComparisonBar(
            expenseAmount: 5000,
            incomeAmount: 10000,
            currency: "KZT"
        )

        AmountComparisonBar(
            expenseAmount: 10000,
            incomeAmount: 5000,
            currency: "USD"
        )

        AmountComparisonBar(
            expenseAmount: 0,
            incomeAmount: 0,
            currency: "KZT"
        )
    }
    .padding()
}
