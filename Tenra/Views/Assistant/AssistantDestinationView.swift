//
//  AssistantDestinationView.swift
//  Tenra
//
//  Where an `open` block of a reply leads (docs/domains/assistant.md §4): the app's own
//  screens, pushed on the assistant's navigation stack, built the way the screens that own
//  them build them. The model names the destination and, for an account or a category, its id
//  from <app_context>; an id that matches nothing (deleted since, or made up) shows an empty
//  state instead of a wrong screen.
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

    /// Nil for an account or a category without an id: such a block leads nowhere.
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
        }
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
