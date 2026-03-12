//
//  TransactionIndexManager.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

/// Manages indexes for fast transaction filtering
/// Provides O(1) lookups instead of O(n) linear searches
nonisolated class TransactionIndexManager {
    // MARK: - Indexes

    /// Index by account ID: accountId -> Set of transaction IDs
    private var byAccount: [String: Set<String>] = [:]

    /// Index by category: category -> Set of transaction IDs
    private var byCategory: [String: Set<String>] = [:]

    /// Index by type: TransactionType -> Set of transaction IDs
    private var byType: [TransactionType: Set<String>] = [:]

    /// All transactions by ID: transactionId -> Transaction
    private var allTransactions: [String: Transaction] = [:]

    /// Whether indexes are currently valid
    private var isValid = false

    // MARK: - Public Methods

    /// Build indexes from transactions
    /// - Parameter transactions: Array of transactions to index
    func buildIndexes(transactions: [Transaction]) {
        PerformanceProfiler.start("buildIndexes")

        // Clear existing indexes
        byAccount.removeAll(keepingCapacity: true)
        byCategory.removeAll(keepingCapacity: true)
        byType.removeAll(keepingCapacity: true)
        allTransactions.removeAll(keepingCapacity: true)

        // Build indexes
        for tx in transactions {
            allTransactions[tx.id] = tx

            // Index by account (both source and target)
            if let accountId = tx.accountId {
                byAccount[accountId, default: []].insert(tx.id)
            }
            if let targetAccountId = tx.targetAccountId {
                byAccount[targetAccountId, default: []].insert(tx.id)
            }

            // Index by category
            if !tx.category.isEmpty {
                byCategory[tx.category, default: []].insert(tx.id)
            }

            // Index by type
            byType[tx.type, default: []].insert(tx.id)
        }

        isValid = true
        PerformanceProfiler.end("buildIndexes")
    }

    /// Invalidate indexes (call when transactions change)
    func invalidate() {
        isValid = false
    }

    /// Check if indexes are valid
    var isIndexValid: Bool {
        isValid
    }

    // MARK: - Filtering Methods

    /// Filter transactions by criteria
    /// - Parameters:
    ///   - accountId: Optional account ID filter
    ///   - category: Optional category filter
    ///   - type: Optional transaction type filter
    /// - Returns: Array of filtered transactions
    func filter(accountId: String? = nil, category: String? = nil, type: TransactionType? = nil) -> [Transaction] {
        guard isValid else {
            return []
        }

        var resultIds: Set<String>?

        // Filter by account
        if let accountId = accountId {
            resultIds = byAccount[accountId]
        }

        // Filter by category (intersection if account filter exists)
        if let category = category {
            let categoryIds = byCategory[category] ?? []
            if let existing = resultIds {
                resultIds = existing.intersection(categoryIds)
            } else {
                resultIds = categoryIds
            }
        }

        // Filter by type (intersection if other filters exist)
        if let type = type {
            let typeIds = byType[type] ?? []
            if let existing = resultIds {
                resultIds = existing.intersection(typeIds)
            } else {
                resultIds = typeIds
            }
        }

        // If no filters specified, return all transactions
        guard let ids = resultIds else {
            return Array(allTransactions.values)
        }

        // Convert IDs to transactions
        return ids.compactMap { allTransactions[$0] }
    }

    /// Get transactions for specific account (fast O(1) lookup)
    /// - Parameter accountId: Account ID
    /// - Returns: Array of transactions for the account
    func transactionsForAccount(_ accountId: String) -> [Transaction] {
        guard isValid else {
            return []
        }

        guard let ids = byAccount[accountId] else {
            return []
        }

        return ids.compactMap { allTransactions[$0] }
    }

    /// Get transactions for specific category (fast O(1) lookup)
    /// - Parameter category: Category name
    /// - Returns: Array of transactions in the category
    func transactionsForCategory(_ category: String) -> [Transaction] {
        guard isValid else {
            return []
        }

        guard let ids = byCategory[category] else {
            return []
        }

        return ids.compactMap { allTransactions[$0] }
    }

    /// Get transactions for specific type (fast O(1) lookup)
    /// - Parameter type: Transaction type
    /// - Returns: Array of transactions of that type
    func transactionsForType(_ type: TransactionType) -> [Transaction] {
        guard isValid else {
            return []
        }

        guard let ids = byType[type] else {
            return []
        }

        return ids.compactMap { allTransactions[$0] }
    }

    /// Get count of transactions for account (fast O(1) lookup)
    /// - Parameter accountId: Account ID
    /// - Returns: Number of transactions
    func countForAccount(_ accountId: String) -> Int {
        byAccount[accountId]?.count ?? 0
    }

    /// Get count of transactions for category (fast O(1) lookup)
    /// - Parameter category: Category name
    /// - Returns: Number of transactions
    func countForCategory(_ category: String) -> Int {
        byCategory[category]?.count ?? 0
    }

    /// Get all indexed accounts
    var indexedAccounts: [String] {
        Array(byAccount.keys)
    }

    /// Get all indexed categories
    var indexedCategories: [String] {
        Array(byCategory.keys)
    }
}
