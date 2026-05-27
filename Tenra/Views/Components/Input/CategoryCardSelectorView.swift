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

    // Mirrors AccountSelectorView's carousel geometry so the cards line up identically.
    private let cardSpacing: CGFloat = AppSpacing.md
    private let neighborPeek: CGFloat = AppSpacing.lg
    private var contentMargin: CGFloat { cardSpacing + neighborPeek }

    @State private var scrollPosition: String?

    init(
        categories: [String],
        type: TransactionType,
        customCategories: [CustomCategory],
        selectedCategory: Binding<String?>,
        onSelectionChange: ((String?) -> Void)? = nil,
        emptyStateMessage: String? = nil
    ) {
        self.categories = categories
        self.type = type
        self.customCategories = customCategories
        self._selectedCategory = selectedCategory
        self.onSelectionChange = onSelectionChange
        self.emptyStateMessage = emptyStateMessage
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
                carousel
            }
        }
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: cardSpacing) {
                ForEach(categories, id: \.self) { category in
                    CategoryCardButton(
                        category: category,
                        type: type,
                        customCategories: customCategories,
                        isSelected: selectedCategory == category,
                        onTap: {
                            guard selectedCategory != category else { return }
                            selectedCategory = category
                            onSelectionChange?(category)
                        }
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(category)
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .contentMargins(.horizontal, contentMargin, for: .scrollContent)
        .scrollClipDisabled()
        .onAppear {
            syncScrollToSelected(animated: false)
        }
        .onChange(of: selectedCategory) { _, _ in
            syncScrollToSelected(animated: true)
        }
        .onScrollPhaseChange { _, newPhase in
            guard newPhase == .idle,
                  let landed = scrollPosition,
                  landed != selectedCategory
            else { return }
            selectedCategory = landed
            onSelectionChange?(landed)
        }
    }

    private func syncScrollToSelected(animated: Bool) {
        let target = selectedCategory
        if animated {
            guard scrollPosition != target else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollPosition = target
            }
        } else {
            DispatchQueue.main.async {
                guard scrollPosition != target else { return }
                scrollPosition = target
            }
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
                IconView(
                    source: .sfSymbol(style.iconName),
                    style: .circle(
                        size: AppIconSize.xxl,
                        tint: .monochrome(style.iconColor),
                        backgroundColor: style.iconColor.opacity(0.15)
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
