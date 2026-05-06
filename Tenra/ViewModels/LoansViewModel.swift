//
//  LoansViewModel.swift
//  Tenra
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
        sourceAccountId: String,
        note: String? = nil
    ) -> Transaction? {
        guard var account = accountsViewModel.getAccount(by: accountId),
              let loanInfo = account.loanInfo else {
            return nil
        }

        let sourceAccount = accountsViewModel.getAccount(by: sourceAccountId)

        let (transaction, updatedLoanInfo) = LoanPaymentService.createEarlyRepaymentTransaction(
            account: account,
            loanInfo: loanInfo,
            amount: amount,
            date: date,
            type: type,
            sourceAccountId: sourceAccountId,
            sourceAccountName: sourceAccount?.name,
            note: note
        )

        account.loanInfo = updatedLoanInfo
        accountsViewModel.updateAccount(account)

        return transaction
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

    // MARK: - Link Existing Transactions

    func linkTransactions(
        toLoan loanId: String,
        transactions: [Transaction],
        transactionStore: TransactionStore
    ) async throws {
        guard let loan = getLoan(by: loanId),
              loan.loanInfo != nil else {
            throw LoanLinkError.loanNotFound
        }

        let loanName = loan.name
        let sortedTransactions = transactions.sorted { $0.date < $1.date }

        // Convert each transaction to loanPayment
        for tx in sortedTransactions {
            // Sanitize the source account reference — drop it if the account no longer
            // exists, otherwise validate() throws targetAccountNotFound on stale ids
            // (e.g. user picked an old expense whose source account was since deleted).
            let resolvedTargetAccountId: String?
            let resolvedTargetAccountName: String?
            if let originalAccountId = tx.accountId,
               !originalAccountId.isEmpty,
               transactionStore.accountById[originalAccountId] != nil {
                resolvedTargetAccountId = originalAccountId
                resolvedTargetAccountName = tx.accountName
            } else {
                resolvedTargetAccountId = nil
                resolvedTargetAccountName = nil
            }

            let updated = Transaction(
                id: tx.id,
                date: tx.date,
                description: tx.description,
                amount: tx.amount,
                currency: tx.currency,
                convertedAmount: tx.convertedAmount,
                type: .loanPayment,
                category: TransactionType.loanPaymentCategoryName,
                subcategory: tx.subcategory,
                accountId: loanId,
                targetAccountId: resolvedTargetAccountId,
                accountName: loanName,
                targetAccountName: resolvedTargetAccountName,
                targetCurrency: tx.targetCurrency,
                targetAmount: tx.targetAmount,
                recurringSeriesId: tx.recurringSeriesId,
                recurringOccurrenceId: tx.recurringOccurrenceId,
                createdAt: tx.createdAt
            )
            try await transactionStore.update(updated)
        }

        // Re-fetch loan after updates (balance may have changed during loop)
        guard var freshLoan = getLoan(by: loanId),
              var loanInfo = freshLoan.loanInfo else {
            throw LoanLinkError.loanNotFound
        }

        // Count ALL loanPayment transactions for this loan (including pre-existing ones)
        let allLoanPayments = transactionStore.transactions.filter {
            $0.accountId == loanId && $0.type == .loanPayment
        }.sorted { $0.date < $1.date }

        let allDates = allLoanPayments.map(\.date)
        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &loanInfo,
            linkedPaymentCount: allLoanPayments.count,
            linkedPaymentDates: allDates
        )

        freshLoan.loanInfo = loanInfo
        updateLoan(freshLoan)
    }

    enum LoanLinkError: LocalizedError {
        case loanNotFound

        var errorDescription: String? {
            switch self {
            case .loanNotFound:
                return String(localized: "loan.linkPayments.error.notFound", defaultValue: "Loan not found")
            }
        }
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
