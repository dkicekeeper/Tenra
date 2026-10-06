//
//  AmountInputView.swift
//  Tenra
//
//  Adapter over DesignKit's CurrencyAmountInput (1.10.0): Tenra's AppSettings give the
//  currencies to offer and the quick-access sheet.
//

import SwiftUI

struct AmountInputView: View {
    @Binding var amount: String
    @Binding var selectedCurrency: String
    let errorMessage: String?
    let baseCurrency: String
    let accountCurrencies: Set<String>
    let appSettings: AppSettings
    /// When set, the amount is entered via the in-app calculator keypad instead of the
    /// system keyboard: the large display reads from this model (the host owns it and
    /// mirrors `model.amountText` into `amount`). The keypad itself is placed by the host.
    var calculatorModel: CalculatorInputModel? = nil
    /// Called when the calculator display is tapped (host re-activates the keypad and
    /// dismisses the system keyboard from a sibling text field).
    var onCalculatorTap: (() -> Void)? = nil
    var onAmountChange: ((String) -> Void)? = nil

    @State private var showingCustomize = false

    var body: some View {
        // DesignKit's CurrencyAmountInput (1.10.0); FX through DesignKitCurrencyConverter
        // (wired in DesignKitBridge), the currencies and the customize sheet from AppSettings.
        CurrencyAmountInput(
            amount: $amount,
            currency: $selectedCurrency,
            baseCurrency: baseCurrency,
            currencies: Array(accountCurrencies.union(appSettings.quickAccessCurrencies)),
            errorMessage: errorMessage,
            calculatorModel: calculatorModel,
            onCalculatorTap: onCalculatorTap,
            onAmountChange: onAmountChange,
            onCustomizeCurrencies: { showingCustomize = true }
        )
        .quickAccessCurrencySheet(isPresented: $showingCustomize, appSettings: appSettings,
                                  accountCurrencies: accountCurrencies)
    }
}

#Preview("Amount Input - Empty") {
    @Previewable @State var amount = ""
    @Previewable @State var currency = "KZT"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: nil,
        baseCurrency: "KZT",
        accountCurrencies: ["KZT"],
        appSettings: .makeDefault()
    )
}

#Preview("Amount Input - With Value") {
    @Previewable @State var amount = "1234.56"
    @Previewable @State var currency = "USD"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: nil,
        baseCurrency: "KZT",
        accountCurrencies: ["KZT"],
        appSettings: .makeDefault()
    )
}

#Preview("Amount Input - Error") {
    @Previewable @State var amount = "abc"
    @Previewable @State var currency = "EUR"

    return AmountInputView(
        amount: $amount,
        selectedCurrency: $currency,
        errorMessage: "Введите корректную сумму",
        baseCurrency: "KZT",
        accountCurrencies: ["KZT"],
        appSettings: .makeDefault()
    )
}
