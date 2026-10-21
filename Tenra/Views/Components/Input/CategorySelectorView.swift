//
//  CategorySelectorView.swift
//  Tenra
//
//  Category picker of the money forms (edit a transaction, a voice entry, a receipt, a loan
//  payment, a Wallet merchant): every category as a chip with its icon in its colour, in a row
//  that scrolls sideways, the chosen one tinted and scrolled into view. The chips and the row are
//  the subcategory chips' under it: DesignKit's `UniversalFilterButton` in a
//  `UniversalCarousel(config: .filter)`.
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

    init(
        categories: [String],
        type: TransactionType,
        customCategories: [CustomCategory],
        selectedCategory: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        warningMessage: String? = nil
    ) {
        self.categories = categories
        self.type = type
        self.customCategories = customCategories
        self._selectedCategory = selectedCategory
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.warningMessage = warningMessage
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
                    config: .filter,
                    scrollToId: .constant(selectedCategory)
                ) {
                    ForEach(categories, id: \.self) { category in
                        chip(category)
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

    private func chip(_ category: String) -> some View {
        let style = CategoryStyleHelper.cached(category: category, type: type, customCategories: customCategories)
        return UniversalFilterButton(
            title: category,
            isSelected: selectedCategory == category,
            showChevron: false,
            onTap: {
                HapticManager.selection()
                selectedCategory = category
                onSelectionChange?(category)
            }
        ) {
            Icon(style.iconName, size: AppIconSize.sm, tint: .monochrome(style.iconColor))
        }
        .accessibilityLabel(String(format: String(localized: "accessibility.category.label"), category))
    }
}

#Preview {
    @Previewable @State var selectedCategory: String? = "Transport"

    return VStack {
        CategorySelectorView(
            categories: ["Food", "Transport", "Shopping", "Entertainment", "Health", "Home"],
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
    .padding(.vertical)
}
