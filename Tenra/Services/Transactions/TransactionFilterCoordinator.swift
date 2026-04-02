//
//  TransactionFilterCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
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

    /// Filter recurring transactions to show only the nearest transaction for each active series
    /// Extracted from TransactionsViewModel.filterRecurringTransactions
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

        // Separate recurring from regular transactions
        for transaction in transactions {
            if let seriesId = transaction.recurringSeriesId {
                recurringTransactionsBySeries[seriesId, default: []].append(transaction)
            } else {
                regularTransactions.append(transaction)
            }
        }

        result.append(contentsOf: regularTransactions)

        // For each active recurring series, find the next upcoming transaction
        for activeSeries in series where activeSeries.isActive {
            if recurringSeriesShown.contains(activeSeries.id) {
                continue
            }

            guard let seriesTransactions = recurringTransactionsBySeries[activeSeries.id] else {
                continue
            }

            // Find the nearest future transaction for this series
            let nextTransaction = seriesTransactions
                .compactMap { transaction -> (Transaction, Date)? in
                    guard let date = dateFormatter.date(from: transaction.date) else {
                        return nil
                    }
                    return (transaction, date)
                }
                .filter { $0.1 >= today }
                .min(by: { $0.1 < $1.1 })
                .map { $0.0 }

            if let nextTransaction = nextTransaction {
                result.append(nextTransaction)
                recurringSeriesShown.insert(activeSeries.id)
            }
        }

        // Sort by date descending
        return result.sorted { tx1, tx2 in
            guard let date1 = dateFormatter.date(from: tx1.date),
                  let date2 = dateFormatter.date(from: tx2.date) else {
                return false
            }
            return date1 > date2
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
