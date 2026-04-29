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
                    if coordinator.isFastPathDone {
                        accountsCard
                            .transition(.opacity)
                    }
                    if coordinator.isFullyInitialized {
                        subscriptionsCard
                            .transition(.opacity)
                        loansCard
                            .transition(.opacity)
                    }
                    if coordinator.isFastPathDone {
                        categoriesCard
                            .transition(.opacity)
                        subcategoriesCard
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, AppSpacing.md)
                .animation(AppAnimation.contentRevealAnimation, value: coordinator.isFastPathDone)
                .animation(AppAnimation.contentRevealAnimation, value: coordinator.isFullyInitialized)
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
        }
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
