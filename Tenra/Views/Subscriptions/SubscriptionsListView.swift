//
//  SubscriptionsListView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsListView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @Namespace private var subscriptionNamespace
    private enum SubscriptionSheetItem: Identifiable {
        case new
        case edit(RecurringSeries)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let sub): return sub.id
            }
        }
    }
    @State private var sheetItem: SubscriptionSheetItem?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !transactionStore.subscriptions.isEmpty {
                    SubscriptionCalendarView(
                        subscriptions: transactionStore.subscriptions,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency
                    )
                    .chartAppear()
                    .screenPadding()
                }

                if transactionStore.subscriptions.isEmpty {
                    emptyState
                        .screenPadding()
                } else {
                    subscriptionsList
                        .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "subscriptions.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: RecurringSeries.self) { subscription in
            SubscriptionDetailView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel,
                subscription: subscription
            )
            .environment(timeFilterManager)
            .navigationTransition(.zoom(sourceID: subscription.id, in: subscriptionNamespace))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetItem = .new
                } label: {
                    Image(systemName: "plus")
                }
                .glassProminentButton()
            }
        }
        .sheet(item: $sheetItem) { item in
            switch item {
            case .new:
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    subscription: nil
                )
            case .edit(let subscription):
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    subscription: subscription
                )
            }
        }
    }
    
    private var emptyState: some View {
        EmptyStateView(
            icon: "creditcard",
            title: String(localized: "subscriptions.empty"),
            description: String(localized: "subscriptions.emptyDescription"),
            actionTitle: String(localized: "subscriptions.addSubscription"),
            action: {
                sheetItem = .new
            }
        )
    }
    
    private var subscriptionsList: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(Array(transactionStore.subscriptions.enumerated()), id: \.element.id) { index, subscription in
                let nextChargeDate = transactionStore.nextChargeDate(for: subscription.id)

                NavigationLink(value: subscription) {
                    SubscriptionCard(
                        subscription: subscription,
                        nextChargeDate: nextChargeDate
                    )
                    .matchedTransitionSource(id: subscription.id, in: subscriptionNamespace)
                }
                .buttonStyle(PlainButtonStyle())
                .chartAppear(delay: Double(index) * 0.05)
            }
        }
    }
}

// MARK: - Previews

#Preview("Subscriptions List - Empty") {
    let coordinator = AppCoordinator()
    return NavigationStack {
        SubscriptionsListView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Subscriptions List - Cards") {
    // Simulates the list body with real SubscriptionCard components
    let dateFormatter = DateFormatters.dateFormatter
    let today = dateFormatter.string(from: Date())
    let sampleSubscriptions = [
        RecurringSeries(id: "p1", amount: Decimal(9.99),  currency: "USD", category: "Развлечения",
                        description: "Netflix",             accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .brandService("Netflix"),  status: .active),
        RecurringSeries(id: "p2", amount: Decimal(4990),  currency: "KZT", category: "Музыка",
                        description: "Spotify Premium",    accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .brandService("Spotify"),  status: .active),
        RecurringSeries(id: "p3", amount: Decimal(2990),  currency: "KZT", category: "Облако",
                        description: "iCloud 50 GB",       accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("cloud.fill"),   status: .active),
        RecurringSeries(id: "p4", amount: Decimal(15000), currency: "KZT", category: "Здоровье",
                        description: "Фитнес зал",         accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("dumbbell.fill"), status: .paused)
    ]
    NavigationStack {
        List {
            ForEach(sampleSubscriptions) { sub in
                SubscriptionCard(
                    subscription: sub,
                    nextChargeDate: Date().addingTimeInterval(Double(Int.random(in: 1...28)) * 86400)
                )
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Подписки")
        .navigationBarTitleDisplayMode(.large)
    }
    .environment(TimeFilterManager())
}

#Preview("Subscription Card") {
    let dateFormatter = DateFormatters.dateFormatter
    let today = dateFormatter.string(from: Date())

    let sampleSubscription = RecurringSeries(
        id: "preview-card",
        amount: Decimal(9.99),
        currency: "USD",
        category: "Entertainment",
        description: "Netflix",
        accountId: "preview-account",
        frequency: .monthly,
        startDate: today,
        kind: .subscription,
        iconSource: .brandService("Netflix"),
        status: .active
    )

    SubscriptionCard(
        subscription: sampleSubscription,
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
