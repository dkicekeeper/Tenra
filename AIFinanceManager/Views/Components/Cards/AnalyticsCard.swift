//
//  AnalyticsCard.swift
//  AIFinanceManager
//
//  Analytics card component showing expense/income summary with progress bar
//

import SwiftUI

struct AnalyticsCard: View {
    let summary: Summary
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header
            HStack {
                Text(String(localized: "analytics.history", defaultValue: "History"))
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }

            // Progress bar with amounts
            ExpenseIncomeProgressBar(
                expenseAmount: summary.totalExpenses,
                incomeAmount: summary.totalIncome,
                currency: currency
            )

            // Planned amount
            if summary.plannedAmount > 0 {
                HStack {
                    Text(String(localized: "analytics.planned", defaultValue: "Planned"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()

                    FormattedAmountText(
                        amount: summary.plannedAmount,
                        currency: currency,
                        fontSize: AppTypography.body,
                        color: AppColors.textPrimary
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(radius: AppRadius.xl)
    }
}

#Preview {
    AnalyticsCard(
        summary: Summary(
            totalIncome: 10000,
            totalExpenses: 5000,
            totalInternalTransfers: 0,
            netFlow: 5000,
            currency: "KZT",
            startDate: "2024-01-01",
            endDate: "2024-01-31",
            plannedAmount: 2000
        ),
        currency: "KZT"
    )
    .padding()
}
