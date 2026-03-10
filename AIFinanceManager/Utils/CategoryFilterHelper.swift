//
//  CategoryFilterHelper.swift
//  AIFinanceManager
//
//  Helper for category filter display logic
//  Phase 14: Extracted from CategoryFilterButton for reusability
//

import SwiftUI

struct CategoryFilterHelper {
    /// Generate display text for category filter
    static func displayText(for selectedCategories: Set<String>?) -> String {
        guard let selectedCategories = selectedCategories else {
            return String(localized: "filter.allCategories")
        }
        if selectedCategories.count == 1 {
            return selectedCategories.first ?? String(localized: "filter.allCategories")
        }
        return String(format: String(localized: "filter.categoriesCount"), selectedCategories.count)
    }

    /// Generate icon view for single selected category
    @ViewBuilder
    static func iconView(
        for selectedCategories: Set<String>?,
        customCategories: [CustomCategory],
        incomeCategories: [String]
    ) -> some View {
        if let selectedCategories = selectedCategories,
           selectedCategories.count == 1,
           let category = selectedCategories.first {
            let isIncome: Bool = {
                if let customCategory = customCategories.first(where: { $0.name == category }) {
                    return customCategory.type == .income
                } else {
                    return incomeCategories.contains(category)
                }
            }()
            let categoryType: TransactionType = isIncome ? .income : .expense
            let iconName = CategoryIcon.iconName(for: category, type: categoryType, customCategories: customCategories)
            let iconColor = CategoryColors.hexColor(for: category, opacity: 1.0, customCategories: customCategories)
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(isIncome ? AppColors.income : iconColor)
        }
    }
}
