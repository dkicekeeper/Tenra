//
//  FinancesView.swift
//  Tenra
//
//  Tab-level hub for managing financial entities: accounts, subscriptions,
//  loans, categories, and subcategories. Each card navigates to the
//  existing list/management view for that entity.
//

import SwiftUI

// MARK: - FinancesDestination

enum FinancesDestination: Hashable {
    case accounts
    case deposits
    case subscriptions
    case loans
    case loanDetail(String) // accountId
    case categories
    case subcategories
}

// MARK: - FinancesView

struct FinancesView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

    @State private var navigationPath = NavigationPath()

    private var transactionsViewModel: TransactionsViewModel { coordinator.transactionsViewModel }
    private var accountsViewModel: AccountsViewModel { coordinator.accountsViewModel }
    private var categoriesViewModel: CategoriesViewModel { coordinator.categoriesViewModel }
    private var transactionStore: TransactionStore { coordinator.transactionStore }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // `.contentReveal` (the pattern used by InsightsView) keeps each card
                    // in the tree and fades it in via its own @State once data is ready.
                    // Unlike `if`-gating + `.transition`, the reveal fires on the view's
                    // own appearance — so the cascade plays when the Finances tab opens,
                    // not only at the instant the init flags flip during app startup.
                    accountsCard
                        .contentReveal(isReady: coordinator.isFastPathDone)
                    depositsCard
                        .contentReveal(isReady: coordinator.isFastPathDone, delay: 0.05)
                    subscriptionsCard
                        .contentReveal(isReady: coordinator.isFullyInitialized, delay: 0.10)
                    loansCard
                        .contentReveal(isReady: coordinator.isFullyInitialized, delay: 0.15)
                    categoriesCard
                        .contentReveal(isReady: coordinator.isFastPathDone, delay: 0.20)
                    subcategoriesCard
                        .contentReveal(isReady: coordinator.isFastPathDone, delay: 0.25)
                }
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle(String(localized: "finances.title"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FinancesDestination.self) { destination in
                switch destination {
                case .accounts:
                    AccountsManagementView(
                        accountsViewModel: accountsViewModel,
                        depositsViewModel: coordinator.depositsViewModel,
                        loansViewModel: coordinator.loansViewModel,
                        transactionsViewModel: transactionsViewModel
                    )
                case .deposits:
                    DepositsListView(
                        accountsViewModel: accountsViewModel,
                        depositsViewModel: coordinator.depositsViewModel,
                        transactionsViewModel: transactionsViewModel
                    )
                case .subscriptions:
                    SubscriptionsListView(
                        transactionStore: transactionStore,
                        transactionsViewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel
                    )
                    .environment(timeFilterManager)
                case .loans:
                    LoansListView(
                        loansViewModel: coordinator.loansViewModel,
                        transactionsViewModel: transactionsViewModel,
                        balanceCoordinator: coordinator.balanceCoordinator
                    )
                    .environment(timeFilterManager)
                case .loanDetail(let accountId):
                    LoanDetailView(
                        loansViewModel: coordinator.loansViewModel,
                        transactionsViewModel: transactionsViewModel,
                        balanceCoordinator: coordinator.balanceCoordinator,
                        accountId: accountId
                    )
                    .environment(timeFilterManager)
                case .categories:
                    CategoriesManagementView(
                        categoriesViewModel: categoriesViewModel,
                        transactionsViewModel: transactionsViewModel
                    )
                case .subcategories:
                    SubcategoriesManagementView(categoriesViewModel: categoriesViewModel)
                }
            }
            // `initial: true` handles cold-launch: pending id is already populated
            // when this view first mounts (set in AppCoordinator.init from the
            // AppDelegate stash). Subsequent fires handle warm-launch (notification
            // tap setting the coordinator's pending id) and `isFullyInitialized`
            // flipping (subscriptions arrive after the deep link did).
            .onChange(of: coordinator.pendingSubscriptionSeriesId, initial: true) {
                navigateToPendingSubscriptionIfPossible()
            }
            .onChange(of: coordinator.isFullyInitialized) {
                navigateToPendingSubscriptionIfPossible()
            }
        }
    }

    /// Resolves a pending deep-link to a subscription detail. If the matching
    /// series isn't loaded yet (cold launch before `isFullyInitialized`), the
    /// pending id is left in place and we retry when state changes.
    private func navigateToPendingSubscriptionIfPossible() {
        guard let seriesId = coordinator.pendingSubscriptionSeriesId else { return }
        guard let subscription = transactionStore.subscriptions.first(where: { $0.id == seriesId }) else {
            // Subscriptions not loaded yet (or series no longer exists).
            // Wait for next isFullyInitialized / pending-id change.
            if coordinator.isFullyInitialized {
                // Series is gone — drop the pending id so we don't loop.
                coordinator.consumePendingSubscription()
            }
            return
        }
        var path = NavigationPath()
        path.append(FinancesDestination.subscriptions)
        path.append(subscription)
        navigationPath = path
        coordinator.consumePendingSubscription()
    }

    // MARK: - Cards

    private var accountsCard: some View {
        NavigationLink(value: FinancesDestination.accounts) {
            AccountsCardView(
                accountsViewModel: accountsViewModel,
                balanceCoordinator: coordinator.balanceCoordinator,
                transactionsViewModel: transactionsViewModel
            )
        }
        .buttonStyle(.bounce)
        .accessibilityIdentifier("finances.accountsCard")
        .screenPadding()
    }

    private var depositsCard: some View {
        NavigationLink(value: FinancesDestination.deposits) {
            DepositsCardView(
                accountsViewModel: accountsViewModel,
                balanceCoordinator: coordinator.balanceCoordinator,
                transactionsViewModel: transactionsViewModel
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var subscriptionsCard: some View {
        NavigationLink(value: FinancesDestination.subscriptions) {
            SubscriptionsCardView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var loansCard: some View {
        NavigationLink(value: FinancesDestination.loans) {
            LoansCardView(
                loansViewModel: coordinator.loansViewModel,
                transactionsViewModel: transactionsViewModel
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var categoriesCard: some View {
        NavigationLink(value: FinancesDestination.categories) {
            CategoriesCardView(categoriesViewModel: categoriesViewModel)
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var subcategoriesCard: some View {
        NavigationLink(value: FinancesDestination.subcategories) {
            SubcategoriesCardView(categoriesViewModel: categoriesViewModel)
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }
}

// MARK: - Preview

#Preview {
    let coordinator = AppCoordinator()
    FinancesView()
        .environment(coordinator)
        .environment(TimeFilterManager())
}
