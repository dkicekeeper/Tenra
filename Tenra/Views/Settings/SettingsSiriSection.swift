//
//  SettingsSiriSection.swift
//  Tenra
//
//  Teaches the Siri phrases. Without this, App Shortcuts are discoverable only
//  by accident, and an undiscovered feature has no effect on retention.
//  Also the way to the merchants the Wallet automation remembered.
//

import SwiftUI
import AppIntents

struct SettingsSiriSection: View {
    let categoriesViewModel: CategoriesViewModel

    var body: some View {
        Section {
            ForEach(Self.examplePhrases, id: \.self) { phrase in
                Label(phrase, systemImage: "quote.bubble")
                    .font(AppTypography.bodySmall)
            }

            UniversalRow(
                String(localized: "settings.merchants.title"),
                icon: "wallet.pass",
                config: .settings,
                accessory: .navigation {
                MerchantCategoriesView(categoriesViewModel: categoriesViewModel)
            }
            )

            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
        } header: {
            SectionHeader(String(localized: "settings.siri.header"), style: .compact)
        } footer: {
            Text("settings.siri.footer")
        }
    }

    private static var examplePhrases: [String] {
        [
            String(localized: "settings.siri.example1"),
            String(localized: "settings.siri.example2"),
            String(localized: "settings.siri.example3")
        ]
    }
}
