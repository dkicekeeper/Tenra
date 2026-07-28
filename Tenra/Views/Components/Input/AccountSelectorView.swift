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
    /// `false` until the scroll view has a measured container and we've written the
    /// first `scrollPosition`. Until then every write is dropped by SwiftUI while
    /// still mutating our `@State` — which permanently desyncs the carousel from
    /// the selection (the state already equals the target, so no later write lands).
    @State private var hasAlignedInitialScroll = false

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
        // Owns the FIRST alignment. `onAppear` fires before the scroll view has a
        // measured container, so `containerRelativeFrame` cards are still zero-width
        // and any `scrollPosition` write there is silently dropped. Waiting for a real
        // container width (then one runloop tick for the cards to size against it) is
        // the only deterministic signal that a write will actually scroll.
        //
        // This matters because the selection often arrives *after* appear —
        // `TransactionAddModal.task` resolves the suggested account asynchronously —
        // so the pre-measurement write was the common case, not the edge case.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width
        } action: { _, containerWidth in
            guard containerWidth > 0 else { return }
            performInitialAlignment()
        }
        // Backstop: `onScrollGeometryChange` only fires when the value *changes*, so a
        // scroll view already sized on its first evaluation may never call the action.
        // `performInitialAlignment` is idempotent, so whichever path runs first wins.
        .onAppear {
            performInitialAlignment()
            syncScrollToSelected(animated: false)
        }
        .onChange(of: selectedAccountId) { _, _ in
            syncScrollToSelected(animated: true)
        }
        // The accounts list can change because a *sibling* selector re-filtered it
        // (transfer screen: the source list excludes the chosen target and vice-versa).
        // Only re-align the scroll when our own selection actually fell out of the new
        // list — re-syncing on every list change visibly scrolls this carousel when the
        // user is interacting with the other selector.
        .onChange(of: accounts.map(\.id)) { _, newIDs in
            guard let selectedAccountId, !newIDs.contains(selectedAccountId) else { return }
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

    /// Performs the one-and-only first `scrollPosition` write, a runloop tick after the
    /// caller's signal so the cards have sized against the measured container. Idempotent
    /// — the flag is set inside the deferred block, immediately before the write, so a
    /// concurrent `syncScrollToSelected` can't slip a dropped write in ahead of it.
    private func performInitialAlignment() {
        guard !hasAlignedInitialScroll else { return }
        DispatchQueue.main.async {
            guard !hasAlignedInitialScroll else { return }
            hasAlignedInitialScroll = true
            if scrollPosition != selectedAccountId {
                scrollPosition = selectedAccountId
            }
        }
    }

    /// Aligns the scroll position with the current `selectedAccountId`.
    ///
    /// No-ops until `hasAlignedInitialScroll` — before the container is measured a
    /// write only corrupts `scrollPosition` without scrolling, and the corrupted
    /// state then blocks the real alignment. The `onScrollGeometryChange` hook above
    /// performs that first write instead.
    ///
    /// The non-animated case defers a runloop tick so the scroll view has re-sized its
    /// content (the accounts list may have just changed under it), and re-reads the
    /// selection at execution time rather than capturing it — the captured value could
    /// already be stale by the time the block runs.
    private func syncScrollToSelected(animated: Bool) {
        guard hasAlignedInitialScroll else { return }
        if animated {
            guard scrollPosition != selectedAccountId else { return }
            withAnimation(AppAnimation.carouselScroll) {
                scrollPosition = selectedAccountId
            }
        } else {
            DispatchQueue.main.async {
                guard scrollPosition != selectedAccountId else { return }
                scrollPosition = selectedAccountId
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
