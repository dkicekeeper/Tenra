//
//  MoneyEntrySheet.swift
//  Tenra
//
//  Money towards a goal or back on a debt (docs/domains/goals-and-debts.md): an adapter over
//  DesignKit's AmountEntrySheet (4.13.0), the hero of what it goes to, the amount on the
//  calculator keypad, a note, and the date buttons with Save. Tenra's AppSettings give the base
//  currency, the currencies to offer and the quick-access sheet; an amount typed in another
//  currency is converted to `currency` on save (DesignKitCurrencyConverter, wired in
//  DesignKitBridge). Nothing here touches an account or a transaction.
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

    @State private var showingCustomize = false

    var body: some View {
        AmountEntrySheet(
            title: title,
            icon: icon,
            subtitle: subtitle,
            currency: currency,
            baseCurrency: appSettings.baseCurrency,
            currencies: Array(Set([currency]).union(appSettings.quickAccessCurrencies)),
            suggestedAmount: suggestedAmount,
            notePlaceholder: String(localized: "moneyEntry.notePlaceholder"),
            onCustomizeCurrencies: { showingCustomize = true },
            onSave: onSave
        )
        .quickAccessCurrencySheet(isPresented: $showingCustomize, appSettings: appSettings,
                                  accountCurrencies: [currency])
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
