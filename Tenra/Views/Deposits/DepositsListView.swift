//
//  DepositsListView.swift
//  Tenra
//
//  Standalone deposit management screen. Deposits used to be managed inside
//  AccountsManagementView; they now have their own card in Finances that routes
//  here. Lists deposits, supports add/edit/delete, interest linking, and routes
//  to DepositDetailView. Reconciles interest accrual on appear.
//

import OSLog
import SwiftUI

struct DepositsListView: View {
    let accountsViewModel: AccountsViewModel
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(PremiumManager.self) private var premium

    @State private var showingAddDeposit = false
    @State private var showingPaywall = false
    @State private var editingDeposit: Account?
    @State private var navigatingDeposit: Account?
    @State private var depositToDelete: Account?
    @State private var showingDeleteDialog = false
    @State private var linkingInterestDeposit: Account?

    @Namespace private var depositNamespace

    private let logger = Logger(subsystem: "Tenra", category: "DepositsListView")

    private var deposits: [Account] {
        accountsViewModel.depositAccounts.sortedByOrder()
    }

    var body: some View {
        Group {
            if deposits.isEmpty {
                EmptyStateView(
                    icon: "lock.square.stack.fill",
                    title: String(localized: "deposit.emptyTitle", defaultValue: "No Deposits"),
                    description: String(localized: "deposit.emptyDescription", defaultValue: "Add a deposit to track interest accrual and capitalization"),
                    actionTitle: String(localized: "account.newDeposit", defaultValue: "New Deposit"),
                    action: {
                        HapticManager.light()
                        // Deposits are a Pro feature (interest accrual + capitalization
                        // tracking) — every add path routes non-Pro users to the paywall.
                        if premium.isPro {
                            showingAddDeposit = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )
            } else if let coordinator = accountsViewModel.balanceCoordinator {
                List {
                    ForEach(deposits) { deposit in
                        AccountRow(
                            account: deposit,
                            onEdit: { navigatingDeposit = deposit },
                            onDelete: {
                                HapticManager.warning()
                                depositToDelete = deposit
                                showingDeleteDialog = true
                            },
                            balanceCoordinator: coordinator,
                            interestToday: depositsViewModel.interestToday(for: deposit),
                            nextPostingDate: depositsViewModel.nextPostingDate(for: deposit),
                            transitionSourceID: deposit.id,
                            transitionNamespace: depositNamespace
                        )
                        .contextMenu {
                            Button {
                                editingDeposit = deposit
                            } label: {
                                Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                HapticManager.warning()
                                depositToDelete = deposit
                                showingDeleteDialog = true
                            } label: {
                                Label(String(localized: "button.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: AppSpacing.md) {
                    ProgressView().scaleEffect(1.2)
                    Text(String(localized: "progress.loadingData"))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(String(localized: "deposit.listTitle", defaultValue: "Deposits"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await reconcileDeposits()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    if premium.isPro {
                        showingAddDeposit = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .primaryButton()
                .accessibilityLabel(String(localized: "account.newDeposit", defaultValue: "New Deposit"))
            }
        }
        .paywallSheet(isPresented: $showingPaywall) {
            // After unlocking Pro, continue straight into the add-deposit flow.
            showingAddDeposit = true
        }
        .navigationDestination(item: $navigatingDeposit) { deposit in
            DepositDetailView(
                depositsViewModel: depositsViewModel,
                transactionsViewModel: transactionsViewModel,
                balanceCoordinator: appCoordinator.balanceCoordinator,
                accountId: deposit.id
            )
            .navigationTransition(.zoom(sourceID: deposit.id, in: depositNamespace))
        }
        .sheet(isPresented: $showingAddDeposit) {
            DepositEditView(
                depositsViewModel: depositsViewModel,
                account: nil,
                onSave: { account in
                    guard account.isDeposit else { return }
                    HapticManager.success()
                    accountsViewModel.addDepositAccount(account)
                    Task { await reconcileDeposits() }
                    showingAddDeposit = false
                }
            )
        }
        .sheet(item: $editingDeposit) { deposit in
            DepositEditView(
                depositsViewModel: depositsViewModel,
                account: deposit,
                onSave: { updatedAccount in
                    HapticManager.success()
                    depositsViewModel.updateDeposit(updatedAccount)
                    transactionsViewModel.recalculateAccountBalances()
                    editingDeposit = nil
                },
                onLinkPayments: {
                    let target = deposit
                    editingDeposit = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        linkingInterestDeposit = target
                    }
                }
            )
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
        .alert(String(localized: "deposit.deleteTitle", defaultValue: "Delete deposit?"), isPresented: $showingDeleteDialog, presenting: depositToDelete) { deposit in
            Button(String(localized: "button.cancel"), role: .cancel) { depositToDelete = nil }
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                Task {
                    await transactionStore.deleteTransactions(forAccountId: deposit.id)
                    depositsViewModel.deleteDeposit(deposit)
                    transactionsViewModel.cleanupDeletedAccount(deposit.id)
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }
                depositToDelete = nil
            }
        } message: { _ in
            Text(String(localized: "deposit.deleteMessage", defaultValue: "All deposit data and related transactions will be deleted."))
        }
    }

    /// Collect interest-accrual transactions for all deposits and batch-persist them.
    private func reconcileDeposits() async {
        var depositTransactions: [Transaction] = []
        depositsViewModel.reconcileAllDeposits(
            allTransactions: transactionsViewModel.allTransactions,
            onTransactionCreated: { depositTransactions.append($0) }
        )
        for tx in depositTransactions {
            do {
                _ = try await transactionStore.add(tx)
            } catch {
                logger.error("Failed to add deposit transaction: \(error.localizedDescription)")
            }
        }
    }
}

#Preview("Deposits List") {
    let coordinator = AppCoordinator()
    NavigationStack {
        DepositsListView(
            accountsViewModel: coordinator.accountsViewModel,
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
    .environment(coordinator.transactionStore)
    .environment(coordinator)
}
