//
//  CurrencySelectorView.swift
//  Tenra
//
//  Adapter over DesignKit's CurrencyPickerMenu (1.10.0): the menu offers the account
//  currencies plus the user's quick-access picks from AppSettings, and "Customize…" opens
//  the quick-access sheet (Tenra settings, so it stays here).
//

import SwiftUI

struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let accountCurrencies: Set<String>
    let appSettings: AppSettings

    @State private var showingCustomize = false

    var body: some View {
        CurrencyPickerMenu(
            selection: $selectedCurrency,
            currencies: Array(accountCurrencies.union(appSettings.quickAccessCurrencies))
        ) {
            showingCustomize = true
        }
        .quickAccessCurrencySheet(isPresented: $showingCustomize, appSettings: appSettings,
                                  accountCurrencies: accountCurrencies)
    }
}

extension View {
    /// The sheet behind "Customize…" in the currency menu: the user's quick-access currencies,
    /// saved to AppSettings as they change.
    func quickAccessCurrencySheet(isPresented: Binding<Bool>, appSettings: AppSettings,
                                  accountCurrencies: Set<String>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                QuickAccessCurrencyPickerView(
                    selectedCurrencyCodes: Binding(
                        get: { Set(appSettings.quickAccessCurrencies) },
                        set: { appSettings.quickAccessCurrencies = Array($0).sorted() }
                    ),
                    accountCurrencies: accountCurrencies
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "button.done")) {
                            isPresented.wrappedValue = false
                        }
                    }
                }
            }
        }
        .onChange(of: appSettings.quickAccessCurrencies) { _, _ in
            appSettings.save()
        }
    }
}

#Preview("Currency Selector") {
    @Previewable @State var selectedCurrency = "KZT"

    return CurrencySelectorView(
        selectedCurrency: $selectedCurrency,
        accountCurrencies: ["KZT", "USD"],
        appSettings: .makeDefault()
    )
    .padding()
}
