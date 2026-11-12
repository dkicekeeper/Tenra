//
//  AccountDetailView.swift
//  Tenra
//
//  Detail screen for regular accounts (not deposits, not loans).
//  Built on EntityDetailScaffold — mirrors SubscriptionDetailView's composition.
//

import OSLog
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
    @State private var convertingAccount: Account?
    @State private var showingPaywall = false
    @State private var cachedTransactions: [Transaction] = []
    @State private var aggregates = AccountAggregates(totalTransactions: 0, totalIncome: 0, totalExpense: 0)
    @State private var accountsById: [String: Account] = [:]
    @Namespace private var transferNamespace
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(PremiumManager.self) private var premium

    private let logger = Logger(subsystem: "Tenra", category: "AccountDetailView")

    /// Live account lookup — reflects edits without re-navigation.
    /// O(1) via the `accountById` index.
    private var liveAccount: Account {
        transactionStore.accountById[account.id] ?? account
    }

    /// Live balance from the BalanceCoordinator (the same source the accounts list
    /// reads). The Account entity's cached `.balance` field doesn't re-read here after
    /// a transaction/transfer until re-navigation; `balances` is @Observable, so reading
    /// it keeps the hero and navigation-bar amount current.
    private var liveBalance: Double {
        accountsViewModel.balanceCoordinator?.balances[account.id] ?? liveAccount.balance
    }

    /// Combined equatable trigger of scalar counters. `mutationVersion` and
    /// `accountsMutationVersion` are `@ObservationIgnored`, so the observable `transactions` is
    /// read too (its count, nothing is copied): otherwise an edit that leaves the balance as it
    /// was (a note, a category) never re-evaluates the body. Same as `CategoryDetailView`.
    private var refreshTrigger: RefreshKey {
        _ = transactionStore.transactions.count
        return RefreshKey(
            mutationVersion: transactionStore.mutationVersion,
            accountsVersion: transactionStore.accountsMutationVersion,
            ratesVersion: transactionStore.currencyRatesVersion,
            accountId: account.id
        )
    }

    private struct RefreshKey: Equatable {
        let mutationVersion: Int
        let accountsVersion: Int
        let ratesVersion: Int
        let accountId: String
    }

    private func refreshData() async {
        // O(1) bucket lookup from the maintained index.
        let bucket = transactionStore.transactionsByAccount[account.id] ?? []
        cachedTransactions = bucket.sorted { $0.date > $1.date }
        // O(1) aggregate read — pre-computed by `TransactionStore+AccountAggregates`.
        aggregates = AccountAggregatesCalculator.compute(
            accountId: account.id,
            store: transactionStore
        )
    }

    var body: some View {

        EntityDetailScaffold(
            navigationTitle: liveAccount.name,
            navigationAmount: liveBalance,
            navigationCurrency: liveAccount.currency,
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
                    primaryAmount: liveBalance,
                    primaryCurrency: liveAccount.currency,
                    showBaseConversion: true,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )
            },
            toolbarMenu: { toolbarMenu }
        )
        .heroAccentGlow(icon: liveAccount.iconSource)
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
        .navigationDestination(isPresented: $showingAddTransaction) {
            // Push the category picker into the navigation stack so the entry point
            // matches the Transfer flow (also a navigationDestination) — back-navigation
            // via swipe/back-button replaces the modal Cancel button.
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
        .sheet(item: $convertingAccount) { converting in
            DepositEditView(
                depositsViewModel: appCoordinator.depositsViewModel,
                account: converting,
                onSave: { updatedAccount in
                    HapticManager.success()
                    accountsViewModel.updateDeposit(updatedAccount)
                    var depositTransactions: [Transaction] = []
                    appCoordinator.depositsViewModel.reconcileAllDeposits(
                        allTransactions: transactionsViewModel.allTransactions,
                        onTransactionCreated: { transaction in
                            depositTransactions.append(transaction)
                        }
                    )
                    Task {
                        for tx in depositTransactions {
                            do {
                                _ = try await transactionStore.add(tx)
                            } catch {
                                logger.error("Failed to add deposit transaction: \(error.localizedDescription)")
                            }
                        }
                    }
                    convertingAccount = nil
                    dismiss()
                }
            )
        }
        // Deposits are Pro: the same gate as the convert action of the accounts list
        // (AccountsManagementView). After unlocking, the conversion form opens.
        .paywallSheet(isPresented: $showingPaywall, source: .depositAdd) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                convertingAccount = liveAccount
            }
        }
        // The same choice as the accounts list (AccountsManagementView): keep the account's
        // transactions in history, or delete them with it.
        .alert(String(localized: "account.deleteTitle"), isPresented: $showingDeleteConfirm) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "account.deleteOnlyAccount"), role: .destructive) {
                HapticManager.warning()
                let account = liveAccount
                accountsViewModel.deleteAccount(account)
                transactionsViewModel.cleanupDeletedAccount(account.id)
                transactionsViewModel.syncAccountsFrom(accountsViewModel)
                dismiss()
            }
            Button(String(localized: "account.deleteAccountAndTransactions"), role: .destructive) {
                HapticManager.warning()
                let account = liveAccount
                Task {
                    await transactionStore.deleteTransactions(forAccountId: account.id)
                }
                accountsViewModel.deleteAccount(account)
                transactionsViewModel.cleanupDeletedAccount(account.id)
                transactionsViewModel.clearAndRebuildAggregateCache()
                dismiss()
            }
        } message: {
            Text(String(format: String(localized: "account.deleteMessage"), liveAccount.name))
        }
        .task(id: refreshTrigger) {
            await refreshData()
        }
        .task(id: transactionStore.accountsMutationVersion) {
            accountsById = Dictionary(uniqueKeysWithValues: transactionStore.accounts.map { ($0.id, $0) })
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
            amount: aggregates.totalIncome,
            currency: liveAccount.currency
        ))
        rows.append(InfoRowConfig(
            icon: "arrow.up.circle",
            label: String(localized: "account.detail.totalExpense", defaultValue: "Total expense"),
            amount: aggregates.totalExpense,
            currency: liveAccount.currency
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
        AskAssistantMenuItem(topic: .account(name: liveAccount.name))

        Button {
            showingEdit = true
        } label: {
            Label(String(localized: "button.edit"), systemImage: "pencil")
        }

        if !liveAccount.isDeposit && !liveAccount.isLoan {
            Button {
                HapticManager.light()
                if premium.isPro {
                    convertingAccount = liveAccount
                } else {
                    showingPaywall = true
                }
            } label: {
                Label(
                    String(localized: "account.convertToDeposit", defaultValue: "Convert to Deposit"),
                    systemImage: "lock.square.stack.fill"
                )
            }
        }

        Divider()

        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label(String(localized: "button.delete"), systemImage: "trash")
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
        .environment(PremiumManager.shared)
    }
}
