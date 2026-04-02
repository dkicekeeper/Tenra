//
//  TransactionQueryServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Protocol for read-only transaction queries (summary, category expenses, etc.)
/// Extracted from TransactionsViewModel to follow SRP
@MainActor
protocol TransactionQueryServiceProtocol {

    /// Calculate summary (income, expenses, net flow) for filtered transactions
    /// - Parameters:
    ///   - transactions: Filtered transactions to summarize
    ///   - baseCurrency: Base currency for summary
    ///   - cacheManager: Cache manager for caching results
    ///   - currencyService: Currency service for conversions
    /// - Returns: Summary with totals
    func calculateSummary(
        transactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> Summary

    /// Get category expenses from aggregate cache or direct calculation
    /// - Parameters:
    ///   - timeFilter: Time filter to apply
    ///   - baseCurrency: Base currency for expenses
    ///   - validCategoryNames: Optional set of valid category names (for filtering deleted categories)
    ///   - aggregateCache: Aggregate cache to query
    ///   - cacheManager: Cache manager for caching results
    ///   - transactions: Optional transactions for direct calculation (date-based filters)
    ///   - currencyService: Optional currency service for conversions (date-based filters)
    /// - Returns: Dictionary of category expenses
    func getCategoryExpenses(
        timeFilter: TimeFilter,
        baseCurrency: String,
        validCategoryNames: Set<String>?,
        cacheManager: TransactionCacheManager,
        transactions: [Transaction]?,
        currencyService: TransactionCurrencyService?
    ) -> [String: CategoryExpense]

    /// Get popular categories sorted by total expense
    /// - Parameter expenses: Category expenses dictionary
    /// - Returns: Sorted array of category names
    func getPopularCategories(
        expenses: [String: CategoryExpense]
    ) -> [String]

    /// Get all unique categories from transactions
    /// - Parameters:
    ///   - transactions: All transactions
    ///   - cacheManager: Cache manager for caching results
    /// - Returns: Sorted array of unique category names
    func getUniqueCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String]

    /// Get expense categories
    /// - Parameters:
    ///   - transactions: All transactions
    ///   - cacheManager: Cache manager for caching results
    /// - Returns: Sorted array of expense category names
    func getExpenseCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String]

    /// Get income categories
    /// - Parameters:
    ///   - transactions: All transactions
    ///   - cacheManager: Cache manager for caching results
    /// - Returns: Sorted array of income category names
    func getIncomeCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String]
}
