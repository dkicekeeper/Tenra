//
//  AssistantDestinationView.swift
//  Tenra
//
//  Where an `open` block of a reply leads (docs/domains/assistant.md §4): the app's own
//  screens, pushed on the assistant's navigation stack, built the way the screens that own
//  them build them. The model names the destination and, for an account, a category or an asset,
//  its id from <app_context>; an id that matches nothing (deleted since, or made up) shows an
//  empty state instead of a wrong screen.
//

import SwiftUI

/// A screen an `open` block leads to.
enum AssistantRoute: Hashable {
    case category(String)
    case account(String)
    /// The history, filtered to a category when the block names one.
    case history(categoryId: String?)
    case analytics
    case budgets
    case subscriptions
    case assets
    case asset(String)
    case accounts
    case deposits
    case loans
    case goals
    case goal(String)
    case debts
    case debt(String)
    case settings
    case backups
    case walletGuide
    case review
    /// A loan's screen with its payment form open.
    case loanPayment(String)
    /// The list a new one belongs to, with its form open and prefilled.
    case create(AgentCreateKind, AgentFormPrefill)

    /// Nil for an account, a category or an asset without an id: such a block leads nowhere.
    init?(destination: AgentDestination, targetId: String?) {
        let id = targetId.flatMap { $0.isEmpty ? nil : $0 }
        switch destination {
        case .category:
            guard let id else { return nil }
            self = .category(id)
        case .account:
            guard let id else { return nil }
            self = .account(id)
        case .history: self = .history(categoryId: id)
        case .analytics: self = .analytics
        case .budgets: self = .budgets
        case .subscriptions: self = .subscriptions
        case .assets: self = .assets
        case .asset:
            guard let id else { return nil }
            self = .asset(id)
        case .accounts: self = .accounts
        case .deposits: self = .deposits
        case .loans: self = .loans
        case .goals: self = .goals
        case .goal:
            guard let id else { return nil }
            self = .goal(id)
        case .debts: self = .debts
        case .debt:
            guard let id else { return nil }
            self = .debt(id)
        case .settings: self = .settings
        case .backups: self = .backups
        case .walletGuide: self = .walletGuide
        case .review: self = .review
        case .loanPayment:
            guard let id else { return nil }
            self = .loanPayment(id)
        case .appReview, .manageSubscription:
            // A link out of the app (AssistantReviewLink), not a screen.
            return nil
        }
    }

    var systemImage: String {
        switch self {
        case .category: "square.grid.2x2"
        case .account: "creditcard"
        case .history: "clock.arrow.circlepath"
        case .analytics: "chart.bar"
        case .budgets: "gauge.with.dots.needle.50percent"
        case .subscriptions: "repeat"
        case .assets, .asset: "house"
        case .accounts: "creditcard"
        case .deposits: "banknote"
        case .loans, .loanPayment: "building.columns"
        case .goals, .goal: "target"
        case .debts, .debt: "person.2"
        case .settings: "gearshape"
        case .backups: "icloud"
        case .walletGuide: "wallet.pass"
        case .review: "checklist"
        case .create: "plus.circle"
        }
    }
}

struct AssistantDestinationView: View {
    let route: AssistantRoute

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

    var body: some View {
        destination
            .environment(timeFilterManager)
    }

