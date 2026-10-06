//
//  CategoryGridView.swift
//  Tenra
//
//  Reusable category grid component with adaptive columns.
//  Displays categories with totals and budget information.
//

import SwiftUI

struct CategoryGridView: View {
    let categories: [CategoryDisplayData]
    let baseCurrency: String
    let gridColumns: Int?
    let onCategoryTap: (String, TransactionType) -> Void
    /// Not `@Sendable` — forwarded to `EmptyCardView.action`, which runs on MainActor.
    let emptyStateAction: (() -> Void)?
    var sourceNamespace: Namespace.ID? = nil

    // MARK: - Body

    var body: some View {
        Group {
            if categories.isEmpty {
                EmptyCardView(
                    sectionTitle: String(localized: "categories.expenseCategories", defaultValue: "Expense Categories"),
                    emptyTitle: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                    action: emptyStateAction
                )
            } else {
                categoryGrid
            }
        }
    }

    // MARK: - Category Grid

    /// DesignKit's `ProgressRingTileGrid` (1.10.0): the tiles, the totals under them and the
    /// columns (4 on an iPhone, or `gridColumns`). Budget rings for expense categories only.
    private var categoryGrid: some View {
        ProgressRingTileGrid(
            items: categories.map(tileItem),
            currency: baseCurrency,
            columns: gridColumns,
            transitionNamespace: sourceNamespace
        ) { item in
            guard let category = categories.first(where: { Self.tileID($0) == item.id }) else { return }
            onCategoryTap(category.name, category.type)
        }
    }

    /// The zoom-transition source id the category detail matches.
    private static func tileID(_ category: CategoryDisplayData) -> String {
        "\(category.name)_\(category.type.rawValue)"
    }

    private func tileItem(_ category: CategoryDisplayData) -> ProgressRingTileGridItem {
        ProgressRingTileGridItem(
            id: Self.tileID(category),
            title: category.name,
            systemImage: category.iconName,
            color: category.iconColor,
            progress: category.type == .expense ? category.budgetProgress.map { LimitProgress($0) } : nil,
            amount: category.total,
            limit: category.budgetAmount,
            accessibilityLabel: String(format: String(localized: "accessibility.category.label"), category.name),
            accessibilityHint: category.budgetProgress.map {
                String(format: String(localized: "accessibility.category.budgetHint"), Int($0.percentage))
            } ?? ""
        )
    }
}

// MARK: - Preview

#Preview("Category Grid - With Data") {
    CategoryGridView(
        categories: [
            CategoryDisplayData(
                id: "1",
                name: "Food",
                type: .expense,
                iconName: "fork.knife",
                iconColor: .orange,
                total: 5000,
                budgetAmount: 10000,
                budgetProgress: BudgetProgress(budgetAmount: 10000, spent: 5000)
            ),
            CategoryDisplayData(
                id: "2",
                name: "Transport",
                type: .expense,
                iconName: "car.fill",
                iconColor: .blue,
                total: 3000,
                budgetAmount: 5000,
                budgetProgress: BudgetProgress(budgetAmount: 5000, spent: 3000)
            ),
            CategoryDisplayData(
                id: "3",
                name: "Home",
                type: .expense,
                iconName: "car.fill",
                iconColor: .blue,
                total: 55000,
                budgetAmount: 50000,
                budgetProgress: BudgetProgress(budgetAmount: 50000, spent: 55000)
            ),
            CategoryDisplayData(
                id: "4",
                name: "Home",
                type: .expense,
                iconName: "car.fill",
                iconColor: .blue,
                total: 130,
                budgetAmount: 300,
                budgetProgress: BudgetProgress(budgetAmount: 300, spent: 130)
            ),
            CategoryDisplayData(
                id: "5",
                name: "Home",
                type: .expense,
                iconName: "car.fill",
                iconColor: .blue,
                total: 5000,
                budgetAmount: 6000,
                budgetProgress: BudgetProgress(budgetAmount: 6000, spent: 5000)
            )
        ],
        baseCurrency: "USD",
        gridColumns: nil,
        onCategoryTap: { _, _ in },
        emptyStateAction: nil
    )
}

#Preview("Category Grid - Empty") {
    CategoryGridView(
        categories: [],
        baseCurrency: "USD",
        gridColumns: 4,
        onCategoryTap: { _, _ in },
        emptyStateAction: { }
    )
}
