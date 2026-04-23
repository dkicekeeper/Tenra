//
//  AccountsManagementView.swift
//  Tenra
//
//  Created on 2024
//

import OSLog
import SwiftUI

struct AccountsManagementView: View {
    let accountsViewModel: AccountsViewModel
    let depositsViewModel: DepositsViewModel
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(\.dismiss) var dismiss
    @State private var showingAddAccount = false
    @State private var showingAddDeposit = false
    @State private var editingAccount: Account?
    @State private var navigatingAccount: Account?
    @State private var accountToDelete: Account?
    @State private var showingAccountDeleteDialog = false
    @State private var convertingAccount: Account?
    @State private var linkingInterestDeposit: Account?
    @State private var mode: ManagementMode = .normal
    @State private var selection: Set<String> = []
    @State private var showingBulkDeleteDialog = false

    // Кешируем baseCurrency для оптимизации
    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    private let logger = Logger(subsystem: "Tenra", category: "AccountsManagementView")

    // Filtered and sorted accounts (loans excluded — managed in dedicated Loans section)
    private var sortedAccounts: [Account] {
        accountsViewModel.accounts.filter { !$0.isLoan }.sortedByOrder()
    }

    // MARK: - Methods

    private func moveAccount(from source: IndexSet, to destination: Int) {
        var reordered = sortedAccounts
        reordered.move(fromOffsets: source, toOffset: destination)

        // Only update order — bypass AccountsViewModel.updateAccount which triggers balance recalc
        transactionStore.reorderAccounts(reordered.map(\.id))

        HapticManager.selection()
    }
    
