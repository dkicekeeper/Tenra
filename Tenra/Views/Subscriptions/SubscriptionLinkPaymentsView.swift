//
//  SubscriptionLinkPaymentsView.swift
//  Tenra
//
//  Thin wrapper around the shared `LinkPaymentsView` component.
//  Binds `SubscriptionTransactionMatcher` and `SubscriptionChargeLinker` to the generic UI.
//

import SwiftUI

struct SubscriptionLinkPaymentsView: View {
    let subscription: RecurringSeries
    let transactionStore: TransactionStore
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    var body: some View {
        // Capture subscription's identifying fields into locals so the Sendable
        // closures don't capture the owning view.
        let sub = subscription
        let store = transactionStore

        LinkPaymentsView(
            title: String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"),
            displayCurrency: subscription.currency,
            findCandidates: { all, mode in
                SubscriptionTransactionMatcher.findCandidates(for: sub, in: all, mode: mode)
            },
            // Each payment takes the place of the planned charge of its period when there is
            // one (SubscriptionChargeLinker), so a charge is never there twice.
            performLink: { selected in
                try await SubscriptionChargeLinker.linkAll(selected, to: sub, store: store)
            },
            options: .subscription,
            transactionStore: transactionStore,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel
        )
    }
}
