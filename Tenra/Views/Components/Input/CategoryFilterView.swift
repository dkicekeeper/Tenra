//
//  CategoryFilterView.swift
//  Tenra
//
//  Reusable category filter component for HistoryView
//

import SwiftUI

struct CategoryFilterView: View {
    let expenseCategories: [String]
    let incomeCategories: [String]
    let customCategories: [CustomCategory]
    let currentFilter: Set<String>?
    let onFilterChanged: (Set<String>?) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var selectedExpenseCategories: Set<String> = []
    @State private var selectedIncomeCategories: Set<String> = []
    @State private var selectedDeletedCategories: Set<String> = []

    // MARK: - Computed: active vs deleted

    private var customCategoryNames: Set<String> {
        Set(customCategories.map(\.name))
    }

    private var activeExpenseCategories: [String] {
        expenseCategories.filter { customCategoryNames.contains($0) }
    }

    private var activeIncomeCategories: [String] {
        incomeCategories.filter { customCategoryNames.contains($0) }
    }

    /// Categories that exist in transactions but were deleted from customCategories
    private var deletedCategories: [String] {
        let deletedExpense = expenseCategories.filter { !customCategoryNames.contains($0) }
        let deletedIncome = incomeCategories.filter { !customCategoryNames.contains($0) }
        // Deduplicate preserving order
        var seen = Set<String>()
        return (deletedExpense + deletedIncome).filter { seen.insert($0).inserted }
    }

    private var isAllDeselected: Bool {
        selectedExpenseCategories.isEmpty && selectedIncomeCategories.isEmpty && selectedDeletedCategories.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                // "All Categories" option
                Section {
                    CheckmarkRow(String(localized: "categoryFilter.allCategories"), isSelected: isAllDeselected) {
                        selectedExpenseCategories.removeAll()
                        selectedIncomeCategories.removeAll()
                        selectedDeletedCategories.removeAll()
                    }
                }

                // MARK: - Expense Categories
                categorySection(
                    title: String(localized: "transactionType.expense"),
                    categories: activeExpenseCategories,
                    emptyText: String(localized: "categoryFilter.noExpenseCategories"),
                    selected: $selectedExpenseCategories
                )

                // MARK: - Income Categories
                categorySection(
                    title: String(localized: "transactionType.income"),
                    categories: activeIncomeCategories,
                    emptyText: String(localized: "categoryFilter.noIncomeCategories"),
                    selected: $selectedIncomeCategories
                )

                // MARK: - Deleted Categories
                if !deletedCategories.isEmpty {
                    categorySection(
                        title: String(localized: "categoryFilter.deletedCategories"),
                        categories: deletedCategories,
                        emptyText: nil,
                        selected: $selectedDeletedCategories
                    )
                }
            }
            .navigationTitle(String(localized: "navigation.categoryFilter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.success()
                        applyFilter()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .primaryButton()
                }
            }
            .onAppear {
                if let filter = currentFilter {
                    selectedExpenseCategories = Set(activeExpenseCategories.filter { filter.contains($0) })
                    selectedIncomeCategories = Set(activeIncomeCategories.filter { filter.contains($0) })
                    selectedDeletedCategories = Set(deletedCategories.filter { filter.contains($0) })
                }
            }
        }
    }

    // MARK: - Category Section

    private func categorySection(
        title: String,
        categories: [String],
        emptyText: String?,
        selected: Binding<Set<String>>
    ) -> some View {
        Section {
            if categories.isEmpty {
                if let emptyText {
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(categories, id: \.self) { category in
                    categoryRow(
                        category: category,
                        isSelected: selected.wrappedValue.contains(category)
                    ) {
                        if selected.wrappedValue.contains(category) {
                            selected.wrappedValue.remove(category)
                        } else {
                            selected.wrappedValue.insert(category)
                        }
                    }
                }
            }
        } header: {
            SectionHeaderView(title)
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(category: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        CheckmarkRow(category, icon: iconConfig(for: category), isSelected: isSelected, action: action)
    }

    /// Plated like the category rows (`CategoryRow`): the icon in the category's colour on a
    /// pale circle of it. A category deleted since keeps the neutral folder, on a neutral
    /// plate. `xl`, the size the category icons here already had.
    private func iconConfig(for categoryName: String) -> IconConfig {
        if let custom = customCategories.first(where: { $0.name == categoryName }) {
            return .custom(
                source: custom.iconSource,
                style: .circle(
                    size: AppIconSize.xl,
                    tint: .monochrome(custom.color),
                    backgroundColor: AppColors.pale(custom.color)
                )
            )
        }
        return .custom(
            source: .sfSymbol("folder"),
            style: .circle(
                size: AppIconSize.xl,
                tint: .monochrome(AppColors.textSecondary),
                backgroundColor: AppColors.Status.neutralPale
            )
        )
    }

    // MARK: - Apply

    private func applyFilter() {
        let allSelected = selectedExpenseCategories
            .union(selectedIncomeCategories)
            .union(selectedDeletedCategories)
        if allSelected.isEmpty {
            onFilterChanged(nil)
        } else {
            onFilterChanged(allSelected)
        }
    }
}

#Preview {
    CategoryFilterView(
        expenseCategories: ["Food", "Transport", "Entertainment"],
        incomeCategories: ["Salary", "Freelance"],
        customCategories: [],
        currentFilter: nil,
        onFilterChanged: { _ in }
    )
}
