//
//  HistoryView.swift
//  Tenra
//
//  Created on 2024
//  Optimized on 2026-01-27 (Phase 2: Decomposition)
//  Task 10 (2026-02-23): Wired to TransactionPaginationController (FRC-based)
//

import SwiftUI
import os

private let historyLogger = Logger(subsystem: "Tenra", category: "HistoryView")

struct HistoryView: View {
    // MARK: - Dependencies

    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    /// FRC-based pagination controller (read-only, set from AppCoordinator).
    let paginationController: TransactionPaginationController
    @Environment(TimeFilterManager.self) private var timeFilterManager

    // MARK: - Managers

    @State private var filterCoordinator = HistoryFilterCoordinator()
    @State private var expensesCache = DateSectionExpensesCache()

    // MARK: - State

    @State private var showingTimeFilter = false

    /// Guards the HistoryTransactionsList from rendering until onAppear has applied the
    /// current time-filter to the FRC.  Without this guard SwiftUI would construct the
    /// List with all 3,530 unfiltered sections, causing a 10-12 second UI freeze before
    /// the filtered 361-section view could be shown.
    ///
    /// The flag resets automatically because NavigationStack creates a new HistoryView
    /// instance on each push — @State properties start fresh on every navigation.
    @State private var isHistoryListReady = false

    // MARK: - Initial Filters

    let initialCategory: String?
    let initialAccountId: String?

    // MARK: - Localized Keys