    var body: some View {
        Group {
            if accountsViewModel.accounts.isEmpty {
                EmptyStateView(
                    icon: "creditcard",
                    title: String(localized: "emptyState.noAccounts"),
                    description: String(localized: "emptyState.startTracking"),
                    actionTitle: String(localized: "account.newAccount"),
                    action: {
                        showingAddAccount = true
                    }
                )
            } else if let coordinator = accountsViewModel.balanceCoordinator {
                List(selection: mode.isSelecting ? $selection : nil) {
                    ForEach(sortedAccounts) { account in
                        AccountRow(
                            account: account,
                            onEdit: {
                                guard !mode.isSelecting else { return }
                                navigatingAccount = account
                            },
                            onDelete: {
                                HapticManager.warning()
                                accountToDelete = account
                                showingAccountDeleteDialog = true
                            },
                            balanceCoordinator: coordinator,
                            interestToday: depositsViewModel.interestToday(for: account),
                            nextPostingDate: depositsViewModel.nextPostingDate(for: account)
                        )
                        .contextMenu {
                            Button {
                                editingAccount = account
                            } label: {
                                Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
                            }

                            if !account.isDeposit {
                                Button {
                                    HapticManager.light()
                                    convertingAccount = account
                                } label: {
                                    Label(String(localized: "account.convertToDeposit", defaultValue: "Convert to Deposit"), systemImage: "lock.square.stack.fill")
                                }
                            }

                            Button(role: .destructive) {
                                HapticManager.warning()
                                accountToDelete = account
                                showingAccountDeleteDialog = true
                            } label: {
                                Label(String(localized: "button.delete"), systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: mode.isReordering ? moveAccount : nil)
                }
                .environment(\.editMode, .constant(mode.editMode))
            } else {
                // balanceCoordinator not yet initialized — show loading state
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(String(localized: "progress.loadingData"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(String(localized: "progress.loadingAccounts"))
            }
        }
        .navigationTitle(String(localized: "settings.accounts"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Reconcile all deposits — collect then batch-persist
            var depositTransactions: [Transaction] = []
            depositsViewModel.reconcileAllDeposits(
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    depositTransactions.append(transaction)
                }
            )
            for tx in depositTransactions {
                do {
                    _ = try await transactionStore.add(tx)
                } catch {
                    logger.error("Failed to add deposit transaction: \(error.localizedDescription)")
                }
            }

            // Reconcile all loans — collect then batch-persist
            var loanTransactions: [Transaction] = []
            loansViewModel.reconcileAllLoans(
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    loanTransactions.append(transaction)
                }
            )
            for tx in loanTransactions {
                do {
                    _ = try await transactionStore.add(tx)
                } catch {
                    logger.error("Failed to add loan payment transaction: \(error.localizedDescription)")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch mode {
                case .normal:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .selecting }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel(String(localized: "bulk.select"))
                case .selecting:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) {
                            mode = .normal
                            selection.removeAll()
                        }
                    } label: {
                        Text(String(localized: "bulk.done"))
                    }
                    .glassProminentButton()
                case .reordering:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .normal }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .glassProminentButton()
                    .accessibilityLabel(String(localized: "accessibility.accounts.doneReordering"))
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .normal {
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .reordering }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "accessibility.accounts.reorder"))
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .normal {
                    Menu {
                        Button(action: {
                            HapticManager.light()
                            showingAddAccount = true
                        }) {
                            Label(String(localized: "account.newAccount"), systemImage: "creditcard")
                        }
                        Button(action: {
                            HapticManager.light()
                            showingAddDeposit = true
                        }) {
                            Label(String(localized: "account.newDeposit"), systemImage: "lock.square.stack.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "accessibility.accounts.addMenu"))
                } else if mode.isSelecting {
                    Button {
                        HapticManager.selection()
                        if selection.count == sortedAccounts.count {
                            selection.removeAll()
                        } else {
                            selection = Set(sortedAccounts.map(\.id))
                        }
                    } label: {
                        Text(selection.count == sortedAccounts.count
                             ? String(localized: "bulk.deselectAll")
                             : String(localized: "bulk.selectAll"))
                    }
                }
            }
        }
        .navigationDestination(item: $navigatingAccount) { account in
            if account.isDeposit {
                DepositDetailView(
                    depositsViewModel: depositsViewModel,
                    transactionsViewModel: transactionsViewModel,
                    balanceCoordinator: appCoordinator.balanceCoordinator,
                    accountId: account.id
                )
            } else if account.isLoan {
                LoanDetailView(
                    loansViewModel: loansViewModel,
                    transactionsViewModel: transactionsViewModel,
                    balanceCoordinator: appCoordinator.balanceCoordinator,
                    accountId: account.id
                )
            } else {
                AccountDetailView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: accountsViewModel,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    account: account
                )
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountEditView(
                accountsViewModel: accountsViewModel,
                transactionsViewModel: transactionsViewModel,
                account: nil,
                onSave: { account in
                    HapticManager.success()
                    Task {
                        await accountsViewModel.addAccount(name: account.name, initialBalance: account.initialBalance ?? 0, currency: account.currency, iconSource: account.iconSource)
                        transactionsViewModel.syncAccountsFrom(accountsViewModel)
                        showingAddAccount = false
                    }
                },
                onCancel: { showingAddAccount = false }
            )
        }
        .sheet(isPresented: $showingAddDeposit) {
            DepositEditView(
                depositsViewModel: depositsViewModel,
                account: nil,
                onSave: { account in
                    guard account.isDeposit else { return }
                    HapticManager.success()
                    accountsViewModel.addDepositAccount(account)
                    var depositTransactions: [Transaction] = []
                    depositsViewModel.reconcileAllDeposits(
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
                    showingAddDeposit = false
                }
            )
        }
        .sheet(item: $editingAccount) { account in
            Group {
                if account.isDeposit {
                    DepositEditView(
                        depositsViewModel: depositsViewModel,
                        account: account,
                        onSave: { updatedAccount in
                            HapticManager.success()
                            depositsViewModel.updateDeposit(updatedAccount)
                            transactionsViewModel.recalculateAccountBalances()
                            editingAccount = nil
                        },
                        onLinkPayments: {
                            // Close edit sheet first, then present link-interest sheet.
                            let deposit = account
                            editingAccount = nil
                            // Small delay so the sheet dismissal completes cleanly.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                linkingInterestDeposit = deposit
                            }
                        }
                    )
                } else {
                    AccountEditView(
                        accountsViewModel: accountsViewModel,
                        transactionsViewModel: transactionsViewModel,
                        account: account,
                        onSave: { updatedAccount in
                            HapticManager.success()
                            accountsViewModel.updateAccount(updatedAccount)
                            transactionsViewModel.syncAccountsFrom(accountsViewModel)
                            editingAccount = nil
                        },
                        onCancel: { editingAccount = nil },
                        onConvertToDeposit: {
                            let accountToConvert = account
                            editingAccount = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                convertingAccount = accountToConvert
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .sheet(item: $linkingInterestDeposit) { deposit in
            NavigationStack {
                DepositLinkInterestView(
                    deposit: deposit,
                    depositsViewModel: depositsViewModel,
                    transactionStore: transactionStore,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    accountsViewModel: accountsViewModel
                )
            }
        }
        .sheet(item: $convertingAccount) { account in
            DepositEditView(
                depositsViewModel: depositsViewModel,
                account: account,
                onSave: { updatedAccount in
                    HapticManager.success()
                    accountsViewModel.updateDeposit(updatedAccount)
                    var depositTransactions: [Transaction] = []
                    depositsViewModel.reconcileAllDeposits(
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
                }
            )
        }
        .overlay(alignment: .bottom) {
            if mode.isSelecting && !selection.isEmpty {
                BulkDeleteButton(count: selection.count) {
                    showingBulkDeleteDialog = true
                }
                .animation(AppAnimation.contentSpring, value: selection.count)
            }
        }
        .alert(
            String(format: String(localized: "bulk.deleteAccounts.title"), selection.count),
            isPresented: $showingBulkDeleteDialog
        ) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "bulk.deleteAccounts.onlyAccounts"), role: .destructive) {
                let ids = selection
                Task {
                    await accountsViewModel.deleteAccounts(ids, deleteTransactions: false)
                    for id in ids {
                        transactionsViewModel.cleanupDeletedAccount(id)
                    }
                    transactionsViewModel.syncAccountsFrom(accountsViewModel)
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .normal
                }
            }
            Button(String(localized: "bulk.deleteAccounts.withTransactions"), role: .destructive) {
                let ids = selection
                Task {
                    await accountsViewModel.deleteAccounts(ids, deleteTransactions: true)
                    for id in ids {
                        transactionsViewModel.cleanupDeletedAccount(id)
                    }
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .normal
                }
            }
        } message: {
            Text(String(localized: "bulk.deleteAccounts.message"))
        }
        .alert(String(localized: "account.deleteTitle"), isPresented: $showingAccountDeleteDialog, presenting: accountToDelete) { account in
            Button(String(localized: "button.cancel"), role: .cancel) {
                accountToDelete = nil
            }
            Button(String(localized: "account.deleteOnlyAccount"), role: .destructive) {
                HapticManager.warning()

                accountsViewModel.deleteAccount(account)

                // Очистить состояние удаленного счета ПЕРЕД пересчетом
                transactionsViewModel.cleanupDeletedAccount(account.id)

                // Транзакции остаются, accountName сохранен
                // NOTE: Aggregate cache is NOT touched - transactions unchanged, aggregates remain valid
                transactionsViewModel.syncAccountsFrom(accountsViewModel)

                accountToDelete = nil
            }
            Button(String(localized: "account.deleteAccountAndTransactions"), role: .destructive) {
                HapticManager.warning()

                // Route through SSOT: each deletion goes through apply(.deleted) so
                // aggregates, cache, and CoreData persistence are all updated correctly.
                Task {
                    await transactionStore.deleteTransactions(forAccountId: account.id)
                }

                // Transactions already removed via TransactionStore above
                accountsViewModel.deleteAccount(account)

                // Очистить состояние удаленного счета ПЕРЕД пересчетом
                transactionsViewModel.cleanupDeletedAccount(account.id)

                // CRITICAL: Use new method to clear and rebuild aggregate cache
                transactionsViewModel.clearAndRebuildAggregateCache()

                accountToDelete = nil
            }
        } message: { account in
            Text(String(format: String(localized: "account.deleteMessage"), account.name))
        }
    }
}

#Preview("Accounts Management") {
    let coordinator = AppCoordinator()
    NavigationStack {
        AccountsManagementView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
    .environment(coordinator.transactionStore)
}

#Preview("Accounts Management - Empty") {
    let coordinator = AppCoordinator()
    return NavigationStack {
        AccountsManagementView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
    .environment(coordinator.transactionStore)
}

#Preview("Account Row") {
    // Sample accounts with different characteristics
    let sampleAccounts = [
        Account(
            id: "preview-1",
            name: "Kaspi Gold",
            currency: "KZT",
            iconSource: .brandService("kaspi.kz"),
            initialBalance: 500000
        ),
        Account(
            id: "preview-2",
            name: "Main Savings",
            currency: "USD",
            iconSource: .brandService("halykbank.kz"),
            initialBalance: 15000
        ),
        Account(
            id: "preview-3",
            name: "Halyk Deposit",
            currency: "KZT",
            iconSource: .brandService("halykbank.kz"),
            depositInfo: DepositInfo(
                bankName: "Halyk Bank",
                principalBalance: Decimal(1000000),
                capitalizationEnabled: true,
                interestRateAnnual: Decimal(12.5),
                interestPostingDay: 15
            ),
            initialBalance: 1000000
        ),
        Account(
            id: "preview-4",
            name: "EUR Account",
            currency: "EUR",
            iconSource: .brandService("alataucitybank.kz"),
            initialBalance: 2500
        ),
        Account(
            id: "preview-5",
            name: "Jusan Deposit",
            currency: "KZT",
            iconSource: .brandService("jusan.kz"),
            depositInfo: DepositInfo(
                bankName: "Jusan Bank",
                principalBalance: Decimal(2000000),
                capitalizationEnabled: false,
                interestRateAnnual: Decimal(10.0),
                interestPostingDay: 1
            ),
            initialBalance: 2000000
        )
    ]
    
    let coordinator = AppCoordinator()

    if let balanceCoordinator = coordinator.accountsViewModel.balanceCoordinator {
        List {
            ForEach(sampleAccounts) { account in
                AccountRow(
                    account: account,
                    onEdit: {},
                    onDelete: {},
                    balanceCoordinator: balanceCoordinator
                )
            }
        }
        .listStyle(PlainListStyle())
    }
}

