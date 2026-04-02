//
//  ImportCacheManager.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Manages lookup caches for CSV import with LRU eviction
/// Prevents unbounded memory growth during large imports while maintaining O(1) lookups
/// Uses the project's LRUCache implementation for automatic eviction
@MainActor
class ImportCacheManager {
    // MARK: - LRU Caches

    /// Account name → Account ID cache with LRU eviction
    private var accountCache: LRUCache<String, String>

    /// Category name+type → Category ID cache with LRU eviction
    private var categoryCache: LRUCache<String, String>

    /// Subcategory name → Subcategory ID cache with LRU eviction
    private var subcategoryCache: LRUCache<String, String>

    /// Stored capacity for cache reinitialization
    private let cacheCapacity: Int

    // MARK: - Initialization

    /// Initializes cache manager with specified capacity
    /// - Parameter capacity: Maximum number of entries per cache (default: 1000)
    init(capacity: Int = 1000) {
        self.cacheCapacity = capacity
        self.accountCache = LRUCache(capacity: capacity)
        self.categoryCache = LRUCache(capacity: capacity)
        self.subcategoryCache = LRUCache(capacity: capacity)
    }

    // MARK: - Account Cache Operations

    /// Caches an account name to ID mapping
    /// - Parameters:
    ///   - name: Account name (will be normalized to lowercase)
    ///   - id: Account ID
    func cacheAccount(name: String, id: String) {
        let key = name.lowercased()
        accountCache.set(key, value: id)
    }

    /// Retrieves cached account ID by name
    /// - Parameter name: Account name (will be normalized to lowercase)
    /// - Returns: Account ID if cached, nil otherwise
    func getAccount(name: String) -> String? {
        let key = name.lowercased()
        return accountCache.get(key)
    }

    // MARK: - Category Cache Operations

    /// Caches a category name+type to ID mapping
    /// - Parameters:
    ///   - name: Category name (will be normalized to lowercase)
    ///   - type: Transaction type for category
    ///   - id: Category ID
    func cacheCategory(name: String, type: TransactionType, id: String) {
        let key = makeCategoryKey(name: name, type: type)
        categoryCache.set(key, value: id)
    }

    /// Retrieves cached category ID by name and type
    /// - Parameters:
    ///   - name: Category name (will be normalized to lowercase)
    ///   - type: Transaction type for category
    /// - Returns: Category ID if cached, nil otherwise
    func getCategory(name: String, type: TransactionType) -> String? {
        let key = makeCategoryKey(name: name, type: type)
        return categoryCache.get(key)
    }

    /// Creates a composite key for category cache (name + type)
    /// - Parameters:
    ///   - name: Category name
    ///   - type: Transaction type
    /// - Returns: Composite key string
    private func makeCategoryKey(name: String, type: TransactionType) -> String {
        "\(name.lowercased())_\(type.rawValue)"
    }

    // MARK: - Subcategory Cache Operations

    /// Caches a subcategory name to ID mapping
    /// - Parameters:
    ///   - name: Subcategory name (will be normalized to lowercase)
    ///   - id: Subcategory ID
    func cacheSubcategory(name: String, id: String) {
        let key = name.lowercased()
        subcategoryCache.set(key, value: id)
    }

    /// Retrieves cached subcategory ID by name
    /// - Parameter name: Subcategory name (will be normalized to lowercase)
    /// - Returns: Subcategory ID if cached, nil otherwise
    func getSubcategory(name: String) -> String? {
        let key = name.lowercased()
        return subcategoryCache.get(key)
    }

    // MARK: - Cache Management

    /// Clears all caches and reinitializes with same capacity
    func clear() {
        accountCache = LRUCache(capacity: cacheCapacity)
        categoryCache = LRUCache(capacity: cacheCapacity)
        subcategoryCache = LRUCache(capacity: cacheCapacity)
    }

    /// Returns cache statistics for debugging and monitoring
    var statistics: ImportCacheStatistics {
        ImportCacheStatistics(
            accountCacheSize: accountCache.count,
            categoryCacheSize: categoryCache.count,
            subcategoryCacheSize: subcategoryCache.count,
            capacity: cacheCapacity
        )
    }
}

// MARK: - Cache Statistics

/// Statistics about import cache usage for monitoring
struct ImportCacheStatistics {
    let accountCacheSize: Int
    let categoryCacheSize: Int
    let subcategoryCacheSize: Int
    let capacity: Int

    var totalCacheSize: Int {
        accountCacheSize + categoryCacheSize + subcategoryCacheSize
    }
}
