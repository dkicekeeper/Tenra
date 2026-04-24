//
//  AccountDetailView.swift
//  Tenra
//
//  Detail screen for regular accounts (not deposits, not loans).
//  Built on EntityDetailScaffold — mirrors SubscriptionDetailView's composition.
//

import SwiftUI

struct AccountDetailView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    let account: Account

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var showingAddTransaction = false
    @State private var showingTransfer = false
    @State private var cachedTransactions: [Transaction] = []
    @State private var aggregates = AccountAggregates(totalTransactions: 0, totalIncome: 0, totalExpense: 0)
    @Namespace private var transferNamespace
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager

    /// Live account lookup — reflects edits without re-navigation.
    private var liveAccount: Account {
        transactionsViewModel.accounts.first(where: { $0.id == account.id }) ?? account
    }

    /// Cheap O(N) single-pass counter; feeds `.task(id:)` so the expensive refresh runs
    /// only when relevant transactions change.
    private var refreshTrigger: Int {
        var n = 0
        for tx in transactionStore.transactions
        where tx.accountId == account.id || tx.targetAccountId == account.id {
            n += 1
        }
        return n
    }

    private func refreshData() async {
        let filtered = transactionStore.transactions
            .filter { $0.accountId == account.id || $0.targetAccountId == account.id }
            .sorted { $0.date > $1.date }
        cachedTransactions = filtered
        aggregates = AccountAggregatesCalculator.compute(
            accountId: account.id,
            accountCurrency: liveAccount.currency,
            transactions: filtered
        )
    }

    var body: some View {
        let accountsById = Dictionary(
            uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) }
        )

        EntityDetailScaffold(
            navigationTitle: liveAccount.name,
            primaryAction: ActionConfig(
                title: String(localized: "account.detail.actions.addTransaction", defaultValue: "Add transaction"),
                systemImage: "plus",
                action: { showingAddTransaction = true }
            ),
            secondaryAction: ActionConfig(
                title: String(localized: "account.detail.actions.transfer", defaultValue: "Transfer"),
                systemImage: "arrow.left.arrow.right",
                action: { showingTransfer = true }
            ),
            infoRows: infoRowConfigs(),
            transactions: cachedTransactions,
            historyCurrency: liveAccount.currency,
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
                    icon: liveAccount.iconSource,
                    title: liveAccount.name,
                    primaryAmount: liveAccount.balance,
                    primaryCurrency: liveAccount.currency,
                    showBaseConversion: true,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )
            },
            toolbarMenu: { toolbarMenu }
        )
        .sheet(isPresented: $showingEdit) {
            AccountEditView(
                accountsViewModel: accountsViewModel,
                transactionsViewModel: transactionsViewModel,
                account: liveAccount,
                onSave: { updatedAccount in
                    HapticManager.success()
                    accountsViewModel.updateAccount(updatedAccount)
                    transactionsViewModel.syncAccountsFrom(accountsViewModel)
                    showingEdit = false
                },
                onCancel: { showingEdit = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddTransaction) {
            // TODO: pre-fill accountId once add-transaction supports it.
            // The existing add flow is category-first (TransactionCategoryPickerView →
            // TransactionAddModal). No pre-fill mechanism exists for the source account,
            // so we present the standard picker and let the user pick category + account.
            NavigationStack {
                TransactionCategoryPickerView(
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    transactionStore: transactionStore,
                    timeFilterManager: timeFilterManager
                )
                .environment(timeFilterManager)
                .navigationTitle(String(localized: "account.detail.actions.addTransaction", defaultValue: "Add transaction"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "quickAdd.cancel")) {
                            showingAddTransaction = false
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showingTransfer) {
            AccountActionView(
                transactionsViewModel: transactionsViewModel,
                accountsViewModel: accountsViewModel,
                account: liveAccount,
                namespace: transferNamespace,
                categoriesViewModel: categoriesViewModel
            )
        }
        .alert(
            String(localized: "account.detail.delete.confirmTitle", defaultValue: "Delete account?"),
            isPresented: $showingDeleteConfirm
        ) {
            Button(String(localized: "quickAdd.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete", defaultValue: "Delete"), role: .destructive) {
                HapticManager.warning()
                accountsViewModel.deleteAccount(liveAccount)
                transactionsViewModel.cleanupDeletedAccount(liveAccount.id)
                transactionsViewModel.syncAccountsFrom(accountsViewModel)
                dismiss()
            }
        } message: {
            Text(String(
                localized: "account.detail.delete.confirmMessage",
                defaultValue: "This will permanently delete the account."
            ))
        }
        .task(id: refreshTrigger) {
            await refreshData()
        }
    }

    // MARK: - Info rows

    private func infoRowConfigs() -> [InfoRowConfig] {
        var rows: [InfoRowConfig] = []
        rows.append(InfoRowConfig(
            icon: "creditcard",
            label: String(localized: "accounts.type", defaultValue: "Type"),
            value: accountTypeLabel()
        ))
        rows.append(InfoRowConfig(
            icon: "dollarsign.circle",
            label: String(localized: "accounts.currency", defaultValue: "Currency"),
            value: liveAccount.currency
        ))
        rows.append(InfoRowConfig(
            icon: "number",
            label: String(localized: "account.detail.transactionCount", defaultValue: "Transactions"),
            value: "\(aggregates.totalTransactions)"
        ))
        rows.append(InfoRowConfig(
            icon: "arrow.down.circle",
            label: String(localized: "account.detail.totalIncome", defaultValue: "Total income"),
            value: Formatting.formatCurrency(aggregates.totalIncome, currency: liveAccount.currency)
        ))
        rows.append(InfoRowConfig(
            icon: "arrow.up.circle",
            label: String(localized: "account.detail.totalExpense", defaultValue: "Total expense"),
            value: Formatting.formatCurrency(aggregates.totalExpense, currency: liveAccount.currency)
        ))
        return rows
    }

    private func accountTypeLabel() -> String {
        if liveAccount.isDeposit {
            return String(localized: "accounts.type.deposit", defaultValue: "Deposit")
        }
        if liveAccount.isLoan {
            return String(localized: "accounts.type.loan", defaultValue: "Loan")
        }
        return String(localized: "accounts.type.regular", defaultValue: "Account")
    }

    @ViewBuilder
    private var toolbarMenu: some View {
        Button {
            showingEdit = true
        } label: {
            Label(String(localized: "common.edit", defaultValue: "Edit"), systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label(String(localized: "common.delete", defaultValue: "Delete"), systemImage: "trash")
        }
    }
}


// MARK: - Previews

#Preview("Account Detail View") {
    let coordinator = AppCoordinator()
    let timeFilterManager = TimeFilterManager()
    let sampleAccount = coordinator.transactionStore.accounts.first(where: { !$0.isDeposit && $0.loanInfo == nil })
        ?? Account(name: "Cash", currency: "KZT", iconSource: .sfSymbol("banknote"), balance: 150_000)

    NavigationStack {
        AccountDetailView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            account: sampleAccount
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(timeFilterManager)
    }
}
