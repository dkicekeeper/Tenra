//
//  DebtEditView.swift
//  Tenra
//
//  A new personal debt, or changes to one (docs/domains/goals-and-debts.md): which way, the
//  amount and currency, who, when it happened, an optional due date and a note. Repayments are
//  marked on the debt's screen, not here.
//

import SwiftUI

struct DebtEditView: View {
    let debt: PersonalDebt?
    let appSettings: AppSettings
    let onSave: (PersonalDebt) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var direction: DebtDirection = .owedToMe
    @State private var person = ""
    @State private var amountText = ""
    @State private var currency = ""
    @State private var date = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var note = ""

    var body: some View {
        EditSheetContainer(
            title: debt == nil ? String(localized: "debt.new") : String(localized: "debt.editTitle"),
            isSaveDisabled: !isValid,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    SegmentedPicker(
                        title: String(localized: "debt.direction"),
                        selection: $direction,
                        options: [
                            (label: String(localized: "debt.direction.owedToMe"), value: DebtDirection.owedToMe),
                            (label: String(localized: "debt.direction.iOwe"), value: DebtDirection.iOwe),
                        ]
                    )
                    .screenPadding()

                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $currency,
                        errorMessage: nil,
                        baseCurrency: appSettings.baseCurrency,
                        accountCurrencies: currency.isEmpty ? [] : [currency],
                        appSettings: appSettings
                    )

                    FormSection {
                        UniversalRow(
                            leadingIcon: .sfSymbol("person", color: AppColors.accent, size: AppIconSize.lg),
                            title: String(localized: "debt.person")
                        ) {
                            FormTextField(
                                text: $person,
                                placeholder: String(localized: "debt.personPlaceholder"),
                                style: .inline
                            )
                        }
                        Divider().padding(.leading, AppSpacing.lg)
                        DatePickerRow(
                            icon: "calendar",
                            title: String(localized: "debt.date"),
                            selection: $date,
                            maxDate: Date()
                        )
                    }
                    .screenPadding()

                    FormSection(header: String(localized: "debt.dueDate")) {
                        ToggleSettingsRow(
                            icon: "calendar.badge.clock",
                            title: String(localized: "debt.hasDueDate"),
                            config: .standard,
                            isOn: $hasDueDate
                        )
                        if hasDueDate {
                            Divider().padding(.leading, AppSpacing.lg)
                            DatePickerRow(
                                icon: "calendar.badge.clock",
                                title: String(localized: "debt.dueDate"),
                                selection: $dueDate
                            )
                        }
                    }
                    .screenPadding()

                    FormSection(header: String(localized: "debt.note")) {
                        FormTextField(
                            text: $note,
                            placeholder: String(localized: "debt.notePlaceholder"),
                            style: .rowMultiline(min: 2, max: 5)
                        )
                    }
                    .screenPadding()
                }
                .padding(.top, AppSpacing.md)
                .animation(AppAnimation.smooth, value: hasDueDate)
            }
        }
        .onAppear(perform: fill)
    }

    private var amount: Double? {
        guard let parsed = AmountFormatter.parse(amountText), parsed > 0 else { return nil }
        return NSDecimalNumber(decimal: parsed).doubleValue
    }

    private var isValid: Bool {
        !person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount != nil
    }

    private func fill() {
        guard let debt else {
            currency = appSettings.baseCurrency
            return
        }
        direction = debt.direction
        person = debt.person
        amountText = AmountInputFormatting.bindingString(for: debt.amount)
        currency = debt.currency
        date = debt.date
        hasDueDate = debt.dueDate != nil
        if let due = debt.dueDate { dueDate = due }
        note = debt.note ?? ""
    }

    private func save() {
        guard let amount else { return }
        var result = debt ?? PersonalDebt(direction: direction, person: "", amount: 0, currency: currency)
        result.direction = direction
        result.person = person.trimmingCharacters(in: .whitespacesAndNewlines)
        result.amount = amount
        result.currency = currency
        result.date = date
        result.dueDate = hasDueDate ? Calendar.current.startOfDay(for: dueDate) : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        result.note = trimmedNote.isEmpty ? nil : trimmedNote
        if let debt, debt.currency != currency, !debt.repayments.isEmpty {
            // Repayments are kept in the debt's currency: they move to the new one with it, or
            // the currency stays when there is no rate to move them at.
            let moved = debt.repayments.map { repayment -> DebtRepayment? in
                guard let amount = CurrencyConverter.convertSync(amount: repayment.amount, from: debt.currency, to: currency) else { return nil }
                var copy = repayment
                copy.amount = (amount * 100).rounded() / 100
                return copy
            }
            if moved.allSatisfy({ $0 != nil }) {
                result.repayments = moved.compactMap { $0 }
            } else {
                result.currency = debt.currency
            }
        }
        // An amount lowered to what already came back settles the debt; one raised above it
        // opens again a debt its repayments had settled.
        if result.settledAt == nil, !result.repayments.isEmpty, result.isCovered {
            result.settledAt = result.repayments.last?.date ?? Date()
        } else if result.settledAt != nil, debt?.isCovered == true, !result.isCovered {
            result.settledAt = nil
        }
        HapticManager.success()
        onSave(result)
        dismiss()
    }
}

#Preview("Debt Edit - New") {
    DebtEditView(debt: nil, appSettings: .makeDefault(), onSave: { _ in })
}
