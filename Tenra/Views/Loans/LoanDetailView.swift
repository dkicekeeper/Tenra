//
//  LoanDetailView.swift
//  Tenra
//
//  Detail view for loan/installment accounts. Uses EntityDetailScaffold for
//  hero/actions/history composition. Payment breakdown, stats, and the
//  amortization schedule live in the scaffold's `customSections` slot.
//

import OSLog
import SwiftUI

struct LoanDetailView: View {
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel
    let balanceCoordinator: BalanceCoordinator
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    let accountId: String

    @State private var showingEditView = false
    @State private var showingPayment = false
    @State private var showingEarlyRepayment = false
    @State private var showingRateChange = false
    @State private var showingDeleteConfirmation = false
    @State private var showingLinkPayments = false
    @State private var showFullSchedule = false
    @State private var cachedSchedule: [LoanPaymentService.AmortizationEntry] = []
    @State private var cachedTransactions: [Transaction] = []
    @State private var reconciliationError: String? = nil
    @State private var paymentError: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager

    private let logger = Logger(subsystem: "Tenra", category: "LoanDetailView")

    /// Live lookup — reflects rename / rate change / payment updates without re-navigation.
    private var liveAccount: Account? {
        loansViewModel.getLoan(by: accountId)
    }

    /// Cheap O(N) counter; feeds `.task(id:)` so `refreshTransactions` only runs
    /// when this loan's transactions change.
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
                    icon: "creditcard",
                    title: String(localized: "loan.notFound", defaultValue: "Loan not found"),
                    description: String(localized: "emptyState.tryDifferentSearch")
                )
                .navigationTitle(String(localized: "loan.title", defaultValue: "Loan"))
            }
        }
        .overlay(alignment: .top) {
            if let msg = paymentError {
                MessageBanner.error(msg)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(AppAnimation.gentleSpring, value: paymentError)
    }

    private func showPaymentError(_ message: String) {
        paymentError = message
        Task {
            try? await Task.sleep(for: .seconds(4))
            paymentError = nil
        }
    }

    @ViewBuilder
    private func scaffold(for account: Account) -> some View {
        let accountsById = Dictionary(
            uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) }
        )

        EntityDetailScaffold(
            navigationTitle: account.name,
            navigationAmount: account.loanInfo.map {
                NSDecimalNumber(decimal: $0.remainingPrincipal).doubleValue
            },
            navigationCurrency: account.currency,
            primaryAction: ActionConfig(
                title: String(localized: "loan.makePayment", defaultValue: "Make Payment"),
                systemImage: "banknote",
                action: {
                    HapticManager.light()
                    showingPayment = true
                }
            ),
            secondaryAction: ActionConfig(
                title: String(localized: "loan.earlyRepayment", defaultValue: "Early Repayment"),
                systemImage: "bolt.fill",
                action: {
                    HapticManager.light()
                    showingEarlyRepayment = true
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
            accountsViewModel: loansViewModel.accountsViewModel,
            balanceCoordinator: balanceCoordinator,
            hero: {
                HeroSection(
                    icon: account.iconSource,
                    title: account.name,
                    primaryAmount: account.loanInfo.map {
                        NSDecimalNumber(decimal: $0.remainingPrincipal).doubleValue
                    } ?? 0,
                    primaryCurrency: account.currency,
                    subtitle: heroSubtitle(for: account),
                    progress: progressConfig(for: account),
                    showBaseConversion: true,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency
                )
            },
            customSections: {
                loanCustomSections(for: account)
            },
            toolbarMenu: {
                loanToolbarMenu
            }
        )
        .sheet(isPresented: $showingEditView) {
            LoanEditView(
                loansViewModel: loansViewModel,
                account: account,
                onSave: { updatedAccount in
                    loansViewModel.updateLoan(updatedAccount)
                    transactionsViewModel.recalculateAccountBalances()
                    showingEditView = false
                }
            )
        }
        .sheet(isPresented: $showingPayment) {
            if let loanInfo = account.loanInfo {
                LoanPaymentView(
                    account: account,
                    loanInfo: loanInfo,
                    availableAccounts: loansViewModel.accountsViewModel.regularAccounts,
                    onPayment: { amount, date, sourceAccountId in
                        if let transaction = loansViewModel.makeManualPayment(
                            accountId: account.id,
                            amount: amount,
                            date: date,
                            sourceAccountId: sourceAccountId
                        ) {
                            Task {
                                do {
                                    _ = try await transactionStore.add(transaction)
                                    transactionsViewModel.recalculateAccountBalances()
                                } catch {
                                    logger.error("Failed to add loan payment: \(error.localizedDescription)")
                                    showPaymentError(String(localized: "loan.paymentFailed", defaultValue: "Payment failed. Please try again."))
                                }
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingEarlyRepayment) {
            if let loanInfo = account.loanInfo {
                LoanEarlyRepaymentView(
                    account: account,
                    loanInfo: loanInfo,
                    availableAccounts: loansViewModel.accountsViewModel.regularAccounts,
                    onRepayment: { amount, date, type, sourceAccountId, note in
                        if let transaction = loansViewModel.makeEarlyRepayment(
                            accountId: account.id,
                            amount: amount,
                            date: date,
                            type: type,
                            sourceAccountId: sourceAccountId,
                            note: note
                        ) {
                            Task {
                                do {
                                    _ = try await transactionStore.add(transaction)
                                    transactionsViewModel.recalculateAccountBalances()
                                } catch {
                                    logger.error("Failed to add early repayment transaction: \(error.localizedDescription)")
                                    showPaymentError(String(localized: "loan.earlyRepaymentFailed", defaultValue: "Early repayment failed. Please try again."))
                                }
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingRateChange) {
            if account.loanInfo != nil {
                LoanRateChangeView(
                    account: account,
                    onRateChanged: { effectiveFrom, annualRate, note in
                        loansViewModel.addLoanRateChange(
                            accountId: account.id,
                            effectiveFrom: effectiveFrom,
                            annualRate: annualRate,
                            note: note
                        )
                    }
                )
            }
        }
        .navigationDestination(isPresented: $showingLinkPayments) {
            LoanLinkPaymentsView(
                loan: account,
                loansViewModel: loansViewModel,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: appCoordinator.categoriesViewModel,
                accountsViewModel: appCoordinator.accountsViewModel,
                balanceCoordinator: balanceCoordinator
            )
        }
        .alert(String(localized: "loan.deleteTitle", defaultValue: "Delete Loan?"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                loansViewModel.deleteLoan(account)
                Task {
                    await transactionStore.deleteTransactions(forAccountId: account.id)
                }
                transactionsViewModel.recalculateAccountBalances()
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "loan.deleteMessage", defaultValue: "All loan data and payment history will be deleted."))
        }
        .task(id: refreshTrigger) {
            await refreshTransactions()
        }
        .task(id: accountId) {
            // Build amortization schedule cache
            if let li = account.loanInfo {
                cachedSchedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: li)
            }

            // Reconcile only this loan's payments — collect synchronously, then batch-persist.
            // Never spawn Task {} inside the onTransactionCreated callback — would race
            // on TransactionStore and diverge loan state from transaction records (CLAUDE.md rule).
            var createdTransactions: [Transaction] = []
            loansViewModel.reconcileLoanPayments(
                for: accountId,
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    createdTransactions.append(transaction)
                }
            )

            for tx in createdTransactions {
                do {
                    _ = try await transactionStore.add(tx)
                } catch {
                    logger.error("Failed to add loan payment transaction: \(error.localizedDescription)")
                    reconciliationError = error.localizedDescription
                }
            }

            // Rebuild schedule after reconciliation (paymentsMade may have changed)
            if !createdTransactions.isEmpty, let li = liveAccount?.loanInfo {
                cachedSchedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: li)
            }
        }
    }

    // MARK: - Hero helpers

    private func progressConfig(for account: Account) -> ProgressConfig? {
        guard let info = account.loanInfo, info.originalPrincipal > 0 else { return nil }
        let paid = NSDecimalNumber(decimal: info.originalPrincipal - info.remainingPrincipal).doubleValue
        let total = NSDecimalNumber(decimal: info.originalPrincipal).doubleValue
        return ProgressConfig(
            current: max(paid, 0),
            total: total,
            label: String(localized: "loan.paidOff", defaultValue: "Paid off"),
            color: AppColors.income
        )
    }

    private func heroSubtitle(for account: Account) -> String? {
        guard let info = account.loanInfo else { return nil }
        if let nextDate = LoanPaymentService.nextPaymentDate(loanInfo: info) {
            return String(
                format: String(localized: "loan.nextPayment", defaultValue: "Next payment: %@"),
                formatDate(nextDate)
            )
        }
        return info.bankName
    }

    // MARK: - Custom sections

    @ViewBuilder
    private func loanCustomSections(for account: Account) -> some View {
        VStack(spacing: AppSpacing.lg) {
            if let error = reconciliationError {
                InlineStatusText(message: error, type: .error)
            }

            if let loanInfo = account.loanInfo {
                // Payment breakdown is meaningless for installments (0% interest, fixed
                // principal-only splits) — hide it entirely for that loan type.
                if loanInfo.loanType != .installment {
                    paymentBreakdownCard(loanInfo: loanInfo, account: account)
                }
                statsCard(loanInfo: loanInfo, account: account)
                amortizationSection(loanInfo: loanInfo, account: account)
            }
        }
        .screenPadding()
    }

    // MARK: - Payment Breakdown Card

    private func paymentBreakdownCard(loanInfo: LoanInfo, account: Account) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "loan.currentPaymentBreakdown", defaultValue: "Current Payment Breakdown"))
                .font(AppTypography.h4)

            if loanInfo.interestRateAnnual > 0, loanInfo.remainingPrincipal > 0 {
                let breakdown = LoanPaymentService.paymentBreakdown(
                    remainingPrincipal: loanInfo.remainingPrincipal,
                    annualRate: loanInfo.interestRateAnnual,
                    monthlyPayment: loanInfo.monthlyPayment
                )

                HStack(spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(String(localized: "loan.principalPortion", defaultValue: "Principal"))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                        FormattedAmountText(
                            amount: NSDecimalNumber(decimal: breakdown.principal).doubleValue,
                            currency: account.currency,
                            fontSize: AppTypography.body,
                            color: AppColors.income
                        )
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(String(localized: "loan.interestPortion", defaultValue: "Interest"))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                        FormattedAmountText(
                            amount: NSDecimalNumber(decimal: breakdown.interest).doubleValue,
                            currency: account.currency,
                            fontSize: AppTypography.body,
                            color: AppColors.expense
                        )
                    }

                    Spacer()
                }

                // Visual ratio bar
                let total = breakdown.principal + breakdown.interest
                if total > 0 {
                    let principalRatio = NSDecimalNumber(decimal: breakdown.principal / total).doubleValue
                    ProportionBar(
                        ratio: principalRatio,
                        leftColor: AppColors.income,
                        rightColor: AppColors.expense
                    )
                }
            } else {
                // Installment — no interest
                Text(String(localized: "loan.noInterest", defaultValue: "Installment — no interest charged"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Stats Card

    private func statsCard(loanInfo: LoanInfo, account: Account) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "loan.stats", defaultValue: "Statistics"))
                .font(AppTypography.h4)

            InfoRow(
                icon: "banknote",
                label: String(localized: "loan.originalAmount", defaultValue: "Original Amount"),
                value: Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue, currency: account.currency)
            )

            if loanInfo.interestRateAnnual > 0 {
                InfoRow(
                    icon: "percent",
                    label: String(localized: "loan.interestRate", defaultValue: "Interest Rate"),
                    value: String(format: "%.2f%% %@", NSDecimalNumber(decimal: loanInfo.interestRateAnnual).doubleValue, String(localized: "loan.annual", defaultValue: "annual"))
                )

                InfoRow(
                    icon: "chart.bar.fill",
                    label: String(localized: "loan.totalInterestPaid", defaultValue: "Interest Paid"),
                    value: Formatting.formatCurrency(NSDecimalNumber(decimal: loanInfo.totalInterestPaid).doubleValue, currency: account.currency)
                )

                let totalInterest = cachedSchedule.reduce(Decimal(0)) { $0 + $1.interest }
                InfoRow(
                    icon: "chart.line.uptrend.xyaxis",
                    label: String(localized: "loan.projectedTotalInterest", defaultValue: "Total Interest (projected)"),
                    value: Formatting.formatCurrency(NSDecimalNumber(decimal: totalInterest).doubleValue, currency: account.currency)
                )
            }

            InfoRow(
                icon: "calendar",
                label: String(localized: "loan.term", defaultValue: "Term"),
                value: String(format: String(localized: "loan.termValue", defaultValue: "%d months"), loanInfo.termMonths)
            )

            InfoRow(
                icon: "checkmark.circle",
                label: String(localized: "loan.paymentsMade", defaultValue: "Payments Made"),
                value: "\(loanInfo.paymentsMade) / \(loanInfo.termMonths)"
            )

            let remaining = LoanPaymentService.remainingPayments(loanInfo: loanInfo)
            InfoRow(
                icon: "hourglass",
                label: String(localized: "loan.paymentsRemaining", defaultValue: "Remaining"),
                value: String(format: String(localized: "loan.paymentsRemainingValue", defaultValue: "%d payments"), remaining)
            )

            InfoRow(
                icon: "calendar.badge.clock",
                label: String(localized: "loan.endDate", defaultValue: "End Date"),
                value: formatDateString(loanInfo.endDate)
            )

            if !loanInfo.earlyRepayments.isEmpty {
                InfoRow(
                    icon: "bolt.fill",
                    label: String(localized: "loan.earlyRepayments", defaultValue: "Early Repayments"),
                    value: "\(loanInfo.earlyRepayments.count)"
                )
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Amortization Schedule

    private func amortizationSection(loanInfo: LoanInfo, account: Account) -> some View {
        let schedule = cachedSchedule
        let displayedEntries = showFullSchedule ? schedule : Array(schedule.prefix(6))

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "loan.amortizationSchedule", defaultValue: "Amortization Schedule"))
                .font(AppTypography.h4)

            if schedule.isEmpty {
                Text(String(localized: "loan.noSchedule", defaultValue: "No schedule available"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(displayedEntries) { entry in
                    amortizationRow(entry: entry, account: account)
                }

                if schedule.count > 6 && !showFullSchedule {
                    Button {
                        withAnimation(AppAnimation.contentSpring) {
                            showFullSchedule = true
                        }
                    } label: {
                        Text(String(format: String(localized: "loan.showAllPayments", defaultValue: "Show all %d payments"), schedule.count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func amortizationRow(entry: LoanPaymentService.AmortizationEntry, account: Account) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("#\(entry.paymentNumber)")
                    .font(AppTypography.bodySmall.weight(.medium))
                Text(formatDateString(entry.date))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                FormattedAmountText(amount: NSDecimalNumber(decimal: entry.payment).doubleValue, currency: account.currency, fontSize: AppTypography.bodySmall)
                if entry.interest > 0 {
                    Text(String(format: String(localized: "loan.interestShort", defaultValue: "int: %@"), Formatting.formatCurrency(NSDecimalNumber(decimal: entry.interest).doubleValue, currency: account.currency)))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.expense)
                }
            }

            // Paid indicator
            Image(systemName: entry.isPaid ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isPaid ? AppColors.income : AppColors.textSecondary)
                .font(AppTypography.body)
        }
        .futureTransactionStyle(isFuture: !entry.isPaid)
    }

    // MARK: - Toolbar menu

    @ViewBuilder
    private var loanToolbarMenu: some View {
        Button {
            HapticManager.selection()
            showingEditView = true
        } label: {
            Label(String(localized: "loan.edit", defaultValue: "Edit Loan"), systemImage: "pencil")
        }

        // Rate changes don't apply to installments (always 0% by definition).
        if liveAccount?.loanInfo?.loanType != .installment {
            Button {
                HapticManager.selection()
                showingRateChange = true
            } label: {
                Label(String(localized: "loan.changeRate", defaultValue: "Change Rate"), systemImage: "chart.line.uptrend.xyaxis")
            }
        }

        // Early Repayment intentionally omitted here — surfaced as the secondary
        // action button on the detail scaffold to avoid duplication.

        Button {
            HapticManager.selection()
            showingLinkPayments = true
        } label: {
            Label(String(localized: "loan.linkPayments", defaultValue: "Link Payments"), systemImage: "link")
        }

        Divider()

        Button(role: .destructive) {
            HapticManager.warning()
            showingDeleteConfirmation = true
        } label: {
            Label(String(localized: "loan.delete", defaultValue: "Delete Loan"), systemImage: "trash")
        }
    }

    // MARK: - Formatters

    private func formatDate(_ date: Date) -> String {
        DateFormatters.displayDateFormatter.string(from: date)
    }

    private func formatDateString(_ dateStr: String) -> String {
        DateFormatters.displayString(from: dateStr)
    }
}

// MARK: - Previews

#Preview("Loan Detail") {
    let coordinator = AppCoordinator()
    let sampleLoan = Account(
        id: "preview-loan",
        name: "Car Loan",
        currency: "KZT",
        iconSource: .brandService("halykbank.kz"),
        loanInfo: LoanInfo(
            bankName: "Halyk Bank",
            loanType: .annuity,
            originalPrincipal: 5_000_000,
            remainingPrincipal: 3_500_000,
            interestRateAnnual: 18.5,
            termMonths: 36,
            startDate: "2025-06-01",
            paymentDay: 15,
            paymentsMade: 9
        ),
        initialBalance: 3_500_000
    )
    let _ = coordinator.transactionStore.addAccount(sampleLoan)

    NavigationStack {
        LoanDetailView(
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            accountId: "preview-loan"
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}

#Preview("Loan Detail - Not Found") {
    let coordinator = AppCoordinator()

    NavigationStack {
        LoanDetailView(
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            accountId: "non-existent"
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}
