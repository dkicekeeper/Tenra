//
//  BudgetProgressRow.swift
//  Tenra
//
//  One row in the budget breakdown list: icon + name + progress bar + spent/budget amounts +
//  remaining days. Adapter over DesignKit's `LimitProgressCard`.
//

import SwiftUI

struct BudgetProgressRow: View {
    let item: BudgetInsightItem
    let currency: String

    var body: some View {
        LimitProgressCard(
            iconSource: item.iconSource,
            title: item.categoryName,
            color: item.color,
            spent: item.spent,
            limit: item.budgetAmount,
            currency: currency,
            percentage: item.percentage,
            isOverLimit: item.isOverBudget,
            caption: item.daysRemaining > 0
                ? String(format: String(localized: "insights.daysLeft"), item.daysRemaining)
                : nil
        )
    }
}

// MARK: - Previews

#Preview {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            ForEach(BudgetInsightItem.mockItems()) { item in
                BudgetProgressRow(item: item, currency: "KZT")
            }
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
    }
}
