//
//  TransactionFilterCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Protocol for coordinating all transaction filtering operations
/// Centralizes filtering logic that was scattered across TransactionsViewModel
@MainActor
protocol TransactionFilterCoordinatorProtocol {

    /// Get filtered transactions based on selected categories and recurring series
    /// - Parameters:
    ///   - transactions: All transactions to filter
    ///   - selectedCategories: Optional set of category names to filter by
    ///   - recurringSeries: Active recurring series for filtering recurring transactions
    /// - Returns: Filtered array of transactions
    func getFiltered(
        transactions: [Transaction],
        selectedCategories: Set<String>?,
        recurringSeries: [RecurringSeries]
    ) -> [Transaction]

    /// Filter transactions by time range
    /// - Parameters:
    ///   - transactions: Transactions to filter
    ///   - timeFilter: Time filter to apply
    /// - Returns: Filtered transactions within time range
    func filterByTime(
        transactions: [Transaction],
        timeFilter: TimeFilter
    ) -> [Transaction]

    /// Filter transactions by time range and categories
    /// - Parameters:
    ///   - transactions: Transactions to filter
    ///   - timeFilter: Time filter to apply
    ///   - categories: Optional set of categories to filter by
    ///   - series: Recurring series for filtering recurring transactions
    /// - Returns: Filtered transactions
    func filterByTimeAndCategory(
        transactions: [Transaction],
        timeFilter: TimeFilter,
        categories: Set<String>?,
        series: [RecurringSeries]
    ) -> [Transaction]

    /// Filter transactions for History view with all filters applied
    /// - Parameters:
    ///   - transactions: Base transactions (already filtered by time and category)
    ///   - accountId: Optional account ID to filter by
    ///   - searchText: Search query
    ///   - accounts: All accounts for lookup
    ///   - baseCurrency: Base currency for formatting
    ///   - getSubcategories: Closure to get subcategories for a transaction
    /// - Returns: Filtered transactions for history display
    func filterForHistory(
        transactions: [Transaction],
        accountId: String?,
        searchText: String,
        accounts: [Account],
        baseCurrency: String,
        getSubcategories: (String) -> [Subcategory]
    ) -> [Transaction]
}
