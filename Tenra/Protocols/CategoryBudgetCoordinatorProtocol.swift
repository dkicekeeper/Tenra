//
//  CategoryBudgetCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Protocol for category budget management with pre-aggregated cache
//  Optimized version of CategoryBudgetService
//

import Foundation

/// Protocol defining budget management operations
@MainActor
protocol CategoryBudgetCoordinatorProtocol {
    /// Set budget for a category
    /// - Parameters:
    ///   - categoryId: Category ID
    ///   - amount: Budget amount
    ///   - period: Budget period (weekly/monthly/yearly)
    ///   - resetDay: Day of month/week to reset (default: 1)
    func setBudget(
        for categoryId: String,
        amount: Double,
        period: CustomCategory.BudgetPeriod,
        resetDay: Int
    )

    /// Remove budget from a category
    /// - Parameter categoryId: Category ID
    func removeBudget(for categoryId: String)

    /// Get budget progress for a category (O(1) from cache)
    /// - Parameter category: The category
    /// - Returns: Budget progress if category has budget, nil otherwise
    func budgetProgress(for category: CustomCategory) -> BudgetProgress?

    /// Refresh budget cache from transactions (call after transaction changes)
    /// - Parameters:
    ///   - transactions: All transactions to analyze
    ///   - categories: All categories with budgets
    func refreshBudgetCache(transactions: [Transaction], categories: [CustomCategory])

    /// Clear budget cache (call when base currency changes)
    func clearCache()
}

/// Delegate protocol for CategoryBudgetCoordinator callbacks
@MainActor
protocol CategoryBudgetDelegate: AnyObject {
    /// Current list of custom categories (read-only)
    var customCategories: [CustomCategory] { get }

    /// Update a category
    /// - Parameter category: Category to update
    func updateCategory(_ category: CustomCategory)
}
