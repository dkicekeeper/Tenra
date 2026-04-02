//
//  DepositDetailView.swift
//  AIFinanceManager
//
//  Detail view for deposit accounts
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
    @State private var showingHistory = false
    @State private var reconciliationError: String? = nil
    @Environment(\.dismiss) var dismiss
    @Namespace private var depositActionNamespace

    private let logger = Logger(subsystem: "AIFinanceManager", category: "DepositDetailView")

    private var account: Account? {
        depositsViewModel.getDeposit(by: accountId)
    }

    private var depositInfo: DepositInfo? {
        account?.depositInfo
    }

    // Computed once per body evaluation — avoids repeated service calls inside nested functions
    private var interestToToday: Decimal {
        depositInfo.map { DepositInterestService.calculateInterestToToday(depositInfo: $0) } ?? 0
    }

    private var nextPosting: Date? {
        depositInfo.flatMap { DepositInterestService.nextPostingDate(depositInfo: $0) }
    }

    var body: some View {
        Group {
            if let account = account {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        if let error = reconciliationError {
                            InlineStatusText(message: error, type: .error)
                                .screenPadding()
                        }

                        if let depositInfo = depositInfo {
                            depositInfoCard(depositInfo: depositInfo, account: account)
                                .screenPadding()

                            actionsSection
                                .screenPadding()
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
                .navigationTitle(account.name)
            } else {
                EmptyStateView(
                    icon: "banknote",
                    title: String(localized: "deposit.notFound"),
                    description: String(localized: "emptyState.tryDifferentSearch")
                )
                .navigationTitle(String(localized: "deposit.title"))
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.selection()
                    showingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel(String(localized: "accessibility.deposit.history"))
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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

                    Divider()

                    Button(role: .destructive) {
                        HapticManager.warning()
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "deposit.delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "accessibility.deposit.moreActions"))
            }
        }
        .sheet(isPresented: $showingHistory) {
            if let account = account {
                NavigationStack {
                    HistoryView(
                        transactionsViewModel: transactionsViewModel,
                        accountsViewModel: depositsViewModel.accountsViewModel,
                        categoriesViewModel: appCoordinator.categoriesViewModel,
                        paginationController: appCoordinator.transactionPaginationController,
                        initialAccountId: account.id
                    )
                    .environment(timeFilterManager)
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            if let account = account {
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
        }
        // Unified transfer sheet — replaces separate showingTransferTo / showingTransferFrom
        .sheet(item: $activeTransferDirection) { direction in
            if let account = account {
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
        }
        .sheet(isPresented: $showingRateChange) {
            if let account = account {
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
        }
        .alert(String(localized: "deposit.deleteTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "button.delete"), role: .destructive) {
                if let account = account {
                    HapticManager.warning()
                    depositsViewModel.deleteDeposit(account)
                    // Route through SSOT so aggregates, cache, and CoreData stay consistent
                    Task {
                        await transactionStore.deleteTransactions(forAccountId: account.id)
                    }
                    transactionsViewModel.recalculateAccountBalances()
                }
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "deposit.deleteMessage"))
        }
        .task {
            // Reconcile only this deposit — not all deposits (targeted, not global)
            depositsViewModel.reconcileDepositInterest(
                for: accountId,
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    Task {
                        do {
                            _ = try await transactionStore.add(transaction)
                        } catch {
                            logger.error("Failed to add deposit interest transaction: \(error.localizedDescription)")
                            await MainActor.run {
                                reconciliationError = error.localizedDescription
                            }
                        }
                    }
                }
            )
        }
    }

    private func depositInfoCard(depositInfo: DepositInfo, account: Account) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack {
                IconView(source: account.iconSource, size: AppIconSize.xxl)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h3)
                    Text(depositInfo.bankName)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Balance
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: "deposit.balance"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                let balance = balanceCoordinator.balances[account.id] ?? 0
                FormattedAmountText(
                    amount: balance,
                    currency: account.currency,
                    fontSize: AppTypography.h2
                )
            }

            // Interest info — uses view-level computed property (computed once per body pass)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if let nextPosting = nextPosting {
                    Text(String(format: String(localized: "deposit.postingWithDate", defaultValue: "Posting: %@"), formatDate(nextPosting)))
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
                value: String(format: String(localized: "deposit.rateAnnual"), formatRate(depositInfo.interestRateAnnual))
            )
            InfoRow(
                icon: "arrow.triangle.2.circlepath",
                label: String(localized: "deposit.capitalization"),
                value: depositInfo.capitalizationEnabled ? String(localized: "deposit.capitalizationEnabled") : String(localized: "deposit.capitalizationDisabled")
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

    private var actionsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                HapticManager.light()
                activeTransferDirection = .toDeposit
            } label: {
                Label(String(localized: "deposit.topUp"), systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()

            Button {
                HapticManager.light()
                activeTransferDirection = .fromDeposit
            } label: {
                Label(String(localized: "deposit.transferToAccount"), systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()
        }
    }

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
