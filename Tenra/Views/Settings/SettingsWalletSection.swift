//
//  SettingsWalletSection.swift
//  Tenra
//
//  Settings → Wallet: what the Wallet automation (LogWalletPaymentIntent) keeps, and how
//  merchants show. The payments it saved with a guess (To review), the merchants with their
//  categories, the cards with their accounts, and the merchants' logos in transaction rows
//  (MerchantLogoStore). How to set the automation up is in Siri & Shortcuts, right above.
//

import SwiftUI

struct SettingsWalletSection: View {
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    var body: some View {
        FormSection(header: String(localized: "settings.wallet.header"), footer: String(localized: "settings.wallet.footer")) {
            UniversalRow(
                String(localized: "walletReview.title"),
                icon: "checkmark.circle",
                accessory: .navigation {
                    WalletReviewView(
                        transactionsViewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel
                    )
                }
            )

            UniversalRow(
                String(localized: "settings.wallet.merchants"),
                icon: "storefront",
                accessory: .navigation {
                    MerchantCategoriesView(
                        transactionsViewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel
                    )
                }
            )

            UniversalRow(
                String(localized: "settings.wallet.cards"),
                icon: "creditcard",
                accessory: .navigation { WalletCardsView(accountsViewModel: accountsViewModel) }
            )

            // A merchant's logo instead of the category icon in transaction rows.
            UniversalRow(
                String(localized: "settings.merchantLogos"),
                icon: "photo.circle",
                accessory: .toggle($showsMerchantLogos)
            )
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        ScrollView {
            SettingsWalletSection(
                transactionsViewModel: coordinator.transactionsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                accountsViewModel: coordinator.accountsViewModel
            )
        }
    }
    .environment(coordinator.transactionStore)
}
