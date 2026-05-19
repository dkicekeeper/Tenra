//
//  TransactionsViewModel.swift
//  Tenra
//

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class TransactionsViewModel {

    // MARK: - Observable State (UI Bindings)

    /// All transactions — reads directly from TransactionStore.
    /// Setter is a no-op — all mutations go through TransactionStore.
    var allTransactions: [Transaction] {
        get { transactionStore?.transactions ?? [] }
        set { }
    }

    /// Display transactions — same as allTransactions
    var displayTransactions: [Transaction] {
        transactionStore?.transactions ?? []
    }

    var categoryRules: [CategoryRule] = []

    /// Accounts — reads directly from TransactionStore
    var accounts: [Account] {
        transactionStore?.accounts ?? []
    }

    /// Categories — reads directly from TransactionStore
    var customCategories: [CustomCategory] {
        transactionStore?.categories ?? []
    }

    /// Computed property delegating to TransactionStore (single source of truth)
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

    var displayMonthsRange: Int = 120  // 10 years - increased from 6 to support historical data imports

    // MARK: - Dependencies (Injected)

    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored var balanceCoordinator: BalanceCoordinator?
    @ObservationIgnored var transactionStore: TransactionStore?

    // MARK: - Services (Remaining)

    @ObservationIgnored let currencyService = TransactionCurrencyService()
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

                // Recurring generation is handled by TransactionStore — no action needed here.
                // TransactionStore.createSeries() already generates transactions.
                self.rebuildIndexes()
                self.isProcessingRecurringNotification = false
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
                // Recurring generation is handled by TransactionStore — no action needed here.
                // TransactionStore.updateSeries() already regenerates transactions.
                self.isProcessingRecurringNotification = false
            }
        }
    }

    // MARK: - Data Loading (CONCURRENT)

    func loadDataAsync() async {
        guard !isDataLoaded else { return }
        isDataLoaded = true
        PerformanceProfiler.start("TransactionsViewModel.loadDataAsync")

        isLoading = true

        await generateRecurringAsync()
        await loadAggregateCacheAsync()

        isLoading = false
        PerformanceProfiler.end("TransactionsViewModel.loadDataAsync")
    }

    private func generateRecurringAsync() async {
        self.generateRecurringTransactions()
    }

    private func loadAggregateCacheAsync() async {
        cacheManager.invalidateCategoryExpenses()
    }

    // MARK: - CRUD Operations (Delegated to Services)

    func addTransaction(_ transaction: Transaction) {
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

    /// Backward compatibility stub — persistence handled by TransactionStore
    func saveToStorage() { }

    /// Backward compatibility stub — persistence handled by TransactionStore
    func saveToStorageDebounced() { }

    func saveToStorageSync() { }

    func loadOlderTransactions() { }

    func syncAccountsFrom(_ accountsViewModel: AccountsViewModel) { }

    func setCategoriesViewModel(_ categoriesViewModel: CategoriesViewModel) { }

    // MARK: - Data Management

    func clearHistory() {
        categoryRules = []
        repository.clearAllData()
    }

    func resetAllData() {
        categoryRules = []
        recurringOccurrences = []
        subcategories = []
        categorySubcategoryLinks = []
        transactionSubcategoryLinks = []
        selectedCategories = nil
        repository.clearAllData()
    }

    // MARK: - Helpers

    func insertTransactionsSorted(_ newTransactions: [Transaction]) {
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
        // O(1) via TransactionStore.categoryIdByName, falls back to the legacy
        // linear scan only when the store reference hasn't been wired up yet.
        if let store = transactionStore,
           let id = store.categoryIdByName[name.lowercased()],
           let cat = store.categoryById[id],
           cat.type == type {
            return cat
        }
        return customCategories.first { $0.name.lowercased() == name.lowercased() && $0.type == type }
    }

    func cleanupDeletedAccount(_ accountId: String) {
        Task {
            await balanceCoordinator?.removeAccount(accountId)
        }
    }

    func rebuildIndexes() {
        cacheManager.rebuildIndexes(transactions: allTransactions)
        cacheManager.buildSubcategoryIndex(links: transactionSubcategoryLinks)
    }

    /// Backward compatibility stub — displayTransactions is a computed property from TransactionStore
    func refreshDisplayTransactions() {
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

    // MARK: - Initial Balance Access

    /// Backward compatibility — reads from account.initialBalance
    func getInitialBalance(for accountId: String) -> Double? {
        return accounts.first(where: { $0.id == accountId })?.initialBalance
    }

    /// Backward compatibility stub — BalanceCoordinator manages calculation modes
    func isAccountImported(_ accountId: String) -> Bool {
        return false
    }

    /// Backward compatibility stub — BalanceCoordinator manages calculation modes
    func resetImportedAccountFlags() { }

    // MARK: - Currency Conversion

    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        currencyService.getConvertedAmount(transactionId: transactionId, to: baseCurrency)
    }

    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        currencyService.getConvertedAmountOrCompute(transaction: transaction, to: baseCurrency)
    }

}

// MARK: - Supporting Types

struct CategoryExpense: Equatable {
    var total: Double
    var subcategories: [String: Double]
}
