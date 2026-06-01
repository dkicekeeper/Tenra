//
//  AccountRepository.swift
//  Tenra
//
//  Created on 2026
//
//  Account-specific data persistence operations

import Foundation
import CoreData
import os

/// Protocol for account repository operations
protocol AccountRepositoryProtocol: Sendable {
    nonisolated func loadAccounts() -> [Account]
    nonisolated func saveAccounts(_ accounts: [Account])
    nonisolated func saveAccountsSync(_ accounts: [Account]) throws
    nonisolated func updateAccountBalance(accountId: String, balance: Double)
    nonisolated func updateAccountBalances(_ balances: [String: Double])
    /// Synchronously (awaited) persist multiple balances — safe to call from async context.
    nonisolated func updateAccountBalancesSync(_ balances: [String: Double]) async
    nonisolated func loadAllAccountBalances() -> [String: Double]

    /// Pre-aggregated income/expense per account — warm-start snapshot for
    /// `TransactionStore.accountAggregatesByAccountId`. Persisted in CoreData
    /// via `AccountAggregateEntity` (Schema v9+).
    nonisolated func loadAccountAggregates() -> [String: AccountAggregates]
    nonisolated func saveAccountAggregates(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String])
    /// Synchronously (awaited) persist account aggregates — guaranteed to finish
    /// before returning. Used by the import/rebuild flush so the aggregate write
    /// is ordered after the raw-transaction save (M-14): a kill between the two
    /// would otherwise leave warm-start aggregates lagging the persisted tx.
    nonisolated func saveAccountAggregatesSync(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) async
}

