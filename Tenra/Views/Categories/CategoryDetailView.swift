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
    @State private var showingSubcategoryManager = false
    @State private var showingDeleteConfirm = false
    @State private var showingAddTransaction = false
    @State private var cachedTransactions: [Transaction] = []
    @State private var aggregates = CategoryAggregates(
        amountInPeriod: 0,
        amountAllTime: 0,
        avgMonthlyLast6: 0,
        totalTransactions: 0
    )

    /// Pre-built account lookup. Refreshed only when accounts mutate
    /// (via `accountsMutationVersion`), not on every body re-eval.
    @State private var accountsById: [String: Account] = [:]

    @Environment(\.dismiss) private var dismiss
    @Environment(TimeFilterManager.self) private var timeFilterManager

    /// Live category lookup — reflects edits (e.g. budget changes) without re-navigation.
    /// O(1) via `categoryById`; falls back to the navigation-time snapshot if the
    /// category was deleted while detail is on screen.
    private var liveCategory: CustomCategory {
        transactionStore.categoryById[category.id] ?? category
    }

    /// Combined equatable trigger — changes when transactions mutate, when the
    /// global period filter changes, when the budget amount changes, or when the
    /// FX-rate cache is updated.
    ///
    /// Reads scalar `mutationVersion`/`categoriesMutationVersion`/`currencyRatesVersion`
    /// counters instead of subscribing to the entire 19k transactions array —
    /// the body re-evals only when something actually relevant changed.
    private var refreshTrigger: RefreshKey {
        RefreshKey(
            mutationVersion: transactionStore.mutationVersion,
            categoriesVersion: transactionStore.categoriesMutationVersion,
            ratesVersion: transactionStore.currencyRatesVersion,
            filterHash: timeFilterManager.currentFilter.hashValue,
            categoryId: category.id,
            budgetAmount: liveCategory.budgetAmount ?? -1
        )
    }

    private struct RefreshKey: Equatable {
        let mutationVersion: Int
        let categoriesVersion: Int
        let ratesVersion: Int
        let filterHash: Int
        let categoryId: String
        let budgetAmount: Double
    }

    private func refreshData() async {
        let name = liveCategory.name

        // O(1) lookup via maintained index — no full-array scan.
        let bucket = transactionStore.transactionsByCategoryName[name] ?? []
        cachedTransactions = bucket.sorted { $0.date > $1.date }

        let range = timeFilterManager.currentFilter.dateRange()
        aggregates = CategoryAggregatesCalculator.compute(
            categoryName: name,
            periodStart: range.start,
            periodEnd: range.end,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            store: transactionStore
        )
    }

    var body: some View {
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
            secondaryAction: ActionConfig(
                title: String(localized: "subcategory.reorder", defaultValue: "Subcategories"),
                systemImage: "list.bullet",
                action: { showingSubcategoryManager = true }
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
                    iconTint: .monochrome(liveCategory.color),
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showingAddTransaction) {
            // Category is already known — push the add-transaction form directly
            // with the category preselected, skipping the picker grid.
            TransactionAddModal(
                category: liveCategory.name,
                type: liveCategory.type,
                currency: transactionsViewModel.appSettings.baseCurrency,
                accounts: accountsViewModel.accounts,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel,
                transactionStore: transactionStore,
                onDismiss: { showingAddTransaction = false }
            )
            .environment(timeFilterManager)
        }
        .sheet(isPresented: $showingSubcategoryManager) {
            SubcategoryReorderView(
                categoriesViewModel: categoriesViewModel,
                categoryId: liveCategory.id
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        .task(id: transactionStore.accountsMutationVersion) {
            accountsById = Dictionary(uniqueKeysWithValues: transactionStore.accounts.map { ($0.id, $0) })
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
        guard let total = scaledBudgetTotal() else { return nil }
        let utilization = total > 0 ? aggregates.amountInPeriod / total : 0
        // label intentionally nil — the budget % is already shown in the info rows,
        // so rendering it under the hero would duplicate it. The ring still shows.
        return ProgressConfig(
            current: aggregates.amountInPeriod,
            total: total,
            label: nil,
            color: budgetColor(for: utilization)
        )
    }

    private func budgetColor(for utilization: Double) -> Color {
        if utilization <= 0.75 { return .green }
        if utilization <= 1.0 { return .orange }
        return .red
    }

    /// The budget limit scaled to the currently selected time-filter period.
    ///
    /// A budget is defined per `budgetPeriod` (weekly / monthly / yearly). When the user
    /// scopes the detail screen to a different period (e.g. "This year"), the limit is
    /// scaled to match so the "spent / limit" comparison stays meaningful. Returns nil
    /// when there's no budget, or for the unbounded "All time" filter where a scaled
    /// limit is meaningless.
    private func scaledBudgetTotal() -> Double? {
        guard liveCategory.type == .expense,
              let budget = liveCategory.budgetAmount, budget > 0 else { return nil }
        let preset = timeFilterManager.currentFilter.preset
        guard preset != .allTime else { return nil }
        return budget * budgetPeriodMultiplier(preset: preset, budgetPeriod: liveCategory.budgetPeriod)
    }

    private func budgetPeriodMultiplier(
        preset: TimeFilterPreset,
        budgetPeriod: CustomCategory.BudgetPeriod
    ) -> Double {
        // Exact multipliers when the selected range aligns with the budget unit —
        // avoids the day-count drift that would make "This month" read e.g. 101.8%.
        switch (budgetPeriod, preset) {
        case (.monthly, .thisMonth), (.monthly, .lastMonth): return 1
        case (.monthly, .thisYear), (.monthly, .lastYear): return 12
        case (.weekly, .thisWeek): return 1
        case (.yearly, .thisYear), (.yearly, .lastYear): return 1
        default: break
        }
        // Otherwise scale by the ratio of days in the selected range to days in the
        // budget unit (e.g. weekly budget viewed over "This year").
        let range = timeFilterManager.currentFilter.dateRange()
        let periodDays = max(range.end.timeIntervalSince(range.start) / 86_400, 1)
        let budgetPeriodDays: Double
        switch budgetPeriod {
        case .weekly: budgetPeriodDays = 7
        case .monthly: budgetPeriodDays = 30.4375
        case .yearly: budgetPeriodDays = 365.25
        }
        return periodDays / budgetPeriodDays
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

        // Budget (expense only, when set) — scaled to the selected period.
        if let budgetTotal = scaledBudgetTotal() {
            let spent = Formatting.formatCurrencySmart(aggregates.amountInPeriod, currency: baseCurrency)
            let total = Formatting.formatCurrencySmart(budgetTotal, currency: baseCurrency)
            let pct = Int((min(max(aggregates.amountInPeriod / budgetTotal, 0), 1) * 100).rounded())
            let spentAmount = aggregates.amountInPeriod
            rows.append(InfoRowConfig(
                icon: "chart.pie",
                label: String(localized: "category.detail.budget", defaultValue: "Budget"),
                value: "\(spent) / \(total) (\(pct)%)",
                valueContent: AnyView(
                    HStack(spacing: AppSpacing.xxs) {
                        FormattedAmountText(
                            amount: spentAmount,
                            currency: baseCurrency,
                            fontSize: AppTypography.bodyEmphasis,
                            fontWeight: .semibold,
                            color: AppColors.textPrimary
                        )
                        Text("/")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.textTertiary)
                        FormattedAmountText(
                            amount: budgetTotal,
                            currency: baseCurrency,
                            fontSize: AppTypography.bodyEmphasis,
                            fontWeight: .semibold,
                            color: AppColors.textPrimary
                        )
                        Text("(\(pct)%)")
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                )
            ))
        }

        // Avg monthly (last 6 months)
        rows.append(InfoRowConfig(
            icon: "calendar",
            label: String(localized: "category.detail.avgMonthly", defaultValue: "Avg. per month"),
            amount: aggregates.avgMonthlyLast6,
            currency: baseCurrency
        ))

        // Total amount, all time
        let totalLabel = liveCategory.type == .expense
            ? String(localized: "category.detail.totalSpent", defaultValue: "Total spent")
            : String(localized: "category.detail.totalEarned", defaultValue: "Total earned")
        rows.append(InfoRowConfig(
            icon: "sum",
            label: totalLabel,
            amount: aggregates.amountAllTime,
            currency: baseCurrency
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
