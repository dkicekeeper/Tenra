//
//  CategoryFilterView.swift
//  AIFinanceManager
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
            ScrollView {
                VStack(spacing: 0) {
                    // "All Categories" option
                    UniversalRow(config: .sheetList) {
                        Text(String(localized: "categoryFilter.allCategories"))
                            .font(AppTypography.h4)
                            .fontWeight(.medium)
                    } trailing: {
                        if isAllDeselected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .selectableRow(isSelected: isAllDeselected) {
                        HapticManager.selection()
                        selectedExpenseCategories.removeAll()
                        selectedIncomeCategories.removeAll()
                        selectedDeletedCategories.removeAll()
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
                    .glassProminentButton()
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

    @ViewBuilder
    private func categorySection(
        title: String,
        categories: [String],
        emptyText: String?,
        selected: Binding<Set<String>>
    ) -> some View {
        SectionHeaderView(title, style: .compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.sm)

        if categories.isEmpty {
            if let emptyText {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
            }
        } else {
            ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                categoryRow(
                    category: category,
                    isSelected: selected.wrappedValue.contains(category)
                ) {
                    HapticManager.selection()
                    if selected.wrappedValue.contains(category) {
                        selected.wrappedValue.remove(category)
                    } else {
                        selected.wrappedValue.insert(category)
                    }
                }

                if index < categories.count - 1 {
                    Divider()
                        .padding(.leading, AppSpacing.lg)
                }
            }
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(category: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let iconConfig = iconConfig(for: category)

        UniversalRow(
            config: .sheetList,
            leadingIcon: iconConfig
        ) {
            Text(category)
                .font(AppTypography.h4)
                .fontWeight(.medium)
        } trailing: {
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(AppColors.accent)
            }
        }
        .selectableRow(isSelected: isSelected, action: action)
    }

    private func iconConfig(for categoryName: String) -> IconConfig {
        if let custom = customCategories.first(where: { $0.name == categoryName }) {
            return .auto(source: custom.iconSource, size: AppIconSize.xl)
        }
        return .sfSymbol("folder", color: AppColors.textSecondary)
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
