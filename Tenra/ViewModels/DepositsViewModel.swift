//
//  DepositsViewModel.swift
//  Tenra
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
        initialPrincipal: Decimal,
        interestRateAnnual: Decimal,
        interestPostingDay: Int,
        capitalizationEnabled: Bool = true
    ) {
        accountsViewModel.addDeposit(
            name: name,
            balance: NSDecimalNumber(decimal: initialPrincipal).doubleValue,
            currency: currency,
            bankName: bankName,
            iconSource: iconSource,
            initialPrincipal: initialPrincipal,
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

    /// Forward updated deposit metadata to BalanceCoordinator's cache.
    /// Balance is owned by the standard transaction pipeline — any newly posted
    /// `.depositInterestAccrual` transactions land via `BalanceCoordinator.processAddTransaction`
    /// during the same `add()` call.
    private func syncDepositBalance(_ account: Account) {
        guard let depositInfo = account.depositInfo,
              let coordinator = balanceCoordinator else { return }
        Task {
            await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
        }
    }

    // MARK: - Recalculate Interest from Scratch

    /// Deletes all auto-posted interest transactions for this deposit, resets
    /// `lastInterestCalculationDate` back to the deposit's `startDate`, and re-runs
    /// reconciliation. Use after the user back-fills historical top-ups/withdrawals
    /// so the new historical principal walk can produce correct interest amounts.
    /// Does not touch user-linked interest transactions (they keep their dates).
    func recalculateInterest(for accountId: String, transactionStore: TransactionStore) async throws {
        guard var account = accountsViewModel.getAccount(by: accountId),
              var info = account.depositInfo else { return }

        // Delete previously-posted interest transactions (generated by the service).
        // Detect them by deterministic id prefix `di_`.
        let postedInterest = transactionStore.transactions.filter {
            $0.accountId == accountId
            && $0.type == .depositInterestAccrual
            && $0.id.hasPrefix("di_")
        }
        for tx in postedInterest {
            try? await transactionStore.delete(tx)
        }

        // Reset the interest-accounting markers back to deposit creation.
        info.lastInterestCalculationDate = info.startDate
        // Reset lastInterestPostingMonth to the month BEFORE startDate so shouldPostInterest
        // fires on the first posting day after startDate.
        let calendar = Calendar.current
        if let startDate = DateFormatters.dateFormatter.date(from: info.startDate),
           let prevMonth = calendar.date(byAdding: .month, value: -1, to: startDate) {
            let comps = calendar.dateComponents([.year, .month], from: prevMonth)
            if let monthStart = calendar.date(from: comps) {
                info.lastInterestPostingMonth = DateFormatters.dateFormatter.string(from: monthStart)
            }
        }
        info.interestAccruedForCurrentPeriod = 0

        account.depositInfo = info
        accountsViewModel.updateAccount(account)

        // Re-run reconciliation — walks historical events day-by-day.
        reconcileDepositInterest(
            for: accountId,
            allTransactions: transactionStore.transactions,
            onTransactionCreated: { transaction in
                Task {
                    _ = try? await transactionStore.add(transaction)
                }
            }
        )
    }

    // MARK: - Link Existing Transactions as Deposit Interest

    /// Convert income transactions on the deposit account into `.depositInterestAccrual`.
    /// Pure classification — does NOT mutate the deposit's `principalBalance` or
    /// `interestAccruedNotCapitalized`. The deposit balance is already what the user
    /// expects (it was entered at creation or computed by the interest service).
    /// Double-counting historical interest into the principal would inflate the balance.
    func linkTransactionsAsInterest(
        depositId: String,
        transactions: [Transaction],
        transactionStore: TransactionStore
    ) async throws {
        guard let deposit = accountsViewModel.getAccount(by: depositId),
              deposit.depositInfo != nil, deposit.isDeposit else {
            return
        }
        let depositName = deposit.name
        let sorted = transactions.sorted { $0.date < $1.date }

        for tx in sorted {
            let updated = Transaction(
                id: tx.id,
                date: tx.date,
                description: tx.description,
                amount: tx.amount,
                currency: tx.currency,
                convertedAmount: tx.convertedAmount,
                type: .depositInterestAccrual,
                category: String(localized: "deposit.interestAccrual.category", defaultValue: "Interest"),
                subcategory: tx.subcategory,
                accountId: depositId,
                targetAccountId: tx.targetAccountId,
                accountName: depositName,
                targetAccountName: tx.targetAccountName,
                targetCurrency: tx.targetCurrency,
                targetAmount: tx.targetAmount,
                recurringSeriesId: tx.recurringSeriesId,
                recurringOccurrenceId: tx.recurringOccurrenceId,
                createdAt: tx.createdAt
            )
            try await transactionStore.update(updated)
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
        let txs = accountsViewModel.transactionStore?.transactions ?? []
        let val = DepositInterestService.calculateInterestToToday(
            depositInfo: depositInfo,
            accountId: account.id,
            allTransactions: txs
        )
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
        let txs = accountsViewModel.transactionStore?.transactions ?? []
        return DepositInterestService.calculateInterestToToday(
            depositInfo: depositInfo,
            accountId: accountId,
            allTransactions: txs
        )
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
