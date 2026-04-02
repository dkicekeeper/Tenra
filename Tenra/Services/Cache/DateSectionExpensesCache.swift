//
//  DateSectionExpensesCache.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//
//  Manages caching of day expenses calculations for performance optimization.
//  Prevents recalculation of expenses on every section render.
//

import Foundation
import SwiftUI

/// Manages caching of daily expenses for transaction sections
/// Provides memoization to avoid expensive recalculations during scrolling
/// Phase 36: Removed @Observable — nothing observes this reactively; it's a plain cache.
@MainActor
final class DateSectionExpensesCache {

    // MARK: - Private Properties

    /// Cache dictionary mapping date keys to calculated expenses
    private var cache: [String: Double] = [:]

    /// Timestamp of last cache invalidation for debugging
    private var lastInvalidation: Date = Date()

    // MARK: - Public Methods

    /// Get expenses for a specific date section with caching
    /// - Parameters:
    ///   - dateKey: The date key identifying the section (e.g., "Today", "2024-01-15")
    ///   - transactions: Array of transactions for this section
    ///   - baseCurrency: Base currency for conversion
    ///   - viewModel: TransactionsViewModel for currency conversion
    /// - Returns: Total expenses for the section in base currency
    func getExpenses(
        for dateKey: String,
        transactions: [Transaction],
        baseCurrency: String,
        viewModel: TransactionsViewModel
    ) -> Double {
        // Check cache first
        if let cached = cache[dateKey] {
            return cached
        }

        // Cache miss - calculate expenses
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif

        let expenses = calculateExpenses(
            transactions: transactions,
            baseCurrency: baseCurrency,
            viewModel: viewModel
        )

        #if DEBUG
        let _ = CFAbsoluteTimeGetCurrent() - startTime
        #endif

        // Store in cache
        cache[dateKey] = expenses

        return expenses
    }

    /// Invalidate all cached expenses
    /// Call this when transactions change or currency settings update
    func invalidate() {
        cache.removeAll()
        lastInvalidation = Date()
    }

    /// Invalidate specific date section
    /// - Parameter dateKey: The date key to invalidate
    func invalidate(dateKey: String) {
        cache.removeValue(forKey: dateKey)
    }

    // MARK: - Private Methods

    /// Calculate total expenses for a section
    /// - Parameters:
    ///   - transactions: Transactions to calculate from
    ///   - baseCurrency: Base currency for conversion
    ///   - viewModel: ViewModel for currency conversion
    /// - Returns: Total expenses in base currency
    private func calculateExpenses(
        transactions: [Transaction],
        baseCurrency: String,
        viewModel: TransactionsViewModel
    ) -> Double {
        return transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { total, transaction in
                // Use ViewModel's cached conversion method
                let amountInBaseCurrency = viewModel.getConvertedAmountOrCompute(
                    transaction: transaction,
                    to: baseCurrency
                )
                return total + amountInBaseCurrency
            }
    }

    #if DEBUG
    /// Get cache statistics for debugging
    /// - Returns: Dictionary with cache stats
    func getStats() -> [String: Any] {
        return [
            "cachedSections": cache.count,
            "lastInvalidation": lastInvalidation,
            "cacheKeys": Array(cache.keys)
        ]
    }
    #endif
}
