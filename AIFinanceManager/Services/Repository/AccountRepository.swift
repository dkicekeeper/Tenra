//
//  AccountRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Account-specific data persistence operations

import Foundation
import CoreData

/// Protocol for account repository operations
protocol AccountRepositoryProtocol {
    func loadAccounts() -> [Account]
    func saveAccounts(_ accounts: [Account])
    func saveAccountsSync(_ accounts: [Account]) throws
    func updateAccountBalance(accountId: String, balance: Double)
    func updateAccountBalances(_ balances: [String: Double])
    /// Synchronously (awaited) persist multiple balances — safe to call from async context.
    func updateAccountBalancesSync(_ balances: [String: Double]) async
    func loadAllAccountBalances() -> [String: Double]
}

/// CoreData implementation of AccountRepositoryProtocol
final class AccountRepository: AccountRepositoryProtocol {

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

        // PERFORMANCE Phase 28-B: Use background context — never fetch on the main thread.
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
        let context = stack.viewContext
        try saveAccountsInternal(accounts, context: context)

        // Save if there are changes
        if context.hasChanges {
            try context.save()
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
        // Fetch all existing accounts
        let fetchRequest = NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
        let existingEntities = try context.fetch(fetchRequest)

        // Build dictionary safely, handling duplicates by keeping the first occurrence
        var existingDict: [String: AccountEntity] = [:]
        for entity in existingEntities {
            // Extract id safely outside perform block
            var entityId: String = ""
            context.performAndWait {
                entityId = entity.id ?? ""
            }
            if !entityId.isEmpty && existingDict[entityId] == nil {
                existingDict[entityId] = entity
            } else if !entityId.isEmpty {
                // Found duplicate - delete the extra entity
                context.delete(entity)
            }
        }

        var keptIds = Set<String>()

        // Update or create accounts
        for account in accounts {
            keptIds.insert(account.id)

            if let existing = existingDict[account.id] {
                // Update existing - MUST use performAndWait for synchronous execution
                context.performAndWait {
                    existing.name = account.name
                    // ⚠️ CRITICAL: Don't overwrite `balance` here — it's managed by BalanceCoordinator
                    // ⚠️ CRITICAL: Don't overwrite `initialBalance` — it's set once at creation and never changes
                    existing.currency = account.currency

                    // Save full iconSource as JSON data (new approach)
                    if let iconSource = account.iconSource,
                       let encoded = try? JSONEncoder().encode(iconSource) {
                        existing.iconSourceData = encoded
                    } else {
                        existing.iconSourceData = nil
                    }

                    // Keep logo field for backward compatibility
                    if case .bankLogo(let bankLogo) = account.iconSource {
                        existing.logo = bankLogo.rawValue
                    } else {
                        existing.logo = BankLogo.none.rawValue
                    }

                    existing.isDeposit = account.isDeposit
                    existing.bankName = account.depositInfo?.bankName
                    existing.shouldCalculateFromTransactions = account.shouldCalculateFromTransactions

                    // Encode full DepositInfo as JSON (v5+)
                    if let depositInfo = account.depositInfo,
                       let encoded = try? JSONEncoder().encode(depositInfo) {
                        existing.depositInfoData = encoded
                    } else {
                        existing.depositInfoData = nil
                    }
                }
            } else {
                // Create new
                _ = AccountEntity.from(account, context: context)
            }
        }

        // Delete accounts that no longer exist
        for entity in existingEntities {
            var entityId: String?
            context.performAndWait {
                entityId = entity.id
            }
            if let id = entityId, !keptIds.contains(id) {
                context.delete(entity)
            }
        }
    }
}
