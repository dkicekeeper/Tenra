//
//  CategoriesManagementView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "Tenra", category: "CategoriesManagementView")

struct CategoriesManagementView: View {
    let categoriesViewModel: CategoriesViewModel
    let transactionsViewModel: TransactionsViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: TransactionType = .expense
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    @State private var categoryToDelete: CustomCategory?
    @State private var showingDeleteDialog = false
    @State private var isReordering = false
    
    // Precompute budget progress once per view update to avoid O(N) × O(rows) per-row computation
    private var budgetProgressMap: [String: BudgetProgress] {
        var map: [String: BudgetProgress] = [:]
        let transactions = transactionsViewModel.allTransactions
        for category in filteredCategories where category.type == .expense {
            if let progress = categoriesViewModel.budgetProgress(for: category, transactions: transactions) {
                map[category.id] = progress
            }
        }
        return map
    }

    // Кешируем отфильтрованные категории для оптимизации
    private var filteredCategories: [CustomCategory] {
        let filtered = categoriesViewModel.customCategories
            .filter { $0.type == selectedType }

        // Sort by custom order if available, otherwise by name
        return filtered.sorted { cat1, cat2 in
            // If both have order, sort by order
            if let order1 = cat1.order, let order2 = cat2.order {
                return order1 < order2
            }
            // If only one has order, it goes first
            if cat1.order != nil {
                return true
            }
            if cat2.order != nil {
                return false
            }
            // If neither has order, sort by name
            return cat1.name < cat2.name
        }
    }

    // MARK: - Methods

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var updatedCategories = filteredCategories
        updatedCategories.move(fromOffsets: source, toOffset: destination)

        // Update order for all categories of this type
        for (index, category) in updatedCategories.enumerated() {
            var updatedCategory = category
            updatedCategory.order = index
            categoriesViewModel.updateCategory(updatedCategory)
        }

        // Invalidate caches to ensure the new order is reflected everywhere
        transactionsViewModel.invalidateCaches()

        HapticManager.selection()
    }

    var body: some View {
        Group {
            if filteredCategories.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: String(localized: "emptyState.noCategories"),
                    description: String(localized: "emptyState.startTracking"),
                    actionTitle: String(localized: "button.add"),
                    action: {
                        showingAddCategory = true
                    }
                )
            } else {
                List {
                    ForEach(filteredCategories) { category in
                        CategoryRow(
                            category: category,
                            isDefault: false,
                            budgetProgress: budgetProgressMap[category.id],
                            currency: transactionsViewModel.appSettings.baseCurrency,
                            onEdit: { editingCategory = category },
                            onDelete: {
                                categoryToDelete = category
                                showingDeleteDialog = true
                            }
                        )
                    }
                    .onMove(perform: isReordering ? moveCategory : nil)
                }
                .environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))
            }
        }
        .animation(AppAnimation.contentSpring, value: selectedType)
        .navigationTitle(String(localized: "navigation.categories"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isReordering {
                    Button {
                        HapticManager.light()
                        withAnimation { isReordering.toggle() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .glassProminentButton()
                } else {
                    Button {
                        HapticManager.light()
                        withAnimation { isReordering.toggle() }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if !isReordering {
                    Button {
                        HapticManager.light()
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .glassProminentButton()
                }
            }
        }
        .safeAreaInset(edge: .top) {
            SegmentedPickerView(
                title: "",
                selection: $selectedType,
                options: [
                    (label: String(localized: "transactionType.expense"), value: TransactionType.expense),
                    (label: String(localized: "transactionType.income"), value: TransactionType.income)
                ]
            )
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(Color(.clear))
            .onChange(of: selectedType) { _, _ in
                HapticManager.selection()
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: nil,
                type: selectedType,
                onSave: { category in
                    HapticManager.success()
                    categoriesViewModel.addCategory(category)
                    transactionsViewModel.invalidateCaches()
                    showingAddCategory = false
                },
                onCancel: { showingAddCategory = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: category,
                type: category.type,
                onSave: { updatedCategory in
                    HapticManager.success()
                    categoriesViewModel.updateCategory(updatedCategory)
                    transactionsViewModel.invalidateCaches()
                    editingCategory = nil
                },
                onCancel: { editingCategory = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(String(localized: "category.deleteTitle"), isPresented: $showingDeleteDialog, presenting: categoryToDelete) { category in
            Button(String(localized: "button.cancel"), role: .cancel) {
                categoryToDelete = nil
            }
            Button(String(localized: "category.deleteOnlyCategory"), role: .destructive) {
                HapticManager.warning()

                // Delete category (transactions keep the category name as string)
                categoriesViewModel.deleteCategory(category, deleteTransactions: false)


                // CRITICAL: Clear and rebuild aggregate cache to remove deleted category entity
                // Even though transactions remain, we need to rebuild so the category disappears from UI
                transactionsViewModel.clearAndRebuildAggregateCache()

                categoryToDelete = nil
            }
            Button(String(localized: "category.deleteCategoryAndTransactions"), role: .destructive) {
                HapticManager.warning()

                let categoryName = category.name
                let categoryType = category.type

                guard let store = transactionsViewModel.transactionStore else {
                    logger.error("transactionStore nil — cannot delete transactions for '\(categoryName, privacy: .private)'")
                    categoriesViewModel.deleteCategory(category, deleteTransactions: true)
                    categoryToDelete = nil
                    return
                }

                // Phase 16 SSOT fix: deleteTransactions goes through TransactionStore.apply()
                // so aggregates, cache, and persistence are all updated correctly.
                // deleteCategory runs AFTER await so CategoryAggregateService can still
                // find the entity during per-transaction aggregate maintenance.
                Task {
                    await store.deleteTransactions(forCategoryName: categoryName, type: categoryType)
                    categoriesViewModel.deleteCategory(category, deleteTransactions: true)
                    transactionsViewModel.recalculateAccountBalances()
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }

                categoryToDelete = nil
            }
        } message: { category in
            Text(String(format: String(localized: "category.deleteMessage"), category.name))
        }
    }
}

// MARK: - Previews

#Preview("Categories Management") {
    let coordinator = AppCoordinator()
    NavigationStack {
        CategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Categories Management - Empty") {
    let coordinator = AppCoordinator()
    // ✅ CATEGORY REFACTORING: Use updateCategories for controlled mutation
    coordinator.categoriesViewModel.updateCategories([])

    return NavigationStack {
        CategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}

#Preview("Category Row") {
    let sampleCategory = CustomCategory(
        id: "preview",
        name: "Food",
        iconSource: .sfSymbol("fork.knife"),
        colorHex: "#3b82f6",
        type: .expense,
        budgetAmount: 10000,
        budgetPeriod: .monthly,
        budgetResetDay: 1
    )

    List {
        CategoryRow(
            category: sampleCategory,
            isDefault: false,
            budgetProgress: nil,
            currency: "KZT",
            onEdit: {},
            onDelete: {}
        )
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
