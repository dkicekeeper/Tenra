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
    @State private var paymentError: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager

    private let logger = Logger(subsystem: "Tenra", category: "LoanDetailView")

    /// Live lookup — reflects rename / rate change / payment updates without re-navigation.
    private var liveAccount: Account? {
        loansViewModel.getLoan(by: accountId)
    }

    /// Refresh key bumps on ANY transaction mutation (add/update/delete), not just
    /// count changes — so editing a linked payment's amount refreshes the cached
    /// list immediately instead of waiting for re-navigation.
    private struct RefreshKey: Equatable {
        let mutationVersion: Int
        let accountId: String
    }

    private var refreshTrigger: RefreshKey {
        // Touch the observable transactions array so the body re-evaluates on any
        // tx mutation (mutationVersion is @ObservationIgnored on its own).
        _ = transactionStore.transactions.count
        return RefreshKey(
            mutationVersion: transactionStore.mutationVersion,
            accountId: accountId
        )
    }

    private func refreshTransactions() async {
        cachedTransactions = transactionStore.transactions
            .filter { $0.accountId == accountId || $0.targetAccountId == accountId }
            .sorted { $0.date > $1.date }
    }

    /// Drives amortization-schedule regeneration: bumps whenever any loan field
    /// that affects the schedule (or its paid markers) changes — so marking a
    /// payment paid re-renders the rows without re-navigation.
    private var scheduleKey: String {
        guard let li = liveAccount?.loanInfo else { return accountId }
        return "\(accountId)|\(li.paymentsMade)|\(li.remainingPrincipal)|\(li.termMonths)|\(li.monthlyPayment)|\(li.interestRateAnnual)|\(li.earlyRepayments.count)"
    }

    /// Most recent loan-payment for this loan — feeds the LoanPaymentView defaults
    /// (amount + previously-used category). Real-world payments are usually rounded
    /// above the calculated annuity (e.g. 340 000 vs 336 829), so the prior actual
    /// is the best suggestion.
    private var mostRecentPayment: Transaction? {
        transactionStore.transactions
            .filter {
                ($0.type == .loanPayment || $0.type == .loanEarlyRepayment)
                && ($0.targetAccountId == accountId || $0.accountId == accountId)
            }
            .sorted { $0.date > $1.date }
            .first
    }

    private var lastPaidAmount: Decimal? {
        mostRecentPayment.map { Decimal($0.amount) }
    }

    /// Previously-used expense category for this loan (skips the technical
    /// "Loan Payment" sentinel so the UI doesn't pre-select a non-list value).
    private var lastUsedCategory: String? {
        guard let category = mostRecentPayment?.category,
              !category.isEmpty,
              category != TransactionType.loanPaymentCategoryName else {
            return nil
        }
        return category
    }

    /// Previously-used subcategory ids for this loan's most recent payment —
    /// resolved through `categoriesViewModel` since they're stored as a M:N
    /// relationship rather than directly on the transaction.
    private var lastUsedSubcategoryIds: Set<String> {
        guard let txId = mostRecentPayment?.id else { return [] }
        return Set(appCoordinator.categoriesViewModel
            .getSubcategoriesForTransaction(txId)
            .map(\.id))
    }

    /// Initial category for a new payment form — prefers the most recent
    /// payment's category (mirrors user habits), falls back to the loan's
    /// configured `defaultCategory`. Returns `nil` when neither applies so the
    /// picker stays unselected.
    private func resolvedInitialCategory(for loanInfo: LoanInfo) -> String? {
        if let lastUsed = lastUsedCategory { return lastUsed }
        guard let stored = loanInfo.defaultCategory,
              !stored.isEmpty,
              stored != TransactionType.loanPaymentCategoryName,
              expensePickerCategories.contains(stored) else { return nil }
        return stored
    }

    /// Initial subcategories for a new payment form — last-used wins when there
    /// were prior payments; otherwise we fall back to the loan's configured
    /// defaults so users don't repeatedly tag every payment.
    private func resolvedInitialSubcategoryIds(for loanInfo: LoanInfo) -> Set<String> {
        if mostRecentPayment != nil {
            return lastUsedSubcategoryIds
        }
        return Set(loanInfo.defaultSubcategoryIds)
    }

    /// Smart default source account for new payments — uses the same ranking the
    /// add-transaction flow uses (recency + volume) instead of naively picking the
    /// first account. Falls back to the first regular account when no suggestion
    /// qualifies (or the suggestion is itself a loan/deposit container).
    private var suggestedSourceAccountId: String? {
        let suggested = loansViewModel.accountsViewModel.suggestedAccount(
            forCategory: "",
            transactions: transactionsViewModel.allTransactions
        )
        if let suggested, !suggested.isLoan, !suggested.isDeposit {
            return suggested.id
        }
        return loansViewModel.accountsViewModel.regularAccounts.first?.id
    }

    /// Expense-catalog categories shown in the LoanPaymentView picker.
    ///
    /// Restricted to **currently active** custom categories — we deliberately
    /// don't backfill from `transactionStore.transactions.category` (the way the
    /// edit flow does) because deleted categories that still appear on legacy
    /// transactions shouldn't be offered as options for a brand-new payment.
    private var expensePickerCategories: [String] {
        let names = appCoordinator.categoriesViewModel.customCategories
            .filter { $0.type == .expense }
            .map(\.name)
        return names.sortedByCustomOrder(
            customCategories: appCoordinator.categoriesViewModel.customCategories,
            type: .expense
        )
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
                    balanceCoordinator: balanceCoordinator,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                    appSettings: transactionsViewModel.appSettings,
                    lastPaidAmount: lastPaidAmount,
                    availableCategories: expensePickerCategories,
                    customCategories: appCoordinator.categoriesViewModel.customCategories,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    initialCategory: resolvedInitialCategory(for: loanInfo),
                    initialSubcategoryIds: resolvedInitialSubcategoryIds(for: loanInfo),
                    defaultSourceAccountId: suggestedSourceAccountId,
                    onPayment: { result in
                        if let transaction = loansViewModel.makeManualPayment(
                            accountId: account.id,
                            amount: result.amount,
                            date: result.date,
                            sourceAccountId: result.sourceAccountId,
                            description: result.note,
                            category: result.category
                        ) {
                            Task {
                                do {
                                    _ = try await transactionStore.add(transaction)
                                    if !result.subcategoryIds.isEmpty {
                                        appCoordinator.categoriesViewModel
                                            .linkSubcategoriesToTransaction(
                                                transactionId: transaction.id,
                                                subcategoryIds: Array(result.subcategoryIds)
                                            )
                                    }
                                    // Only the source bank + the loan account change —
                                    // a targeted recalc avoids the multi-second stall of
                                    // rescanning all transactions across every account.
                                    transactionsViewModel.recalculateBalances(
                                        for: [result.sourceAccountId, account.id]
                                    )
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
                    balanceCoordinator: balanceCoordinator,
                    baseCurrency: transactionsViewModel.appSettings.baseCurrency,
                    appSettings: transactionsViewModel.appSettings,
                    availableCategories: expensePickerCategories,
                    customCategories: appCoordinator.categoriesViewModel.customCategories,
                    categoriesViewModel: appCoordinator.categoriesViewModel,
                    initialCategory: resolvedInitialCategory(for: loanInfo),
                    initialSubcategoryIds: resolvedInitialSubcategoryIds(for: loanInfo),
                    defaultSourceAccountId: suggestedSourceAccountId,
                    onRepayment: { result in
                        if let transaction = loansViewModel.makeEarlyRepayment(
                            accountId: account.id,
                            amount: result.amount,
                            date: result.date,
                            type: result.type,
                            sourceAccountId: result.sourceAccountId,
                            note: result.note,
                            category: result.category
                        ) {
                            Task {
                                do {
                                    _ = try await transactionStore.add(transaction)
                                    if !result.subcategoryIds.isEmpty {
                                        appCoordinator.categoriesViewModel
                                            .linkSubcategoriesToTransaction(
                                                transactionId: transaction.id,
                                                subcategoryIds: Array(result.subcategoryIds)
                                            )
                                    }
                                    // Targeted recalc — only the source bank + loan change.
                                    transactionsViewModel.recalculateBalances(
                                        for: [result.sourceAccountId, account.id]
                                    )
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
        .task(id: scheduleKey) {
            if let li = account.loanInfo {
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
                amount: NSDecimalNumber(decimal: loanInfo.originalPrincipal).doubleValue,
                currency: account.currency
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
                    amount: NSDecimalNumber(decimal: loanInfo.totalInterestPaid).doubleValue,
                    currency: account.currency
                )

                let totalInterest = cachedSchedule.reduce(Decimal(0)) { $0 + $1.interest }
                InfoRow(
                    icon: "chart.line.uptrend.xyaxis",
                    label: String(localized: "loan.projectedTotalInterest", defaultValue: "Total Interest (projected)"),
                    amount: NSDecimalNumber(decimal: totalInterest).doubleValue,
                    currency: account.currency
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
                    AmortizationScheduleRow(entry: entry, currency: account.currency)
                        .contextMenu {
                            scheduleRowMenu(entry: entry, accountId: account.id)
                        }
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

    /// Long-press menu on a schedule row. Marking a payment paid also marks every
    /// earlier one (loan installments can't skip prior payments); the inverse
    /// clears this payment and all later ones.
    @ViewBuilder
    private func scheduleRowMenu(entry: LoanPaymentService.AmortizationEntry, accountId: String) -> some View {
        if entry.isPaid {
            Button {
                HapticManager.light()
                loansViewModel.markPaymentsPaid(accountId: accountId, upToPaymentNumber: entry.paymentNumber - 1)
            } label: {
                Label(
                    String(localized: "loan.markUnpaid", defaultValue: "Отметить неоплаченным"),
                    systemImage: "circle"
                )
            }
        } else {
            Button {
                HapticManager.light()
                loansViewModel.markPaymentsPaid(accountId: accountId, upToPaymentNumber: entry.paymentNumber)
            } label: {
                Label(
                    String(localized: "loan.markPaid", defaultValue: "Отметить оплаченным"),
                    systemImage: "checkmark.circle.fill"
                )
            }
        }
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
