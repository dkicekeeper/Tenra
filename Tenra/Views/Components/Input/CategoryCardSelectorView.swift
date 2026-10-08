//
//  CategoryCardSelectorView.swift
//  Tenra
//
//  Card-style horizontal category selector — mirrors AccountSelectorView so the income
//  top-up flow presents categories as full-width snap cards instead of compact chips.
//

import SwiftUI

struct CategoryCardSelectorView: View {
    let categories: [String]
    let type: TransactionType
    let customCategories: [CustomCategory]
    @Binding var selectedCategory: String?
    let onSelectionChange: ((String?) -> Void)?
    let emptyStateMessage: String?
    /// Optional button under the empty-state message (e.g. "Add income category"),
    /// so an empty list is never a dead end.
    let emptyStateAction: (() -> Void)?
    let emptyStateActionTitle: String?

    init(
        categories: [String],
        type: TransactionType,
        customCategories: [CustomCategory],
        selectedCategory: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil,
        emptyStateAction: (() -> Void)? = nil,
        emptyStateActionTitle: String? = nil
    ) {
        self.categories = categories
        self.type = type
        self.customCategories = customCategories
        self._selectedCategory = selectedCategory
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
        self.emptyStateAction = emptyStateAction
        self.emptyStateActionTitle = emptyStateActionTitle
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
                if let action = emptyStateAction, let title = emptyStateActionTitle {
                    Button(title, action: action)
                        .dsButton(.secondary)
                        .frame(maxWidth: .infinity)
                }
            } else {
                carousel
            }
        }
    }

    /// DesignKit's `SnapCardPicker` (2.9.0), as the account selector: the same snapping and
    /// geometry, so the cards line up identically.
    private var carousel: some View {
        SnapCardPicker(
            categories,
            id: \.self,
            selection: $selectedCategory,
            onSelectionChange: { onSelectionChange?($0) }
        ) { category, isSelected, select in
            CategoryCardButton(
                category: category,
                type: type,
                customCategories: customCategories,
                isSelected: isSelected,
                onTap: select
            )
        }
    }
}

// MARK: - Card

private struct CategoryCardButton: View {
    let category: String
    let type: TransactionType
    let customCategories: [CustomCategory]
    let isSelected: Bool
    let onTap: () -> Void

    private var style: CategoryStyleData {
        CategoryStyleHelper.cached(category: category, type: type, customCategories: customCategories)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                // Match the canonical category icon (CategoryRow): xxl circle with
                // category-color tint over a soft category-color background. The
                // carousel previously used `xl` with no background, which read as a
                // smaller, washed-out icon next to AccountRadioButton in the same flow.
                Icon(
                    source: .sfSymbol(style.iconName),
                    style: .circle(
                        size: AppIconSize.Tile.sm,
                        tint: .monochrome(style.iconColor),
                        backgroundColor: AppColors.pale(style.iconColor)
                    )
                )

                Text(category)
                    .font(AppTypography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.lg)
            .cardStyle()
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .stroke(AppColors.accent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
                    .animation(AppAnimation.gentleSpring, value: isSelected)
            }
        }
        .buttonStyle(.bounce)
    }
}

#Preview {
    @Previewable @State var selected: String? = "Зарплата"
    return CategoryCardSelectorView(
        categories: ["Зарплата", "Фриланс", "Подарок", "Инвестиции"],
        type: .income,
        customCategories: [],
        selectedCategory: $selected
    )
}
