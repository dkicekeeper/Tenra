//
//  SettingsSiriSection.swift
//  Tenra
//
//  Teaches the Siri phrases. Without this, App Shortcuts are discoverable only
//  by accident, and an undiscovered feature has no effect on retention.
//  Also the way to what the Wallet automation keeps: the payments it saved with a
//  guess (To review), the merchants and the cards it remembered.
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

            NavigationSettingsRow(
                icon: "checkmark.circle",
                title: String(localized: "walletReview.title")
            ) {
                WalletReviewView(
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel
                )
            }

            NavigationSettingsRow(
                icon: "wallet.pass",
                title: String(localized: "settings.merchants.title")
            ) {
                MerchantCategoriesView(
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel
                )
            }

            NavigationSettingsRow(
                icon: "creditcard",
                title: String(localized: "settings.cards.title")
            ) {
                WalletCardsView(accountsViewModel: accountsViewModel)
            }

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
