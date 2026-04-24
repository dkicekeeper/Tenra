//
//  DepositDetailView.swift
//  Tenra
//
//  Detail view for deposit accounts. Uses EntityDetailScaffold for hero/info/
//  actions/history composition; deposit-specific interest breakdown lives in
//  the scaffold's `customSections` slot.
//

import OSLog
import SwiftUI

// DepositTransferDirection is the shared enum for deposit transfer direction.
// Defined here (primary consumer) and visible to AccountActionView via module scope.
enum DepositTransferDirection: Identifiable {
    case toDeposit
    case fromDeposit

    var id: Int { self == .toDeposit ? 0 : 1 }
}

struct DepositDetailView: View {
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    let balanceCoordinator: BalanceCoordinator
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    let accountId: String
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @State private var showingEditView = false
    @State private var activeTransferDirection: DepositTransferDirection? = nil
    @State private var showingRateChange = false
    @State private var showingDeleteConfirmation = false
    @State private var showingLinkInterest = false
    @State private var reconciliationError: String? = nil
    @State private var cachedTransactions: [Transaction] = []
    @Environment(\.dismiss) var dismiss
    @Namespace private var depositActionNamespace

    private let logger = Logger(subsystem: "Tenra", category: "DepositDetailView")

    /// Live account lookup — reflects edits (rename, rate change, capitalization toggle)
    /// in real time without re-navigating.
    private var liveAccount: Account? {
        depositsViewModel.getDeposit(by: accountId)
    }

    private var depositInfo: DepositInfo? {
        liveAccount?.depositInfo
    }

    /// Computed once per body evaluation — avoids repeated service calls inside nested functions.
    private var interestToToday: Decimal {
        depositInfo.map { DepositInterestService.calculateInterestToToday(depositInfo: $0) } ?? 0
    }

    private var nextPosting: Date? {
        depositInfo.flatMap { DepositInterestService.nextPostingDate(depositInfo: $0) }
    }

    /// Cheap O(N) single-pass counter; feeds `.task(id:)` so the expensive refresh
    /// runs only when relevant transactions change.
    private var refreshTrigger: Int {
        var n = 0
        for tx in transactionStore.transactions
        where tx.accountId == accountId || tx.targetAccountId == accountId {
            n += 1
        }
        return n
    }

