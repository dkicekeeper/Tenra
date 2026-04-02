//
//  CurrencySelectorView.swift
//  AIFinanceManager
//
//  Currency selector using Menu picker style
//

import SwiftUI

struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let availableCurrencies: [String]
    /// Base (home) currency. When set, the chip is highlighted only when
    /// the selected currency differs from the base — i.e. a foreign currency is in use.
    let baseCurrency: String

    init(
        selectedCurrency: Binding<String>,
        availableCurrencies: [String] = ["KZT", "USD", "EUR", "RUB", "GBP"],
        baseCurrency: String = ""
    ) {
        self._selectedCurrency = selectedCurrency
        self.availableCurrencies = availableCurrencies
        self.baseCurrency = baseCurrency
    }
    
    var body: some View {
        Menu {
            ForEach(availableCurrencies, id: \.self) { currency in
                Button(action: {
                    selectedCurrency = currency
                    HapticManager.selection()
                }) {
                    HStack {
                        Text(Formatting.currencySymbol(for: currency))
                        Spacer()
                        if selectedCurrency == currency {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(Formatting.currencySymbol(for: selectedCurrency))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle(isSelected: !baseCurrency.isEmpty
                ? selectedCurrency != baseCurrency
                : !availableCurrencies.isEmpty && selectedCurrency != availableCurrencies.first)
        }
    }
}

#Preview("Currency Selector") {
    @Previewable @State var selectedCurrency = "KZT"
    
    return CurrencySelectorView(selectedCurrency: $selectedCurrency)
        .padding()
}
