//
//  TransactionStore+AccountCRUD.swift
//  Tenra
//
//  Account CRUD operations extracted from TransactionStore.
//

import Foundation
import os

// 🔍 DIAG [balance-zero-bug]
private let accountCRUDLogger = Logger(subsystem: "Tenra", category: "AccountCRUD")

// MARK: - Account CRUD Operations

extension TransactionStore {

    /// Add a new account
    func addAccount(_ account: Account) {
        // Check if account already exists — O(1) via accountById
        if accountById[account.id] != nil {
            return
        }

        accounts.append(account)
        rebuildAccountById()

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccountsToRepository()

            // ✅ Save order to UserDefaults (UI preference)
            if let order = account.order {
                AccountOrderManager.shared.setOrder(order, for: account.id)
            }

        }

    }

    /// Update an existing account
    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        accounts[index] = account
        rebuildAccountById()

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccountsToRepository()

            // ✅ Save order to UserDefaults (UI preference, separate from repository)
            if let order = account.order {
                AccountOrderManager.shared.setOrder(order, for: account.id)
            }

        }

    }

    /// Delete an account
    func deleteAccount(_ accountId: String) {
        accounts.removeAll { $0.id == accountId }
        rebuildAccountById()

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccountsToRepository()

            // ✅ Remove order from UserDefaults
            AccountOrderManager.shared.removeOrder(for: accountId)

        }

    }

    /// Delete multiple accounts — single persist at the end
    func deleteAccounts(_ ids: Set<String>) {
        // 🔍 DIAG [balance-zero-bug]: snapshot of remaining accounts + their in-memory balance
        // right before persistence. If any remaining account shows `balance=0` here, the stale
        // in-memory Account struct is the culprit; if balances look right, the corruption is
        // happening in CoreData later.
        accountCRUDLogger.log("🗑️ deleteAccounts START: removing \(ids.count) ids=\(Array(ids), privacy: .public) totalAccountsBefore=\(self.accounts.count)")
        accounts.removeAll { ids.contains($0.id) }
        rebuildAccountById()
        for a in accounts {
            accountCRUDLogger.log("🗑️ deleteAccounts remaining: id=\(a.id, privacy: .public) name=\(a.name, privacy: .public) balance=\(a.balance) initial=\(a.initialBalance ?? -1) shouldCalc=\(a.shouldCalculateFromTransactions)")
        }

        if !isImporting {
            persistAccountsToRepository()

            for id in ids {
                AccountOrderManager.shared.removeOrder(for: id)
            }
        }
        accountCRUDLogger.log("🗑️ deleteAccounts END — saveAccounts dispatched")
    }

    /// Deletes all transactions associated with an account (where accountId or targetAccountId matches).
    /// Call this before deleteAccount when you want to remove an account with all its transactions.
    /// Each deletion goes through apply(.deleted) so aggregates, cache, and persistence are all updated.
    func deleteTransactions(forAccountId accountId: String) async {
        let toDelete = transactions.filter {
            $0.accountId == accountId || $0.targetAccountId == accountId
        }
        for transaction in toDelete {
            let event = TransactionEvent.deleted(transaction)
            try? await apply(event)
        }
    }

    /// Deletes all transactions matching the given category name and type.
    /// Call this before deleteCategory when you want to remove a category with all its transactions.
    /// Each deletion goes through apply(.deleted) so aggregates, cache, and persistence are all updated.
    func deleteTransactions(forCategoryName categoryName: String, type: TransactionType) async {
        let toDelete = transactions.filter {
            $0.category == categoryName && $0.type == type
        }
        for transaction in toDelete {
            let event = TransactionEvent.deleted(transaction)
            try? await apply(event)
        }
    }

    // MARK: - Account Reordering

    /// Update display order for accounts without triggering balance recalculation.
    /// Only mutates `order` field — balances, names, and all other fields are preserved.
    func reorderAccounts(_ orderedIds: [String]) {
        var orderMap = [String: Int]()
        for (index, id) in orderedIds.enumerated() {
            orderMap[id] = index
            if let accountIndex = accounts.firstIndex(where: { $0.id == id }) {
                accounts[accountIndex].order = index
            }
        }
        rebuildAccountById()

        persistAccountsToRepository()
        AccountOrderManager.shared.setOrders(orderMap)
    }

    // MARK: - Account Persistence

    /// Persist accounts to repository
    internal func persistAccountsToRepository() {
        repository.saveAccounts(accounts)
    }
}
