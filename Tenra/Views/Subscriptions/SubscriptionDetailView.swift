//
//  SubscriptionDetailView.swift
//  AIFinanceManager
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionDetailView: View {
    // ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    let subscription: RecurringSeries
    @State private var showingEditView = false
    @State private var showingDeleteConfirmation = false
    @State private var cachedTransactions: [Transaction] = []
    @Environment(\.dismiss) var dismiss

    private func refreshTransactions() async {
        // Use only the transactions already in the store — the single-next-occurrence
        // model guarantees exactly 1 future transaction exists for active series.
        // No horizon-based generation needed (that was the old 3-month approach).
        cachedTransactions = transactionStore.transactions
            .filter { $0.recurringSeriesId == subscription.id }
            .sorted { $0.date < $1.date }
    }

    private var nextChargeDate: Date? {
        transactionStore.nextChargeDate(for: subscription.id)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Info card
                subscriptionInfoCard
                    .screenPadding()
                
                // Transactions history
                if !cachedTransactions.isEmpty {
                    transactionsSection
                        .screenPadding()
                }
            }
//            .padding(.vertical, AppSpacing.md)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditView = true
                    } label: {
                        Label(String(localized: "subscriptions.edit"), systemImage: "pencil")
                    }
                    
                    if subscription.subscriptionStatus == .active {
                        Button {
                            Task {
                                try await transactionStore.pauseSubscription(id: subscription.id)
                            }
                        } label: {
                            Label(String(localized: "subscriptions.pause"), systemImage: "pause.circle")
                        }
                    } else if subscription.subscriptionStatus == .paused {
                        Button {
                            Task {
                                // Find subcategory IDs from any existing transaction in this series
                                // to apply them to newly generated occurrences after resume.
                                let existingTx = transactionStore.transactions.first {
                                    $0.recurringSeriesId == subscription.id
                                }
                                let subcategoryIds = existingTx.map {
                                    categoriesViewModel.getSubcategoriesForTransaction($0.id).map { $0.id }
                                } ?? []

                                let idsBefore = Set(transactionStore.transactions.map { $0.id })

                                try await transactionStore.resumeSubscription(id: subscription.id)

                                if !subcategoryIds.isEmpty {
                                    let idsAfter = Set(transactionStore.transactions.map { $0.id })
                                    let newIds = idsAfter.subtracting(idsBefore)
                                    for id in newIds {
                                        categoriesViewModel.linkSubcategoriesToTransaction(
                                            transactionId: id,
                                            subcategoryIds: subcategoryIds
                                        )
                                    }
                                }
                            }
                        } label: {
                            Label(String(localized: "subscriptions.resume"), systemImage: "play.circle")
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "subscriptions.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            SubscriptionEditView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                subscription: subscription
            )
        }
        .alert(String(localized: "subscriptions.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {}
            
            Button(String(localized: "subscriptions.deleteOnlySubscription"), role: .destructive) {
                Task {
                    try await transactionStore.deleteSeries(id: subscription.id, deleteTransactions: false)
                    dismiss()
                }
            }
            
            Button(String(localized: "subscriptions.deleteSubscriptionAndTransactions"), role: .destructive) {
                Task {
                    try await transactionStore.deleteSeries(id: subscription.id, deleteTransactions: true)
                    dismiss()
                }
            }
        } message: {
            Text(String(localized: "subscriptions.deleteConfirmMessage"))
        }
        .task(id: subscription.id) {
            await refreshTransactions()
        }
        .onChange(of: transactionStore.transactions.count) { _, _ in
            Task { await refreshTransactions() }
        }
    }
    
    private var subscriptionInfoCard: some View {
        VStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(spacing: AppSpacing.md) {
                // REFACTORED 2026-02-02: Use IconView with glass effect
                IconView(
                    source: subscription.iconSource,
                    style: .glassHero()
                )
                
                VStack(alignment: .center, spacing: AppSpacing.xs) {
                    Text(subscription.description)
                        .font(AppTypography.h1)
                    
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: subscription.amount).doubleValue,
                        currency: subscription.currency,
                        fontSize: AppTypography.h4,
                        color: .secondary
                    )
                }
                Spacer()
            }
            VStack(spacing: AppSpacing.sm)
            {
                InfoRow(
                    icon: "tag.fill",
                    label: String(
                        localized: "subscriptions.category"
                    ),
                    value: subscription.category
                )
                InfoRow(
                    icon: "repeat",
                    label: String(
                        localized: "subscriptions.frequency"
                    ),
                    value: subscription.frequency.displayName
                )
                
                if let nextDate = nextChargeDate {
                    InfoRow(
                        icon: "calendar.badge.clock",
                        label: String(
                            localized: "subscriptions.nextCharge"
                        ),
                        value: formatDate(
                            nextDate
                        )
                    )
                }
                
                if let accountId = subscription.accountId,
                   let account = transactionsViewModel.accounts.first(
                    where: {
                        $0.id == accountId
                    }) {
                    InfoRow(
                        icon: "creditcard.fill",
                        label: String(
                            localized: "subscriptions.account"
                        ),
                        value: account.name
                    )
                }
                
                InfoRow(
                    icon: "checkmark.circle.fill",
                    label: String(
                        localized: "subscriptions.status"
                    ),
                    value: statusText
                )
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }
    }
    
    private var statusText: String {
        switch subscription.subscriptionStatus {
        case .active:
            return String(localized: "subscriptions.status.active")
        case .paused:
            return String(localized: "subscriptions.status.paused")
        case .archived:
            return String(localized: "subscriptions.status.archived")
        case .none:
            return String(localized: "subscriptions.status.unknown")
        }
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "subscriptions.transactionHistory"))
                .font(AppTypography.h4)

            VStack(spacing: AppSpacing.sm) {
                ForEach(cachedTransactions) { transaction in
                    let styleData = CategoryStyleHelper.cached(
                        category: transaction.category,
                        type: transaction.type,
                        customCategories: categoriesViewModel.customCategories
                    )
                    let sourceAccount = transactionsViewModel.accounts.first { $0.id == transaction.accountId }
                    let targetAccount = transaction.targetAccountId.flatMap { tid in
                        transactionsViewModel.accounts.first { $0.id == tid }
                    }

                    TransactionCard(
                        transaction: transaction,
                        currency: subscription.currency,
                        styleData: styleData,
                        sourceAccount: sourceAccount,
                        targetAccount: targetAccount,
                        viewModel: nil,
                        categoriesViewModel: nil,
                        accountsViewModel: nil,
                        balanceCoordinator: nil
                    )
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateFormatter.string(from: date)
    }
}



