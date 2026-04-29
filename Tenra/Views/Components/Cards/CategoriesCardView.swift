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
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(String(localized: "finances.categories.title"))
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)

                if categories.isEmpty {
                    EmptyStateView(
                        title: String(localized: "finances.categories.empty"),
                        style: .compact
                    )
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("\(categories.count)")
                            .font(AppTypography.h2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.textPrimary)
                            .contentTransition(.numericText())

                        Text(String(format: String(localized: "finances.categories.count"), categories.count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !categories.isEmpty {
                categoryIcons
            }
        }
        .animation(AppAnimation.gentleSpring, value: categories.isEmpty)
        .padding(AppSpacing.lg)
        .cardStyle()
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
