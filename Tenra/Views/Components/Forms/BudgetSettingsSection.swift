//
//  BudgetSettingsSection.swift
//  Tenra
//
//  Universal budget settings component for category budgets
//  Created 2026-02-17
//

import SwiftUI

/// Universal budget settings section component
/// Displays budget amount, period, and reset day fields in a card
struct BudgetSettingsSection: View {
    var header: String? = nil
    @Binding var budgetAmount: String
    @Binding var selectedPeriod: CustomCategory.BudgetPeriod
    @Binding var resetDay: Int

    var body: some View {
        // DesignKit's glass section (8.0.0), its dividers its own; the reset day's explanation
        // as its footer.
        FormSection(header: header, footer: selectedPeriod == .monthly ? String(localized: "budget_reset_day_description") : nil) {
            UniversalRow(String(localized: "budget.amount"), icon: "banknote",
                         accessory: .textField($budgetAmount, placeholder: "0", keyboard: .decimalPad))

            UniversalRow(
                String(localized: "budget.period"),
                icon: "calendar",
                accessory: .menu($selectedPeriod, options: [
                    (label: String(localized: "budget.weekly"), value: CustomCategory.BudgetPeriod.weekly),
                    (label: String(localized: "budget.monthly"), value: CustomCategory.BudgetPeriod.monthly),
                    (label: String(localized: "yearly"), value: CustomCategory.BudgetPeriod.yearly)
                ])
            )

            if selectedPeriod == .monthly {
                UniversalRow(String(localized: "budget_reset_day"), icon: "arrow.clockwise",
                             accessory: .stepper($resetDay, in: 1...31))
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
                Icon(
                    source: .sfSymbol("fork.knife"),
                    style: .circle(
                        size: AppIconSize.Tile.xxxl,
                        tint: .monochrome(.pink),
                        backgroundColor: AppColors.bgCard
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
