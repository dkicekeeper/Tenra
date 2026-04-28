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
    @State private var showingUnlinkAllConfirmation = false
    @State private var cachedTransactions: [Transaction] = []
    @State private var cachedSpentAllTimeInSubCurrency: Double = 0
    @Environment(\.dismiss) var dismiss

    /// Live subscription from the store — reflects pause/resume/edit changes in real time.
    private var liveSubscription: RecurringSeries {
        transactionStore.seriesById[subscription.id] ?? subscription
    }

    /// Reactive trigger: cheap O(N) single pass on transactions (count only).
    /// Intentionally avoids hashing all ids — that was the 3000-tx freeze culprit.
    private var linkedTransactionCount: Int {
        var n = 0
        for tx in transactionStore.transactions where tx.recurringSeriesId == subscription.id {
            n += 1
        }
        return n
    }

    private func refreshTransactions() async {
        let linked = transactionStore.transactions
            .filter { $0.recurringSeriesId == subscription.id }
            .sorted { $0.date > $1.date }
        cachedTransactions = linked
        // Recompute cached sum off the main critical path; O(N) but only on store change.
        cachedSpentAllTimeInSubCurrency = computeSpentAllTime(in: linked, currency: liveSubscription.currency)
    }

    private func computeSpentAllTime(in txs: [Transaction], currency: String) -> Double {
        txs.reduce(0.0) { total, tx in
            if tx.currency == currency {
                return total + tx.amount
            }
            if let converted = CurrencyConverter.convertSync(
                amount: tx.amount, from: tx.currency, to: currency
            ) {
                return total + converted
            }
            if let stored = tx.convertedAmount { return total + stored }
            return total + tx.amount
        }
    }

    private var nextChargeDate: Date? {
        transactionStore.nextChargeDate(for: liveSubscription.id)
    }

    var body: some View {
        let accountsById = Dictionary(uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) })

        EntityDetailScaffold(
            navigationTitle: liveSubscription.description,
            navigationAmount: NSDecimalNumber(decimal: liveSubscription.amount).doubleValue,
            navigationCurrency: liveSubscription.currency,
            infoRows: infoRowConfigs(),
            transactions: cachedTransactions,
            historyCurrency: liveSubscription.currency,
            accountsById: accountsById,
            styleHelper: { tx in
                CategoryStyleHelper.cached(
                    category: tx.category,
                    type: tx.type,
                    customCategories: categoriesViewModel.customCategories
                )
            },
            viewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: accountsViewModel.balanceCoordinator,
            hero: {
                HeroSection(
                    icon: liveSubscription.iconSource,
                    title: liveSubscription.description,
                    primaryAmount: NSDecimalNumber(decimal: liveSubscription.amount).doubleValue,
                    primaryCurrency: liveSubscription.currency,
                    showBaseConversion: true,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )
            },
            toolbarMenu: {
                subscriptionToolbarMenu
            }
        )
        .sheet(isPresented: $showingEditView) {
            SubscriptionEditView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
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
        .alert(
            String(localized: "subscription.unlinkAll.title", defaultValue: "Unlink all transactions?"),
            isPresented: $showingUnlinkAllConfirmation
        ) {
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {}
            Button(String(localized: "subscription.unlinkAll.confirm", defaultValue: "Unlink All"), role: .destructive) {
                Task {
                    try? await transactionStore.unlinkAllTransactions(fromSeriesId: subscription.id)
                }
            }
        } message: {
            Text(String(
                format: String(localized: "subscription.unlinkAll.message", defaultValue: "Remove the subscription link from %d transactions? The transactions themselves remain intact."),
                linkedTransactionCount
            ))
        }
        .navigationDestination(isPresented: $showingLinkPayments) {
            SubscriptionLinkPaymentsView(
                subscription: liveSubscription,
                transactionStore: transactionStore,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel
            )
        }
        .task(id: linkedTransactionCount) {
            await refreshTransactions()
        }
    }

    private func infoRowConfigs() -> [InfoRowConfig] {
        var rows: [InfoRowConfig] = []
        rows.append(InfoRowConfig(
            icon: "tag.fill",
            label: String(localized: "subscriptions.category"),
            value: liveSubscription.category
        ))
        rows.append(InfoRowConfig(
            icon: "repeat",
            label: String(localized: "subscriptions.frequency"),
            value: liveSubscription.frequency.displayName
        ))
        if let nextDate = nextChargeDate {
            rows.append(InfoRowConfig(
                icon: "calendar.badge.clock",
                label: String(localized: "subscriptions.nextCharge"),
                value: formatDate(nextDate)
            ))
        }
        if let accountId = liveSubscription.accountId,
           let account = transactionsViewModel.accounts.first(where: { $0.id == accountId }) {
            rows.append(InfoRowConfig(
                icon: "creditcard.fill",
                label: String(localized: "subscriptions.account"),
                value: account.name
            ))
        }
        rows.append(InfoRowConfig(
            icon: "checkmark.circle.fill",
            label: String(localized: "subscriptions.status"),
            value: statusText
        ))
        rows.append(InfoRowConfig(
            icon: "sum",
            label: String(localized: "subscriptions.spentAllTime", defaultValue: "Spent all time"),
            value: spentAllTimeDisplay
        ))
        return rows
    }

    @ViewBuilder
    private var subscriptionToolbarMenu: some View {
        Button {
            showingLinkPayments = true
        } label: {
            Label(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"),
                  systemImage: "link.badge.plus")
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

        if linkedTransactionCount > 0 {
            Divider()
            Button(role: .destructive) {
                showingUnlinkAllConfirmation = true
            } label: {
                Label(String(localized: "subscription.unlinkAll", defaultValue: "Unlink all transactions"),
                      systemImage: "link.badge.minus")
            }
        }

        Divider()

        Button(role: .destructive) {
            showingDeleteConfirmation = true
        } label: {
            Label(String(localized: "subscriptions.delete"), systemImage: "trash")
        }
    }

    private var spentAllTimeDisplay: String {
        let subCurrency = liveSubscription.currency
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let subTotal = cachedSpentAllTimeInSubCurrency
        let primary = Formatting.formatCurrency(subTotal, currency: subCurrency)

        if subCurrency != baseCurrency,
           let baseTotal = CurrencyConverter.convertSync(amount: subTotal, from: subCurrency, to: baseCurrency) {
            return primary + " · " + Formatting.formatCurrency(baseTotal, currency: baseCurrency)
        }
        return primary
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