/// CoreData implementation of AccountRepositoryProtocol
nonisolated final class AccountRepository: AccountRepositoryProtocol, @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "AccountRepository")
    private let stack: CoreDataStack
    private let saveCoordinator: CoreDataSaveCoordinator
    private let userDefaultsRepository: UserDefaultsRepository

    init(
        stack: CoreDataStack = .shared,
        saveCoordinator: CoreDataSaveCoordinator,
        userDefaultsRepository: UserDefaultsRepository = UserDefaultsRepository()
    ) {
        self.stack = stack
        self.saveCoordinator = saveCoordinator
        self.userDefaultsRepository = userDefaultsRepository
    }

    // MARK: - Load Operations

    func loadAccounts() -> [Account] {
        PerformanceProfiler.start("AccountRepository.loadAccounts")

        // Use background context — never fetch on the main thread.
        let bgContext = stack.newBackgroundContext()
        var accounts: [Account] = []
        var loadError: Error? = nil

        bgContext.performAndWait {
            let request = AccountEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            request.fetchBatchSize = 50

            do {
                let entities = try bgContext.fetch(request)
                accounts = entities.map { $0.toAccount() }
            } catch {
                loadError = error
            }
        }

        PerformanceProfiler.end("AccountRepository.loadAccounts")

        if loadError != nil {
            // Fallback to UserDefaults if Core Data fetch failed
            return userDefaultsRepository.loadAccounts()
        }
        return accounts
    }

    func loadAllAccountBalances() -> [String: Double] {
        let bgContext = stack.newBackgroundContext()
        var balances: [String: Double] = [:]
        bgContext.performAndWait {
            let request = NSFetchRequest<NSDictionary>(entityName: "AccountEntity")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id", "balance"]
            guard let dicts = try? bgContext.fetch(request) else { return }
            for dict in dicts {
                if let id = dict["id"] as? String,
                   let bal = dict["balance"] as? Double {
                    balances[id] = bal
                }
            }
        }
        return balances
    }

    // MARK: - Save Operations

    func saveAccounts(_ accounts: [Account]) {

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            PerformanceProfiler.start("AccountRepository.saveAccounts")

            do {
                try await self.saveCoordinator.performSave(operation: "saveAccounts") { context in
                    try self.saveAccountsInternal(accounts, context: context)
                }

                PerformanceProfiler.end("AccountRepository.saveAccounts")

            } catch {
                PerformanceProfiler.end("AccountRepository.saveAccounts")
            }
        }
    }

    func saveAccountsSync(_ accounts: [Account]) throws {
        let context = stack.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        try context.performAndWait {
            try saveAccountsInternal(accounts, context: context)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    // MARK: - Balance Update Operations

    func updateAccountBalance(accountId: String, balance: Double) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                try await self.saveCoordinator.performSave(operation: "updateAccountBalance") { context in
                    let fetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
                    fetchRequest.predicate = NSPredicate(format: "id == %@", accountId)
                    fetchRequest.fetchLimit = 1

                    if let account = try context.fetch(fetchRequest).first {
                        account.balance = balance

                    }
                }
            } catch {
                Self.logger.error("updateAccountBalance failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func updateAccountBalances(_ balances: [String: Double]) {
        guard !balances.isEmpty else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.updateAccountBalancesSync(balances)
        }
    }

    /// Awaited (non-fire-and-forget) version — guaranteed to finish before returning.
    func updateAccountBalancesSync(_ balances: [String: Double]) async {
        guard !balances.isEmpty else { return }

        // Use a unique operation name per call so concurrent saves for different account sets
        // don't get rejected by CoreDataSaveCoordinator's duplicate-operation guard.
        let operationId = "updateAccountBalancesSync_\(UUID().uuidString)"

        do {
            try await saveCoordinator.performSave(operation: operationId) { context in
                let accountIds = Array(balances.keys)
                let fetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
                fetchRequest.predicate = NSPredicate(format: "id IN %@", accountIds)

                let accounts = try context.fetch(fetchRequest)
                for account in accounts {
                    if let accountId = account.id, let newBalance = balances[accountId] {
                        account.balance = newBalance
                    }
                }
            }
        } catch {
            // Save failed — balance will be recalculated from transactions on next startup
            // for dynamic accounts; manual accounts may show stale balance until next update
        }
    }

    // MARK: - Private Helper Methods

    private nonisolated func saveAccountsInternal(_ accounts: [Account], context: NSManagedObjectContext) throws {
        // Caller is already inside context.perform/performAndWait — direct access is safe.
        let fetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
        let existingEntities = try context.fetch(fetchRequest)

        var existingDict: [String: AccountEntity] = [:]
        for entity in existingEntities {
            let entityId = entity.id ?? ""
            if !entityId.isEmpty && existingDict[entityId] == nil {
                existingDict[entityId] = entity
            } else if !entityId.isEmpty {
                Self.logger.warning("⚠️ saveAccountsInternal: deleting DUPLICATE entity id=\(entityId, privacy: .public) balance=\(entity.balance)")
                context.delete(entity)
            } else {
                Self.logger.warning("⚠️ saveAccountsInternal: fetched entity with EMPTY id (balance=\(entity.balance)) — not added to dict")
            }
        }

        var keptIds = Set<String>()

        for account in accounts {
            keptIds.insert(account.id)

            if let existing = existingDict[account.id] {
                // Direct mutation — caller is already inside perform/performAndWait
                existing.name = account.name
                // ⚠️ CRITICAL: Don't overwrite `balance` here — it's managed by BalanceCoordinator
                // ⚠️ CRITICAL: Don't overwrite `initialBalance` — it's set once at creation and never changes
                existing.currency = account.currency

                if let iconSource = account.iconSource,
                   let encoded = try? JSONEncoder().encode(iconSource) {
                    existing.iconSourceData = encoded
                } else {
                    existing.iconSourceData = nil
                }

                existing.logo = nil

                existing.isDeposit = account.isDeposit
                existing.isLoan = account.isLoan
                existing.bankName = account.depositInfo?.bankName ?? account.loanInfo?.bankName
                existing.shouldCalculateFromTransactions = account.shouldCalculateFromTransactions
                existing.includeInBalance = account.includeInBalance

                if let depositInfo = account.depositInfo,
                   let encoded = try? JSONEncoder().encode(depositInfo) {
                    existing.depositInfoData = encoded
                } else {
                    existing.depositInfoData = nil
                }

                if let loanInfo = account.loanInfo,
                   let encoded = try? JSONEncoder().encode(loanInfo) {
                    existing.loanInfoData = encoded
                } else {
                    existing.loanInfoData = nil
                }
            } else {
                // New entity. AccountEntity.from now preserves account.balance, so a
                // create-miss for an existing account no longer zeroes its running balance.
                _ = AccountEntity.from(account, context: context)
            }
        }

        for entity in existingEntities {
            if let id = entity.id, !keptIds.contains(id) {
                Self.logger.log("🔍 saveAccountsInternal: deleting entity id=\(id, privacy: .public) balance=\(entity.balance) (not in keptIds)")
                context.delete(entity)
            }
        }
    }

    // MARK: - Account Aggregates (Schema v9+)

    func loadAccountAggregates() -> [String: AccountAggregates] {
        let bg = stack.newBackgroundContext()
        var result: [String: AccountAggregates] = [:]
        bg.performAndWait {
            let request = AccountAggregateEntity.fetchRequest()
            if let entities = try? bg.fetch(request) {
                for entity in entities {
                    if let snap = entity.toSnapshot() {
                        result[snap.accountId] = snap.aggregate
                    }
                }
            }
        }
        return result
    }

    func saveAccountAggregates(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.saveAccountAggregatesSync(aggregates, currencyByAccountId: currencyByAccountId)
        }
    }

    /// Awaited (non-fire-and-forget) account-aggregate persist. Uses a unique
    /// operation name per call so it never collides with an in-flight debounced
    /// `saveAccountAggregates` (the duplicate-operation guard would otherwise
    /// reject it and silently skip the write). See M-14.
    func saveAccountAggregatesSync(_ aggregates: [String: AccountAggregates], currencyByAccountId: [String: String]) async {
        let operationId = "saveAccountAggregatesSync_\(UUID().uuidString)"
        do {
            try await self.saveCoordinator.performSave(operation: operationId) { context in
                try self.saveAccountAggregatesInternal(
                    aggregates,
                    currencyByAccountId: currencyByAccountId,
                    context: context
                )
            }
        } catch {
            Self.logger.error("saveAccountAggregatesSync failed: \(error.localizedDescription)")
        }
    }

    private nonisolated func saveAccountAggregatesInternal(
        _ aggregates: [String: AccountAggregates],
        currencyByAccountId: [String: String],
        context: NSManagedObjectContext
    ) throws {
        let request = AccountAggregateEntity.fetchRequest()
        let existing = try context.fetch(request)
        var byId: [String: AccountAggregateEntity] = [:]
        for entity in existing {
            if let id = entity.accountId { byId[id] = entity }
        }
        var kept = Set<String>()

        for (accountId, agg) in aggregates {
            kept.insert(accountId)
            let currency = currencyByAccountId[accountId] ?? "KZT"
            if let entity = byId[accountId] {
                entity.totalTransactions = Int32(agg.totalTransactions)
                entity.totalIncome = agg.totalIncome
                entity.totalExpense = agg.totalExpense
                entity.currency = currency
                entity.lastUpdated = Date()
            } else {
                _ = AccountAggregateEntity.from(
                    accountId: accountId,
                    aggregate: agg,
                    currency: currency,
                    context: context
                )
            }
        }

        // Drop entries for accounts that no longer have aggregates (e.g. deleted account).
        for entity in existing {
            if let id = entity.accountId, !kept.contains(id) {
                context.delete(entity)
            }
        }
    }
}
