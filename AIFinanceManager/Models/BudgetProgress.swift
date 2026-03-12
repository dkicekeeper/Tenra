//
//  BudgetProgress.swift
//  AIFinanceManager
//
//  Created on 2026-01-15
//

import Foundation

struct BudgetProgress {
    let budgetAmount: Double
    let spent: Double
    let remaining: Double
    let percentage: Double  // 0-100+
    let isOverBudget: Bool

    init(budgetAmount: Double, spent: Double) {
        self.budgetAmount = budgetAmount
        self.spent = spent
        self.remaining = budgetAmount - spent
        self.percentage = budgetAmount > 0 ? (spent / budgetAmount) * 100 : 0
        self.isOverBudget = spent > budgetAmount
    }
}
