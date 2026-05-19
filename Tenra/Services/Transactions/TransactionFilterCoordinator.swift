//
//  TransactionFilterCoordinator.swift
//  Tenra
//
//  Created on 2026-02-01
//

import Foundation

/// Coordinator for all transaction filtering operations
/// Centralizes filtering logic extracted from TransactionsViewModel
/// Combines TransactionFilterService and custom filtering from ViewModel
@MainActor
class TransactionFilterCoordinator: TransactionFilterCoordinatorProtocol {

    // MARK: - Dependencies

    private let filterService: TransactionFilterService
    private let dateFormatter: DateFormatter

    // MARK: - Initialization

    init(filterService: TransactionFilterService, dateFormatter: DateFormatter) {
        self.filterService = filterService
        self.dateFormatter = dateFormatter
    }

    // MARK: - TransactionFilterCoordinatorProtocol Implementation

    func getFiltered(
        transactions: [Transaction],
        selectedCategories: Set<String>?,
        recurringSeries: [RecurringSeries]
    ) -> [Transaction] {
        var filtered = transactions

        // Apply category filter if present
        if let selectedCategories = selectedCategories {
            filtered = filterService.filterByCategories(filtered, categories: selectedCategories)
        }

        // Filter recurring transactions (show only nearest for each series)
        return filterRecurringTransactions(filtered, series: recurringSeries)
    }

    func filterByTime(
        transactions: [Transaction],
        timeFilter: TimeFilter
    ) -> [Transaction] {
        let range = timeFilter.dateRange()
        return filterService.filterByTimeRange(transactions, start: range.start, end: range.end)
    }

    func filterByTimeAndCategory(
        transactions: [Transaction],
        timeFilter: TimeFilter,
        categories: Set<String>?,
        series: [RecurringSeries]
    ) -> [Transaction] {
        let range = timeFilter.dateRange()
        return filterService.filterByTimeAndCategory(
            transactions,
            series: series,
            start: range.start,
            end: range.end,
            categories: categories
        )
    }

    func filterForHistory(
        transactions: [Transaction],
        accountId: String?,
        searchText: String,
        accounts: [Account],
        baseCurrency: String,
        getSubcategories: (String) -> [Subcategory]
    ) -> [Transaction] {
        var filtered = transactions

        // Filter by account if specified
        if let accountId = accountId {
            filtered = filterService.filterByAccount(filtered, accountId: accountId)
        }

        // Filter by search text if provided
        if !searchText.isEmpty {
            filtered = filterBySearchText(
                filtered,
                searchText: searchText,
                accounts: accounts,
                baseCurrency: baseCurrency,
                getSubcategories: getSubcategories
            )
        }

        return filtered
    }

    // MARK: - Private Helpers

    /// Filter recurring transactions to show only the nearest transaction for each active series.
    /// Extracted from TransactionsViewModel.filterRecurringTransactions.
    ///
    /// Parses each tx date exactly once into a local `dateCache` instead of the
    /// previous 3-4 `DateFormatter.date(from:)` calls per recurring tx (once in
    /// the compactMap, twice per comparison in the final sort).
    private func filterRecurringTransactions(
        _ transactions: [Transaction],
        series: [RecurringSeries]
    ) -> [Transaction] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var result: [Transaction] = []
        var recurringSeriesShown: Set<String> = []
        var regularTransactions: [Transaction] = []
        var recurringTransactionsBySeries: [String: [Transaction]] = [:]

        // Separate recurring from regular transactions.
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }

        result.append(contentsOf: regularTransactions)

        // Pre-parse dates for everything we might touch — recurring buckets are
        // visited here AND in the final sort. Build the cache once, share it.
        var dateCache: [String: Date] = [:]
        dateCache.reserveCapacity(transactions.count)
        @inline(__always) func cachedDate(for tx: Transaction) -> Date? {
            if let cached = dateCache[tx.id] { return cached }
            guard let parsed = dateFormatter.date(from: tx.date) else { return nil }
            dateCache[tx.id] = parsed
            return parsed
        }

        // For each active recurring series, find the next upcoming transaction.
        for activeSeries in series where activeSeries.isActive {
            if recurringSeriesShown.contains(activeSeries.id) { continue }
            guard let seriesTransactions = recurringTransactionsBySeries[activeSeries.id] else { continue }

            let nextTransaction = seriesTransactions
                .compactMap { tx -> (Transaction, Date)? in
                    guard let date = cachedDate(for: tx) else { return nil }
                    return (tx, date)
                }
                .filter { $0.1 >= today }
                .min(by: { $0.1 < $1.1 })
                .map { $0.0 }

            if let nextTransaction {
                result.append(nextTransaction)
                recurringSeriesShown.insert(activeSeries.id)
            }
        }

        // Sort by date descending — comparator reads the cache, O(1) per access.
        return result.sorted { tx1, tx2 in
            guard let d1 = cachedDate(for: tx1),
                  let d2 = cachedDate(for: tx2) else {
                return false
            }
            return d1 > d2
        }
    }

    /// Advanced search filtering across multiple fields
    /// Extracted from TransactionsViewModel.filterTransactionsForHistory
    private func filterBySearchText(
        _ transactions: [Transaction],
        searchText: String,
        accounts: [Account],
        baseCurrency: String,
        getSubcategories: (String) -> [Subcategory]
    ) -> [Transaction] {
        let searchLower = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let searchNumber = Double(searchText.replacingOccurrences(of: ",", with: "."))

        // Create accounts lookup dictionary for O(1) access
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        return transactions.filter { transaction in
            // Search in category
            if transaction.category.lowercased().contains(searchLower) {
                return true
            }

            // Search in subcategories
            let linkedSubcategories = getSubcategories(transaction.id)
            if linkedSubcategories.contains(where: { $0.name.lowercased().contains(searchLower) }) {
                return true
            }

            // Search in description
            if transaction.description.lowercased().contains(searchLower) {
                return true
            }

            // Search in account name
            if let accountId = transaction.accountId,
               let account = accountsById[accountId],
               account.name.lowercased().contains(searchLower) {
                return true
            }

            // Search in target account name (for transfers)
            if let targetAccountId = transaction.targetAccountId,
               let targetAccount = accountsById[targetAccountId],
               targetAccount.name.lowercased().contains(searchLower) {
                return true
            }

            // Search by exact amount (as string)
            let amountString = String(format: "%.2f", transaction.amount)
            if amountString.contains(searchText) || amountString.lowercased().contains(searchLower) {
                return true
            }

            // Search by numeric amount
            if let searchNum = searchNumber, abs(transaction.amount - searchNum) < 0.01 {
                return true
            }

            // Search in formatted currency amount
            let formattedAmount = Formatting.formatCurrency(transaction.amount, currency: baseCurrency).lowercased()
            if formattedAmount.contains(searchLower) {
                return true
            }

            return false
        }
    }
}
