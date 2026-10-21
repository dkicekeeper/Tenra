//
//  WalletCardsView.swift
//  Tenra
//
//  Settings → Siri & Shortcuts → Wallet cards: the cards whose payments the Wallet
//  action (LogWalletPaymentIntent) records, each with its account (CardAccountMemory).
//  Pick another account for a card, or swipe to forget it: its next payment goes to
//  the suggested account and waits in To review.
//

import SwiftUI

struct WalletCardsView: View {
    let accountsViewModel: AccountsViewModel

    @State private var memory = CardAccountMemory.shared

    var body: some View {
        Group {
            if memory.cards.isEmpty {
                EmptyState(
                    icon: "creditcard",
                    title: String(localized: "settings.cards.emptyTitle"),
                    description: String(localized: "settings.cards.emptyMessage")
                )
            } else {
                List {
                    Section {
                        ForEach(memory.cards) { card in
                            row(card)
                        }
                    } footer: {
                        Text(String(localized: "settings.cards.footer"))
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.cards.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row

    private func row(_ card: CardAccountMemory.Card) -> some View {
        UniversalRow(
            card.displayName,
            icon: "creditcard",
            config: .settings,
            accessory: .picker(
                Binding(
                    get: { card.accountId },
                    set: { memory.remember(accountId: $0, forCard: card.displayName) }
                ),
                options: accountOptions(keeping: card.accountId)
            )
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.warning()
                memory.forget(card: card.displayName)
            } label: {
                Label(String(localized: "settings.merchants.forget"), systemImage: "trash")
            }
        }
    }

    /// The accounts a card can pay from. A remembered account that no longer qualifies
    /// (deleted, or turned into a deposit) is listed by its id until it is replaced, so the
    /// row never shows an empty value.
    private func accountOptions(keeping accountId: String) -> [(label: String, value: String)] {
        let eligible = accountsViewModel.accounts.filter { !$0.isLoan && !$0.isDeposit }
        var options = eligible.map { (label: $0.name, value: $0.id) }
        if !eligible.contains(where: { $0.id == accountId }) {
            options.insert((label: String(localized: "settings.cards.accountDeleted"), value: accountId), at: 0)
        }
        return options
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        WalletCardsView(accountsViewModel: coordinator.accountsViewModel)
    }
}