    private let todayKey = String(localized: "date.today")
    private let yesterdayKey = String(localized: "date.yesterday")
    private let searchPrompt = String(localized: "search.placeholder")

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        accountsViewModel: AccountsViewModel,
        categoriesViewModel: CategoriesViewModel,
        paginationController: TransactionPaginationController,
        initialCategory: String? = nil,
        initialAccountId: String? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.accountsViewModel = accountsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.paginationController = paginationController
        self.initialCategory = initialCategory
        self.initialAccountId = initialAccountId
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isHistoryListReady {
                HistoryTransactionsList(
                    paginationController: paginationController,
                    expensesCache: expensesCache,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    debouncedSearchText: filterCoordinator.debouncedSearchText,
                    selectedAccountFilter: filterCoordinator.selectedAccountFilter,
                    todayKey: todayKey,
                    yesterdayKey: yesterdayKey
                )
            }
        }
        .safeAreaBar(edge: .top) {
            HistoryFilterSection(
                timeFilterDisplayName: timeFilterManager.currentFilter.displayName,
                accounts: accountsViewModel.accounts,
                selectedCategories: transactionsViewModel.selectedCategories,
                customCategories: categoriesViewModel.customCategories,
                incomeCategories: transactionsViewModel.incomeCategories,
                selectedAccountFilter: $filterCoordinator.selectedAccountFilter,
                showingAccountFilter: $filterCoordinator.showingAccountFilter,
                showingCategoryFilter: $filterCoordinator.showingCategoryFilter,
                onTimeFilterTap: { showingTimeFilter = true },
                balanceCoordinator: accountsViewModel.balanceCoordinator
            )
        }
        .navigationTitle(String(localized: "navigation.history"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $filterCoordinator.searchText,
            isPresented: $filterCoordinator.isSearchActive,
            prompt: searchPrompt
        )
        .onAppear {
            handleOnAppear()
        }
        .onChange(of: timeFilterManager.currentFilter) { _, _ in
            HapticManager.selection()
            applyFiltersToController()
        }
        .onChange(of: filterCoordinator.selectedAccountFilter) { _, _ in
            filterCoordinator.applyAccountFilter()
            applyFiltersToController()
        }
        .onChange(of: filterCoordinator.searchText) { _, newValue in
            filterCoordinator.applySearch(newValue)
        }
        .onChange(of: filterCoordinator.debouncedSearchText) { _, _ in
            applyFiltersToController()
        }
        .onChange(of: transactionsViewModel.accounts) { _, _ in
            applyFiltersToController()
        }
        .onChange(of: transactionsViewModel.selectedCategories) { _, _ in
            filterCoordinator.applyCategoryFilterChange()
            applyFiltersToController()
        }
        .onChange(of: transactionsViewModel.allTransactions) { _, _ in
            expensesCache.invalidate()
        }
        .onChange(of: transactionsViewModel.appSettings.baseCurrency) { _, _ in
            expensesCache.invalidate()
        }
        .onChange(of: paginationController.sections.count) { oldCount, newCount in
            historyLogger.debug("🔄 [History] sections.count: \(oldCount)→\(newCount) (totalCount:\(self.paginationController.totalCount))")
        }
        .onDisappear {
            resetFilters()
        }
        .sheet(isPresented: $filterCoordinator.showingCategoryFilter) {
            CategoryFilterView(
                expenseCategories: transactionsViewModel.expenseCategories,
                incomeCategories: transactionsViewModel.incomeCategories,
                customCategories: categoriesViewModel.customCategories,
                currentFilter: transactionsViewModel.selectedCategories,
                onFilterChanged: { newFilter in
                    transactionsViewModel.selectedCategories = newFilter
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTimeFilter) {
            TimeFilterView(filterManager: timeFilterManager)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $filterCoordinator.showingAccountFilter) {
            AccountFilterView(
                accounts: accountsViewModel.accounts,
                selectedAccountId: $filterCoordinator.selectedAccountFilter,
                balanceCoordinator: accountsViewModel.balanceCoordinator
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Private Methods

    private func setupInitialFilters() {
        if let category = initialCategory {
            historyLogger.debug("🎯 [History] setupInitialFilters — setting category: \(category)")
            transactionsViewModel.selectedCategories = [category]
        } else {
            historyLogger.debug("🎯 [History] setupInitialFilters — clearing categories (initialCategory is nil)")
            transactionsViewModel.selectedCategories = nil
        }
    }

    private func handleOnAppear() {
        setupInitialFilters()
        let t0 = CACurrentMediaTime()
        let sectionCount = paginationController.sections.count
        let totalCount = paginationController.totalCount
        // 📌 KEY: The gap between [HistoryList] body log and this onAppear log
        //    = time SwiftUI spent constructing/rendering the initial List.
        //    If sections.count here != sections.count in [HistoryList] body, the
        //    filter was applied mid-render (unusual). If it matches, the freeze
        //    is the time from body-log to this log.
        historyLogger.debug("👁️  [History] onAppear — FRC sections:\(sectionCount) totalCount:\(totalCount) allTx:\(self.transactionsViewModel.allTransactions.count) t:\(String(format: "%.3f", t0))")
        if sectionCount == 0 {
            historyLogger.debug("⚠️  [History] onAppear — paginationController has NO sections yet (FRC not ready or empty db)")
        }

        PerformanceProfiler.start("HistoryView.onAppear")

        // Set initial account filter
        filterCoordinator.setInitialAccountFilter(initialAccountId)

        // Sync debounced search with current search
        filterCoordinator.debouncedSearchText = filterCoordinator.searchText

        // Apply current filters to the FRC controller
        applyFiltersToController()

        // Filter is now applied (e.g., 361 sections for "This Year").
        // Setting this flag tells the body to swap Color.clear for HistoryTransactionsList.
        // SwiftUI will render the filtered list on the very next frame — no 3,530-section freeze.
        isHistoryListReady = true

        let t1 = CACurrentMediaTime()
        historyLogger.debug("👁️  [History] onAppear DONE in \(String(format: "%.0f", (t1-t0)*1000))ms — sections now:\(self.paginationController.sections.count) isReady:true")

        PerformanceProfiler.end("HistoryView.onAppear")
    }

    /// Forwards current filter state to the FRC-based pagination controller.
    /// The FRC handles predicate updates and triggers `controllerDidChangeContent`
    /// which rebuilds `sections` — no manual grouping/sorting needed.
    ///
    /// Uses batchUpdateFilters() to apply all four filter values atomically,
    /// preventing 4× redundant rebuildSections() calls.
    private func applyFiltersToController() {
        let t0 = CACurrentMediaTime()
        PerformanceProfiler.start("HistoryView.applyFiltersToController")

        let hasFilters = filterCoordinator.selectedAccountFilter != nil ||
                        !filterCoordinator.debouncedSearchText.isEmpty ||
                        transactionsViewModel.selectedCategories != nil
        historyLogger.debug("🔎 [History] applyFiltersToController — hasFilters:\(hasFilters) search:'\(self.filterCoordinator.debouncedSearchText)' account:\(self.filterCoordinator.selectedAccountFilter ?? "nil") category:\(self.transactionsViewModel.selectedCategories?.first ?? "nil")")

        // Resolve date range — allTime maps to a sentinel range that is functionally
        // equivalent to no predicate (nil), so we pass nil in that case.
        let timeFilter = timeFilterManager.currentFilter
        let resolvedDateRange: (start: Date, end: Date)?
        if timeFilter.preset == .allTime {
            resolvedDateRange = nil
        } else {
            let range = timeFilter.dateRange()
            resolvedDateRange = (start: range.start, end: range.end)
        }
        historyLogger.debug("🔎 [History] timeFilter=.\(timeFilter.preset.rawValue) resolvedDateRange=\(resolvedDateRange != nil ? "set" : "nil→allTime(no predicate)")")

        // Single atomic update — triggers exactly one performFetch + rebuildSections
        // instead of four (one per property assignment).
        paginationController.batchUpdateFilters(
            searchQuery: filterCoordinator.debouncedSearchText,
            selectedAccountId: .some(filterCoordinator.selectedAccountFilter),
            selectedCategoryId: .some(transactionsViewModel.selectedCategories?.first),
            dateRange: .some(resolvedDateRange)
        )

        let t1 = CACurrentMediaTime()
        historyLogger.debug("🔎 [History] applyFiltersToController DONE in \(String(format: "%.0f", (t1-t0)*1000))ms — sections:\(self.paginationController.sections.count)")

        PerformanceProfiler.end("HistoryView.applyFiltersToController")
    }

    private func resetFilters() {
        historyLogger.debug("🔁 [History] resetFilters() (onDisappear) — clearing user filters (keeping dateRange)")
        filterCoordinator.reset()
        transactionsViewModel.selectedCategories = nil
        // Clear user-driven filters (search, account, category, type) but NOT dateRange.
        // dateRange is always re-derived from timeFilterManager.currentFilter in the
        // next handleOnAppear() → applyFiltersToController().  Keeping it here means:
        //   • FRC retains the filtered set (~361 sections) instead of resetting to 18k/3530
        //   • The 17ms full-table re-fetch on every disappear is eliminated
        //   • On the next open the predicate deduplication guard skips the fetch entirely
        //     (if the time filter hasn't changed), so History opens in 0ms additional work
        paginationController.batchUpdateFilters(
            searchQuery: "",
            selectedAccountId: .some(nil),
            selectedCategoryId: .some(nil),
            selectedType: .some(nil)
            // dateRange: intentionally NOT reset — see comment above
        )
    }
}

// MARK: - Previews

#Preview("History View") {
    let coordinator = AppCoordinator()
    NavigationStack {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            paginationController: coordinator.transactionPaginationController
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Deep Link — Category") {
    let coordinator = AppCoordinator()
    NavigationStack {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            paginationController: coordinator.transactionPaginationController,
            initialCategory: coordinator.categoriesViewModel.customCategories.first?.name
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Deep Link — Account") {
    let coordinator = AppCoordinator()
    NavigationStack {
        HistoryView(
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            paginationController: coordinator.transactionPaginationController,
            initialAccountId: coordinator.accountsViewModel.accounts.first?.id
        )
        .environment(TimeFilterManager())
    }
}
