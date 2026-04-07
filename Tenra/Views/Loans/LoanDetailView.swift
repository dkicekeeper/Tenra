//
//  LoanDetailView.swift
//  Tenra
//
//  Detail view for loan/installment accounts with amortization schedule,
//  payment breakdown, early repayment, and rate change actions.
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
    @State private var showingHistory = false
    @State private var showFullSchedule = false
    @State private var reconciliationError: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager

    private let logger = Logger(subsystem: "Tenra", category: "LoanDetailView")

    private var account: Account? {
        loansViewModel.getLoan(by: accountId)
    }

    private var loanInfo: LoanInfo? {
        account?.loanInfo
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

                        if let loanInfo = loanInfo {
                            headerCard(loanInfo: loanInfo, account: account)
                                .chartAppear()
                                .screenPadding()

                            paymentBreakdownCard(loanInfo: loanInfo, account: account)
                                .chartAppear(delay: 0.05)
                                .screenPadding()

                            statsCard(loanInfo: loanInfo, account: account)
                                .chartAppear(delay: 0.1)
                                .screenPadding()

                            amortizationSection(loanInfo: loanInfo)
                                .chartAppear(delay: 0.15)
                                .screenPadding()

                            actionsSection
                                .chartAppear(delay: 0.2)
                                .screenPadding()
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
                .navigationTitle(account.name)
            } else {
                EmptyStateView(
                    icon: "creditcard",
                    title: String(localized: "loan.notFound", defaultValue: "Loan not found"),
                    description: String(localized: "emptyState.tryDifferentSearch")
                )
                .navigationTitle(String(localized: "loan.title", defaultValue: "Loan"))
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
                .accessibilityLabel(String(localized: "loan.history", defaultValue: "Payment History"))
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        HapticManager.selection()
                        showingEditView = true
                    } label: {
                        Label(String(localized: "loan.edit", defaultValue: "Edit Loan"), systemImage: "pencil")
                    }

                    Button {
                        HapticManager.selection()
                        showingRateChange = true
                    } label: {
                        Label(String(localized: "loan.changeRate", defaultValue: "Change Rate"), systemImage: "chart.line.uptrend.xyaxis")
                    }

                    Button {
                        HapticManager.selection()
                        showingEarlyRepayment = true
                    } label: {
                        Label(String(localized: "loan.earlyRepayment", defaultValue: "Early Repayment"), systemImage: "bolt.fill")
                    }

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
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "loan.actions", defaultValue: "Loan Actions"))
            }
        }
        .sheet(isPresented: $showingHistory) {
            if let account = account {
                NavigationStack {
                    HistoryView(
                        transactionsViewModel: transactionsViewModel,
                        accountsViewModel: loansViewModel.accountsViewModel,
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
        }
        .sheet(isPresented: $showingPayment) {
            if let account = account, let loanInfo = loanInfo {
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
                                }
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingEarlyRepayment) {
            if let account = account, let loanInfo = loanInfo {
                LoanEarlyRepaymentView(
                    account: account,
                    loanInfo: loanInfo,
                    onRepayment: { amount, date, type, note in
                        loansViewModel.makeEarlyRepayment(
                            accountId: account.id,
                            amount: amount,
                            date: date,
                            type: type,
                            note: note
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showingRateChange) {
            if let account = account, account.loanInfo != nil {
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
            if let account = account {
                LoanLinkPaymentsView(
                    loan: account,
                    loansViewModel: loansViewModel,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    accountsViewModel: appCoordinator.accountsViewModel,
                    balanceCoordinator: balanceCoordinator
                )
            }
        }
        .alert(String(localized: "loan.deleteTitle", defaultValue: "Delete Loan?"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "button.delete"), role: .destructive) {
                if let account = account {
                    HapticManager.warning()
                    loansViewModel.deleteLoan(account)
                    Task {
                        await transactionStore.deleteTransactions(forAccountId: account.id)
                    }
                    transactionsViewModel.recalculateAccountBalances()
                }
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "loan.deleteMessage", defaultValue: "All loan data and payment history will be deleted."))
        }
        .task(id: accountId) {
            // Reconcile only this loan's payments
            let store = transactionStore
            loansViewModel.reconcileLoanPayments(
                for: accountId,
                allTransactions: transactionsViewModel.allTransactions,
                onTransactionCreated: { transaction in
                    Task { @MainActor in
                        do {
                            _ = try await store.add(transaction)
                        } catch {
                            logger.error("Failed to add loan payment transaction: \(error.localizedDescription)")
                            reconciliationError = error.localizedDescription
                        }
                    }
                }
            )
        }
    }

    // MARK: - Header Card

    private func headerCard(loanInfo: LoanInfo, account: Account) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Icon + Name + Bank
            HStack {
                IconView(source: account.iconSource, size: AppIconSize.xxl)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h3)
                    HStack(spacing: AppSpacing.xs) {
                        Text(loanInfo.bankName)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondaryAccessible)
                        LoanTypeBadge(loanType: loanInfo.loanType)
                    }
                }
                Spacer()
            }

            // Progress bar
            let progress = LoanPaymentService.progressPercentage(loanInfo: loanInfo)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack {
                    Text(String(localized: "loan.paidOff", defaultValue: "Paid off"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(AppTypography.bodySmall.weight(.medium))
                        .foregroundStyle(AppColors.income)
                }
                ProgressView(value: progress)
                    .tint(AppColors.income)
                    .accessibilityValue(String(format: "%.0f%%", progress * 100))
            }

            Divider()

            // Remaining Principal
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: "loan.remainingPrincipal", defaultValue: "Remaining"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                FormattedAmountText(
                    amount: NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue,
                    currency: account.currency,
                    fontSize: AppTypography.h2
                )
            }

            // Next Payment
            if let nextDate = LoanPaymentService.nextPaymentDate(loanInfo: loanInfo) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(String(format: String(localized: "loan.nextPayment", defaultValue: "Next payment: %@"), formatDate(nextDate)))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondaryAccessible)
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue,
                        currency: account.currency,
                        fontSize: AppTypography.h4,
                        color: AppColors.planned
                    )
                }
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
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

                let totalInterest = LoanPaymentService.totalInterestOverLife(loanInfo: loanInfo)
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

    private func amortizationSection(loanInfo: LoanInfo) -> some View {
        let schedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: loanInfo)
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
                    amortizationRow(entry: entry)
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

    private func amortizationRow(entry: LoanPaymentService.AmortizationEntry) -> some View {
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
                FormattedAmountText(amount: NSDecimalNumber(decimal: entry.payment).doubleValue, currency: account?.currency ?? "KZT", fontSize: AppTypography.bodySmall)
                if entry.interest > 0 {
                    Text(String(format: String(localized: "loan.interestShort", defaultValue: "int: %@"), Formatting.formatCurrency(NSDecimalNumber(decimal: entry.interest).doubleValue, currency: account?.currency ?? "KZT")))
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

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Button {
                HapticManager.light()
                showingPayment = true
            } label: {
                Label(String(localized: "loan.makePayment", defaultValue: "Make Payment"), systemImage: "banknote")
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()

            Button {
                HapticManager.light()
                showingEarlyRepayment = true
            } label: {
                Label(String(localized: "loan.makeEarlyRepayment", defaultValue: "Early Repayment"), systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .secondaryButton()
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
