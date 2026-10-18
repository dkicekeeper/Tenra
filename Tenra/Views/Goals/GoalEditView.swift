//
//  GoalEditView.swift
//  Tenra
//
//  A new savings goal, or changes to one (docs/domains/goals-and-debts.md): icon, name, target
//  and currency in the hero; an optional deadline; and the account the goal follows, or none
//  to mark contributions by hand (a new goal can start with what is already saved).
//

import SwiftUI

struct GoalEditView: View {
    let goal: SavingsGoal?
    /// Accounts a goal can follow (loans are not offered).
    let accounts: [Account]
    let baseCurrency: String
    let onSave: (SavingsGoal) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var iconSource: IconSource?
    @State private var targetText = ""
    @State private var currency = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    /// Empty: no account, contributions are marked by hand.
    @State private var linkedAccountId = ""
    @State private var alreadySavedText = ""

    var body: some View {
        EditSheetContainer(
            title: goal == nil ? String(localized: "goal.new") : String(localized: "goal.editTitle"),
            isSaveDisabled: !isValid,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.sm) {
                        EditableHeroSection(
                            iconSource: $iconSource,
                            title: $name,
                            balance: $targetText,
                            currency: $currency,
                            titlePlaceholder: String(localized: "goal.namePlaceholder"),
                            config: .accountHero
                        )
                        Text(String(localized: "goal.targetHint"))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    FormSection(header: String(localized: "goal.deadline")) {
                        ToggleSettingsRow(
                            icon: "calendar",
                            title: String(localized: "goal.hasDeadline"),
                            config: .standard,
                            isOn: $hasDeadline
                        )
                        if hasDeadline {
                            Divider().padding(.leading, AppSpacing.lg)
                            DatePickerRow(
                                icon: "calendar.badge.clock",
                                title: String(localized: "goal.deadline"),
                                selection: $deadline,
                                minDate: Date()
                            )
                        }
                    }

                    FormSection(
                        header: String(localized: "goal.account"),
                        footer: String(localized: "goal.account.hint")
                    ) {
                        NavigationPickerRow(
                            icon: "building.columns",
                            title: String(localized: "goal.account"),
                            selection: $linkedAccountId,
                            options: [(label: String(localized: "goal.account.none"), value: "")]
                                + accounts.map { (label: $0.name, value: $0.id) }
                        )
                        if goal == nil, linkedAccountId.isEmpty {
                            Divider().padding(.leading, AppSpacing.lg)
                            UniversalRow(
                                leadingIcon: .sfSymbol("banknote", color: AppColors.accent, size: AppIconSize.lg),
                                title: String(localized: "goal.alreadySaved")
                            ) {
                                FormTextField(
                                    text: $alreadySavedText,
                                    placeholder: "0",
                                    style: .inline,
                                    keyboardType: .decimalPad
                                )
                            }
                        }
                    }
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
                .animation(AppAnimation.smooth, value: hasDeadline)
                .animation(AppAnimation.smooth, value: linkedAccountId)
            }
        }
        .onAppear(perform: fill)
    }

    private var target: Double? {
        guard let parsed = AmountFormatter.parse(targetText), parsed > 0 else { return nil }
        return NSDecimalNumber(decimal: parsed).doubleValue
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && target != nil
    }

    private func fill() {
        guard let goal else {
            currency = baseCurrency
            return
        }
        name = goal.name
        iconSource = goal.iconSource
        targetText = AmountInputFormatting.bindingString(for: goal.targetAmount)
        currency = goal.currency
        hasDeadline = goal.deadline != nil
        if let date = goal.deadline { deadline = date }
        linkedAccountId = goal.linkedAccountId ?? ""
    }

    private func save() {
        guard let target else { return }
        var result = goal ?? SavingsGoal(name: "", targetAmount: 0, currency: currency)
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.iconSource = iconSource
        result.targetAmount = target
        result.currency = currency
        if let goal, goal.currency != currency, !goal.contributions.isEmpty {
            // Contributions are kept in the goal's currency: they move to the new one with it,
            // or the currency stays when there is no rate to move them at.
            let moved = goal.contributions.map { contribution -> GoalContribution? in
                guard let amount = CurrencyConverter.convertSync(amount: contribution.amount, from: goal.currency, to: currency) else { return nil }
                var copy = contribution
                copy.amount = (amount * 100).rounded() / 100
                return copy
            }
            if moved.allSatisfy({ $0 != nil }) {
                result.contributions = moved.compactMap { $0 }
            } else {
                result.currency = goal.currency
            }
        }
        result.deadline = hasDeadline ? Calendar.current.startOfDay(for: deadline) : nil
        result.linkedAccountId = linkedAccountId.isEmpty ? nil : linkedAccountId
        if goal == nil, result.linkedAccountId == nil,
           let saved = AmountFormatter.parse(alreadySavedText), saved > 0 {
            result.contributions = [GoalContribution(amount: NSDecimalNumber(decimal: saved).doubleValue, date: Date())]
        }
        HapticManager.success()
        onSave(result)
        dismiss()
    }
}

#Preview("Goal Edit - New") {
    GoalEditView(goal: nil, accounts: [], baseCurrency: "KZT", onSave: { _ in })
}
