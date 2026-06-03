//
//  SubcategoriesCardView.swift
//  Tenra
//
//  Summary card showing subcategory count and the number of parent categories
//  they're linked to. Subcategory has no icon/color of its own, so we render
//  a single decorative `tag.fill` mark via IconView for visual parity with
//  the other Finance cards.
//

import SwiftUI

struct SubcategoriesCardView: View {
    let categoriesViewModel: CategoriesViewModel

    private var subcategories: [Subcategory] {
        categoriesViewModel.subcategories
    }

    /// Distinct parent categories that have at least one subcategory link.
    /// Drives both the count subtitle and the facepile decoration so the visual
    /// motif matches CategoriesCardView (icons + per-category tint).
    private var linkedCategories: [CustomCategory] {
        let categoryById = Dictionary(uniqueKeysWithValues: categoriesViewModel.customCategories.map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [CustomCategory] = []
        for link in categoriesViewModel.categorySubcategoryLinks {
            guard !seen.contains(link.categoryId), let cat = categoryById[link.categoryId] else { continue }
            seen.insert(link.categoryId)
            result.append(cat)
        }
        return result
    }

    var body: some View {
        FinanceCard(
            title: String(localized: "finances.subcategories.title"),
            isEmpty: subcategories.isEmpty,
            emptyTitle: String(localized: "finances.subcategories.empty"),
            subtitle: String(format: String(localized: "finances.subcategories.linkedTo"), linkedCategories.count)
        ) {
            Text("\(subcategories.count)")
                .font(AppTypography.h2)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())
        } trailing: {
            // Facepile shows linked parent categories; hidden when none are linked yet.
            if !linkedCategories.isEmpty {
                PackedCircleIconsView(
                    items: linkedCategories.map { category in
                        PackedCircleItem(
                            id: category.id,
                            iconSource: category.iconSource,
                            amount: 1,
                            tint: category.color
                        )
                    }
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Subcategories Card") {
    let coordinator = AppCoordinator()
    SubcategoriesCardView(categoriesViewModel: coordinator.categoriesViewModel)
        .screenPadding()
}
