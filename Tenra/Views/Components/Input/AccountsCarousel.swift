//
//  AccountsCarousel.swift
//  Tenra
//
//  Horizontal scrollable carousel of account cards
//

import SwiftUI

/// Displays accounts in a horizontal scrollable carousel
/// Extracted from ContentView for reusability and cleaner structure
struct AccountsCarousel: View {
    // MARK: - Properties
    let accounts: [Account]
    let balanceCoordinator: BalanceCoordinator
    let namespace: Namespace.ID

    // MARK: - Body
    var body: some View {
        // Snapshot the balances dict here — this view subscribes to it (parent of
        // AccountCard), so per-card body re-evals only happen when the row's specific
        // balance changes. Without this hoist, AccountCard would observe the whole
        // dict and every balance write would re-render every visible card.
        let balancesById = balanceCoordinator.balances
        // Skip scrollTransition when the carousel almost certainly won't scroll
        // (1–2 cards fit on every iPhone width). The modifier still subscribes
        // each card to scroll-frame updates even when no scrolling happens —
        // visible as extra render work during the home-screen reveal. Threshold of
        // 3 is conservative: 3 cards × ~200pt + spacing already exceeds a standard
        // iPhone viewport, so the transition still applies whenever it matters.
        let useScrollTransition = accounts.count >= 3
        UniversalCarousel(config: .cards) {
            ForEach(accounts.sortedByOrder()) { account in
                AccountCard(
                    account: account,
                    balance: balancesById[account.id] ?? 0,
                    namespace: namespace
                )
                .modifier(CarouselScrollTransition(enabled: useScrollTransition))
                .id(account.id)
            }
        }
        .screenPadding()
    }
}

// MARK: - Conditional Scroll Transition

/// Wraps `.scrollTransition` so it can be applied conditionally without changing
/// the view's identity. Using `Group { if … } else { … }` would split identity
/// between the two branches and undo `matchedGeometryEffect`-driven transitions.
private struct CarouselScrollTransition: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.scrollTransition(.animated(.easeOut(duration: 0.3))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.75)
                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
            }
        } else {
            content
        }
    }
}

// MARK: - Preview
#Preview {
    @Previewable @Namespace var ns
    let coordinator = AppCoordinator()

    return NavigationStack {
        AccountsCarousel(
            accounts: [
                Account(
                    id: "1",
                    name: "Kaspi Bank",
                    currency: "KZT",
                    iconSource: .brandService("kaspi.kz"),
                    depositInfo: nil,
                    initialBalance: 150000
                ),
                Account(
                    id: "2",
                    name: "Halyk Bank",
                    currency: "KZT",
                    iconSource: .brandService("halykbank.kz"),
                    depositInfo: nil,
                    initialBalance: 250000
                )
            ],
            balanceCoordinator: coordinator.balanceCoordinator,
            namespace: ns
        )
    }
}
