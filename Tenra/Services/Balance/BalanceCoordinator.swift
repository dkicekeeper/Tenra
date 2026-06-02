//
//  BalanceCoordinator.swift
//  Tenra
//
//  Created on 2026-02-02
//
//  SINGLE ENTRY POINT for all balance operations
//  Coordinates between Store and Engine
//  Provides unified API for balance management
//

import Foundation
import Observation
import os

// MARK: - Balance Coordinator

/// Main coordinator for balance management
/// Facade pattern - hides complexity of balance calculation system
/// All balance operations should go through this coordinator
@Observable
@MainActor
final class BalanceCoordinator: BalanceCoordinatorProtocol {

    // MARK: - Logger
    private static let logger = Logger(subsystem: "Tenra", category: "BalanceCoordinator")

    // MARK: - Observable State

    private(set) var balances: [String: Double] = [:]

    // MARK: - Dependencies

    @ObservationIgnored private let store: BalanceStore
    @ObservationIgnored private let engine: BalanceCalculationEngine
    @ObservationIgnored private let repository: DataRepositoryProtocol

    // MARK: - State

    @ObservationIgnored private var optimisticUpdates: [UUID: OptimisticUpdate] = [:]

    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol,
        cacheManager: TransactionCacheManager? = nil
    ) {
        self.repository = repository
        self.store = BalanceStore()
        self.engine = BalanceCalculationEngine(cacheManager: cacheManager)
    }

    /// The outstanding debt for a loan account — its balance derives from this single
    /// source (loanInfo.remainingPrincipal), not from summing payment transactions.
    /// Returns nil for non-loan accounts.
    private static func loanDebt(of account: Account) -> Double? {
        guard account.isLoan, let info = account.loanInfo else { return nil }
        return NSDecimalNumber(decimal: info.remainingPrincipal).doubleValue
    }

    // MARK: - Account Management

    /// Register accounts and compute initial balances using persisted `account.balance`.
    ///
    /// `account.balance` in CoreData is updated synchronously by `persistIncremental(_:)` on
    /// every mutation, so it is always accurate between launches.
    func registerAccounts(_ accounts: [Account]) async {

        var accountBalancesByID: [String: AccountBalance] = [:]
        var phase1Balances: [String: Double] = [:]

        for account in accounts {
            let ab = AccountBalance(
                accountId: account.id,
                currentBalance: account.initialBalance ?? 0,
                initialBalance: account.initialBalance,
                depositInfo: account.depositInfo,
                currency: account.currency
            )
            accountBalancesByID[account.id] = ab
            // Loan accounts: balance IS the outstanding debt (remainingPrincipal), never the
            // persisted running balance. Other accounts use persisted `account.balance`,
            // kept accurate by persistIncremental() on every mutation.
            phase1Balances[account.id] = Self.loanDebt(of: account) ?? account.balance
        }

        store.registerAccounts(Array(accountBalancesByID.values))
        store.updateBalances(phase1Balances, source: .manual)

        // Publish immediately — UI shows balances with zero startup delay.
        // Merge into existing balances to preserve any already-loaded accounts.
        var merged = self.balances
        for (id, bal) in phase1Balances { merged[id] = bal }
        self.balances = merged
    }

    func removeAccount(_ accountId: String) async {
        store.removeAccount(accountId)
        var updated = self.balances
        updated.removeValue(forKey: accountId)
        self.balances = updated
    }

    // MARK: - Transaction Updates

    func updateForTransaction(
        _ transaction: Transaction,
        operation: TransactionUpdateOperation
    ) async {
        switch operation {
        case .add:
            await processAddTransaction(transaction)
        case .remove:
            await processRemoveTransaction(transaction)
        case .update(let old, let new):
            await processUpdateTransaction(old: old, new: new)
        }
    }

    func updateForTransactions(
        _ transactions: [Transaction],
        operation: TransactionUpdateOperation
    ) async {
        guard !transactions.isEmpty else { return }

        for transaction in transactions {
            switch operation {
            case .add:
                await processAddTransaction(transaction)
            case .remove:
                await processRemoveTransaction(transaction)
            case .update:
                // Update in batch doesn't make sense — each needs its own old transaction
                break
            }
        }
    }

    // MARK: - Account Updates

    func updateForAccount(
        _ account: Account,
        newBalance: Double
    ) async {
        store.setBalance(newBalance, for: account.id, source: .manual)
        var updated = self.balances
        updated[account.id] = newBalance
        self.balances = updated
        persistBalance(newBalance, for: account.id)
    }

    func updateDepositInfo(
        _ account: Account,
        depositInfo: DepositInfo
    ) async {
        store.updateDepositInfo(depositInfo, for: account.id)
    }

    // MARK: - Recalculation

    func recalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        await processRecalculateAll(accounts: accounts, transactions: transactions)
    }

    func recalculateAccounts(
        _ accountIds: Set<String>,
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        await processRecalculateAccounts(accountIds, accounts: accounts, transactions: transactions)
    }

    // MARK: - Optimistic Updates

    func optimisticUpdate(
        accountId: String,
        delta: Double
    ) async -> UUID {
        let operationId = UUID()

        guard let currentBalance = store.getBalance(for: accountId) else {
            return operationId
        }

        let newBalance = currentBalance + delta

        // Apply optimistic update immediately
        store.setBalance(newBalance, for: accountId, source: .manual)

        // Track for potential revert
        let update = OptimisticUpdate(
            id: operationId,
            accountId: accountId,
            previousBalance: currentBalance,
            delta: delta,
            timestamp: Date()
        )
        optimisticUpdates[operationId] = update

        return operationId
    }

    func revertOptimisticUpdate(_ operationId: UUID) async {
        guard let update = optimisticUpdates.removeValue(forKey: operationId) else {
            return
        }

        store.setBalance(update.previousBalance, for: update.accountId, source: .manual)
    }

    func setInitialBalance(_ balance: Double, for accountId: String) async {
        store.setInitialBalance(balance, for: accountId)
    }

    func persistInitialBalance(_ balance: Double, for accountId: String) async {
        store.setInitialBalance(balance, for: accountId)
        await repository.updateInitialBalancesSync([accountId: balance])
    }

    func getInitialBalance(for accountId: String) async -> Double? {
        return store.getInitialBalance(for: accountId)
    }

    // MARK: - Private Processing

    /// Accounts whose balance a transaction can move: its own account plus, for
    /// transfers and loan payments, the target account. Order-preserving, de-duplicated.
    private func affectedAccountIds(of tx: Transaction) -> [String] {
        var ids: [String] = []
        if let a = tx.accountId { ids.append(a) }
        if let t = tx.targetAccountId, t != tx.accountId { ids.append(t) }
        return ids
    }

    /// Process add transaction.
    /// Applies the unified `contribution` to every affected account leg (source,
    /// transfer target, AND loan target — the latter was previously skipped). The
    /// future-date and deposit-startDate gates live inside `contribution(policy:)`,
    /// so this path matches full recalculation by construction.
    private func processAddTransaction(_ transaction: Transaction) async {
        var updatedBalances = self.balances

        for accountId in affectedAccountIds(of: transaction) {
            guard let account = store.getAccount(accountId) else { continue }
            let delta = engine.contribution(of: transaction, to: account, policy: .currentBalance)
            guard delta != 0 else { continue }

            let newBalance = account.currentBalance + delta
            store.setBalance(newBalance, for: accountId, source: .transaction(transaction.id))
            updatedBalances[accountId] = newBalance
            persistBalance(newBalance, for: accountId)
        }

        self.balances = updatedBalances
    }

    /// Process remove transaction — the exact inverse of add (subtract the contribution).
    private func processRemoveTransaction(_ transaction: Transaction) async {
        var updatedBalances = self.balances

        for accountId in affectedAccountIds(of: transaction) {
            guard let account = store.getAccount(accountId) else { continue }
            let delta = engine.contribution(of: transaction, to: account, policy: .currentBalance)
            guard delta != 0 else { continue }

            let newBalance = account.currentBalance - delta
            store.setBalance(newBalance, for: accountId, source: .recalculation)
            updatedBalances[accountId] = newBalance
            persistBalance(newBalance, for: accountId)
        }

        self.balances = updatedBalances
    }

    /// Process update transaction: for every account either revision touches, apply
    /// `contribution(new) − contribution(old)`. Each `contribution` independently
    /// applies the future/deposit gates, so edits that cross the today boundary are
    /// handled correctly (a future→past edit applies without a phantom revert, and
    /// vice-versa) with no special-casing.
    private func processUpdateTransaction(old: Transaction, new: Transaction) async {
        var updatedBalances = self.balances

        var seen = Set<String>()
        let ids = (affectedAccountIds(of: old) + affectedAccountIds(of: new)).filter { seen.insert($0).inserted }

        for accountId in ids {
            guard let account = store.getAccount(accountId) else { continue }
            let delta = engine.contribution(of: new, to: account, policy: .currentBalance)
                      - engine.contribution(of: old, to: account, policy: .currentBalance)
            guard delta != 0 else { continue }

            let newBalance = account.currentBalance + delta
            store.setBalance(newBalance, for: accountId, source: .transaction(new.id))
            updatedBalances[accountId] = newBalance
            persistBalance(newBalance, for: accountId)
        }

        self.balances = updatedBalances
    }

    /// Process full recalculation for all accounts
    private func processRecalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async {

        var newBalances: [String: Double] = [:]

        for account in accounts {
            guard let accountBalance = store.getAccount(account.id) else {
                continue
            }

            // Loan accounts: balance is the outstanding debt, not a tx-derived sum.
            if let debt = Self.loanDebt(of: account) {
                newBalances[account.id] = debt
                continue
            }

            let calculatedBalance = engine.calculateBalance(
                account: accountBalance,
                transactions: transactions
            )

            newBalances[account.id] = calculatedBalance
        }

        store.updateBalances(newBalances, source: .recalculation)

        // Persist all balances to Core Data
        persistBalances(newBalances)

        // Publish balances to trigger UI updates
        self.balances = newBalances
    }

    /// Process recalculation for specific accounts
    private func processRecalculateAccounts(
        _ accountIds: Set<String>,
        accounts: [Account],
        transactions: [Transaction]
    ) async {
        var newBalances: [String: Double] = [:]

        // Build accounts dict ONCE before the loop — replaces O(K×N) `accounts.first(where:)`
        // scan per accountId with O(N + K) total. Critical when currency change or bulk
        // import triggers recalc on dozens of accounts at once.
        let accountById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        for accountId in accountIds {
            guard let account = accountById[accountId] else {
                continue
            }

            guard let accountBalance = store.getAccount(account.id) else {
                continue
            }

            // Loan accounts: balance is the outstanding debt, not a tx-derived sum.
            if let debt = Self.loanDebt(of: account) {
                newBalances[account.id] = debt
                continue
            }

            let calculatedBalance = engine.calculateBalance(
                account: accountBalance,
                transactions: transactions
            )

            newBalances[account.id] = calculatedBalance
        }

        store.updateBalances(newBalances, source: .recalculation)

        // Merge and publish balances to trigger UI updates
        var updatedBalances = self.balances
        for (accountId, balance) in newBalances {
            updatedBalances[accountId] = balance
        }
        self.balances = updatedBalances
    }

    // MARK: - Persistence

    /// Persist balance to Core Data after balance calculation.
    /// Goes through the `DataRepositoryProtocol` facade — the awaited
    /// `updateAccountBalancesSync` is now part of the protocol, so no downcast
    /// to `CoreDataRepository` is needed (M-10). On non-CoreData repositories
    /// (UserDefaults preview/fallback) this is a no-op by design.
    private func persistBalance(_ balance: Double, for accountId: String) {
        let repo = repository
        Task.detached(priority: .userInitiated) {
            await repo.updateAccountBalancesSync([accountId: balance])
        }
    }

    /// Persist multiple balances to Core Data after batch recalculation.
    private func persistBalances(_ balances: [String: Double]) {
        repository.updateAccountBalances(balances)
    }
}

// MARK: - Optimistic Update

/// Represents an optimistic balance update
private struct OptimisticUpdate {
    let id: UUID
    let accountId: String
    let previousBalance: Double
    let delta: Double
    let timestamp: Date
}
