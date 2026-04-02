//
//  TransactionStore+AccountCRUD.swift
//  AIFinanceManager
//
//  Account CRUD operations extracted from TransactionStore.
//  Phase C: File split for maintainability.
//

import Foundation

// MARK: - Account CRUD Operations (Phase 3)

extension TransactionStore {

    /// Add a new account
    /// Phase 3: TransactionStore is now Single Source of Truth for accounts
    func addAccount(_ account: Account) {
        // Check if account already exists
        if accounts.contains(where: { $0.id == account.id }) {
            return
        }

        accounts.append(account)

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccountsToRepository()

            // ✅ Save order to UserDefaults (UI preference)
            if let order = account.order {
                AccountOrderManager.shared.setOrder(order, for: account.id)
            }

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
            // @Observable automatically notifies SwiftUI when accounts array changes
        }

    }

    /// Update an existing account
    /// Phase 3: TransactionStore is now Single Source of Truth for accounts
    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        accounts[index] = account

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccountsToRepository()

            // ✅ Save order to UserDefaults (UI preference, separate from repository)
            if let order = account.order {
                AccountOrderManager.shared.setOrder(order, for: account.id)
            }

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
        }

    }

    /// Delete an account
    /// Phase 3: TransactionStore is now Single Source of Truth for accounts
    func deleteAccount(_ accountId: String) {
        accounts.removeAll { $0.id == accountId }

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccountsToRepository()

            // ✅ Remove order from UserDefaults
            AccountOrderManager.shared.removeOrder(for: accountId)

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
        }

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

        persistAccountsToRepository()
        AccountOrderManager.shared.setOrders(orderMap)
    }

    // MARK: - Account Persistence

    /// Persist accounts to repository
    /// Phase 3: TransactionStore now manages account persistence
    internal func persistAccountsToRepository() {
        repository.saveAccounts(accounts)
    }
}
