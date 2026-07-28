//
//  LoansListView.swift
//  Tenra
//
//  List view displaying all loans and installments with progress,
//  next payment info, and navigation to detail/edit views.
//

import OSLog
import SwiftUI

struct LoansListView: View {
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel
    let balanceCoordinator: BalanceCoordinator
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(PremiumManager.self) private var premium

    @State private var showingAddLoan = false
    @State private var showingPaywall = false
    @State private var showingPayAll = false
    @State private var selectedFilter: LoanFilter = .all
    @State private var payAllError: String? = nil
    @State private var isClosedSectionExpanded = false

    private let logger = Logger(subsystem: "Tenra", category: "LoansListView")

    enum LoanFilter: String, CaseIterable {
        case all
        case credits
        case installments

        var label: String {
            switch self {
            case .all: return String(localized: "loan.filterAll", defaultValue: "All")
            case .credits: return String(localized: "loan.filterCredits", defaultValue: "Credits")
            case .installments: return String(localized: "loan.filterInstallments", defaultValue: "Installments")
            }
        }
    }

    /// Только активные кредиты — закрытые живут в отдельной секции ниже и не
    /// участвуют в фильтре.
    private var filteredLoans: [Account] {
        applyTypeFilter(to: loansViewModel.activeLoans)
    }

    private var filteredClosedLoans: [Account] {
        applyTypeFilter(to: loansViewModel.closedLoans)
    }

    private func applyTypeFilter(to loans: [Account]) -> [Account] {
        switch selectedFilter {
        case .all: return loans
        case .credits: return loans.filter { $0.loanInfo?.loanType == .annuity }
        case .installments: return loans.filter { $0.loanInfo?.loanType == .installment }
        }
    }

