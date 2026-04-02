//
//  TransactionsViewModel+Queries.swift
//  AIFinanceManager
//
//  Query, filtering, and cache management extracted from TransactionsViewModel.
//  Phase C: File split for maintainability.
//

import Foundation

// MARK: - Queries (Delegated to QueryService)

extension TransactionsViewModel {

    func summary(timeFilterManager: TimeFilterManager) -> Summary {
        let filtered = filterCoordinator.filterByTime(
            transactions: allTransactions,
            timeFilter: timeFilterManager.currentFilter
        )

        // IMPORTANT: Always invalidate summary cache because time filtering produces different results
        // The cache doesn't account for time filters, so we need fresh calculation each time
        cacheManager.summaryCacheInvalidated = true

        let result = queryService.calculateSummary(
            transactions: filtered,
            baseCurrency: appSettings.baseCurrency,
            cacheManager: cacheManager,
            currencyService: currencyService
        )

        // ✅ FIX: Don't restore invalidation state
        // calculateSummary() already sets it to false after computing the new summary
        // Restoring the old state was breaking the invalidation flow when transactions changed

        return result
    }

    func categoryExpenses(
        timeFilterManager: TimeFilterManager,
        categoriesViewModel: CategoriesViewModel? = nil
    ) -> [String: CategoryExpense] {
        let validCategoryNames: Set<String>? = categoriesViewModel.map { vm in
            Set(vm.customCategories.map { $0.name })
        }

        // Phase 40: All transactions in memory — always compute directly from allTransactions.
        let filter = timeFilterManager.currentFilter
        let result = queryService.getCategoryExpenses(
            timeFilter: filter,
            baseCurrency: appSettings.baseCurrency,
            validCategoryNames: validCategoryNames,
            cacheManager: cacheManager,
            transactions: allTransactions,
            currencyService: currencyService
        )

        return result
    }

    func popularCategories(
        timeFilterManager: TimeFilterManager,
        categoriesViewModel: CategoriesViewModel? = nil
    ) -> [String] {
        let expenses = categoryExpenses(
            timeFilterManager: timeFilterManager,
            categoriesViewModel: categoriesViewModel
        )
        return queryService.getPopularCategories(expenses: expenses)
    }

    var uniqueCategories: [String] {
        queryService.getUniqueCategories(transactions: allTransactions, cacheManager: cacheManager)
    }

    var expenseCategories: [String] {
        queryService.getExpenseCategories(transactions: allTransactions, cacheManager: cacheManager)
    }

    var incomeCategories: [String] {
        queryService.getIncomeCategories(transactions: allTransactions, cacheManager: cacheManager)
    }

    // MARK: - Filtering (Delegated to FilterCoordinator)

    var filteredTransactions: [Transaction] {
        filterCoordinator.getFiltered(
            transactions: allTransactions,
            selectedCategories: selectedCategories,
            recurringSeries: recurringSeries
        )
    }

    func transactionsFilteredByTime(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        filterCoordinator.filterByTime(transactions: allTransactions, timeFilter: timeFilterManager.currentFilter)
    }

    func transactionsFilteredByTimeAndCategory(_ timeFilterManager: TimeFilterManager) -> [Transaction] {
        filterCoordinator.filterByTimeAndCategory(
            transactions: allTransactions,
            timeFilter: timeFilterManager.currentFilter,
            categories: selectedCategories,
            series: recurringSeries
        )
    }

    func filterTransactionsForHistory(
        timeFilterManager: TimeFilterManager,
        accountId: String?,
        searchText: String
    ) -> [Transaction] {
        let transactions = transactionsFilteredByTimeAndCategory(timeFilterManager)

        return filterCoordinator.filterForHistory(
            transactions: transactions,
            accountId: accountId,
            searchText: searchText,
            accounts: accounts,
            baseCurrency: appSettings.baseCurrency,
            getSubcategories: { [weak self] transactionId in
                self?.getSubcategoriesForTransaction(transactionId) ?? []
            }
        )
    }

    func groupAndSortTransactionsByDate(_ transactions: [Transaction]) -> (grouped: [String: [Transaction]], sortedKeys: [String]) {
        groupingService.groupByDate(transactions)
    }

    // MARK: - Cache Management (Delegated to CacheCoordinator)

    func invalidateCaches() {
        // ✅ Invalidate category expenses cache when transactions change
        // This is a derived cache computed from aggregates, so it must be cleared
        // to reflect the updated aggregate values after incremental updates
        cacheManager.invalidateCategoryExpenses()
    }

    // Phase 21: Stub methods kept for backward compatibility
    func rebuildAggregateCacheAfterImport() async { cacheManager.invalidateAll() }
    func rebuildAggregateCacheInBackground() { cacheManager.invalidateAll() }
    func clearAndRebuildAggregateCache() { cacheManager.invalidateAll() }
    func precomputeCurrencyConversions() { /* No-op */ }
}
