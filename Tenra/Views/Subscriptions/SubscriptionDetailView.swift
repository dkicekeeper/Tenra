//
//  SubscriptionDetailView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionDetailView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    let subscription: RecurringSeries
    @State private var showingEditView = false
    @State private var showingDeleteConfirmation = false
    @State private var showingLinkPayments = false
    @State private var cachedTransactions: [Transaction] = []
    @Environment(\.dismiss) var dismiss

    /// Live subscription from the store — reflects pause/resume/edit changes in real time.
    private var liveSubscription: RecurringSeries {
        transactionStore.recurringSeries.first(where: { $0.id == subscription.id }) ?? subscription
    }

    private func refreshTransactions() async {
        cachedTransactions = transactionStore.transactions
            .filter { $0.recurringSeriesId == subscription.id }
            .sorted { $0.date > $1.date }
    }

    private var nextChargeDate: Date? {
        transactionStore.nextChargeDate(for: liveSubscription.id)
    }

    private var transactionDateSections: [(date: String, displayLabel: String, transactions: [Transaction])] {
        let grouped = Dictionary(grouping: cachedTransactions) { $0.date }
        return grouped.sorted { $0.key > $1.key }.map { key, txs in
            (date: key, displayLabel: formatTransactionDate(key), transactions: txs)
        }
    }

    private func formatTransactionDate(_ isoDate: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: isoDate) else { return isoDate }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "common.today", defaultValue: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "common.yesterday", defaultValue: "Yesterday") }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return DateFormatters.displayDateFormatter.string(from: date)
        }
        return DateFormatters.displayDateWithYearFormatter.string(from: date)
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
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingLinkPayments = true
                    } label: {
                        Label(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"), systemImage: "link.badge.plus")
                    }

                    Button {
                        showingEditView = true
                    } label: {
                        Label(String(localized: "subscriptions.edit"), systemImage: "pencil")
                    }
                    
                    if liveSubscription.subscriptionStatus == .active {
                        Button {
                            Task {
                                try await transactionStore.pauseSubscription(id: liveSubscription.id)
                            }
                        } label: {
                            Label(String(localized: "subscriptions.pause"), systemImage: "pause.circle")
                        }
                    } else if liveSubscription.subscriptionStatus == .paused {
                        Button {
                            Task {
                                // Find subcategory IDs from any existing transaction in this series
                                // to apply them to newly generated occurrences after resume.
                                let existingTx = transactionStore.transactions.first {
                                    $0.recurringSeriesId == liveSubscription.id
                                }
                                let subcategoryIds = existingTx.map {
                                    categoriesViewModel.getSubcategoriesForTransaction($0.id).map { $0.id }
                                } ?? []

                                let idsBefore = Set(transactionStore.transactions.map { $0.id })

                                try await transactionStore.resumeSubscription(id: liveSubscription.id)

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
                subscription: liveSubscription
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
        .navigationDestination(isPresented: $showingLinkPayments) {
            SubscriptionLinkPaymentsView(
                subscription: liveSubscription,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel
            )
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
                IconView(
                    source: liveSubscription.iconSource,
                    style: .glassHero()
                )

                VStack(alignment: .center, spacing: AppSpacing.xs) {
                    Text(liveSubscription.description)
                        .font(AppTypography.h1)
                    
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: liveSubscription.amount).doubleValue,
                        currency: liveSubscription.currency,
                        fontSize: AppTypography.h4,
                        color: .secondary
                    )

                    if liveSubscription.currency != transactionsViewModel.appSettings.baseCurrency {
                        ConvertedAmountView(
                            amount: NSDecimalNumber(decimal: liveSubscription.amount).doubleValue,
                            fromCurrency: liveSubscription.currency,
                            toCurrency: transactionsViewModel.appSettings.baseCurrency,
                            fontSize: AppTypography.caption,
                            color: .secondary.opacity(0.7)
                        )
                    }
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
                    value: liveSubscription.category
                )
                InfoRow(
                    icon: "repeat",
                    label: String(
                        localized: "subscriptions.frequency"
                    ),
                    value: liveSubscription.frequency.displayName
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
                
                if let accountId = liveSubscription.accountId,
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
        switch liveSubscription.subscriptionStatus {
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

            VStack(spacing: 0) {
                ForEach(transactionDateSections, id: \.date) { section in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(section.displayLabel)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.secondary)
                            .padding(.top, AppSpacing.sm)

                        ForEach(section.transactions) { transaction in
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
                                currency: liveSubscription.currency,
                                styleData: styleData,
                                sourceAccount: sourceAccount,
                                targetAccount: targetAccount,
                                viewModel: transactionsViewModel,
                                categoriesViewModel: categoriesViewModel,
                                accountsViewModel: accountsViewModel,
                                balanceCoordinator: accountsViewModel.balanceCoordinator
                            )
                        }
                    }
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
            accountsViewModel: coordinator.accountsViewModel,
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
            accountsViewModel: coordinator.accountsViewModel,
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
            accountsViewModel: coordinator.accountsViewModel,
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

