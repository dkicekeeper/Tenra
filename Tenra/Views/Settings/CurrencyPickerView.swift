//
//  CurrencyPickerView.swift
//  Tenra
//
//  Full-screen searchable currency list with "Popular" and "All" sections.
//

import SwiftUI

struct CurrencyPickerView: View {
    let selectedCurrency: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    // MARK: - Filtered Data

    private var filteredCurrencies: [CurrencyInfo] {
        guard !searchText.isEmpty else {
            return CurrencyInfo.allCurrencies
        }
        let query = searchText.lowercased()
        return CurrencyInfo.allCurrencies.filter {
            $0.code.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    private var showPopularSection: Bool {
        searchText.isEmpty
    }

    // MARK: - Body

    var body: some View {
        List {
            if showPopularSection {
                Section(header: Text(String(localized: "currency.popular"))) {
                    ForEach(CurrencyInfo.popularCurrencies) { currency in
                        currencyRow(currency)
                    }
                }
            }

            Section(header: Text(String(localized: "currency.all"))) {
                ForEach(filteredCurrencies) { currency in
                    currencyRow(currency)
                }
            }
        }
        .navigationTitle(String(localized: "currency.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: String(localized: "currency.searchPrompt")
        )
    }

    // MARK: - Row

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            onSelect(currency.code)
            HapticManager.selection()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.code)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(currency.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text(currency.symbol)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                if currency.code == selectedCurrency {
                    Image(systemName: "checkmark")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        CurrencyPickerView(selectedCurrency: "KZT") { code in
            print("Selected: \(code)")
        }
    }
}
