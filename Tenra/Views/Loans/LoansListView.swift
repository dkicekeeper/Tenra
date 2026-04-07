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

    @State private var showingAddLoan = false
    @State private var showingPayAll = false
    @State private var selectedFilter: LoanFilter = .all

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

    private var filteredLoans: [Account] {
        switch selectedFilter {
        case .all: return loansViewModel.loans
        case .credits: return loansViewModel.loans.filter { $0.loanInfo?.loanType == .annuity }
        case .installments: return loansViewModel.loans.filter { $0.loanInfo?.loanType == .installment }
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
                        showingAddLoan = true
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
                            NavigationLink(value: HomeDestination.loanDetail(loan.id)) {
                                LoanCard(loan: loan)
                            }
                            .buttonStyle(.plain)
                            .chartAppear(delay: Double(index) * 0.05)
                            .screenPadding()
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(String(localized: "loan.listTitle", defaultValue: "Loans"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppSpacing.md) {
                    if !activeLoans.isEmpty {
                        Button {
                            HapticManager.light()
                            showingPayAll = true
                        } label: {
                            Image(systemName: "creditcard")
                        }
                        .accessibilityLabel(String(localized: "loan.payAll", defaultValue: "Pay All"))
                    }

                    Button {
                        HapticManager.light()
                        showingAddLoan = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .glassProminentButton()
                }
            }
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
                onPayAll: { sourceAccountId, dateStr in
                    payAllLoans(sourceAccountId: sourceAccountId, dateStr: dateStr)
                }
            )
        }
    }

    // MARK: - Summary

    private var loansSummary: some View {
        let totalDebt = loansViewModel.loans.compactMap { $0.loanInfo?.remainingPrincipal }
            .reduce(Decimal(0), +)
        let totalMonthlyPayment = loansViewModel.loans.compactMap { $0.loanInfo?.monthlyPayment }
            .reduce(Decimal(0), +)
        let primaryCurrency = loansViewModel.loans.first?.currency ?? "KZT"

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

            Text(String(format: String(localized: "loan.activeCount", defaultValue: "%d active loans"), loansViewModel.loans.count))
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
        loansViewModel.loans.filter { ($0.loanInfo?.remainingPrincipal ?? 0) > 0 }
    }

    private func payAllLoans(sourceAccountId: String, dateStr: String) {
        Task {
            for loan in activeLoans {
                guard let loanInfo = loan.loanInfo else { continue }
                if let transaction = loansViewModel.makeManualPayment(
                    accountId: loan.id,
                    amount: loanInfo.monthlyPayment,
                    date: dateStr,
                    sourceAccountId: sourceAccountId
                ) {
                    do {
                        _ = try await transactionStore.add(transaction)
                    } catch {
                        logger.error("Failed to add payment for \(loan.name): \(error.localizedDescription)")
                    }
                }
            }
            transactionsViewModel.recalculateAccountBalances()
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
    }
}
