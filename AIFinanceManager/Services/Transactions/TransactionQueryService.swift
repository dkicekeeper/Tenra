//
//  TransactionQueryService.swift
//  AIFinanceManager
//
//  Created on 2026-02-01
//  Phase 2 Refactoring: Service Extraction
//

import Foundation

/// Service for read-only transaction queries
/// Extracted from TransactionsViewModel (lines 553-715) to follow SRP
@MainActor
class TransactionQueryService: TransactionQueryServiceProtocol {

    // MARK: - Dependencies

    // @MainActor isolation: all callers are @MainActor methods on this class.
    // Static let avoids repeated DateFormatters.dateFormatter lookups in tight loops.
    @MainActor private static let dateFormatter = DateFormatters.dateFormatter

    // MARK: - TransactionQueryServiceProtocol Implementation

    func calculateSummary(
        transactions: [Transaction],
        baseCurrency: String,
        cacheManager: TransactionCacheManager,
        currencyService: TransactionCurrencyService
    ) -> Summary {

        // Return cached summary if valid
        if !cacheManager.summaryCacheInvalidated, let cached = cacheManager.cachedSummary {
            return cached
        }

        PerformanceProfiler.start("TransactionQueryService.calculateSummary")

        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = Self.dateFormatter

        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0
        var plannedExpenses: Double = 0

        for transaction in transactions {
            // Use cached conversion if available
            let amountInBaseCurrency = currencyService.getConvertedAmountOrCompute(
                transaction: transaction,
                to: baseCurrency
            )

            guard let transactionDate = dateFormatter.date(from: transaction.date) else {
                continue
            }

            let isFutureDate = transactionDate > today

            if !isFutureDate {
                switch transaction.type {
                case .income:
                    totalIncome += amountInBaseCurrency
                case .expense:
                    totalExpenses += amountInBaseCurrency
                case .internalTransfer:
                    totalInternal += amountInBaseCurrency
                case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                    break
                case .loanPayment, .loanEarlyRepayment:
                    totalExpenses += amountInBaseCurrency
                }
            } else {
                // Calculate planned amount from future expense transactions
                if transaction.type == .expense || transaction.type == .loanPayment {
                    plannedExpenses += amountInBaseCurrency
                }
            }
        }

        let dates = transactions.map { $0.date }.sorted()

        let result = Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: baseCurrency,
            startDate: dates.first ?? "",
            endDate: dates.last ?? "",
            plannedAmount: plannedExpenses
        )


        cacheManager.cachedSummary = result
        cacheManager.summaryCacheInvalidated = false

        PerformanceProfiler.end("TransactionQueryService.calculateSummary")
        return result
    }

    func getCategoryExpenses(
        timeFilter: TimeFilter,
        baseCurrency: String,
        validCategoryNames: Set<String>?,
        cacheManager: TransactionCacheManager,
        transactions: [Transaction]? = nil,
        currencyService: TransactionCurrencyService? = nil
    ) -> [String: CategoryExpense] {

        // Check cache with time filter as key
        if let cached = cacheManager.getCachedCategoryExpenses(for: timeFilter) {
            return cached
        }

        // Phase 36: aggregateCache stub removed — always calculate from transactions directly
        guard let transactions = transactions, let currencyService = currencyService else {
            return [:]
        }

        let result = calculateCategoryExpensesFromTransactions(
            transactions: transactions,
            timeFilter: timeFilter,
            baseCurrency: baseCurrency,
            validCategoryNames: validCategoryNames,
            currencyService: currencyService
        )

        // Only cache non-empty results
        if !result.isEmpty {
            cacheManager.setCachedCategoryExpenses(result, for: timeFilter)
        }

        return result
    }

    /// Calculate category expenses directly from transactions (for date-based filters)
    private func calculateCategoryExpensesFromTransactions(
        transactions: [Transaction],
        timeFilter: TimeFilter,
        baseCurrency: String,
        validCategoryNames: Set<String>?,
        currencyService: TransactionCurrencyService
    ) -> [String: CategoryExpense] {

        let dateRange = timeFilter.dateRange()
        let dateFormatter = Self.dateFormatter
        var result: [String: CategoryExpense] = [:]

        let now = Date()

        for transaction in transactions {
            // Only expense transactions
            guard transaction.type == .expense else { continue }

            // Filter by date range
            guard let transactionDate = dateFormatter.date(from: transaction.date),
                  transactionDate >= dateRange.start && transactionDate < dateRange.end else {
                continue
            }

            // ✅ FIX 2026-02-08: Exclude future transactions from expense calculations
            // Future recurring transactions should not count as expenses until their date arrives
            guard transactionDate <= now else {
                continue
            }

            let category = transaction.category.isEmpty
                ? String(localized: "category.uncategorized")
                : transaction.category

            // Filter by valid category names if provided
            if let validNames = validCategoryNames, !validNames.contains(category) {
                continue
            }

            // Convert to base currency
            let amountInBaseCurrency = currencyService.getConvertedAmountOrCompute(
                transaction: transaction,
                to: baseCurrency
            )

            // Update category total
            if var existing = result[category] {
                existing.total += amountInBaseCurrency

                // Handle subcategory if present
                if let subcategory = transaction.subcategory {
                    existing.subcategories[subcategory, default: 0] += amountInBaseCurrency
                }

                result[category] = existing
            } else {
                // Create new entry
                var subcategories: [String: Double] = [:]
                if let subcategory = transaction.subcategory {
                    subcategories[subcategory] = amountInBaseCurrency
                }

                result[category] = CategoryExpense(
                    total: amountInBaseCurrency,
                    subcategories: subcategories
                )
            }
        }

        return result
    }

    func getPopularCategories(
        expenses: [String: CategoryExpense]
    ) -> [String] {
        return Array(expenses.keys)
            .sorted { expenses[$0]?.total ?? 0 > expenses[$1]?.total ?? 0 }
    }

    func getUniqueCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedUniqueCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in transactions {
            if let subcategory = transaction.subcategory {
                categories.insert("\(transaction.category):\(subcategory)")
            } else {
                categories.insert(transaction.category)
            }
        }

        let result = Array(categories).sorted()
        cacheManager.cachedUniqueCategories = result
        return result
    }

    func getExpenseCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedExpenseCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in transactions where transaction.type == .expense {
            let categoryName = transaction.category.isEmpty
                ? String(localized: "category.uncategorized")
                : transaction.category
            categories.insert(categoryName)
        }

        let result = Array(categories).sorted()
        cacheManager.cachedExpenseCategories = result
        return result
    }

    func getIncomeCategories(
        transactions: [Transaction],
        cacheManager: TransactionCacheManager
    ) -> [String] {
        if !cacheManager.categoryListsCacheInvalidated, let cached = cacheManager.cachedIncomeCategories {
            return cached
        }

        var categories = Set<String>()
        for transaction in transactions where transaction.type == .income {
            let categoryName = transaction.category.isEmpty
                ? String(localized: "category.uncategorized")
                : transaction.category
            categories.insert(categoryName)
        }

        let result = Array(categories).sorted()
        cacheManager.cachedIncomeCategories = result
        return result
    }
}
