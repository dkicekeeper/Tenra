//
//  MoneyEntrySheet.swift
//  Tenra
//
//  Money towards a goal or back on a debt (docs/domains/goals-and-debts.md): the hero of what
//  it goes to, the amount on the calculator keypad, a note, and the date buttons with Save,
//  laid out as LoanPaymentView. The amount may be typed in another currency; it is converted
//  to `currency` on save. Nothing here touches an account or a transaction.
//

import SwiftUI

struct MoneyEntrySheet: View {
    let title: String
    let icon: IconSource
    var subtitle: String? = nil
    /// The goal's or the debt's currency: what `onSave` receives.
    let currency: String
    let appSettings: AppSettings
    /// Filled in to start with (what is left of a debt); none leaves the amount empty.
    var suggestedAmount: Double? = nil
    let onSave: (_ amount: Double, _ date: Date, _ note: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var calc = CalculatorInputModel()
    @State private var selectedCurrency = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var validationError: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    HeroSection(icon: icon, title: title, subtitle: subtitle)

                    if let validationError {
                        InlineStatusText(message: validationError, type: .error)
                            .screenPadding()
                    }

                    AmountInputView(
                        amount: $amountText,
                        selectedCurrency: $selectedCurrency,
                        errorMessage: nil,
                        baseCurrency: appSettings.baseCurrency,
                        accountCurrencies: [currency],
                        appSettings: appSettings,
                        // "≈" in the goal's or the debt's own currency when typed in another.
                        equivalentCurrency: currency,
                        calculatorModel: calc,
                        onCalculatorTap: { noteFocused = false }
                    )

                    FormTextField(
                        text: $note,
                        placeholder: String(localized: "moneyEntry.notePlaceholder"),
                        style: .multiline(min: 2, max: 6),
                        externalFocus: $noteFocused
                    )
                    .screenPadding()
                }
                .animation(AppAnimation.gentleSpring, value: validationError)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "button.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .dsButton()
                    .disabled(!isValid)
                    .accessibilityLabel(String(localized: "button.save"))
                }
            }
            .dateButtonsSafeArea(selectedDate: $date, isDisabled: !isValid, maxDate: Date()) { _ in
                save()
            }
            .safeAreaInset(edge: .bottom) {
                if !noteFocused {
                    CalculatorKeypad(model: calc)
                        .background(AppColors.bgBase)
                }
            }
            .onChange(of: calc.amountText) { _, newValue in
                amountText = newValue
            }
            .onAppear {
                selectedCurrency = currency
                if let suggestedAmount, suggestedAmount > 0 {
                    amountText = AmountInputFormatting.bindingString(for: suggestedAmount)
                    calc.seed(amountText)
                }
            }
        }
    }

    private var isValid: Bool {
        guard let amount = AmountFormatter.parse(amountText) else { return false }
        return amount > 0
    }

    private func save() {
        guard let parsed = AmountFormatter.parse(amountText), parsed > 0 else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "moneyEntry.invalidAmount")
            }
            HapticManager.error()
            return
        }
        let typed = NSDecimalNumber(decimal: parsed).doubleValue
        guard let amount = CurrencyConverter.convertSync(amount: typed, from: selectedCurrency, to: currency) else {
            withAnimation(AppAnimation.contentSpring) {
                validationError = String(localized: "currency.error.conversionFailed")
            }
            HapticManager.error()
            return
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(amount, date, trimmed.isEmpty ? nil : trimmed)
        HapticManager.success()
        dismiss()
    }
}

#Preview("Money Entry") {
    MoneyEntrySheet(
        title: "Car",
        icon: .sfSymbol("car.fill"),
        subtitle: "1 800 000 ₸ left",
        currency: "KZT",
        appSettings: .makeDefault(),
        onSave: { _, _, _ in }
    )
}
