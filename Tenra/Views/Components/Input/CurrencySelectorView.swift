//
//  CurrencySelectorView.swift
//  Tenra
//
//  Configurable currency selector using Menu picker.
//  Shows account currencies + user's quick-access picks + "Customize..." action.
//

import SwiftUI

struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let accountCurrencies: Set<String>
    let appSettings: AppSettings

    @State private var showingCustomize = false

    /// Merged, deduplicated, sorted currency list for the Menu.
    private var menuCurrencies: [CurrencyInfo] {
        let quickAccess = Set(appSettings.quickAccessCurrencies)
        let allCodes = accountCurrencies.union(quickAccess)
        return allCodes
            .compactMap { CurrencyInfo.find($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            currencyMenu
        }
        .sheet(isPresented: $showingCustomize) {
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
                            showingCustomize = false
                        }
                    }
                }
            }
        }
        .onChange(of: appSettings.quickAccessCurrencies) { _, _ in
            appSettings.save()
        }
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies) { currency in
                Button(action: {
                    selectedCurrency = currency.code
                    HapticManager.selection()
                }) {
                    HStack {
                        Text("\(currency.code) \(currency.symbol)")
                        Spacer()
                        if selectedCurrency == currency.code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button(action: {
                showingCustomize = true
            }) {
                Label(
                    String(localized: "currency.customizeAction"),
                    systemImage: "slider.horizontal.3"
                )
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(Formatting.currencySymbol(for: selectedCurrency))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle(isSelected: false)
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
