//
//  AccountSelectorView.swift
//  Tenra
//
//  Reusable account selector component with horizontal scroll
//

import SwiftUI

struct AccountSelectorView: View {
    let accounts: [Account]
    @Binding var selectedAccountId: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    let warningMessage: String?
    let balanceCoordinator: BalanceCoordinator

    // Centered card sits with `contentMargin` on each side. Within that margin,
    // `cardSpacing` is the gap between cards and `neighborPeek` is the visible
    // portion of the neighbor card extending to the screen edge.
    private let cardSpacing: CGFloat = AppSpacing.md
    private let neighborPeek: CGFloat = AppSpacing.lg

    private var contentMargin: CGFloat {
        cardSpacing + neighborPeek
    }

    @State private var scrollPosition: String?

    init(
        accounts: [Account],
        selectedAccountId: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        warningMessage: String? = nil,
        balanceCoordinator: BalanceCoordinator
    ) {
        self.accounts = accounts
        self._selectedAccountId = selectedAccountId
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.warningMessage = warningMessage
        self.balanceCoordinator = balanceCoordinator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if accounts.isEmpty {
                if let message = emptyStateMessage {
                    Text(message)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                }
            } else {
                accountCarousel
            }

            if let warning = warningMessage {
                InlineStatusText(message: warning, type: .warning)
                    .padding(.horizontal, AppSpacing.sm)
            }
        }
    }

    private var accountCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: cardSpacing) {
                ForEach(accounts.sortedByOrder()) { account in
                    AccountRadioButton(
                        account: account,
                        isSelected: selectedAccountId == account.id,
                        onTap: {
                            guard selectedAccountId != account.id else { return }
                            selectedAccountId = account.id
                            onSelectionChange?(account.id)
                        },
                        balanceCoordinator: balanceCoordinator
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(account.id)
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .contentMargins(.horizontal, contentMargin, for: .scrollContent)
        .scrollClipDisabled()
        // Defer the initial position to the next runloop tick. `containerRelativeFrame`
        // doesn't have a measured width during the synchronous onAppear, and assigning
        // `scrollPosition` before the scroll view has sized its content silently no-ops.
        .onAppear {
            syncScrollToSelected(animated: false)
        }
        .onChange(of: selectedAccountId) { _, _ in
            syncScrollToSelected(animated: true)
        }
        // Re-sync when the accounts list itself changes (e.g. when a sibling carousel
        // filters out the currently-selected id, or new accounts arrive). Without this,
        // the scroll position can drift away from the selection after a list refresh.
        .onChange(of: accounts.map(\.id)) { _, _ in
            syncScrollToSelected(animated: false)
        }
        // Commit auto-selection only when scroll settles. During a tap-induced
        // animated scroll, `scrollPosition` momentarily reports every card the
        // animation passes over — committing on each would fire spurious
        // selection changes. At `.idle` the position is stable: if it differs
        // from `selectedAccountId`, the change came from a user drag.
        .onScrollPhaseChange { _, newPhase in
            guard newPhase == .idle,
                  let landedId = scrollPosition,
                  landedId != selectedAccountId
            else { return }
            selectedAccountId = landedId
            onSelectionChange?(landedId)
        }
    }

    /// Aligns the scroll position with the current `selectedAccountId`. Defers the
    /// non-animated case to the next runloop tick so the scroll view has a measured
    /// width when we assign `scrollPosition` — without the defer, the assignment
    /// silently no-ops on first appear (and after the accounts list changes).
    private func syncScrollToSelected(animated: Bool) {
        let target = selectedAccountId
        if animated {
            guard scrollPosition != target else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollPosition = target
            }
        } else {
            DispatchQueue.main.async {
                guard scrollPosition != target else { return }
                scrollPosition = target
            }
        }
    }
}

// MARK: - Previews

private let previewAccounts: [Account] = [
    Account(name: "Main Card", currency: "USD", iconSource: .sfSymbol("creditcard.fill"), initialBalance: 1_234.56),
    Account(name: "Savings", currency: "EUR", iconSource: .sfSymbol("banknote.fill"), initialBalance: 8_500),
    Account(name: "Travel Wallet", currency: "GBP", iconSource: .sfSymbol("airplane"), initialBalance: 250),
    Account(name: "Cash", currency: "USD", iconSource: .sfSymbol("dollarsign.circle.fill"), initialBalance: 75.25),
    Account(name: "Investment Brokerage Long Name", currency: "USD", iconSource: .sfSymbol("chart.line.uptrend.xyaxis"), initialBalance: 42_000)
]

#Preview("Multiple — no selection") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()

    AccountSelectorView(
        accounts: previewAccounts,
        selectedAccountId: $selectedId,
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(previewAccounts)
    }
}

#Preview("Multiple — pre-selected (middle)") {
    @Previewable @State var selectedId: String? = previewAccounts[2].id
    let coordinator = AppCoordinator()

    AccountSelectorView(
        accounts: previewAccounts,
        selectedAccountId: $selectedId,
        onSelectionChange: { id in
            print("Selection changed to: \(id ?? "nil")")
        },
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(previewAccounts)
    }
}

#Preview("Single account") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()
    let single = [previewAccounts[0]]

    AccountSelectorView(
        accounts: single,
        selectedAccountId: $selectedId,
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(single)
    }
}

#Preview("Two accounts with warning") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()
    let two = Array(previewAccounts.prefix(2))

    AccountSelectorView(
        accounts: two,
        selectedAccountId: $selectedId,
        warningMessage: "Please select an account before proceeding",
        balanceCoordinator: coordinator.balanceCoordinator
    )
    .task {
        await coordinator.balanceCoordinator.registerAccounts(two)
    }
}

#Preview("Empty state") {
    @Previewable @State var selectedId: String? = nil
    let coordinator = AppCoordinator()

    AccountSelectorView(
        accounts: [],
        selectedAccountId: $selectedId,
        emptyStateMessage: "No accounts available — add one in Settings",
        balanceCoordinator: coordinator.balanceCoordinator
    )
}

#Preview("Stacked variants") {
    @Previewable @State var selectedA: String? = nil
    @Previewable @State var selectedB: String? = previewAccounts[0].id
    @Previewable @State var selectedC: String? = nil
    let coordinator = AppCoordinator()
    let two = Array(previewAccounts.prefix(2))

    ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Multiple, no selection")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)
                AccountSelectorView(
                    accounts: previewAccounts,
                    selectedAccountId: $selectedA,
                    balanceCoordinator: coordinator.balanceCoordinator
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Pre-selected first")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)
                AccountSelectorView(
                    accounts: two,
                    selectedAccountId: $selectedB,
                    balanceCoordinator: coordinator.balanceCoordinator
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Empty")
                    .font(AppTypography.h4)
                    .padding(.horizontal, AppSpacing.lg)
                AccountSelectorView(
                    accounts: [],
                    selectedAccountId: $selectedC,
                    emptyStateMessage: "No accounts available",
                    balanceCoordinator: coordinator.balanceCoordinator
                )
            }
        }
        .padding(.vertical, AppSpacing.lg)
    }
    .task {
        await coordinator.balanceCoordinator.registerAccounts(previewAccounts)
    }
}
