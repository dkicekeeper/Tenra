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
/// language (its own setting, VoiceRecognitionLanguage). Merchant logos are in the Wallet
/// section (SettingsWalletSection).
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
        FormSection(header: String(localized: "settings.general")) {
            // Base Currency Picker: a row with its value, pushing the currencies (DesignKit
            // 8.0.0: a card's navigation row draws its own chevron).
            UniversalRow(
                String(localized: "settings.baseCurrency"),
                icon: "dollarsign.circle",
                value: "\(Formatting.currencySymbol(for: selectedCurrency)) \(selectedCurrency)",
                accessory: .navigation {
                    CurrencyPickerView(
                        selectedCurrency: selectedCurrency,
                        onSelect: onCurrencyChange
                    )
                }
            )

            // Background settings navigation link
            UniversalRow(
                String(localized: "settings.background"),
                icon: "photo.on.rectangle",
                accessory: .navigation {
                    backgroundDestination
                }
            )

            // DesignKit's list row (4.14.0): the settings row, its value and the list it pushes.
            UniversalRow(
                String(localized: "settings.voiceLanguage"),
                icon: "waveform",
                accessory: .picker($voiceLanguage, options: voiceLanguageOptions)
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
        ScrollView {
            SettingsGeneralSection(
                selectedCurrency: "KZT",
                onCurrencyChange: { _ in }
            ) {
                Text("Background Settings")
            }
        }
    }
}
