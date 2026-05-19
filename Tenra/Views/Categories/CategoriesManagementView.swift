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
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    @State private var selectedType: TransactionType = .expense
    @State private var showingAddCategory = false
    @State private var editingCategory: CustomCategory?
    @State private var categoryToDelete: CustomCategory?
    @State private var showingDeleteDialog = false
    @State private var navigatingCategory: CustomCategory?
    @State private var mode: ManagementMode = .normal
    @State private var selection: Set<String> = []
    @State private var showingBulkDeleteDialog = false

    @Namespace private var categoryNamespace

    /// Pre-computed snapshots, refreshed only when an upstream observable scalar
    /// (categories mutation version, transactions mutation version, fx rates,
    /// segmented type) actually changes. This prevents the body from doing the
    /// O(N_cat × N_tx) walk that caused the post-budget-set lag.
    @State private var budgetProgressMap: [String: BudgetProgress] = [:]
    @State private var filteredCategories: [CustomCategory] = []

    /// Scalar refresh key for the snapshot rebuild.
    private struct CategoryListKey: Equatable {
        let categoriesVersion: Int
        let mutationVersion: Int
        let ratesVersion: Int
        let baseCurrency: String
        let type: TransactionType
    }

    private var listKey: CategoryListKey {
        CategoryListKey(
            categoriesVersion: transactionStore.categoriesMutationVersion,
            mutationVersion: transactionStore.mutationVersion,
            ratesVersion: transactionStore.currencyRatesVersion,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            type: selectedType
        )
    }

    /// Rebuild the cached snapshots. Both passes are O(N_categories) — they read
    /// pre-aggregated totals via CategoryBudgetService (O(≤31) hashmap lookups
    /// per category) instead of scanning all transactions.
    private func rebuildCategorySnapshots() {
        let sorted = transactionStore.categories
            .filter { $0.type == selectedType }
            .sorted { cat1, cat2 in
                switch (cat1.order, cat2.order) {
                case let (a?, b?): return a < b
                case (_?, nil):    return true
                case (nil, _?):    return false
                default:           return cat1.name < cat2.name
                }
            }
        filteredCategories = sorted

        var map: [String: BudgetProgress] = [:]
        map.reserveCapacity(sorted.count)
        for category in sorted where category.type == .expense {
            if let progress = categoriesViewModel.budgetProgress(for: category) {
                map[category.id] = progress
            }
        }
        budgetProgressMap = map
    }

    // MARK: - Methods

    private func moveCategory(from source: IndexSet, to destination: Int) {
        var updatedCategories = filteredCategories
        updatedCategories.move(fromOffsets: source, toOffset: destination)
        // Atomic reorder + single CoreData persist; was N× saveCategoriesSync.
        transactionStore.reorderCategories(orderedIds: updatedCategories.map { $0.id })
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
                List(selection: mode.isSelecting ? $selection : nil) {
                    ForEach(filteredCategories) { category in
                        CategoryRow(
                            category: category,
                            isDefault: false,
                            budgetProgress: budgetProgressMap[category.id],
                            currency: transactionsViewModel.appSettings.baseCurrency,
                            onEdit: {
                                guard !mode.isSelecting else { return }
                                navigatingCategory = category
                            },
                            onDelete: {
                                categoryToDelete = category
                                showingDeleteDialog = true
                            },
                            transitionSourceID: category.id,
                            transitionNamespace: categoryNamespace
                        )
                        .contextMenu {
                            Button {
                                editingCategory = category
                            } label: {
                                Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                HapticManager.warning()
                                categoryToDelete = category
                                showingDeleteDialog = true
                            } label: {
                                Label(String(localized: "button.delete"), systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: mode.isReordering ? moveCategory : nil)
                }
                .environment(\.editMode, .constant(mode.editMode))
            }
        }
        .animation(AppAnimation.contentSpring, value: selectedType)
        .navigationTitle(String(localized: "navigation.categories"))
        .navigationBarTitleDisplayMode(.large)
        .task(id: listKey) { rebuildCategorySnapshots() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch mode {
                case .normal:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .selecting }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel(String(localized: "bulk.select"))
                case .selecting:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) {
                            mode = .normal
                            selection.removeAll()
                        }
                    } label: {
                        Text(String(localized: "bulk.done"))
                    }
                    .primaryButton()
                case .reordering:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .normal }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .primaryButton()
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .normal {
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .reordering }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .normal {
                    Button {
                        HapticManager.light()
                        showingAddCategory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .primaryButton()
                } else if mode.isSelecting {
                    Button {
                        HapticManager.selection()
                        let filteredIds = Set(filteredCategories.map(\.id))
                        if selection == filteredIds {
                            selection.removeAll()
                        } else {
                            selection = filteredIds
                        }
                    } label: {
                        Text(selection.count == filteredCategories.count
                             ? String(localized: "bulk.deselectAll")
                             : String(localized: "bulk.selectAll"))
                    }
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
                selection.removeAll()
            }
        }
        .navigationDestination(item: $navigatingCategory) { category in
            CategoryDetailView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: appCoordinator.accountsViewModel,
                category: category
            )
            .navigationTransition(.zoom(sourceID: category.id, in: categoryNamespace))
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
        .overlay(alignment: .bottom) {
            if mode.isSelecting && !selection.isEmpty {
                BulkDeleteButton(count: selection.count) {
                    showingBulkDeleteDialog = true
                }
                .animation(AppAnimation.contentSpring, value: selection.count)
            }
        }
        .alert(
            String(format: String(localized: "bulk.deleteCategories.title"), selection.count),
            isPresented: $showingBulkDeleteDialog
        ) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "bulk.deleteCategories.onlyCategories"), role: .destructive) {
                let ids = selection
                Task {
                    await categoriesViewModel.deleteCategories(ids, deleteTransactions: false)
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .normal
                }
            }
            Button(String(localized: "bulk.deleteCategories.withTransactions"), role: .destructive) {
                let ids = selection
                Task {
                    await categoriesViewModel.deleteCategories(ids, deleteTransactions: true)
                    transactionsViewModel.recalculateAccountBalances()
                    transactionsViewModel.clearAndRebuildAggregateCache()
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .normal
                }
            }
        } message: {
            Text(String(localized: "bulk.deleteCategories.message"))
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

                // deleteTransactions goes through TransactionStore.apply()
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
