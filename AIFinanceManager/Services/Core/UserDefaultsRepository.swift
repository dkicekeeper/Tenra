//
//  UserDefaultsRepository.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  UserDefaults implementation of DataRepositoryProtocol

import Foundation

/// UserDefaults-based implementation of DataRepositoryProtocol
/// Handles all data persistence operations using UserDefaults
nonisolated final class UserDefaultsRepository: DataRepositoryProtocol {
    
    // MARK: - Storage Keys
    
    private let storageKeyTransactions = "allTransactions"
    private let storageKeyRules = "categoryRules"
    private let storageKeyAccounts = "accounts"
    private let storageKeyCustomCategories = "customCategories"
    private let storageKeyRecurringSeries = "recurringSeries"
    private let storageKeyRecurringOccurrences = "recurringOccurrences"
    private let storageKeySubcategories = "subcategories"
    private let storageKeyCategorySubcategoryLinks = "categorySubcategoryLinks"
    private let storageKeyTransactionSubcategoryLinks = "transactionSubcategoryLinks"
    
    // MARK: - UserDefaults
    
    private let userDefaults: UserDefaults
    
    // MARK: - Initialization
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Transactions
    
    func loadTransactions(dateRange: DateInterval? = nil) -> [Transaction] {
        guard let data = userDefaults.data(forKey: storageKeyTransactions),
              let decoded = try? JSONDecoder().decode([Transaction].self, from: data) else {
            return []
        }
        
        // Apply date range filter if provided
        guard let dateRange = dateRange else {
            return decoded
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return decoded.filter { transaction in
            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                return false
            }
            return transactionDate >= dateRange.start && transactionDate <= dateRange.end
        }
    }
    
    func saveTransactions(_ transactions: [Transaction]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(transactions) {
            userDefaults.set(encoded, forKey: storageKeyTransactions)
        }
    }

    func deleteTransactionImmediately(id: String) {
        // UserDefaults fallback: no immediate per-record delete; no-op.
        // Deletions are handled by the next full saveTransactions() call.
    }

    func insertTransaction(_ transaction: Transaction) {
        // UserDefaults fallback: no-op. Targeted insert only applies to CoreData.
    }

    func updateTransactionFields(_ transaction: Transaction) {
        // UserDefaults fallback: no-op. Targeted update only applies to CoreData.
    }

    func batchInsertTransactions(_ transactions: [Transaction]) {
        // UserDefaults fallback: no-op. NSBatchInsertRequest only applies to CoreData.
    }

    // MARK: - Accounts
    
    func loadAccounts() -> [Account] {
        guard let data = userDefaults.data(forKey: storageKeyAccounts),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveAccounts(_ accounts: [Account]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(accounts) {
            userDefaults.set(encoded, forKey: storageKeyAccounts)
        }
    }

    func updateAccountBalance(accountId: String, balance: Double) {
        // UserDefaults implementation: noop (balance stored in Account.initialBalance)
        // This method exists only for protocol conformance
    }

    func updateAccountBalances(_ balances: [String: Double]) {
        // UserDefaults implementation: noop
    }

    // MARK: - Categories
    
    func loadCategories() -> [CustomCategory] {
        guard let data = userDefaults.data(forKey: storageKeyCustomCategories),
              let decoded = try? JSONDecoder().decode([CustomCategory].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveCategories(_ categories: [CustomCategory]) {
        // ✅ FIX: Make synchronous to prevent data loss on app termination
        // UserDefaults writes are fast enough and need to complete immediately
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(categories) {
            userDefaults.set(encoded, forKey: storageKeyCustomCategories)

        }
    }
    
    // MARK: - Category Rules
    
    func loadCategoryRules() -> [CategoryRule] {
        guard let data = userDefaults.data(forKey: storageKeyRules),
              let decoded = try? JSONDecoder().decode([CategoryRule].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveCategoryRules(_ rules: [CategoryRule]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(rules) {
            userDefaults.set(encoded, forKey: storageKeyRules)
        }
    }
    
    // MARK: - Recurring Series
    
    func loadRecurringSeries() -> [RecurringSeries] {
        guard let data = userDefaults.data(forKey: storageKeyRecurringSeries),
              let decoded = try? JSONDecoder().decode([RecurringSeries].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveRecurringSeries(_ series: [RecurringSeries]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(series) {
            userDefaults.set(encoded, forKey: storageKeyRecurringSeries)
        }
    }
    
    // MARK: - Recurring Occurrences
    
    func loadRecurringOccurrences() -> [RecurringOccurrence] {
        guard let data = userDefaults.data(forKey: storageKeyRecurringOccurrences),
              let decoded = try? JSONDecoder().decode([RecurringOccurrence].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(occurrences) {
            userDefaults.set(encoded, forKey: storageKeyRecurringOccurrences)
        }
    }
    
    // MARK: - Subcategories
    
    func loadSubcategories() -> [Subcategory] {
        guard let data = userDefaults.data(forKey: storageKeySubcategories),
              let decoded = try? JSONDecoder().decode([Subcategory].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveSubcategories(_ subcategories: [Subcategory]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(subcategories) {
            userDefaults.set(encoded, forKey: storageKeySubcategories)
            userDefaults.synchronize() // Гарантируем немедленное сохранение
        }
    }
    
    // MARK: - Category-Subcategory Links
    
    func loadCategorySubcategoryLinks() -> [CategorySubcategoryLink] {
        guard let data = userDefaults.data(forKey: storageKeyCategorySubcategoryLinks),
              let decoded = try? JSONDecoder().decode([CategorySubcategoryLink].self, from: data) else {
            return []
        }
        return decoded
    }

    func saveCategorySubcategoryLinks(_ links: [CategorySubcategoryLink]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(links) {
            userDefaults.set(encoded, forKey: storageKeyCategorySubcategoryLinks)
            userDefaults.synchronize()
        }
    }
    
    // MARK: - Transaction-Subcategory Links
    
    func loadTransactionSubcategoryLinks() -> [TransactionSubcategoryLink] {
        guard let data = userDefaults.data(forKey: storageKeyTransactionSubcategoryLinks),
              let decoded = try? JSONDecoder().decode([TransactionSubcategoryLink].self, from: data) else {
            return []
        }
        return decoded
    }
    
    func saveTransactionSubcategoryLinks(_ links: [TransactionSubcategoryLink]) {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(links) {
            userDefaults.set(encoded, forKey: storageKeyTransactionSubcategoryLinks)
            userDefaults.synchronize() // Гарантируем немедленное сохранение
        }
    }
    
    // MARK: - Clear All Data
    
    /// Clears all stored data
    func clearAllData() {
        let keys = [
            storageKeyTransactions,
            storageKeyRules,
            storageKeyAccounts,
            storageKeyCustomCategories,
            storageKeyRecurringSeries,
            storageKeyRecurringOccurrences,
            storageKeySubcategories,
            storageKeyCategorySubcategoryLinks,
            storageKeyTransactionSubcategoryLinks
        ]
        
        for key in keys {
            userDefaults.removeObject(forKey: key)
        }
        
        userDefaults.synchronize()
    }
}
