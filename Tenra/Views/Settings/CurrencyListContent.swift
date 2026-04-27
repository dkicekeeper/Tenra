//
//  CurrencyListContent.swift
//  Tenra
//
//  Reusable currency list (List + searchable + popular/all sections).
//  Owners: CurrencyPickerView (legacy callback flow), OnboardingCurrencyStep (binding flow).
//

import SwiftUI

struct CurrencyListContent: View {
    let selectedCurrency: String
    let onTap: (String) -> Void

    @State private var searchText = ""

    // MARK: - Filtered Data

    private var filteredCurrencies: [CurrencyInfo] {
        guard !searchText.isEmpty else { return CurrencyInfo.allCurrencies }
        let query = searchText.lowercased()
        return CurrencyInfo.allCurrencies.filter {
            $0.code.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    private var showPopularSection: Bool { searchText.isEmpty }

    // MARK: - Body

    var body: some View {
        List {
            if showPopularSection {
                Section(header: Text(String(localized: "currency.popular"))) {
                    ForEach(CurrencyInfo.popularCurrencies) { currencyRow($0) }
                }
            }
            Section(header: Text(String(localized: "currency.all"))) {
                ForEach(filteredCurrencies) { currencyRow($0) }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "currency.searchPrompt"))
    }

    // MARK: - Row

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            onTap(currency.code)
            HapticManager.selection()
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
