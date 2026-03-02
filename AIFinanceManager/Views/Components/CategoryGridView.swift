//
//  CategoryGridView.swift
//  AIFinanceManager
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
    let emptyStateAction: (() -> Void)?
    var sourceNamespace: Namespace.ID? = nil

    // MARK: - Body

    var body: some View {
        Group {
            if categories.isEmpty {
                emptyState
            } else {
                categoryGrid
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if let action = emptyStateAction {
                Button(action: {
                    HapticManager.light()
                    action()
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            Text(String(localized: "categories.expenseCategories", defaultValue: "Expense Categories"))
                                .font(AppTypography.h3)
                                .foregroundStyle(.primary)
                        }

                        EmptyStateView(
                            title: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                            style: .compact
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCardStyle(radius: AppRadius.pill)
                }
                .buttonStyle(.bounce)
            } else {
                EmptyStateView(
                    title: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                    style: .compact
                )
            }
        }
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: AppSpacing.xxxl) {
            ForEach(categories) { category in
                CategoryGridItem(
                    category: category,
                    baseCurrency: baseCurrency,
                    sourceNamespace: sourceNamespace,
                    onTap: {
                        onCategoryTap(category.name, category.type)
                    }
                )
            }
        }
        .padding(AppSpacing.xxs)
    }

    // MARK: - Adaptive Columns

    private var adaptiveColumns: [GridItem] {
        if let columns = gridColumns {
            return Array(
                repeating: GridItem(.flexible(), spacing: AppSpacing.md),
                count: columns
            )
        }

        // Use adaptive column without relying on UIScreen.main (deprecated in iOS 26)
        // SwiftUI's adaptive GridItem automatically adjusts based on available space
        // Minimum 100 allows 3 columns on standard iPhone screens
        return [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: AppSpacing.md)]
    }
}

// MARK: - Category Grid Item

private struct CategoryGridItem: View {
    let category: CategoryDisplayData
    let baseCurrency: String
    var sourceNamespace: Namespace.ID? = nil
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            CategoryChip(
                category: category.name,
                type: category.type,
                customCategories: [],
                isSelected: false,
                onTap: onTap,
                budgetProgress: category.budgetProgress,
                iconName: category.iconName,
                iconColor: category.iconColor
            )

            if let totalText = category.formattedTotal(currency: baseCurrency) {
                Text(totalText)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let budgetText = category.formattedBudget(currency: baseCurrency) {
                Text(budgetText)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .matchedTransitionSourceIfPresent(
            id: "\(category.name)_\(category.type.rawValue)",
            namespace: sourceNamespace
        )
    }
}

// MARK: - Helpers

private extension View {
    @ViewBuilder
    func matchedTransitionSourceIfPresent(id: some Hashable, namespace: Namespace.ID?) -> some View {
        if let ns = namespace {
            matchedTransitionSource(id: id, in: ns)
        } else {
            self
        }
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
