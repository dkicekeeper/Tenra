//
//  CategoryBudgetCoordinator.swift
//  AIFinanceManager
//
//  Optimized service for category budget management with pre-aggregated cache
//  Replaces CategoryBudgetService with O(1) budget lookups
//

import Foundation

/// Service responsible for budget calculations and period management
/// OPTIMIZATION: Pre-aggregates spent amounts to avoid O(N×M) complexity
@MainActor
final class CategoryBudgetCoordinator: CategoryBudgetCoordinatorProtocol {

    // MARK: - Dependencies

    /// Delegate for callbacks to ViewModel
    weak var delegate: CategoryBudgetDelegate?

    /// Currency conversion service
    private let currencyService: TransactionCurrencyService?

    /// App settings for base currency
    private let appSettings: AppSettings?

    // MARK: - Cache

    /// Pre-aggregated budget cache: [categoryId: spent amount in base currency]
    /// OPTIMIZATION: O(1) lookup instead of O(M) filtering per category
    private var budgetCache: [String: Double] = [:]



    // MARK: - Initialization

    init(
        currencyService: TransactionCurrencyService? = nil,
        appSettings: AppSettings? = nil
    ) {
        self.currencyService = currencyService
        self.appSettings = appSettings
    }

    init(
        delegate: CategoryBudgetDelegate,
        currencyService: TransactionCurrencyService?,
        appSettings: AppSettings?
    ) {
        self.delegate = delegate
        self.currencyService = currencyService
        self.appSettings = appSettings
    }

    // MARK: - Public Methods

    func setBudget(
        for categoryId: String,
        amount: Double,
        period: CustomCategory.BudgetPeriod = .monthly,
        resetDay: Int = 1
    ) {
        guard let delegate = delegate else {
            return
        }

        guard let index = delegate.customCategories.firstIndex(where: { $0.id == categoryId }) else {
            return
        }

        var category = delegate.customCategories[index]
        category.budgetAmount = amount
        category.budgetPeriod = period
        category.budgetStartDate = Date()
        category.budgetResetDay = resetDay

        delegate.updateCategory(category)

    }

    func removeBudget(for categoryId: String) {
        guard let delegate = delegate else {
            return
        }

        guard let index = delegate.customCategories.firstIndex(where: { $0.id == categoryId }) else {
            return
        }

        var category = delegate.customCategories[index]
        category.budgetAmount = nil
        category.budgetStartDate = nil

        // Remove from cache
        budgetCache.removeValue(forKey: categoryId)

        delegate.updateCategory(category)

    }

    func budgetProgress(for category: CustomCategory) -> BudgetProgress? {
        // Only expense categories can have budgets
        guard let budgetAmount = category.budgetAmount,
              category.type == .expense else { return nil }

        // Get spent from cache (O(1))
        let spent = budgetCache[category.id] ?? 0

        return BudgetProgress(budgetAmount: budgetAmount, spent: spent)
    }

    func refreshBudgetCache(transactions: [Transaction], categories: [CustomCategory]) {

        // Clear cache
        budgetCache.removeAll()

        // Filter categories with budgets
        let categoriesWithBudgets = categories.filter { $0.budgetAmount != nil && $0.type == .expense }

        guard !categoriesWithBudgets.isEmpty else {
            return
        }

        // Calculate period start dates for all categories with budgets
        let periodStarts = categoriesWithBudgets.reduce(into: [String: Date]()) { result, category in
            result[category.id] = budgetPeriodStart(for: category)
        }

        // Single pass through transactions - O(M)
        for transaction in transactions {
            guard transaction.type == .expense else { continue }

            // Parse transaction date
            guard let transactionDate = DateFormatters.dateFormatter.date(from: transaction.date) else { continue }

            // Check if transaction belongs to any category with budget
            for category in categoriesWithBudgets {
                guard transaction.category == category.name else { continue }

                // Check if transaction is in budget period
                guard let periodStart = periodStarts[category.id],
                      transactionDate >= periodStart,
                      transactionDate <= Date() else { continue }

                // Convert to base currency
                let amount: Double
                if let currencyService = currencyService, let appSettings = appSettings {
                    amount = currencyService.getConvertedAmountOrCompute(
                        transaction: transaction,
                        to: appSettings.baseCurrency
                    )
                } else {
                    amount = transaction.amount
                }

                // Add to cache
                budgetCache[category.id, default: 0] += amount
            }
        }

    }

    func clearCache() {
        budgetCache.removeAll()
    }

    // MARK: - Private Helpers

    /// Calculate budget period start date for a category
    /// - Parameter category: The category to calculate period start for
    /// - Returns: Start date of current budget period
    private func budgetPeriodStart(for category: CustomCategory) -> Date {
        guard category.budgetStartDate != nil else { return Date() }

        let calendar = Calendar.current
        let now = Date()

        switch category.budgetPeriod {
        case .weekly:
            // Start of current week
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        case .monthly:
            // Reset on specific day of month
            let components = calendar.dateComponents([.year, .month], from: now)
            var startComponents = components
            startComponents.day = category.budgetResetDay

            if let resetDate = calendar.date(from: startComponents) {
                // If reset day hasn't happened this month yet, use previous month
                if resetDate > now {
                    return calendar.date(byAdding: .month, value: -1, to: resetDate) ?? resetDate
                }
                return resetDate
            }
            return now

        case .yearly:
            // Start of current year
            return calendar.dateInterval(of: .year, for: now)?.start ?? now
        }
    }
}

// MARK: - Factory Methods

extension CategoryBudgetCoordinator {
    /// Create coordinator with dependencies
    /// - Parameters:
    ///   - delegate: Delegate for callbacks
    ///   - currencyService: Currency conversion service
    ///   - appSettings: App settings for base currency
    /// - Returns: Configured coordinator
    static func create(
        delegate: CategoryBudgetDelegate,
        currencyService: TransactionCurrencyService,
        appSettings: AppSettings
    ) -> CategoryBudgetCoordinator {
        CategoryBudgetCoordinator(
            delegate: delegate,
            currencyService: currencyService,
            appSettings: appSettings
        )
    }
}
