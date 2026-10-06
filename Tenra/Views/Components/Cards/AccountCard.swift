//
//  AccountCard.swift
//  Tenra
//
//  Account card of the home carousel. Adapter over DesignKit's `BalanceCard`: the account,
//  the navigation link, the zoom transition and the VoiceOver copy stay here.
//

import SwiftUI

struct AccountCard: View {
    let account: Account
    /// Pre-resolved balance — passed in from AccountsCarousel so this card does NOT
    /// subscribe to BalanceCoordinator.balances. Reading the dict here would mean any
    /// balance change re-renders every visible card; with a value passed in, only the
    /// owning ForEach row whose value actually changed re-renders.
    let balance: Double
    var namespace: Namespace.ID

    var body: some View {
        NavigationLink(value: account) {
            BalanceCard(
                iconSource: account.iconSource,
                title: account.name,
                amount: balance,
                currency: account.currency
            )
            .glassEffectID("account-card-\(account.id)", in: namespace)
        }
        .buttonStyle(.bounce)
        .matchedTransitionSource(id: account.id, in: namespace)
        .accessibilityLabel(String(format: String(localized: "accessibility.accountCard.label"), account.name, Formatting.formatCurrency(balance, currency: account.currency)))
        .accessibilityHint(String(localized: "accessibility.accountCard.hint"))
    }
}

#Preview("Account Card") {
    @Previewable @Namespace var ns
    NavigationStack {
        AccountCard(
            account: Account(name: "Main Account", currency: "USD", iconSource: nil, initialBalance: 1000),
            balance: 1000,
            namespace: ns
        )
        .padding()
    }
}