    @ViewBuilder
    private var destination: some View {
        let store = coordinator.transactionStore
        switch route {
        case .category(let id):
            if let category = store.categories.first(where: { $0.id == id }) {
                CategoryDetailView(
                    transactionStore: store,
                    transactionsViewModel: coordinator.transactionsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    category: category
                )
            } else {
                missing
            }
        case .account(let id):
            if let account = store.accounts.first(where: { $0.id == id }) {
                accountDetail(account)
            } else {
                missing
            }
        case .history(let categoryId):
            HistoryView(
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                paginationController: coordinator.transactionPaginationController,
                initialCategory: categoryId.flatMap { id in store.categories.first { $0.id == id }?.name }
            )
        case .analytics:
            InsightsView(insightsViewModel: coordinator.insightsViewModel)
                .navigationTitle(String(localized: "tab.analytics"))
        case .budgets:
            // Budgets live on the categories: their progress shows in this list.
            CategoriesManagementView(
                categoriesViewModel: coordinator.categoriesViewModel,
                transactionsViewModel: coordinator.transactionsViewModel
            )
        case .subscriptions:
            SubscriptionsListView(
                transactionStore: store,
                transactionsViewModel: coordinator.transactionsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                accountsViewModel: coordinator.accountsViewModel
            )
        case .assets:
            // Its cards push FinancesDestination, which only Finances' own stack handles.
            AssetsListView(assetStore: coordinator.assetStore)
                .navigationDestination(for: FinancesDestination.self) { destination in
                    if case .assetDetail(let assetId) = destination {
                        AssetDetailView(assetStore: coordinator.assetStore, assetId: assetId)
                            .environment(timeFilterManager)
                    }
                }
        case .asset(let id):
            // An id that matches nothing: the screen's own "not found".
            AssetDetailView(assetStore: coordinator.assetStore, assetId: id)
        case .accounts:
            accountsList(adding: nil)
        case .deposits:
            depositsList(adding: nil)
        case .loans:
            loansList(adding: nil)
        case .loanPayment(let id):
            if let account = store.accounts.first(where: { $0.id == id }), account.isLoan {
                LoanDetailView(
                    loansViewModel: coordinator.loansViewModel,
                    transactionsViewModel: coordinator.transactionsViewModel,
                    balanceCoordinator: coordinator.balanceCoordinator,
                    accountId: account.id,
                    paying: true
                )
            } else {
                missing
            }
        case .goals:
            // Its cards push FinancesDestination, which only Finances' own stack handles.
            GoalsListView(goalStore: coordinator.goalStore)
                .navigationDestination(for: FinancesDestination.self) { destination in
                    if case .goalDetail(let goalId) = destination {
                        GoalDetailView(goalStore: coordinator.goalStore, goalId: goalId)
                            .environment(timeFilterManager)
                    }
                }
        case .goal(let id):
            if coordinator.goalStore.goals.contains(where: { $0.id == id }) {
                GoalDetailView(goalStore: coordinator.goalStore, goalId: id)
            } else {
                missing
            }
        case .debts:
            DebtsListView(debtStore: coordinator.debtStore)
                .navigationDestination(for: FinancesDestination.self) { destination in
                    if case .debtDetail(let debtId) = destination {
                        DebtDetailView(debtStore: coordinator.debtStore, debtId: debtId)
                            .environment(timeFilterManager)
                    }
                }
        case .debt(let id):
            if coordinator.debtStore.debts.contains(where: { $0.id == id }) {
                DebtDetailView(debtStore: coordinator.debtStore, debtId: id)
            } else {
                missing
            }
        case .settings:
            SettingsView(
                settingsViewModel: coordinator.settingsViewModel,
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                transactionStore: store,
                depositsViewModel: coordinator.depositsViewModel,
                loansViewModel: coordinator.loansViewModel,
                cloudSyncViewModel: coordinator.cloudSyncViewModel
            )
        case .backups:
            CloudBackupsView(
                cloudSyncViewModel: coordinator.cloudSyncViewModel,
                transactionCount: coordinator.transactionsViewModel.allTransactions.count,
                accountCount: coordinator.accountsViewModel.accounts.count,
                categoryCount: coordinator.categoriesViewModel.customCategories.count
            )
        case .walletGuide:
            WalletSetupGuideView()
        case .review:
            WalletReviewView(
                transactionsViewModel: coordinator.transactionsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                accountsViewModel: coordinator.accountsViewModel
            )
        case .create(let kind, let prefill):
            switch kind {
            case .account: accountsList(adding: prefill)
            case .deposit: depositsList(adding: prefill)
            case .loan: loansList(adding: prefill)
            case .category:
                CategoriesManagementView(
                    categoriesViewModel: coordinator.categoriesViewModel,
                    transactionsViewModel: coordinator.transactionsViewModel,
                    adding: prefill
                )
            }
        }
    }

    // The lists as Finances builds them; with `adding`, the list opens its own form for a new
    // one (its Pro gate first), so a thing made from Ten's button is saved the list's way.

    private func accountsList(adding prefill: AgentFormPrefill?) -> some View {
        AccountsManagementView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            adding: prefill
        )
    }

    private func depositsList(adding prefill: AgentFormPrefill?) -> some View {
        DepositsListView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            adding: prefill
        )
    }

    private func loansList(adding prefill: AgentFormPrefill?) -> some View {
        LoansListView(
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            adding: prefill
        )
    }

    /// The account's detail screen by its kind, as the accounts list opens it.
    @ViewBuilder
    private func accountDetail(_ account: Account) -> some View {
        if account.isDeposit {
            DepositDetailView(
                depositsViewModel: coordinator.depositsViewModel,
                transactionsViewModel: coordinator.transactionsViewModel,
                balanceCoordinator: coordinator.balanceCoordinator,
                accountId: account.id
            )
        } else if account.isLoan {
            LoanDetailView(
                loansViewModel: coordinator.loansViewModel,
                transactionsViewModel: coordinator.transactionsViewModel,
                balanceCoordinator: coordinator.balanceCoordinator,
                accountId: account.id
            )
        } else {
            AccountDetailView(
                transactionStore: coordinator.transactionStore,
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                account: account
            )
        }
    }

    private var missing: some View {
        EmptyState(
            icon: "questionmark.folder",
            title: String(localized: "assistant.open.missing")
        )
    }
}
