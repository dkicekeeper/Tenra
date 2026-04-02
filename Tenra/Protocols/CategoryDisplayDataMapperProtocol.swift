//
//  CategoryDisplayDataMapperProtocol.swift
//  AIFinanceManager
//
//  Protocol for mapping categories to display data
//

import Foundation

/// Protocol for category display data mapping
@MainActor
protocol CategoryDisplayDataMapperProtocol {
    /// Map categories to display data with totals and budget info
    func mapCategories(
        customCategories: [CustomCategory],
        categoryExpenses: [String: CategoryExpense],
        type: TransactionType,
        baseCurrency: String,
        currentFilter: TimeFilter
    ) -> [CategoryDisplayData]
}
