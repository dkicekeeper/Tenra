//
//  LoansViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing loans (credits) and installments (рассрочки)

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class LoansViewModel {
    // MARK: - Observable Properties

    /// Computed directly from accountsViewModel — always in sync (Phase 16 pattern)
    var loans: [Account] {
        accountsViewModel.accounts.filter { $0.isLoan }
    }

    // MARK: - Dependencies

    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored let accountsViewModel: AccountsViewModel

    /// Injected by AppCoordinator after init (late injection — intentionally observable)
    var balanceCoordinator: BalanceCoordinator?

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol, accountsViewModel: AccountsViewModel) {
        self.repository = repository
        self.accountsViewModel = accountsViewModel
    }

    // MARK: - Loan Management

    /// Add a fully-formed loan Account (preserves computed fields in LoanInfo)
    func addLoanAccount(_ account: Account) {
        guard account.isLoan else { return }
        accountsViewModel.addLoanAccount(account)
    }

    func updateLoan(_ account: Account) {
        guard account.isLoan else { return }
        accountsViewModel.updateLoan(account)
    }

    func deleteLoan(_ account: Account) {
        accountsViewModel.deleteLoan(account)
    }

    // MARK: - Interest Rate Management

    func addLoanRateChange(accountId: String, effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              var loanInfo = account.loanInfo else {
            return
        }

        // Add rate change to history
        loanInfo.interestRateHistory.append(RateChange(
            effectiveFrom: effectiveFrom,
            annualRate: annualRate,
            note: note
        ))
        loanInfo.interestRateAnnual = annualRate

        // Recalculate monthly payment for remaining term
        let remainingMonths = LoanPaymentService.remainingPayments(loanInfo: loanInfo)
        if remainingMonths > 0 {
            loanInfo.monthlyPayment = LoanPaymentService.calculateMonthlyPayment(
                principal: loanInfo.remainingPrincipal,
                annualRate: annualRate,
                termMonths: remainingMonths
            )
        }

        account.loanInfo = loanInfo
        accountsViewModel.updateAccount(account)
    }

    // MARK: - Early Repayment

    func makeEarlyRepayment(
        accountId: String,
        amount: Decimal,
        date: String,
        type: EarlyRepaymentType,
        note: String? = nil
    ) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              var loanInfo = account.loanInfo else {
            return
        }

        LoanPaymentService.applyEarlyRepayment(
            loanInfo: &loanInfo,
            amount: amount,
            date: date,
            type: type,
            note: note
        )

        account.loanInfo = loanInfo
        accountsViewModel.updateAccount(account)
    }

    // MARK: - Manual Payment

    /// Record a manual loan payment from a source bank account.
    /// Returns the Transaction for the caller to persist via TransactionStore.
    func makeManualPayment(
        accountId: String,
        amount: Decimal,
        date: String,
        sourceAccountId: String
    ) -> Transaction? {
        guard var account = accountsViewModel.getAccount(by: accountId),
              let loanInfo = account.loanInfo else {
            return nil
        }

        let sourceAccount = accountsViewModel.getAccount(by: sourceAccountId)

        let (transaction, updatedLoanInfo) = LoanPaymentService.createManualPayment(
            account: account,
            loanInfo: loanInfo,
            paymentAmount: amount,
            dateStr: date,
            sourceAccountId: sourceAccountId,
            sourceAccountName: sourceAccount?.name
        )

        account.loanInfo = updatedLoanInfo
        accountsViewModel.updateAccount(account)

        return transaction
    }

    // MARK: - Reconciliation

    /// Reconcile payments for all loans
    func reconcileAllLoans(allTransactions: [Transaction], onTransactionCreated: @escaping (Transaction) -> Void) {
        for account in accountsViewModel.accounts where account.isLoan {
            var updatedAccount = account
            LoanPaymentService.reconcileLoanPayments(
                account: &updatedAccount,
                allTransactions: allTransactions,
                onTransactionCreated: onTransactionCreated
            )
            accountsViewModel.updateAccount(updatedAccount)
        }
    }

    /// Reconcile payments for a specific loan
    func reconcileLoanPayments(for accountId: String, allTransactions: [Transaction], onTransactionCreated: @escaping (Transaction) -> Void) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              account.isLoan else {
            return
        }

        LoanPaymentService.reconcileLoanPayments(
            account: &account,
            allTransactions: allTransactions,
            onTransactionCreated: onTransactionCreated
        )
        accountsViewModel.updateAccount(account)
    }

    // MARK: - Helper Methods

    /// Get loan by ID
    func getLoan(by id: String) -> Account? {
        loans.first { $0.id == id }
    }

    /// Next payment date for a loan account
    func nextPaymentDate(for account: Account) -> Date? {
        guard let loanInfo = account.loanInfo else { return nil }
        return LoanPaymentService.nextPaymentDate(loanInfo: loanInfo)
    }

    /// Remaining payments count for a loan account
    func remainingPayments(for account: Account) -> Int {
        guard let loanInfo = account.loanInfo else { return 0 }
        return LoanPaymentService.remainingPayments(loanInfo: loanInfo)
    }

    /// Progress percentage (0.0 – 1.0) of principal paid off
    func progressPercentage(for account: Account) -> Double {
        guard let loanInfo = account.loanInfo else { return 0 }
        return LoanPaymentService.progressPercentage(loanInfo: loanInfo)
    }

    /// Payment breakdown for the current month (interest vs principal)
    func currentPaymentBreakdown(for account: Account) -> (interest: Decimal, principal: Decimal)? {
        guard let loanInfo = account.loanInfo, loanInfo.remainingPrincipal > 0 else { return nil }
        return LoanPaymentService.paymentBreakdown(
            remainingPrincipal: loanInfo.remainingPrincipal,
            annualRate: loanInfo.interestRateAnnual,
            monthlyPayment: loanInfo.monthlyPayment
        )
    }

    /// Total interest over life of loan
    func totalInterestOverLife(for account: Account) -> Decimal {
        guard let loanInfo = account.loanInfo else { return 0 }
        return LoanPaymentService.totalInterestOverLife(loanInfo: loanInfo)
    }
}
