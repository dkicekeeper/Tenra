//
//  ExpenseIncomeProgressBar.swift
//  AIFinanceManager
//
//  Progress bar component showing expense and income amounts
//

import SwiftUI

struct ExpenseIncomeProgressBar: View {
    let expenseAmount: Double
    let incomeAmount: Double
    let currency: String

    @State private var displayExpensePercent: Double = 0
    @State private var displayIncomePercent: Double = 0

    private var total: Double {
        expenseAmount + incomeAmount
    }

    private var expensePercent: Double {
        total > 0 ? max(0, min(1, expenseAmount / total)) : 0.0
    }

    private var incomePercent: Double {
        total > 0 ? max(0, min(1, incomeAmount / total)) : 0.0
    }

    private static let barAnimation = Animation.spring(response: 0.55, dampingFraction: 0.72)

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            // Progress bar
            GeometryReader { geometry in
                HStack(spacing: AppSpacing.xs) {
                    // Always render both bars; animated width drives show/hide naturally.
                    if expensePercent > 0 || displayExpensePercent > 0 {
                        Rectangle()
                            .foregroundStyle(AppColors.destructive)
                            .frame(width: geometry.size.width * displayExpensePercent)
                            .clipShape(.rect(cornerRadius: AppRadius.sm))
                            .shadow(color: AppColors.destructive.opacity(0.3), radius: 8)
                    }
                    if incomePercent > 0 || displayIncomePercent > 0 {
                        Rectangle()
                            .foregroundStyle(AppColors.income)
                            .frame(width: geometry.size.width * displayIncomePercent)
                            .clipShape(.rect(cornerRadius: AppRadius.sm))
                            .shadow(color: AppColors.income.opacity(0.3), radius: 8)
                    }
                }
                .clipped()
            }
            .frame(height: AppSpacing.md)
            .onAppear {
                withAnimation(Self.barAnimation) {
                    displayExpensePercent = expensePercent
                    displayIncomePercent = incomePercent
                }
            }
            .onChange(of: expensePercent) { _, newValue in
                withAnimation(Self.barAnimation) {
                    displayExpensePercent = newValue
                }
            }
            .onChange(of: incomePercent) { _, newValue in
                withAnimation(Self.barAnimation) {
                    displayIncomePercent = newValue
                }
            }
            
            // Amounts below progress bar
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
        ExpenseIncomeProgressBar(
            expenseAmount: 5000,
            incomeAmount: 10000,
            currency: "KZT"
        )
        
        ExpenseIncomeProgressBar(
            expenseAmount: 10000,
            incomeAmount: 5000,
            currency: "USD"
        )
    }
    .padding()
}
