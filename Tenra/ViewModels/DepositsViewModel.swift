//
//  DepositsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing deposits and interest calculations

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class DepositsViewModel {
    // MARK: - Observable Properties

    /// Computed directly from accountsViewModel — always in sync (Phase 16 pattern)
    var deposits: [Account] {
        accountsViewModel.accounts.filter { $0.isDeposit }
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

    // MARK: - Deposit Management

    func addDeposit(
        name: String,
        currency: String,
        bankName: String,
        iconSource: IconSource?,
        principalBalance: Decimal,
        interestRateAnnual: Decimal,
        interestPostingDay: Int,
        capitalizationEnabled: Bool = true
    ) {
        accountsViewModel.addDeposit(
            name: name,
            balance: NSDecimalNumber(decimal: principalBalance).doubleValue,
            currency: currency,
            bankName: bankName,
            iconSource: iconSource,
            principalBalance: principalBalance,
            capitalizationEnabled: capitalizationEnabled,
            interestRateAnnual: interestRateAnnual,
            interestPostingDay: interestPostingDay
        )
    }

    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        accountsViewModel.updateDeposit(account)
    }

    func deleteDeposit(_ account: Account) {
        accountsViewModel.deleteDeposit(account)
    }

    // MARK: - Interest Rate Management

    func addDepositRateChange(accountId: String, effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              var depositInfo = account.depositInfo else {
            return
        }

        DepositInterestService.addRateChange(
            depositInfo: &depositInfo,
            effectiveFrom: effectiveFrom,
            annualRate: annualRate,
            note: note
        )

        account.depositInfo = depositInfo
        accountsViewModel.updateAccount(account)
    }

    // MARK: - Interest Reconciliation

    /// Reconcile interest for all deposits
    func reconcileAllDeposits(allTransactions: [Transaction], onTransactionCreated: @escaping (Transaction) -> Void) {
        for account in accountsViewModel.accounts where account.isDeposit {
            var updatedAccount = account
            DepositInterestService.reconcileDepositInterest(
                account: &updatedAccount,
                allTransactions: allTransactions,
                onTransactionCreated: onTransactionCreated
            )
            accountsViewModel.updateAccount(updatedAccount)
            syncDepositBalance(updatedAccount)
        }
    }

    /// Reconcile interest for a specific deposit
    func reconcileDepositInterest(for accountId: String, allTransactions: [Transaction], onTransactionCreated: @escaping (Transaction) -> Void) {
        guard var account = accountsViewModel.getAccount(by: accountId),
              account.isDeposit else {
            return
        }

        DepositInterestService.reconcileDepositInterest(
            account: &account,
            allTransactions: allTransactions,
            onTransactionCreated: onTransactionCreated
        )
        accountsViewModel.updateAccount(account)
        syncDepositBalance(account)
    }

    /// Sync deposit balance to BalanceCoordinator after interest reconciliation.
    /// Without this, BalanceCoordinator's in-memory state stays stale until next full recalculation.
    private func syncDepositBalance(_ account: Account) {
        guard let depositInfo = account.depositInfo,
              let coordinator = balanceCoordinator else { return }
        let newBalance = BalanceCalculationEngine().calculateDepositBalance(depositInfo: depositInfo)
        Task {
            await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
            await coordinator.updateForAccount(account, newBalance: newBalance)
        }
    }

    // MARK: - Helper Methods

    /// Get deposit by ID
    func getDeposit(by id: String) -> Account? {
        deposits.first { $0.id == id }
    }

    /// Calculate interest to today for a deposit account (for use in list rows)
    func interestToday(for account: Account) -> Double? {
        guard let depositInfo = account.depositInfo else { return nil }
        let val = DepositInterestService.calculateInterestToToday(depositInfo: depositInfo)
        return val > 0 ? NSDecimalNumber(decimal: val).doubleValue : nil
    }

    /// Get next posting date for a deposit account (for use in list rows)
    func nextPostingDate(for account: Account) -> Date? {
        guard let depositInfo = account.depositInfo else { return nil }
        return DepositInterestService.nextPostingDate(depositInfo: depositInfo)
    }

    /// Calculate interest to today for a deposit by ID
    func calculateInterestToToday(for accountId: String) -> Decimal? {
        guard let account = getDeposit(by: accountId),
              let depositInfo = account.depositInfo else {
            return nil
        }
        return DepositInterestService.calculateInterestToToday(depositInfo: depositInfo)
    }

    /// Get next posting date for a deposit by ID
    func nextPostingDate(for accountId: String) -> Date? {
        guard let account = getDeposit(by: accountId),
              let depositInfo = account.depositInfo else {
            return nil
        }
        return DepositInterestService.nextPostingDate(depositInfo: depositInfo)
    }
}
