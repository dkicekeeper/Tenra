//
//  SettingsGeneralSection.swift
//  Tenra
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
    let onCurrencyChange: (String) -> Void
    let backgroundDestination: BackgroundDest

    // MARK: - Initializer

    init(
        selectedCurrency: String,
        onCurrencyChange: @escaping (String) -> Void,
        @ViewBuilder backgroundDestination: () -> BackgroundDest
    ) {
        self.selectedCurrency = selectedCurrency
        self.onCurrencyChange = onCurrencyChange
        self.backgroundDestination = backgroundDestination()
    }

    // MARK: - Body

    var body: some View {
        Section(header: SectionHeader(String(localized: "settings.general"), style: .list)) {
            // Base Currency Picker
            NavigationLink {
                CurrencyPickerView(
                    selectedCurrency: selectedCurrency,
                    onSelect: onCurrencyChange
                )
            } label: {
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
                    HStack(spacing: AppSpacing.sm) {
                        Text(Formatting.currencySymbol(for: selectedCurrency))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(selectedCurrency)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
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

}

// MARK: - Preview

#Preview {
    NavigationStack {
        List {
            SettingsGeneralSection(
                selectedCurrency: "KZT",
                onCurrencyChange: { _ in }
            ) {
                Text("Background Settings")
            }
        }
    }
}
