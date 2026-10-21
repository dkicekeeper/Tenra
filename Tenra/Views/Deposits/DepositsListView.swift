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
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<String> = []
    @State private var showingBulkDeleteDialog = false

    @Namespace private var depositNamespace

    private let logger = Logger(subsystem: "Tenra", category: "DepositsListView")

    private var deposits: [Account] {
        accountsViewModel.depositAccounts.sortedByOrder()
    }

    /// Deposits are a Pro feature (interest accrual + capitalization tracking): every add path
    /// routes non-Pro users to the paywall.
    private func addDeposit() {
        HapticManager.light()
        if premium.isPro {
            showingAddDeposit = true
        } else {
            showingPaywall = true
        }
    }

    /// A drag in DesignKit's `CardList`: the deposits' own order (`Account.order`, by list).
    private func moveDeposit(from source: IndexSet, to destination: Int) {
        var reordered = deposits
        reordered.move(fromOffsets: source, toOffset: destination)
        transactionStore.reorderAccounts(reordered.map(\.id))
    }

    private func confirmDelete(_ deposit: Account) {
        HapticManager.warning()
        depositToDelete = deposit
        showingDeleteDialog = true
    }

    /// A deposit goes with its transactions (interest, top-ups), as one deleted from its menu.
    private func delete(_ deposit: Account) async {
        await transactionStore.deleteTransactions(forAccountId: deposit.id)
        depositsViewModel.deleteDeposit(deposit)
        transactionsViewModel.cleanupDeletedAccount(deposit.id)
    }

    var body: some View {
        Group {
            if deposits.isEmpty {
                MascotEmptyState(
                    icon: "lock.square.stack.fill",
                    title: String(localized: "deposit.emptyTitle", defaultValue: "No Deposits"),
                    description: String(localized: "deposit.emptyDescription", defaultValue: "Add a deposit to track interest accrual and capitalization"),
                    actionTitle: String(localized: "account.newDeposit", defaultValue: "New Deposit"),
                    action: addDeposit,
                    line: String(localized: "assistant.empty.deposits")
                )
            } else if let coordinator = accountsViewModel.balanceCoordinator {
                // A card per deposit (DesignKit 8.0.0's `CardList`): a tap opens it, a long press
                // shows Edit and Delete; the toolbar selects, reorders and adds.
                ScrollView {
                    CardList(deposits, mode: mode, selection: $selection, onMove: moveDeposit) { deposit in
                        AccountRow(
                            account: deposit,
                            onEdit: { navigatingDeposit = deposit },
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
                                confirmDelete(deposit)
                            } label: {
                                Label(String(localized: "button.delete"), systemImage: "trash")
                            }
                        }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.md)
                }
                .transition(.skeletonReveal)
            } else {
                ScrollView {
                    CardListSkeleton(count: 3)
                        .screenPadding()
                        .padding(.vertical, AppSpacing.md)
                }
                .scrollDisabled(true)
                .transition(.opacity)
            }
        }
        // The list comes into focus where its skeleton was (DesignKit's skeleton reveal).
        .animation(AppAnimation.smooth, value: accountsViewModel.balanceCoordinator == nil)
        .navigationTitle(String(localized: "deposit.listTitle", defaultValue: "Deposits"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            await reconcileDeposits()
        }
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: deposits.map(\.id),
            addLabel: String(localized: "account.newDeposit", defaultValue: "New Deposit"),
            onAdd: addDeposit,
            onDeleteSelected: { showingBulkDeleteDialog = true }
        )
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
            .softScrollEdges()
        }
        .alert(String(localized: "deposit.deleteTitle", defaultValue: "Delete deposit?"), isPresented: $showingDeleteDialog, presenting: depositToDelete) { deposit in
            Button(String(localized: "button.cancel"), role: .cancel) { depositToDelete = nil }
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                Task {
                    await delete(deposit)
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }
                depositToDelete = nil
            }
        } message: { _ in
            Text(String(localized: "deposit.deleteMessage", defaultValue: "All deposit data and related transactions will be deleted."))
        }
        .alert(
            String(format: String(localized: "bulk.deleteDeposits.title", defaultValue: "Delete %d deposits?"), selection.count),
            isPresented: $showingBulkDeleteDialog
        ) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                let doomed = deposits.filter { selection.contains($0.id) }
                Task {
                    for deposit in doomed {
                        await delete(deposit)
                    }
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .browsing
                }
            }
        } message: {
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
    // Required: the view reads `@Environment(PremiumManager.self)` for the Pro gate.
    // A non-optional `@Environment(T.self)` traps when T isn't in the environment.
    .environment(PremiumManager.shared)
}
