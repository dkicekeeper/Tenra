//
//  QuickAccessCurrencyPickerView.swift
//  Tenra
//
//  Fullscreen multiselect currency list for configuring which currencies
//  appear in the transaction currency Menu.
//

import SwiftUI

struct QuickAccessCurrencyPickerView: View {
    @Binding var selectedCurrencyCodes: Set<String>
    let accountCurrencies: Set<String>

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

    /// All selected currencies (account + user-picked), sorted by name.
    private var selectedCurrencyInfos: [CurrencyInfo] {
        let allSelected = accountCurrencies.union(selectedCurrencyCodes)
        return allSelected
            .compactMap { CurrencyInfo.find($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var showSelectedSection: Bool {
        searchText.isEmpty && !selectedCurrencyInfos.isEmpty
    }

    // MARK: - Body

    var body: some View {
        List {
            if showSelectedSection {
                Section(header: Text(String(localized: "currency.selected"))) {
                    ForEach(selectedCurrencyInfos) { currency in
                        if accountCurrencies.contains(currency.code) {
                            lockedRow(currency)
                        } else {
                            toggleRow(currency)
                        }
                    }
                }
            }

            Section(header: Text(String(localized: "currency.all"))) {
                ForEach(filteredCurrencies) { currency in
                    let isInSelectedSection = showSelectedSection
                        && (accountCurrencies.contains(currency.code) || selectedCurrencyCodes.contains(currency.code))
                    if !isInSelectedSection {
                        toggleRow(currency)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "currency.customize"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: String(localized: "currency.searchPrompt")
        )
    }

    // MARK: - Rows

    private func lockedRow(_ currency: CurrencyInfo) -> some View {
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

            Image(systemName: "checkmark")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private func toggleRow(_ currency: CurrencyInfo) -> some View {
        Button {
            if selectedCurrencyCodes.contains(currency.code) {
                selectedCurrencyCodes.remove(currency.code)
            } else {
                selectedCurrencyCodes.insert(currency.code)
            }
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

                if selectedCurrencyCodes.contains(currency.code) {
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
    @Previewable @State var selected: Set<String> = ["USD", "EUR"]
    NavigationStack {
        QuickAccessCurrencyPickerView(
            selectedCurrencyCodes: $selected,
            accountCurrencies: ["KZT", "USD"]
        )
    }
}