#Preview("Active Subscription") {
    let coordinator = AppCoordinator()
    let timeFilterManager = TimeFilterManager()
    
    NavigationStack {
        SubscriptionDetailView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            subscription: RecurringSeries(
                amount: 9.99,
                currency: "USD",
                category: "Entertainment",
                description: "Netflix",
                frequency: .monthly,
                startDate: "2024-01-01",
                kind: .subscription,
                iconSource: .sfSymbol("tv.fill"),
                status: .active
            )
        )
        .environment(timeFilterManager)
    }
}

#Preview("Paused Subscription") {
    let coordinator = AppCoordinator()
    let timeFilterManager = TimeFilterManager()
    
    NavigationStack {
        SubscriptionDetailView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            subscription: RecurringSeries(
                amount: 14.99,
                currency: "USD",
                category: "Music",
                description: "Spotify",
                frequency: .monthly,
                startDate: "2024-01-01",
                kind: .subscription,
                iconSource: .sfSymbol("music.note"),
                status: .paused
            )
        )
        .environment(timeFilterManager)
    }
}

#Preview("Archived Subscription") {
    let coordinator = AppCoordinator()
    let timeFilterManager = TimeFilterManager()
    
    NavigationStack {
        SubscriptionDetailView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            subscription: RecurringSeries(
                amount: 4.99,
                currency: "USD",
                category: "Storage",
                description: "iCloud",
                frequency: .monthly,
                startDate: "2023-01-01",
                kind: .subscription,
                iconSource: .sfSymbol("cloud.fill"),
                status: .archived
            )
        )
        .environment(timeFilterManager)
    }
}

