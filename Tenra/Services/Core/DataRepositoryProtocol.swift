//
//  DataRepositoryProtocol.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Protocol defining data persistence operations for all entities

import Foundation

/// Protocol for data repository operations
/// Provides abstraction layer for data persistence
/// Sendable conformance allows capturing `any DataRepositoryProtocol` in Task.detached
/// (all concrete implementations use CoreDataStack which is @unchecked Sendable).
/// All methods are nonisolated so they can be called from Task.detached and other
/// nonisolated contexts without MainActor hop warnings.
protocol DataRepositoryProtocol: Sendable {
    // MARK: - Transactions

    /// Load transactions with optional date range filter
    /// - Parameter dateRange: Optional date range to filter transactions. If nil, loads all transactions
    /// - Returns: Array of transactions matching the filter
    nonisolated func loadTransactions(dateRange: DateInterval?) -> [Transaction]

    nonisolated func saveTransactions(_ transactions: [Transaction])
    nonisolated func deleteTransactionImmediately(id: String)

    /// Insert a single new transaction into CoreData. O(1) — does NOT fetch existing records.
    /// Use for .added events in TransactionStore.apply(). Prerequisite: transaction.id must be non-empty.
    nonisolated func insertTransaction(_ transaction: Transaction)

    /// Update fields of a single existing transaction by ID. O(1) — fetches by PK only.
    /// Use for .updated events in TransactionStore.apply().
    nonisolated func updateTransactionFields(_ transaction: Transaction)

    /// Batch-insert multiple new transactions using NSBatchInsertRequest. O(N) but fast.
    /// Bypasses NSManagedObject lifecycle — ideal for CSV import of 1k+ records.
    /// Note: Does NOT set CoreData relationships (account/recurringSeries).
    /// accountId/targetAccountId String columns are used as fallbacks by toTransaction().
    nonisolated func batchInsertTransactions(_ transactions: [Transaction])

    // MARK: - Accounts
    nonisolated func loadAccounts() -> [Account]
    nonisolated func saveAccounts(_ accounts: [Account])
    nonisolated func updateAccountBalance(accountId: String, balance: Double)
    nonisolated func updateAccountBalances(_ balances: [String: Double])

    // MARK: - Categories
    nonisolated func loadCategories() -> [CustomCategory]
    nonisolated func saveCategories(_ categories: [CustomCategory])

    // MARK: - Category Rules
    nonisolated func loadCategoryRules() -> [CategoryRule]
    nonisolated func saveCategoryRules(_ rules: [CategoryRule])

    // MARK: - Recurring Series
    nonisolated func loadRecurringSeries() -> [RecurringSeries]
    nonisolated func saveRecurringSeries(_ series: [RecurringSeries])

    // MARK: - Recurring Occurrences
    nonisolated func loadRecurringOccurrences() -> [RecurringOccurrence]
    nonisolated func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence])

    // MARK: - Subcategories
    nonisolated func loadSubcategories() -> [Subcategory]
    nonisolated func saveSubcategories(_ subcategories: [Subcategory])

    // MARK: - Category-Subcategory Links
    nonisolated func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink]
    nonisolated func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink])

    // MARK: - Transaction-Subcategory Links
    nonisolated func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink]
    nonisolated func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink])

    // MARK: - Clear All Data
    nonisolated func clearAllData()
}
