//
//  SettingsGeneralSection.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//  Updated: background picker moved to SettingsHomeBackgroundView
//

import SwiftUI

/// Props-based General section for Settings.
/// Groups currency picker + navigation link to the background settings page.
struct SettingsGeneralSection<BackgroundDest: View>: View {

    // MARK: - Props

    let selectedCurrency: String
    let availableCurrencies: [String]
    let onCurrencyChange: (String) -> Void
    let backgroundDestination: BackgroundDest

    // MARK: - Initializer

    init(
        selectedCurrency: String,
        availableCurrencies: [String],
        onCurrencyChange: @escaping (String) -> Void,
        @ViewBuilder backgroundDestination: () -> BackgroundDest
    ) {
        self.selectedCurrency = selectedCurrency
        self.availableCurrencies = availableCurrencies
        self.onCurrencyChange = onCurrencyChange
        self.backgroundDestination = backgroundDestination()
    }

    // MARK: - Body

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.general"))) {
            // Base Currency Picker
            UniversalRow(
                config: .settings,
                leadingIcon: .sfSymbol("dollarsign.circle",
                                       color: AppColors.accent,
                                       size: AppIconSize.md)
            ) {
                Text(String(localized: "settings.baseCurrency"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                currencyMenu
            }

            // Background settings navigation link
            NavigationSettingsRow(
                icon: "photo.on.rectangle",
                title: String(localized: "settings.background")
            ) {
                backgroundDestination
            }
        }
    }

    // MARK: - Currency Menu

    private var currencyMenu: some View {
        Menu {
            ForEach(availableCurrencies, id: \.self) { currency in
                Button {
                    onCurrencyChange(currency)
                } label: {
                    HStack {
                        Text(Formatting.currencySymbol(for: currency))
                        if selectedCurrency == currency {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(Formatting.currencySymbol(for: selectedCurrency))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.secondaryBackground)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        List {
            SettingsGeneralSection(
                selectedCurrency: "KZT",
                availableCurrencies: ["KZT", "USD", "EUR", "RUB"],
                onCurrencyChange: { _ in }
            ) {
                Text("Background Settings")
            }
        }
    }
}
