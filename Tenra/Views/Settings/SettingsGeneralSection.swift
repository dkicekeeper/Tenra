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
/// Groups currency picker + navigation link to the background settings page + the voice
/// language (its own setting, VoiceRecognitionLanguage).
struct SettingsGeneralSection<BackgroundDest: View>: View {

    // MARK: - Props

    let selectedCurrency: String
    let onCurrencyChange: (String) -> Void
    let backgroundDestination: BackgroundDest

    /// Empty: as in the app.
    @AppStorage(VoiceRecognitionLanguage.defaultsKey) private var voiceLanguage = ""

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
        Section(header: SectionHeader(String(localized: "settings.general"), style: .compact)) {
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
                                           size: AppIconSize.md),
                    title: String(localized: "settings.baseCurrency")
                ) {
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

            // DesignKit's list row (4.14.0): the settings row, its value and the list it pushes.
            NavigationPickerRow(
                icon: "waveform",
                title: String(localized: "settings.voiceLanguage"),
                selection: $voiceLanguage,
                options: voiceLanguageOptions,
                style: .list
            )
        }
    }

    private var voiceLanguageOptions: [(label: String, value: String)] {
        [(String(localized: "settings.voiceLanguage.app"), "")]
            + VoiceRecognitionLanguage.choices().map { (VoiceRecognitionLanguage.displayName($0), $0) }
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
