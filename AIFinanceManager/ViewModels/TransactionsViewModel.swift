//
//  TransactionsViewModel.swift
//  AIFinanceManager
//
//  Phase 2 Refactoring Complete: 2026-02-01
//  Reduction: 1,501 → ~600 lines (-60%)
//

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class TransactionsViewModel {

    // MARK: - Observable State (UI Bindings)

    // MARK: - Phase 16: Computed Properties from TransactionStore (Single Source of Truth)
    // These are no longer stored arrays — they read directly from TransactionStore
    // eliminating O(N) array copies on every mutation.

    /// All transactions — reads directly from TransactionStore (SSOT)
    /// Setter is a no-op legacy compatibility shim — prefer direct TransactionStore mutations
    var allTransactions: [Transaction] {
        get { transactionStore?.transactions ?? [] }
        set {
            // No-op: legacy compatibility path — all mutations go through TransactionStore
        }
    }

    /// Display transactions — same as allTransactions (no separate filtering)
    var displayTransactions: [Transaction] {
        transactionStore?.transactions ?? []
    }

    var categoryRules: [CategoryRule] = []

    /// Accounts — reads directly from TransactionStore (SSOT)
    var accounts: [Account] {
        transactionStore?.accounts ?? []
    }

    /// Categories — reads directly from TransactionStore (SSOT)
    var customCategories: [CustomCategory] {
        transactionStore?.categories ?? []
    }

    /// ✨ Phase 9: Now computed property delegating to TransactionStore (Single Source of Truth)
    /// This eliminates data duplication and manual synchronization
    var recurringSeries: [RecurringSeries] {
        transactionStore?.recurringSeries ?? []
    }

    var recurringOccurrences: [RecurringOccurrence] = []
    var subcategories: [Subcategory] = []
    var categorySubcategoryLinks: [CategorySubcategoryLink] = []
    var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []
    var selectedCategories: Set<String>? = nil
    var isLoading = false
    var errorMessage: String?
    var currencyConversionWarning: String? = nil
    var appSettings: AppSettings = AppSettings.load()
    var hasOlderTransactions: Bool = false

    // MIGRATED: initialAccountBalances moved to BalanceCoordinator
    // MIGRATED: accountsWithCalculatedInitialBalance moved to BalanceCoordinator (calculation modes)
    var displayMonthsRange: Int = 120  // 10 years - increased from 6 to support historical data imports

    // MARK: - Dependencies (Injected)

    @ObservationIgnored let repository: DataRepositoryProtocol
    // MIGRATED: accountBalanceService removed - using BalanceCoordinator instead
    // MIGRATED: balanceCalculationService removed - using BalanceCoordinator instead

    // ✨ Phase 9: Removed subscriptionsViewModel - recurring operations now in TransactionStore

    /// REFACTORED 2026-02-02: BalanceCoordinator as Single Source of Truth for balances
    /// Injected by AppCoordinator - replaces old TransactionBalanceCoordinator
    @ObservationIgnored var balanceCoordinator: BalanceCoordinator?

    /// Phase 8: TransactionStore as Single Source of Truth for all transaction operations
    /// ✨ Phase 9: Now includes recurring operations (subscriptions + recurring transactions)
    /// Replaces legacy CRUD services, cache managers, and coordinators
    @ObservationIgnored var transactionStore: TransactionStore?

    // MARK: - Services (Remaining)

    @ObservationIgnored let currencyService = TransactionCurrencyService()

    /// Phase 8: Minimal cache for read-only display operations
    /// Write operations handled by TransactionStore + UnifiedTransactionCache
    @ObservationIgnored let cacheManager = TransactionCacheManager()

    // MARK: - Services (initialized eagerly for @Observable compatibility)

    @ObservationIgnored let filterCoordinator: TransactionFilterCoordinatorProtocol
    @ObservationIgnored let queryService: TransactionQueryServiceProtocol
    @ObservationIgnored let groupingService: TransactionGroupingService

    // MARK: - Batch Mode for Performance

    var isBatchMode = false
    var pendingBalanceRecalculation = false
    var pendingSave = false

    // MARK: - Notification Processing Guard

    private var isProcessingRecurringNotification = false
    private var isDataLoaded = false

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository

        // Initialize services (required for @Observable compatibility)
        let filterService = TransactionFilterService(dateFormatter: DateFormatters.dateFormatter)
        self.filterCoordinator = TransactionFilterCoordinator(filterService: filterService, dateFormatter: DateFormatters.dateFormatter)
        self.queryService = TransactionQueryService()
        self.groupingService = TransactionGroupingService(
            dateFormatter: DateFormatters.dateFormatter,
            displayDateFormatter: DateFormatters.displayDateFormatter,
            displayDateWithYearFormatter: DateFormatters.displayDateWithYearFormatter,
            cacheManager: cacheManager
        )

        setupRecurringSeriesObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupRecurringSeriesObserver() {
        // Listen for NEW recurring series created
        NotificationCenter.default.addObserver(
            forName: .recurringSeriesCreated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, let _ = notification.userInfo?["seriesId"] as? String else { return }

                guard !self.isProcessingRecurringNotification else { return }

                self.isProcessingRecurringNotification = true
                defer { self.isProcessingRecurringNotification = false }

                // Recurring generation is handled by TransactionStore — no action needed here.
                // TransactionStore.createSeries() already generates transactions.
                self.rebuildIndexes()
            }
        }

        // Listen for UPDATED recurring series
        NotificationCenter.default.addObserver(
            forName: .recurringSeriesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self, let _ = notification.userInfo?["seriesId"] as? String else { return }
                guard !self.isProcessingRecurringNotification else { return }

                self.isProcessingRecurringNotification = true
                defer { self.isProcessingRecurringNotification = false }

                // Recurring generation is handled by TransactionStore — no action needed here.
                // TransactionStore.updateSeries() already regenerates transactions.
            }
        }
    }

    // MARK: - Data Loading (CONCURRENT)

    func loadDataAsync() async {
        guard !isDataLoaded else { return }
        isDataLoaded = true
        PerformanceProfiler.start("TransactionsViewModel.loadDataAsync")

        await MainActor.run { isLoading = true }

        // PERFORMANCE OPTIMIZATION: Concurrent loading (Phase 2)
        // Phase 8: Storage loading handled by TransactionStore
        await generateRecurringAsync()
        await loadAggregateCacheAsync()

        await MainActor.run { isLoading = false }
        PerformanceProfiler.end("TransactionsViewModel.loadDataAsync")
    }

    /// Generate recurring transactions asynchronously (Phase 2)
    private func generateRecurringAsync() async {
        await MainActor.run {
            self.generateRecurringTransactions()
        }
    }

    /// Load aggregate cache asynchronously
    /// Phase 8: Aggregate caching handled by TransactionStore
    private func loadAggregateCacheAsync() async {
        // Phase 8: Aggregate caching handled by TransactionStore
        // No action needed
        await MainActor.run {
            cacheManager.invalidateCategoryExpenses()
        }
    }

    // MARK: - CRUD Operations (Delegated to Services)

    func addTransaction(_ transaction: Transaction) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            return
        }

        Task {
            do {
                _ = try await transactionStore.add(transaction)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTransactions(_ newTransactions: [Transaction]) {
        // Phase 17: Use addBatch() instead of individual adds
        // This triggers ONE sync instead of N syncs
        guard let transactionStore = transactionStore else { return }

        Task {
            do {
                try await transactionStore.addBatch(newTransactions)
                rebuildIndexes()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addTransactionsForImport(_ newTransactions: [Transaction]) {
        // Phase 8: Import via TransactionStore
        guard let transactionStore = transactionStore else {
            return
        }

        Task {
            do {
                for transaction in newTransactions {
                    _ = try await transactionStore.add(transaction)
                }
                // Cache and balance updates handled automatically by TransactionStore
                if isBatchMode {
                    pendingBalanceRecalculation = true
                    pendingSave = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateTransaction(_ transaction: Transaction) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            return
        }


        Task {
            do {
                try await transactionStore.update(transaction)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteTransaction(_ transaction: Transaction) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            return
        }

        // CRITICAL: Remove recurring occurrence if linked
        if let occurrenceId = transaction.recurringOccurrenceId {
            recurringOccurrences.removeAll { $0.id == occurrenceId }
        }

        Task {
            do {
                try await transactionStore.delete(transaction)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateTransactionCategory(_ transactionId: String, category: String, subcategory: String?) {
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else { return }

        let newRule = CategoryRule(
            description: transaction.description,
            category: category,
            subcategory: subcategory
        )

        categoryRules.removeAll { $0.description.lowercased() == newRule.description.lowercased() }
        categoryRules.append(newRule)

        // Phase 16: Update transactions via TransactionStore
        guard let store = transactionStore else { return }
        let matchingDescription = newRule.description.lowercased()

        Task {
            for tx in store.transactions where tx.description.lowercased() == matchingDescription {
                let updated = Transaction(
                    id: tx.id,
                    date: tx.date,
                    description: tx.description,
                    amount: tx.amount,
                    currency: tx.currency,
                    convertedAmount: tx.convertedAmount,
                    type: tx.type,
                    category: category,
                    subcategory: subcategory,
                    accountId: tx.accountId,
                    targetAccountId: tx.targetAccountId,
                    targetCurrency: tx.targetCurrency,
                    targetAmount: tx.targetAmount,
                    recurringSeriesId: tx.recurringSeriesId,
                    recurringOccurrenceId: tx.recurringOccurrenceId,
                    createdAt: tx.createdAt
                )
                try? await store.update(updated)
            }
        }
    }

    // MARK: - Account Operations

    func transfer(from sourceId: String, to targetId: String, amount: Double, date: String, description: String) {
        // Phase 8: Delegate to TransactionStore
        guard let transactionStore = transactionStore else {
            return
        }

        guard let sourceIndex = accounts.firstIndex(where: { $0.id == sourceId }) else { return }
        let currency = accounts[sourceIndex].currency

        Task {
            do {
                try await transactionStore.transfer(
                    from: sourceId,
                    to: targetId,
                    amount: amount,
                    currency: currency,
                    date: date,
                    description: description
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Balance Management

    func recalculateAccountBalances() {
        // Recalculate all balances through BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.recalculateAll(accounts: accounts, transactions: allTransactions)
            }
        }
    }

    func scheduleBalanceRecalculation() {
        // CRITICAL: Recalculate all account balances after transaction changes
        // This is called after recurring transaction generation, CSV import, etc.

        if let coordinator = balanceCoordinator {
            Task {

                await coordinator.recalculateAll(
                    accounts: accounts,
                    transactions: allTransactions
                )

            }
        } else {
        }
    }

    func calculateTransactionsBalance(for accountId: String) -> Double {
        // Direct balance access from BalanceCoordinator (O(1))
        return balanceCoordinator?.balances[accountId] ?? 0.0
    }

    func resetAndRecalculateAllBalances() {

        // MIGRATED: Initial balances are already in account.initialBalance
        for account in accounts {
            // Update BalanceCoordinator with initial balance from account
            if let initialBalance = account.initialBalance {
                Task {
                    await balanceCoordinator?.setInitialBalance(initialBalance, for: account.id)
                }
            }
        }

        recalculateAccountBalances()
        saveToStorage()
    }

    // MARK: - Storage

    func saveToStorage() {
        // Phase 8: Persistence handled by TransactionStore automatically
        // This is a backward compatibility stub
    }

    func saveToStorageDebounced() {
        // Phase 8: Persistence handled by TransactionStore automatically
        // This is a backward compatibility stub
    }

    func saveToStorageSync() {
        // Phase 8: Persistence handled by TransactionStore automatically
        // This is a backward compatibility stub
    }

    func loadOlderTransactions() {
        // Phase 8: Loading handled by TransactionStore
        // This is a backward compatibility stub
    }

    /// PHASE 3: DEPRECATED - Accounts are now managed by TransactionStore
    /// AccountsViewModel observes TransactionStore.$accounts instead
    /// This method is kept for backward compatibility but does nothing
    func syncAccountsFrom(_ accountsViewModel: AccountsViewModel) {
        // Phase 16: Accounts are computed from TransactionStore — no manual sync needed
    }

    /// Setup reference to CategoriesViewModel (Single Source of Truth)
    /// Call this from AppCoordinator after both ViewModels are initialized
    /// - Parameter categoriesViewModel: The single source of truth for categories
    /// NOTE: With @Observable, we sync directly instead of using Combine publishers
    func setCategoriesViewModel(_ categoriesViewModel: CategoriesViewModel) {
        // Phase 16: customCategories is now a computed property from TransactionStore
        // No manual sync needed — @Observable handles change notifications automatically
    }

    // MARK: - Data Management

    func clearHistory() {
        categoryRules = []
        // Phase 16: Transactions and accounts are managed by TransactionStore
        repository.clearAllData()
    }

    func resetAllData() {
        categoryRules = []
        recurringOccurrences = []
        subcategories = []
        categorySubcategoryLinks = []
        transactionSubcategoryLinks = []
        selectedCategories = nil
        // Phase 16: All data arrays (transactions, accounts, categories) are now
        // computed properties from TransactionStore — clearing via repository
        repository.clearAllData()
    }

    // MARK: - Helpers

    func insertTransactionsSorted(_ newTransactions: [Transaction]) {
        // Phase 16: Transactions are managed by TransactionStore
        // New transactions should be added via TransactionStore.addBatch()
        guard !newTransactions.isEmpty, let store = transactionStore else { return }
        Task {
            try? await store.addBatch(newTransactions)
        }
    }

    func getSubcategoriesForTransaction(_ transactionId: String) -> [Subcategory] {
        let linkedSubcategoryIds = cacheManager.getSubcategoryIds(for: transactionId)
        return subcategories.filter { linkedSubcategoryIds.contains($0.id) }
    }

    func getCategory(name: String, type: TransactionType) -> CustomCategory? {
        customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    func cleanupDeletedAccount(_ accountId: String) {
        // MIGRATED: BalanceCoordinator handles account removal
        Task {
            await balanceCoordinator?.removeAccount(accountId)
        }
    }

    func rebuildIndexes() {
        cacheManager.rebuildIndexes(transactions: allTransactions)
        cacheManager.buildSubcategoryIndex(links: transactionSubcategoryLinks)
    }

    func refreshDisplayTransactions() {
        // Phase 16: displayTransactions is now a computed property from TransactionStore
        // This method is kept for backward compatibility but is a no-op
        // hasOlderTransactions is now always false (all transactions are loaded)
        hasOlderTransactions = false
    }

    // MARK: - Batch Operations

    func beginBatch() {
        isBatchMode = true
        pendingBalanceRecalculation = false
        pendingSave = false
    }

    func endBatch() {
        isBatchMode = false

        if pendingBalanceRecalculation {
            recalculateAccountBalances()
            pendingBalanceRecalculation = false
        }

        if pendingSave {
            saveToStorage()
            pendingSave = false
        }

        refreshDisplayTransactions()
    }

    func endBatchWithoutSave() {
        isBatchMode = false

        if pendingBalanceRecalculation {
            recalculateAccountBalances()
            pendingBalanceRecalculation = false
        }

        pendingSave = false
        refreshDisplayTransactions()
    }

    func scheduleSave() {
        if isBatchMode {
            pendingSave = true
        } else {
            saveToStorageDebounced()
        }
    }

    // MARK: - Initial Balance Access (MIGRATED to BalanceCoordinator)

    func getInitialBalance(for accountId: String) -> Double? {
        // MIGRATED: Get from account.initialBalance
        // Note: This method is primarily for backward compatibility
        return accounts.first(where: { $0.id == accountId })?.initialBalance
    }

    func isAccountImported(_ accountId: String) -> Bool {
        // MIGRATED: Check BalanceCoordinator calculation mode
        // Async access not possible here, return false for now (not critical)
        return false
    }

    func resetImportedAccountFlags() {
        // MIGRATED: No longer needed - BalanceCoordinator manages modes
        // This method kept for backward compatibility but does nothing
    }

    // MARK: - Currency Conversion

    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        currencyService.getConvertedAmount(transactionId: transactionId, to: baseCurrency)
    }

    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        currencyService.getConvertedAmountOrCompute(transaction: transaction, to: baseCurrency)
    }

    // MARK: - Private Helpers
    // MIGRATED: clearBalanceFlags removed - balance modes managed by BalanceCoordinator
}

// MARK: - Supporting Types

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
