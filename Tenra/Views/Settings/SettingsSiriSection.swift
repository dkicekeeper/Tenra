//
//  SettingsSiriSection.swift
//  Tenra
//
//  Teaches the Siri phrases. Without this, App Shortcuts are discoverable only
//  by accident, and an undiscovered feature has no effect on retention.
//  Also the way to the Wallet automation: how to set it up (WalletSetupGuideView) and
//  what it keeps: the payments it saved with a guess (To review), the merchants and the
//  cards it remembered.
//

import SwiftUI
import AppIntents

struct SettingsSiriSection: View {
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    var body: some View {
        Section {
            ForEach(Self.examplePhrases, id: \.self) { phrase in
                Label(phrase, systemImage: "quote.bubble")
                    .font(AppTypography.bodySmall)
            }

            UniversalRow(
                String(localized: "walletSetup.title"),
                icon: "list.number",
                config: .settings,
                accessory: .navigation { WalletSetupGuideView() }
            )

            UniversalRow(
                String(localized: "walletReview.title"),
                icon: "checkmark.circle",
                config: .settings,
                accessory: .navigation {
                    WalletReviewView(
                        transactionsViewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel
                    )
                }
            )

            UniversalRow(
                String(localized: "settings.merchants.title"),
                icon: "wallet.pass",
                config: .settings,
                accessory: .navigation {
                    MerchantCategoriesView(
                        transactionsViewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel
                    )
                }
            )

            UniversalRow(
                String(localized: "settings.cards.title"),
                icon: "creditcard",
                config: .settings,
                accessory: .navigation { WalletCardsView(accountsViewModel: accountsViewModel) }
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
