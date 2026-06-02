//
//  TransactionStore+Computed.swift
//  Tenra
//
//  Computed properties, caching, and calculation methods extracted from TransactionStore.
//

import Foundation

// MARK: - Computed Properties with Caching

extension TransactionStore {

    /// Expenses grouped by category (cached)
    var categoryExpenses: [CachedCategoryExpense] {
        // Try cache first
        if let cached: [CachedCategoryExpense] = cache.categoryExpenses {
            return cached
        }

        // Calculate
        let result = calculateCategoryExpenses(transactions: transactions)

        // Cache result
        cache.setCachedCategoryExpenses(result)

        return result
    }

    /// Daily expenses for a specific date (cached)
    func expenses(for date: Date) -> Double {
        let dateString = DateFormatters.dateFormatter.string(from: date)

        // Try cache first
        if let cached = cache.dailyExpenses(for: dateString) {
            return cached
        }

        // Calculate
        let result = calculateDailyExpenses(for: dateString, transactions: transactions)

        // Cache result
        cache.setDailyExpenses(result, for: dateString)

        return result
    }

    // MARK: - Calculation Methods

    /// Calculate category expenses from transactions
    private func calculateCategoryExpenses(transactions: [Transaction]) -> [CachedCategoryExpense] {
        var categoryMap: [String: Double] = [:]

        for tx in transactions where tx.type == .expense && !tx.category.isEmpty {
            let amountInBase = convertToBaseCurrency(amount: tx.amount, from: tx.currency)
            categoryMap[tx.category, default: 0] += amountInBase
        }

        return categoryMap.map { CachedCategoryExpense(name: $0.key, amount: $0.value, currency: baseCurrency) }
            .sorted { $0.amount > $1.amount }  // Sort by amount descending
    }

    /// Calculate daily expenses for a specific date
    private func calculateDailyExpenses(for dateString: String, transactions: [Transaction]) -> Double {
        return transactions
            .filter { $0.date == dateString && $0.type == .expense }
            .reduce(0.0) { sum, tx in
                sum + convertToBaseCurrency(amount: tx.amount, from: tx.currency)
            }
    }

    /// Convert amount to base currency
    private func convertToBaseCurrency(amount: Double, from currency: String) -> Double {
        return convertToCurrency(amount: amount, from: currency, to: baseCurrency)
    }

    /// Convert amount between currencies
    private func convertToCurrency(amount: Double, from: String, to: String) -> Double {
        // Same currency - no conversion
        if from == to {
            return amount
        }

        // Use currency converter (sync version for computed properties)
        return CurrencyConverter.convertSync(amount: amount, from: from, to: to) ?? amount
    }
}
