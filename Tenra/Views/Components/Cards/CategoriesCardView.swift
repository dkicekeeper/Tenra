//
//  CategoriesCardView.swift
//  Tenra
//
//  Summary card showing total category count plus a facepile of category icons.
//

import SwiftUI

struct CategoriesCardView: View {
    let categoriesViewModel: CategoriesViewModel

    private var categories: [CustomCategory] {
        categoriesViewModel.customCategories
    }

    var body: some View {
        FinanceCard(
            title: String(localized: "finances.categories.title"),
            isEmpty: categories.isEmpty,
            emptyTitle: String(localized: "finances.categories.empty"),
            subtitle: String(format: String(localized: "finances.categories.count"), categories.count)
        ) {
            Text("\(categories.count)")
                .font(AppTypography.h2)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())
        } trailing: {
            categoryIcons
        }
    }

    // MARK: - Icons

    /// Equal-weight facepile — categories don't have an inherent "amount" axis,
    /// so all circles render at the same size. SF-symbol icons take the category's
    /// own color as their monochrome tint; brand-service logos render `.original`.
    private var categoryIcons: some View {
        PackedCircleIconsView(
            items: categories.map { category in
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

// MARK: - Preview

#Preview("Categories Card") {
    let coordinator = AppCoordinator()
    CategoriesCardView(categoriesViewModel: coordinator.categoriesViewModel)
        .screenPadding()
}
