//
//  BudgetSettingsSection.swift
//  AIFinanceManager
//
//  Universal budget settings component for category budgets
//  Created 2026-02-17
//

import SwiftUI

/// Universal budget settings section component
/// Displays budget amount, period, and reset day fields in a card
struct BudgetSettingsSection: View {
    @Binding var budgetAmount: String
    @Binding var selectedPeriod: CustomCategory.BudgetPeriod
    @Binding var resetDay: Int

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            VStack(spacing: 0) {
                // Budget Amount
                UniversalRow(
                    config: .standard,
                    leadingIcon: .sfSymbol("banknote", color: AppColors.accent, size: AppIconSize.lg)
                ) {
                    Text(String(localized: "budget.amount"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                } trailing: {
                    TextField("0", text: $budgetAmount)
                        .fontWeight(.semibold)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(String(localized: "budget.amount"))
                }

                Divider()

                // Budget Period
                MenuPickerRow(
                    icon: "calendar",
                    title: String(localized: "budget.period"),
                    selection: $selectedPeriod,
                    options: [
                        (label: String(localized: "budget.weekly"), value: CustomCategory.BudgetPeriod.weekly),
                        (label: String(localized: "budget.monthly"), value: CustomCategory.BudgetPeriod.monthly),
                        (label: String(localized: "yearly"), value: CustomCategory.BudgetPeriod.yearly)
                    ]
                )

                if selectedPeriod == .monthly {
                    Divider()

                    // Reset Day
                    UniversalRow(
                        config: .standard,
                        leadingIcon: .sfSymbol("arrow.clockwise", color: AppColors.accent, size: AppIconSize.lg)
                    ) {
                        Stepper(
                            String(localized: "budget_reset_day") + " \(resetDay)",
                            value: $resetDay,
                            in: 1...31
                        )
                        .accessibilityLabel(String(localized: "budget_reset_day"))
                        .accessibilityValue("\(resetDay)")
                    }
                }

            }
            .cardStyle()

            if selectedPeriod == .monthly {
                Text(String(localized: "budget_reset_day_description"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Previews

#Preview("Budget Settings - Monthly") {
    @Previewable @State var amount = "10000"
    @Previewable @State var period: CustomCategory.BudgetPeriod = .monthly
    @Previewable @State var resetDay = 1

    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            BudgetSettingsSection(
                budgetAmount: $amount,
                selectedPeriod: $period,
                resetDay: $resetDay
            )
        }
        .padding()
    }
}

#Preview("Budget Settings - Weekly") {
    @Previewable @State var amount = "5000"
    @Previewable @State var period: CustomCategory.BudgetPeriod = .weekly
    @Previewable @State var resetDay = 1

    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            BudgetSettingsSection(
                budgetAmount: $amount,
                selectedPeriod: $period,
                resetDay: $resetDay
            )
        }
        .padding()
    }
}

#Preview("Budget Settings - Yearly") {
    @Previewable @State var amount = "120000"
    @Previewable @State var period: CustomCategory.BudgetPeriod = .yearly
    @Previewable @State var resetDay = 1

    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            BudgetSettingsSection(
                budgetAmount: $amount,
                selectedPeriod: $period,
                resetDay: $resetDay
            )
        }
        .padding()
    }
}

#Preview("In Category Edit Context") {
    @Previewable @State var name = "Food"
    @Previewable @State var amount = "15000"
    @Previewable @State var period: CustomCategory.BudgetPeriod = .monthly
    @Previewable @State var resetDay = 15

    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            // Category Name
            VStack(spacing: AppSpacing.md) {
                IconView(
                    source: .sfSymbol("fork.knife"),
                    style: .circle(
                        size: AppIconSize.ultra,
                        tint: .monochrome(.pink),
                        backgroundColor: AppColors.surface
                    )
                )

                Text(name)
                    .font(AppTypography.h1)
            }
            .padding(.vertical, AppSpacing.lg)

            // Budget Settings
            BudgetSettingsSection(
                budgetAmount: $amount,
                selectedPeriod: $period,
                resetDay: $resetDay
            )
        }
        .padding()
    }
}