    var body: some View {
        Group {
            if loansViewModel.loans.isEmpty {
                EmptyStateView(
                    icon: "creditcard",
                    title: String(localized: "loan.emptyTitle", defaultValue: "No Loans"),
                    description: String(localized: "loan.emptyDescription", defaultValue: "Add your credits and installments to track payments and progress"),
                    actionTitle: String(localized: "loan.addLoan", defaultValue: "Add Loan"),
                    action: {
                        HapticManager.light()
                        // Loans are a Pro feature (amortization + payment tracking) —
                        // every add path routes non-Pro users to the paywall.
                        if premium.isPro {
                            showingAddLoan = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        // Summary card
                        loansSummary
                            .chartAppear()
                            .screenPadding()

                        // Filter
                        if hasMultipleTypes {
                            Picker(String(localized: "loan.filter", defaultValue: "Filter"), selection: $selectedFilter) {
                                ForEach(LoanFilter.allCases, id: \.self) { filter in
                                    Text(filter.label).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .screenPadding()
                        }

                        // Loan cards
                        ForEach(Array(filteredLoans.enumerated()), id: \.element.id) { index, loan in
                            NavigationLink(value: FinancesDestination.loanDetail(loan.id)) {
                                LoanCard(loan: loan)
                            }
                            .buttonStyle(.plain)
                            .chartAppear(delay: Double(index) * 0.05)
                            .screenPadding()
                        }

                        if !filteredClosedLoans.isEmpty {
                            closedLoansSection
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(String(localized: "loan.listTitle", defaultValue: "Loans"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    if premium.isPro {
                        showingAddLoan = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .primaryButton()
                .accessibilityLabel(String(localized: "loan.add", defaultValue: "Add Loan"))
            }
        }
        .paywallSheet(isPresented: $showingPaywall) {
            // After unlocking Pro, continue straight into the add-loan flow.
            showingAddLoan = true
        }
        .sheet(isPresented: $showingAddLoan) {
            LoanEditView(
                loansViewModel: loansViewModel,
                account: nil,
                onSave: { newAccount in
                    loansViewModel.addLoanAccount(newAccount)
                    showingAddLoan = false
                }
            )
        }
        .sheet(isPresented: $showingPayAll) {
            LoanPayAllView(
                activeLoans: activeLoans,
                availableAccounts: loansViewModel.accountsViewModel.regularAccounts,
                currency: loansViewModel.loans.first?.currency ?? "KZT",
                defaultAmounts: lastPaidAmounts(for: activeLoans),
                onPayAll: { amounts, sourceAccountId, dateStr in
                    payAllLoans(amounts: amounts, sourceAccountId: sourceAccountId, dateStr: dateStr)
                }
            )
        }
        .overlay(alignment: .top) {
            if let msg = payAllError {
                MessageBanner.error(msg)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(AppAnimation.gentleSpring, value: payAllError)
    }

    // MARK: - Closed loans

    /// Погашенные кредиты держим отдельно и свёрнутыми: они не требуют действий, но
    /// историю платежей и график по ним пользователь должен уметь открыть.
    ///
    /// Заголовок + `if`, а НЕ `DisclosureGroup`: тот клипает своё содержимое (так он
    /// анимирует раскрытие), а `cardStyle()` на iOS 26 это `.glassEffect`, свечение
    /// которого выходит за границы фигуры, и клип его срезает. По той же причине
    /// `screenPadding()` висит на каждой карточке отдельно, как у активных кредитов,
    /// а не на контейнере секции.
    private var closedLoansSection: some View {
        VStack(spacing: AppSpacing.md) {
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) {
                    isClosedSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Text(String(localized: "loan.closedSection", defaultValue: "Closed"))
                        .font(AppTypography.h4)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("\(filteredClosedLoans.count)")
                        .font(AppTypography.h4)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .rotationEffect(.degrees(isClosedSectionExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .screenPadding()

            if isClosedSectionExpanded {
                ForEach(filteredClosedLoans) { loan in
                    NavigationLink(value: FinancesDestination.loanDetail(loan.id)) {
                        LoanCard(loan: loan)
                    }
                    .buttonStyle(.plain)
                    .screenPadding()
                }
            }
        }
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Summary

    private var loansSummary: some View {
        // Закрытые кредиты исключены из всех сводных чисел: их остаток равен нулю, а
        // monthlyPayment остаётся заполненным навсегда и раздувал бы «Ежемесячно».
        let active = loansViewModel.activeLoans
        let totalDebt = active.compactMap { $0.loanInfo?.remainingPrincipal }
            .reduce(Decimal(0), +)
        let totalMonthlyPayment = active.compactMap { $0.loanInfo?.monthlyPayment }
            .reduce(Decimal(0), +)
        let primaryCurrency = active.first?.currency ?? loansViewModel.loans.first?.currency ?? "KZT"

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(String(localized: "loan.totalDebt", defaultValue: "Total Debt"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: totalDebt).doubleValue,
                        currency: primaryCurrency,
                        fontSize: AppTypography.h3
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text(String(localized: "loan.monthlyTotal", defaultValue: "Monthly"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                    FormattedAmountText(
                        amount: NSDecimalNumber(decimal: totalMonthlyPayment).doubleValue,
                        currency: primaryCurrency,
                        fontSize: AppTypography.h3,
                        color: AppColors.expense
                    )
                }
            }

            Text(String(format: String(localized: "loan.activeCount", defaultValue: "%d active loans"), active.count))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private var hasMultipleTypes: Bool {
        let types = Set(loansViewModel.loans.compactMap { $0.loanInfo?.loanType })
        return types.count > 1
    }

    private var activeLoans: [Account] {
        loansViewModel.activeLoans
    }

    /// Pay All only available when all active loans share a single currency
    private var canPayAll: Bool {
        let currencies = Set(activeLoans.map(\.currency))
        return currencies.count == 1
    }

    /// Resolves a per-loan default payment amount = the most recent linked
    /// loan-payment for that loan, falling back to `monthlyPayment` when no
    /// prior payment exists.
    private func lastPaidAmounts(for loans: [Account]) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        let allPayments = transactionStore.transactions.filter {
            $0.type == .loanPayment || $0.type == .loanEarlyRepayment
        }
        for loan in loans {
            let mostRecent = allPayments
                .filter { $0.targetAccountId == loan.id || $0.accountId == loan.id }
                .sorted { $0.date > $1.date }
                .first
            if let mostRecent {
                result[loan.id] = Decimal(mostRecent.amount)
            }
        }
        return result
    }

    private func payAllLoans(amounts: [String: Decimal], sourceAccountId: String, dateStr: String) {
        Task {
            var failedLoanNames: [String] = []
            for loan in activeLoans {
                guard let loanInfo = loan.loanInfo else { continue }
                let amount = amounts[loan.id] ?? loanInfo.monthlyPayment
                if let transaction = loansViewModel.makeManualPayment(
                    accountId: loan.id,
                    amount: amount,
                    date: dateStr,
                    sourceAccountId: sourceAccountId
                ) {
                    do {
                        _ = try await transactionStore.add(transaction)
                    } catch {
                        logger.error("Failed to add payment for \(loan.name): \(error.localizedDescription)")
                        failedLoanNames.append(loan.name)
                    }
                }
            }
            transactionsViewModel.recalculateAccountBalances()
            if !failedLoanNames.isEmpty {
                payAllError = String(localized: "loan.payAllPartialFailed \(failedLoanNames.joined(separator: ", "))")
                try? await Task.sleep(for: .seconds(4))
                payAllError = nil
            }
        }
    }
}

// MARK: - Previews

#Preview("Loans List") {
    let coordinator = AppCoordinator()
    let sampleLoans: [Account] = [
        Account(
            id: "preview-loan-1",
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
        ),
        Account(
            id: "preview-loan-2",
            name: "iPhone Installment",
            currency: "KZT",
            iconSource: .brandService("kaspi.kz"),
            loanInfo: LoanInfo(
                bankName: "Kaspi Bank",
                loanType: .installment,
                originalPrincipal: 600_000,
                remainingPrincipal: 400_000,
                interestRateAnnual: 0,
                termMonths: 12,
                startDate: "2026-01-15",
                paymentDay: 15,
                paymentsMade: 2
            ),
            initialBalance: 400_000
        )
    ]
    let _ = sampleLoans.forEach { coordinator.transactionStore.addAccount($0) }

    NavigationStack {
        LoansListView(
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        // Required: the view reads `@Environment(PremiumManager.self)` for the Pro gate.
        // A non-optional `@Environment(T.self)` traps during dynamic-property update when
        // T isn't in the environment, so omitting it crashes the preview process.
        .environment(PremiumManager.shared)
    }
}

#Preview("Loans List - Empty") {
    let coordinator = AppCoordinator()

    NavigationStack {
        LoansListView(
            loansViewModel: coordinator.loansViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        // Required: the view reads `@Environment(PremiumManager.self)` for the Pro gate.
        // A non-optional `@Environment(T.self)` traps during dynamic-property update when
        // T isn't in the environment, so omitting it crashes the preview process.
        .environment(PremiumManager.shared)
    }
}
