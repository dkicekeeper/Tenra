//
//  CategoryBudgetService.swift
//  AIFinanceManager
//
//  Service for category budget calculations and progress tracking.
//  Extracted from CategoriesViewModel for better separation of concerns.
//
//  Phase 40: Removed BudgetSpendingCacheService fast path — all transactions in memory, O(N) is fast.
//

import Foundation

/// Service responsible for budget calculations and period management.
struct CategoryBudgetService {

    // MARK: - Dependencies

    let currencyService: TransactionCurrencyService?
    let baseCurrency: String?

    // MARK: - Initialization

    init(
        currencyService: TransactionCurrencyService? = nil,
        appSettings: AppSettings? = nil,
        baseCurrency: String? = nil
    ) {
        self.currencyService = currencyService
        self.baseCurrency = baseCurrency ?? appSettings?.baseCurrency
    }

    // MARK: - Public Methods

    /// Calculate budget progress for a category.
    /// - Parameters:
    ///   - category: The category to calculate progress for
    ///   - transactions: All transactions to analyze (used as fallback)
    /// - Returns: BudgetProgress if category has budget, nil otherwise
    nonisolated func budgetProgress(for category: CustomCategory, transactions: [Transaction]) -> BudgetProgress? {
        // Only expense categories can have budgets
        guard let budgetAmount = category.budgetAmount,
              category.type == .expense else { return nil }

        // Calculate spent amount for current period
        let spent = calculateSpent(for: category, transactions: transactions)

        return BudgetProgress(budgetAmount: budgetAmount, spent: spent)
    }

    /// Calculate spent amount for a category in the current budget period.
    ///
    /// Phase 40: Always O(N) scan — all transactions are in memory, cache removed.
    nonisolated func calculateSpent(for category: CustomCategory, transactions: [Transaction]) -> Double {
        let periodStart = budgetPeriodStart(for: category)
        let periodEnd = Date()

        // Phase 36: Use cached DateFormatter instead of allocating a new one per call
        let dateFormatter = DateFormatters.dateFormatter

        return transactions
            .filter { transaction in
                guard transaction.category == category.name,
                      transaction.type == .expense,
                      let transactionDate = dateFormatter.date(from: transaction.date) else {
                    return false
                }
                return transactionDate >= periodStart && transactionDate <= periodEnd
            }
            .reduce(0) { sum, transaction in
                // Convert to base currency if possible (nonisolated fallback path)
                if let base = baseCurrency {
                    if transaction.currency == base {
                        return sum + transaction.amount
                    } else {
                        return sum + (transaction.convertedAmount ?? transaction.amount)
                    }
                } else {
                    // Fallback: use amount without conversion
                    return sum + transaction.amount
                }
            }
    }

    /// Calculate budget period start date for a category.
    /// - Parameter category: The category to calculate period start for
    /// - Returns: Start date of current budget period
    nonisolated func budgetPeriodStart(for category: CustomCategory) -> Date {
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

// MARK: - Static Helpers

extension CategoryBudgetService {

    /// Create budget service with all dependencies.
    static func create(
        currencyService: TransactionCurrencyService,
        appSettings: AppSettings
    ) -> CategoryBudgetService {
        CategoryBudgetService(
            currencyService: currencyService,
            appSettings: appSettings
        )
    }
}
