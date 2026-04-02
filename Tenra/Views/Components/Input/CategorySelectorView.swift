//
//  CategorySelectorView.swift
//  AIFinanceManager
//
//  Reusable category selector component with horizontal scroll
//

import SwiftUI

struct CategorySelectorView: View {
    let categories: [String]
    let type: TransactionType
    let customCategories: [CustomCategory]
    @Binding var selectedCategory: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    let warningMessage: String?
    let budgetProgressMap: [String: BudgetProgress]?

    init(
        categories: [String],
        type: TransactionType,
        customCategories: [CustomCategory],
        selectedCategory: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        warningMessage: String? = nil,
        budgetProgressMap: [String: BudgetProgress]? = nil
    ) {
        self.categories = categories
        self.type = type
        self.customCategories = customCategories
        self._selectedCategory = selectedCategory
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.warningMessage = warningMessage
        self.budgetProgressMap = budgetProgressMap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if categories.isEmpty {
                if let message = emptyStateMessage {
                    Text(message)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                }
            } else {
                UniversalCarousel(
                    config: .standard,
                    scrollToId: .constant(selectedCategory)
                ) {
                    ForEach(categories, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            type: type,
                            customCategories: customCategories,
                            isSelected: selectedCategory == category,
                            onTap: {
                                selectedCategory = category
                                onSelectionChange?(category)
                            },
                            budgetProgress: budgetProgressMap?[category]
                        )
                        .frame(width: 80)
                        .id(category)
                    }
                }
            }

            if let warning = warningMessage {
                InlineStatusText(message: warning, type: .warning)
                    .padding(.horizontal, AppSpacing.sm)
            }
        }
    }
}

#Preview {
    @Previewable @State var selectedCategory: String? = nil
    
    return VStack {
        CategorySelectorView(
            categories: ["Food", "Transport", "Shopping", "Entertainment"],
            type: .expense,
            customCategories: [],
            selectedCategory: $selectedCategory,
            emptyStateMessage: nil,
            warningMessage: nil
        )
        
        CategorySelectorView(
            categories: [],
            type: .expense,
            customCategories: [],
            selectedCategory: $selectedCategory,
            emptyStateMessage: "No categories available",
            warningMessage: nil
        )
    }
    .padding()
}
