//
//  CategoryDetailView.swift
//  Tenra
//
//  Detail screen for a single custom category.
//  Built on EntityDetailScaffold — mirrors AccountDetailView's composition.
//  Period-scoped via global TimeFilterManager; shows optional budget progress
//  in the hero when the expense category has a budget.
//

import SwiftUI
import os.log

private let categoryDetailLogger = Logger(subsystem: "Tenra", category: "CategoryDetailView")

struct CategoryDetailView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    let category: CustomCategory

    @State private var showingEdit = false
    @State private var showingSubcategories = false
    @State private var showingDeleteConfirm = false
    @State private var showingAddTransaction = false
    @State private var cachedTransactions: [Transaction] = []
    @State private var aggregates = CategoryAggregates(
        amountInPeriod: 0,
        amountAllTime: 0,
        avgMonthlyLast6: 0,
        totalTransactions: 0
    )

    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager

    /// Live category lookup — reflects edits (e.g. budget changes) without re-navigation.
    private var liveCategory: CustomCategory {
        categoriesViewModel.customCategories.first(where: { $0.id == category.id }) ?? category
    }

    /// Cheap O(N) single-pass counter; feeds `.task(id:)` so the expensive refresh runs
    /// only when relevant transactions change or when the period filter changes.
    private var refreshTrigger: RefreshKey {
        var n = 0
        for tx in transactionStore.transactions where tx.category == liveCategory.name {
            n += 1
        }
        return RefreshKey(
            count: n,
            filterHash: timeFilterManager.currentFilter.hashValue,
            budgetAmount: liveCategory.budgetAmount ?? -1
        )
    }

    /// Combined equatable trigger — changes when transactions matching this category
    /// change, when the global period filter changes, or when the budget amount changes.
    private struct RefreshKey: Equatable {
        let count: Int
        let filterHash: Int
        let budgetAmount: Double
    }

    private func refreshData() async {
        let name = liveCategory.name
        let filtered = transactionStore.transactions
            .filter { $0.category == name }
            .sorted { $0.date > $1.date }
        cachedTransactions = filtered

        let range = timeFilterManager.currentFilter.dateRange()
        aggregates = CategoryAggregatesCalculator.compute(
            categoryName: name,
            periodStart: range.start,
            periodEnd: range.end,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            transactions: transactionStore.transactions
        )
    }

    var body: some View {
        let accountsById = Dictionary(
            uniqueKeysWithValues: transactionsViewModel.accounts.map { ($0.id, $0) }
        )
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency

        EntityDetailScaffold(
            navigationTitle: liveCategory.name,
            navigationAmount: aggregates.amountInPeriod,
            navigationCurrency: baseCurrency,
            primaryAction: ActionConfig(
                title: String(localized: "category.detail.actions.addTransaction", defaultValue: "Add transaction"),
                systemImage: "plus",
                action: { showingAddTransaction = true }
            ),
            infoRows: infoRowConfigs(),
            transactions: cachedTransactions,
            historyCurrency: baseCurrency,
            accountsById: accountsById,
            styleHelper: { tx in
                CategoryStyleHelper.cached(
                    category: tx.category,
                    type: tx.type,
                    customCategories: categoriesViewModel.customCategories
                )
            },
            viewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: accountsViewModel.balanceCoordinator,
            hero: {
                HeroSection(
                    icon: liveCategory.iconSource,
                    title: liveCategory.name,
                    primaryAmount: aggregates.amountInPeriod,
                    primaryCurrency: baseCurrency,
                    subtitle: timeFilterManager.currentFilter.displayName,
                    progress: budgetProgress()
                )
            },
            toolbarMenu: { toolbarMenu }
        )
        .sheet(isPresented: $showingEdit) {
            CategoryEditView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel,
                category: liveCategory,
                type: liveCategory.type,
                onSave: { updatedCategory in
                    HapticManager.success()
                    categoriesViewModel.updateCategory(updatedCategory)
                    transactionsViewModel.invalidateCaches()
                    showingEdit = false
                },
                onCancel: { showingEdit = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showingAddTransaction) {
            // Push the category picker into the navigation stack so the entry point
            // matches the Transfer flow (also a navigationDestination) — back-navigation
            // via swipe/back-button replaces the modal Cancel button.
            TransactionCategoryPickerView(
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel,
                transactionStore: transactionStore,
                timeFilterManager: timeFilterManager
            )
            .environment(timeFilterManager)
            .navigationTitle(String(localized: "category.detail.actions.addTransaction", defaultValue: "Add transaction"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $showingSubcategories) {
            CategorySubcategoriesView(
                categoriesViewModel: categoriesViewModel,
                category: liveCategory
            )
        }
        .confirmationDialog(
            String(localized: "category.deleteTitle", defaultValue: "Delete category?"),
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "category.deleteOnlyCategory", defaultValue: "Delete category only"),
                role: .destructive
            ) {
                performDelete(deleteTransactions: false)
            }
            Button(
                String(localized: "category.deleteCategoryAndTransactions", defaultValue: "Delete category and transactions"),
                role: .destructive
            ) {
                performDelete(deleteTransactions: true)
            }
            Button(String(localized: "button.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(format: String(localized: "category.deleteMessage"), liveCategory.name))
        }
        .task(id: refreshTrigger) {
            await refreshData()
        }
    }

    // MARK: - Delete

    private func performDelete(deleteTransactions: Bool) {
        HapticManager.warning()
        let target = liveCategory

        if deleteTransactions {
            let categoryName = target.name
            let categoryType = target.type
            guard let store = transactionsViewModel.transactionStore else {
                categoryDetailLogger.error("transactionStore nil — cannot delete transactions for category")
                categoriesViewModel.deleteCategory(target, deleteTransactions: true)
                dismiss()
                return
            }
            Task {
                await store.deleteTransactions(forCategoryName: categoryName, type: categoryType)
                categoriesViewModel.deleteCategory(target, deleteTransactions: true)
                transactionsViewModel.recalculateAccountBalances()
                transactionsViewModel.clearAndRebuildAggregateCache()
            }
        } else {
            categoriesViewModel.deleteCategory(target, deleteTransactions: false)
            transactionsViewModel.clearAndRebuildAggregateCache()
        }

        dismiss()
    }

    // MARK: - Budget progress

    private func budgetProgress() -> ProgressConfig? {
        guard liveCategory.type == .expense else { return nil }
        guard let budget = liveCategory.budgetAmount, budget > 0 else { return nil }
        let utilization = aggregates.amountInPeriod / budget
        return ProgressConfig(
            current: aggregates.amountInPeriod,
            total: budget,
            label: String(localized: "category.detail.budget", defaultValue: "Budget"),
            color: budgetColor(for: utilization)
        )
    }

    private func budgetColor(for utilization: Double) -> Color {
        if utilization <= 0.75 { return .green }
        if utilization <= 1.0 { return .orange }
        return .red
    }

    // MARK: - Info rows

    private func infoRowConfigs() -> [InfoRowConfig] {
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        var rows: [InfoRowConfig] = []

        // Type
        let typeLabel = liveCategory.type == .expense
            ? String(localized: "category.detail.type.expense", defaultValue: "Expense")
            : String(localized: "category.detail.type.income", defaultValue: "Income")
        rows.append(InfoRowConfig(
            icon: liveCategory.type == .expense ? "arrow.up.circle" : "arrow.down.circle",
            label: String(localized: "accounts.type", defaultValue: "Type"),
            value: typeLabel
        ))

        // Budget (expense only, when set)
        if liveCategory.type == .expense, let budget = liveCategory.budgetAmount, budget > 0 {
            let spent = Formatting.formatCurrency(aggregates.amountInPeriod, currency: baseCurrency)
            let total = Formatting.formatCurrency(budget, currency: baseCurrency)
            let pct = Int((min(max(aggregates.amountInPeriod / budget, 0), 1) * 100).rounded())
            rows.append(InfoRowConfig(
                icon: "chart.pie",
                label: String(localized: "category.detail.budget", defaultValue: "Budget"),
                value: "\(spent) / \(total) (\(pct)%)"
            ))
        }

        // Avg monthly (last 6 months)
        rows.append(InfoRowConfig(
            icon: "calendar",
            label: String(localized: "category.detail.avgMonthly", defaultValue: "Avg. per month"),
            value: Formatting.formatCurrency(aggregates.avgMonthlyLast6, currency: baseCurrency)
        ))

        // Total amount, all time
        let totalLabel = liveCategory.type == .expense
            ? String(localized: "category.detail.totalSpent", defaultValue: "Total spent")
            : String(localized: "category.detail.totalEarned", defaultValue: "Total earned")
        rows.append(InfoRowConfig(
            icon: "sum",
            label: totalLabel,
            value: Formatting.formatCurrency(aggregates.amountAllTime, currency: baseCurrency)
        ))

        return rows
    }

    // MARK: - Toolbar menu

    @ViewBuilder
    private var toolbarMenu: some View {
        Button {
            showingEdit = true
        } label: {
            Label(String(localized: "common.edit", defaultValue: "Edit"), systemImage: "pencil")
        }

        Button {
            showingSubcategories = true
        } label: {
            Label(
                String(localized: "category.detail.manageSubcategories", defaultValue: "Manage subcategories"),
                systemImage: "tag.fill"
            )
        }

        Divider()

        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            Label(String(localized: "common.delete", defaultValue: "Delete"), systemImage: "trash")
        }
    }
}


// MARK: - Previews

#Preview("Category Detail View") {
    let coordinator = AppCoordinator()
    let timeFilterManager = TimeFilterManager()
    let sampleCategory = coordinator.categoriesViewModel.customCategories.first(where: { $0.type == .expense })
        ?? CustomCategory(
            name: "Groceries",
            iconSource: .sfSymbol("cart.fill"),
            colorHex: "#34C759",
            type: .expense,
            budgetAmount: 120_000
        )

    NavigationStack {
        CategoryDetailView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            category: sampleCategory
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(timeFilterManager)
    }
}