    private func refreshTransactions() async {
        cachedTransactions = transactionStore.transactions
            .filter { $0.accountId == accountId || $0.targetAccountId == accountId }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if let account = liveAccount {
                scaffold(for: account)
            } else {
                EmptyStateView(
                    icon: "banknote",
                    title: String(localized: "deposit.notFound"),
                    description: String(localized: "emptyState.tryDifferentSearch")
                )
                .navigationTitle(String(localized: "deposit.title"))
            }
        }
    }

    @ViewBuilder
    private func scaffold(for account: Account) -> some View {
        let accountsById = Dictionary(
            uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) }
        )

        EntityDetailScaffold(
            navigationTitle: account.name,
            navigationAmount: balanceCoordinator.balances[account.id] ?? account.balance,
            navigationCurrency: account.currency,
            primaryAction: ActionConfig(
                title: String(localized: "deposit.topUp"),
                systemImage: "plus",
                action: {
                    HapticManager.light()
                    activeTransferDirection = .toDeposit
                }
            ),
            secondaryAction: ActionConfig(
                title: String(localized: "deposit.transferToAccount"),
                systemImage: "arrow.left.arrow.right",
                action: {
                    HapticManager.light()
                    activeTransferDirection = .fromDeposit
                }
            ),
            infoRows: [],
            transactions: cachedTransactions,
            historyCurrency: account.currency,
            accountsById: accountsById,
            styleHelper: { tx in
                CategoryStyleHelper.cached(
                    category: tx.category,
                    type: tx.type,
                    customCategories: appCoordinator.categoriesViewModel.customCategories
                )
            },
            viewModel: transactionsViewModel,
            categoriesViewModel: appCoordinator.categoriesViewModel,
            accountsViewModel: depositsViewModel.accountsViewModel,
            balanceCoordinator: balanceCoordinator,
            hero: {
                HeroSection(
                    icon: account.iconSource,
                    title: account.name,
                    primaryAmount: balanceCoordinator.balances[account.id] ?? account.balance,
                    primaryCurrency: account.currency,
                    subtitle: account.depositInfo?.bankName,
                    showBaseConversion: true,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )
            },
            customSections: {
                interestSection(for: account)
            },
            toolbarMenu: {
                depositToolbarMenu
            }
        )
        .sheet(isPresented: $showingEditView) {
            DepositEditView(
                depositsViewModel: depositsViewModel,
                account: account,
                onSave: { updatedAccount in
                    HapticManager.success()
                    depositsViewModel.updateDeposit(updatedAccount)
                    transactionsViewModel.recalculateAccountBalances()
                    showingEditView = false
                }
            )
        }
        // Unified transfer sheet — replaces separate showingTransferTo / showingTransferFrom
        .sheet(item: $activeTransferDirection) { direction in
            NavigationStack {
                AccountActionView(
                    transactionsViewModel: transactionsViewModel,
                    accountsViewModel: depositsViewModel.accountsViewModel,
                    account: account,
                    namespace: depositActionNamespace,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    transferDirection: direction
                )
                .environment(timeFilterManager)
            }
        }
        .sheet(isPresented: $showingRateChange) {
            DepositRateChangeView(
                account: account,
                onRateChanged: { effectiveFrom, annualRate, note in
                    depositsViewModel.addDepositRateChange(
                        accountId: account.id,
                        effectiveFrom: effectiveFrom,
                        annualRate: annualRate,
                        note: note
                    )
                }
            )
        }
        .sheet(isPresented: $showingLinkInterest) {
            NavigationStack {
                DepositLinkInterestView(
                    deposit: account,
                    depositsViewModel: depositsViewModel,
                    transactionStore: transactionStore,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    accountsViewModel: depositsViewModel.accountsViewModel
                )
            }
        }
        .alert(String(localized: "deposit.deleteTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                depositsViewModel.deleteDeposit(account)
                // Route through SSOT so aggregates, cache, and CoreData stay consistent
                Task {
                    await transactionStore.deleteTransactions(forAccountId: account.id)
                }
                transactionsViewModel.recalculateAccountBalances()
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "deposit.deleteMessage"))
        }
        .task(id: refreshTrigger) {
            await refreshTransactions()
        }
        .task {
            // Reconcile only this deposit — not all deposits (targeted, not global).
            // Collect generated interest transactions synchronously in the callback,
            // then batch-persist after reconciliation completes. Never spawn Task {}
            // inside onTransactionCreated — it races on TransactionStore across days.
            var interestTransactions: [Transaction] = []
            depositsViewModel.reconcileDepositInterest(
                for: accountId,
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    interestTransactions.append(transaction)
                }
            )
            for tx in interestTransactions {
                do {
                    _ = try await transactionStore.add(tx)
                } catch {
                    logger.error("Failed to add deposit interest transaction: \(error.localizedDescription)")
                    reconciliationError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Interest section (customSections slot)

    @ViewBuilder
    private func interestSection(for account: Account) -> some View {
        VStack(spacing: AppSpacing.lg) {
            if let error = reconciliationError {
                InlineStatusText(message: error, type: .error)
            }

            if let depositInfo = account.depositInfo {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // Interest info — uses view-level computed property (computed once per body pass)
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        if let nextPosting = nextPosting {
                            Text(String(
                                format: String(localized: "deposit.postingWithDate", defaultValue: "Posting: %@"),
                                formatDate(nextPosting)
                            ))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "deposit.interestToday"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(.secondary)
                        }
                        FormattedAmountText(
                            amount: NSDecimalNumber(decimal: interestToToday).doubleValue,
                            currency: account.currency,
                            fontSize: AppTypography.h4,
                            color: AppColors.planned
                        )
                    }

                    Divider()

                    // Details
                    InfoRow(
                        icon: "percent",
                        label: String(localized: "deposit.rate"),
                        value: String(
                            format: String(localized: "deposit.rateAnnual"),
                            formatRate(depositInfo.interestRateAnnual)
                        )
                    )
                    InfoRow(
                        icon: "arrow.triangle.2.circlepath",
                        label: String(localized: "deposit.capitalization"),
                        value: depositInfo.capitalizationEnabled
                            ? String(localized: "deposit.capitalizationEnabled")
                            : String(localized: "deposit.capitalizationDisabled")
                    )
                    InfoRow(
                        icon: "calendar.day.timeline.left",
                        label: String(localized: "deposit.postingDay"),
                        value: "\(depositInfo.interestPostingDay)"
                    )
                }
                .padding(AppSpacing.lg)
                .cardStyle()
            }
        }
        .screenPadding()
    }

    // MARK: - Toolbar menu

    @ViewBuilder
    private var depositToolbarMenu: some View {
        Button {
            HapticManager.selection()
            showingEditView = true
        } label: {
            Label(String(localized: "deposit.edit"), systemImage: "pencil")
        }

        Button {
            HapticManager.selection()
            showingRateChange = true
        } label: {
            Label(String(localized: "deposit.changeRate"), systemImage: "chart.line.uptrend.xyaxis")
        }

        Button {
            HapticManager.selection()
            showingLinkInterest = true
        } label: {
            Label(
                String(localized: "deposit.linkInterest.title", defaultValue: "Link Interest Payments"),
                systemImage: "link.badge.plus"
            )
        }

        Button {
            HapticManager.selection()
            if let id = liveAccount?.id {
                Task {
                    try? await depositsViewModel.recalculateInterest(
                        for: id,
                        transactionStore: transactionStore
                    )
                }
            }
        } label: {
            Label(
                String(localized: "deposit.recalculateInterest", defaultValue: "Recalculate Interest"),
                systemImage: "arrow.clockwise"
            )
        }

        Divider()

        Button(role: .destructive) {
            HapticManager.warning()
            showingDeleteConfirmation = true
        } label: {
            Label(String(localized: "deposit.delete"), systemImage: "trash")
        }
    }

    // MARK: - Formatting helpers

    private func formatRate(_ rate: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: rate).doubleValue)
    }

    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateFormatter.string(from: date)
    }
}


// MARK: - Previews

#Preview("Deposit Detail View") {
    let coordinator = AppCoordinator()

    NavigationStack {
        DepositDetailView(
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            accountId: coordinator.depositsViewModel.deposits.first?.id ?? "test"
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}

#Preview("Deposit Detail View - Not Found") {
    let coordinator = AppCoordinator()

    NavigationStack {
        DepositDetailView(
            depositsViewModel: coordinator.depositsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            accountId: "non-existent"
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}
