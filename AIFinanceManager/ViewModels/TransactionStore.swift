//
//  TransactionStore.swift
//  AIFinanceManager
//
//  Created on 2026-02-05
//  Refactoring Phase 0-6: Single Source of Truth for Transactions
//
//  Purpose: Unified store for all transaction operations
//  Replaces: TransactionCRUDService, CategoryAggregateService, multiple cache managers
//  Pattern: Event Sourcing + Single Source of Truth + LRU Cache
//

import Foundation
import Combine
import CoreData
import Observation

/// Errors that can occur during transaction operations
enum TransactionStoreError: LocalizedError {
    case invalidAmount
    case accountNotFound
    case targetAccountNotFound
    case categoryNotFound
    case transactionNotFound
    case idMismatch
    case cannotRemoveRecurring
    case cannotDeleteDepositInterest
    case persistenceFailed(Error)

    // ✨ Phase 9: Recurring errors
    case seriesNotFound
    case invalidSeriesData
    case invalidStartDate

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return String(localized: "error.transaction.invalidAmount", defaultValue: "Invalid amount")
        case .accountNotFound:
            return String(localized: "error.transaction.accountNotFound", defaultValue: "Account not found")
        case .targetAccountNotFound:
            return String(localized: "error.transaction.targetAccountNotFound", defaultValue: "Target account not found")
        case .categoryNotFound:
            return String(localized: "error.transaction.categoryNotFound", defaultValue: "Category not found")
        case .transactionNotFound:
            return String(localized: "error.transaction.notFound", defaultValue: "Transaction not found")
        case .idMismatch:
            return String(localized: "error.transaction.idMismatch", defaultValue: "Transaction ID mismatch")
        case .cannotRemoveRecurring:
            return String(localized: "error.transaction.cannotRemoveRecurring", defaultValue: "Cannot remove recurring series")
        case .cannotDeleteDepositInterest:
            return String(localized: "error.transaction.cannotDeleteDepositInterest", defaultValue: "Cannot delete deposit interest")
        case .persistenceFailed(let error):
            return String(localized: "error.transaction.persistenceFailed", defaultValue: "Failed to save: \(error.localizedDescription)")

        // ✨ Phase 9: Recurring errors
        case .seriesNotFound:
            return String(localized: "error.recurring.seriesNotFound", defaultValue: "Recurring series not found")
        case .invalidSeriesData:
            return String(localized: "error.recurring.invalidData", defaultValue: "Invalid recurring series data")
        case .invalidStartDate:
            return String(localized: "error.recurring.invalidStartDate", defaultValue: "Invalid start date format")
        }
    }
}

/// Single Source of Truth for all transaction data
/// All transaction operations (add/update/delete/transfer) go through this store
/// Modernized with @Observable macro for better performance and less boilerplate
@Observable
@MainActor
final class TransactionStore {
    // MARK: - Observable State (Single Source of Truth)

    /// All transactions - THE ONLY source of transaction data
    private(set) var transactions: [Transaction] = []

    /// All accounts - managed alongside transactions for balance updates
    private(set) var accounts: [Account] = []

    /// All categories - needed for validation
    private(set) var categories: [CustomCategory] = []

    // MARK: - Subcategory Data (Phase 10: CSV Import Fix - Single Source of Truth)

    /// All subcategories - managed alongside categories
    private(set) var subcategories: [Subcategory] = []

    /// Links between categories and subcategories
    private(set) var categorySubcategoryLinks: [CategorySubcategoryLink] = []

    /// Links between transactions and subcategories
    private(set) var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []

    // MARK: - Recurring Data (Phase 9: Aggressive Integration) ✨

    /// All recurring series - subscriptions and generic recurring transactions
    private(set) var recurringSeries: [RecurringSeries] = []

    /// All recurring occurrences - tracks which transactions were generated from which series
    private(set) var recurringOccurrences: [RecurringOccurrence] = []

    // MARK: - Dependencies

    @ObservationIgnored internal let repository: DataRepositoryProtocol  // ✨ Phase 9: internal for access from extension
    @ObservationIgnored private let cache: UnifiedTransactionCache

    // ✅ REFACTORED: Balance coordinator is now REQUIRED (not optional)
    // This ensures balance updates always occur, no silent failures
    @ObservationIgnored private let balanceCoordinator: BalanceCoordinator

    // ✨ Phase 9: Recurring dependencies (internal for access from extension)
    @ObservationIgnored internal let recurringGenerator: RecurringTransactionGenerator
    @ObservationIgnored internal let recurringValidator: RecurringValidationService
    @ObservationIgnored internal let recurringCache: LRUCache<String, [Transaction]>

    // Settings
    internal var baseCurrency: String = "KZT"

    // Import mode flag - when true, persistence is deferred until finishImport()
    private(set) var isImporting: Bool = false

    // Phase 17: Debounce task for coalescing rapid mutations into single sync
    private var syncDebounceTask: Task<Void, Never>?

    // Coordinator for syncing changes to ViewModels (with @Observable we need manual sync)
    @ObservationIgnored weak var coordinator: AppCoordinator?

    // MARK: - Phase 22: Persistent Aggregate Services

    /// Maintains per-category spending totals in CategoryAggregateEntity.
    /// Updated incrementally on each transaction mutation (O(1) per transaction).
    @ObservationIgnored let categoryAggregateService: CategoryAggregateService

    /// Maintains per-month income/expense totals in MonthlyAggregateEntity.
    /// Used by InsightsService for O(M) chart data instead of O(N×M) scans.
    @ObservationIgnored let monthlyAggregateService: MonthlyAggregateService

    // MARK: - Task 11: Transaction Windowing Strategy

    /// How many calendar months of transactions to load into the in-memory store for
    /// real-time business logic (balance delta, recurring checks, current-period insights).
    ///
    /// Set to 0 (disabled) until the three blockers below are resolved:
    ///
    /// BLOCKER 1 — BalanceCoordinator.registerAccounts(_:transactions:)  [RESOLVED — Phase 31 Task 5]
    ///   Phase B background recalculation removed. registerAccounts now only reads the persisted
    ///   `account.balance` field (kept accurate by persistIncremental() on every mutation).
    ///   No transaction list is passed; windowing does not affect balance correctness.
    ///
    /// BLOCKER 2 — InsightsService reads transactionStore.transactions directly  [RESOLVED — Phase 31 Task 6]
    ///   InsightsService.generateAllInsights() captures `Array(transactionStore.transactions)`
    ///   at line 85 and passes it as `allTransactions` to generators including:
    ///   - accountDormancy (needs all-time transaction dates per account)
    ///   - spendingVelocity (needs multi-month trend window)
    ///   - incomeSourceBreakdown (needs the selected period's transactions)
    ///   - computePeriodDataPoints (for .allTime / .year granularities spanning years)
    ///   All four generators now read from CategoryAggregateService / MonthlyAggregateService
    ///   (Phase 22 aggregate services). Windowing does not affect insight correctness.
    ///
    /// BLOCKER 3 — AppCoordinator aggregate rebuild reads transactionStore.transactions  [RESOLVED — Phase 31 Task 4]
    ///   AppCoordinator.initialize aggregate rebuild now calls
    ///   `repository.loadTransactions(dateRange: nil)` on a background context independently,
    ///   bypassing the in-memory windowed store entirely. Aggregate records are always built
    ///   from the full transaction history regardless of the window setting.
    ///
    /// All three blockers resolved in Phase 31 (Tasks 4, 5, 6). Window is now active.
    /// UI history is served by TransactionPaginationController (NSFetchedResultsController)
    /// and is not affected by this constant — it always queries CoreData directly.
    private let windowMonths: Int = 3  // Phase 31: enabled — all blockers resolved

    /// The start of the in-memory transaction window, or nil if all transactions are loaded.
    /// ContentView uses this to decide whether to fall back to MonthlyAggregateService for
    /// filters that extend beyond the window (e.g. "All Time", "Last Year").
    var windowStartDate: Date? {
        guard windowMonths > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: -windowMonths, to: Date())
    }

    /// Total transaction count across ALL of CoreData, not just the in-memory window.
    /// Updated in loadData() via COUNT query and maintained via apply() events.
    /// Use this instead of `transactions.count` when checking "are there any transactions at all?"
    /// — `transactions` only holds the last 3 months due to windowing.
    private(set) var totalTransactionCount: Int = 0

    /// Returns (totalIncome, totalExpenses) for the given period using MonthlyAggregateService.
    /// O(M) CoreData fetch where M = number of calendar months in [startDate, endDate].
    /// Called by ContentView when the time filter extends beyond the in-memory window.
    func fetchAggregateSummary(from startDate: Date, to endDate: Date, currency: String) -> (income: Double, expenses: Double) {
        let records = monthlyAggregateService.fetchRange(from: startDate, to: endDate, currency: currency)
        return (
            income:   records.reduce(0.0) { $0 + $1.totalIncome },
            expenses: records.reduce(0.0) { $0 + $1.totalExpenses }
        )
    }

    /// Returns the total planned (future-dated) expenses within [startDate, endDate].
    /// "Planned" = expense transactions with date > today.
    /// Reads directly from CoreData viewContext — bypasses the 3-month in-memory window.
    /// Called by ContentView for the aggregate summary path so the "Planned" row shows correctly
    /// even for out-of-window filters (e.g. "All Time", "Last Year").
    func fetchPlannedExpenses(from startDate: Date, to endDate: Date, currency: String) -> Double {
        let today = Date()
        guard endDate > today else { return 0 }  // Past period — no future transactions possible

        // TransactionEntity.date is NSDate — use NSDate comparison directly.
        let context = CoreDataStack.shared.viewContext
        let request = TransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "type == %@ AND date > %@ AND date <= %@",
            "expense", today as NSDate, endDate as NSDate
        )
        request.fetchBatchSize = 100

        do {
            let entities = try context.fetch(request)
            return entities.reduce(0.0) { total, entity in
                let tx = entity.toTransaction()
                if tx.currency == currency { return total + tx.amount }
                if let c = tx.convertedAmount, c > 0 { return total + c }
                return total + (CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: currency) ?? tx.amount)
            }
        } catch {
            return 0
        }
    }

    /// Returns the date of the earliest transaction in CoreData.
    /// O(1) — sorted ASC + fetchLimit 1. Bypasses the 3-month in-memory window.
    /// Used by InsightsViewModel to compute the correct granularity window for .month / .quarter.
    func fetchFirstTransactionDate() -> Date? {
        let context = CoreDataStack.shared.viewContext
        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        request.fetchLimit = 1
        do {
            let entities = try context.fetch(request)
            return entities.first?.date
        } catch {}
        return nil
    }

    /// Fetches expense transactions for a specific category within [startDate, endDate] from CoreData.
    /// Bypasses the in-memory window — used by InsightsViewModel.categoryDeepDive() when the
    /// previous-bucket period falls outside the 3-month window.
    func fetchCategoryTransactions(categoryName: String, from startDate: Date, to endDate: Date) -> [Transaction] {
        let startString = DateFormatters.dateFormatter.string(from: startDate)
        let endString   = DateFormatters.dateFormatter.string(from: endDate)
        let context = CoreDataStack.shared.viewContext
        let request = TransactionEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "category == %@ AND type == %@ AND date >= %@ AND date <= %@",
            categoryName, "expense", startString, endString
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        do {
            return try context.fetch(request).map { $0.toTransaction() }
        } catch {
            return []
        }
    }

    /// Returns [categoryName: CategoryExpense] for the given period using CategoryAggregateService.
    /// O(1) for allTime (pre-summed year==0 records), O(M) for date ranges (monthly records summed per category).
    /// Called by TransactionsViewModel when the time filter extends beyond the in-memory window.
    ///
    /// - Parameters:
    ///   - preset: The filter preset — `.allTime` uses the year==0 all-time totals, others use fetchRange.
    ///   - startDate / endDate: The filter bounds.
    ///   - currency: Base currency string.
    ///   - validCategoryNames: Optional allowlist — only categories in this set are returned.
    func fetchCategoryExpenses(
        preset: TimeFilterPreset,
        from startDate: Date,
        to endDate: Date,
        currency: String,
        validCategoryNames: Set<String>? = nil
    ) -> [String: CategoryExpense] {
        // allTime → use the pre-summed year==0/month==0 records (O(categories), most accurate).
        // Any other out-of-window filter → sum monthly rows for the date range (O(M)).
        let aggregates: [CategoryMonthlyAggregate]
        if preset == .allTime {
            aggregates = categoryAggregateService.fetchAllTime(currency: currency)
        } else {
            aggregates = categoryAggregateService.fetchRange(from: startDate, to: endDate, currency: currency)
        }

        return aggregates.reduce(into: [String: CategoryExpense]()) { result, agg in
            guard !agg.categoryName.isEmpty else { return }
            if let validNames = validCategoryNames, !validNames.contains(agg.categoryName) { return }
            result[agg.categoryName] = CategoryExpense(total: agg.totalExpenses, subcategories: [:])
        }
    }

    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol,
        balanceCoordinator: BalanceCoordinator,
        cacheCapacity: Int = 1000
    ) {
        self.repository = repository
        self.balanceCoordinator = balanceCoordinator
        self.cache = UnifiedTransactionCache(capacity: cacheCapacity)

        // ✨ Phase 9: Initialize recurring dependencies (internal for access from extension)
        self.recurringGenerator = RecurringTransactionGenerator(dateFormatter: DateFormatters.dateFormatter)
        self.recurringValidator = RecurringValidationService()
        self.recurringCache = LRUCache<String, [Transaction]>(capacity: 100)

        // Phase 22: Initialize persistent aggregate services
        self.categoryAggregateService = CategoryAggregateService()
        self.monthlyAggregateService = MonthlyAggregateService()

        // Setup notification observer for app lifecycle
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .applicationDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.rescheduleSubscriptionNotifications()
            }
        }
    }

    private func rescheduleSubscriptionNotifications() async {
        let activeSubscriptions = subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
        await SubscriptionNotificationScheduler.shared.rescheduleAllActiveSubscriptions(subscriptions: activeSubscriptions)
    }

    // MARK: - Data Loading

    /// Load initial data from repository.
    /// Phase 28-B: All CoreData fetches run on a background thread via Task.detached.
    /// MainActor is NOT blocked — it awaits the background result.
    ///
    /// Task 11 / Phase 31: When windowMonths > 0 (currently 3), only transactions within the
    /// rolling window are loaded into memory.  The window is computed here on @MainActor and
    /// passed to the background fetch as a DateInterval predicate.  Filters that extend beyond
    /// the window (e.g. "All Time", "Last Year") use MonthlyAggregateService via
    /// fetchAggregateSummary(from:to:currency:) — see ContentView `.task(id: summaryTrigger)`.
    func loadData() async throws {
        // Capture repository before leaving @MainActor — it's a constant (@ObservationIgnored let).
        let repo = self.repository

        // Task 11: Build optional date window. nil means "load all" (current behaviour).
        let txDateRange: DateInterval? = windowMonths > 0
            ? {
                let now = Date()
                let windowStart: Date
                if let computed = Calendar.current.date(byAdding: .month, value: -windowMonths, to: now) {
                    windowStart = computed
                } else {
                    assertionFailure("Calendar overflow computing transaction window — windowMonths=\(windowMonths)")
                    windowStart = Date.distantPast
                }
                return DateInterval(start: windowStart, end: now)
            }()
            : nil

        // Run ALL repository reads on a background thread.
        // Each repository method uses bgContext.performAndWait internally (Change 1),
        // so they are safe to call from any thread.
        let (txs, accs, cats, subs, catLinks, txLinks, series, occurrences) =
            try await Task.detached(priority: .userInitiated) {
                let txs        = repo.loadTransactions(dateRange: txDateRange)
                let accs       = repo.loadAccounts()
                let cats       = repo.loadCategories()
                let subs       = repo.loadSubcategories()
                let catLinks   = repo.loadCategorySubcategoryLinks()
                let txLinks    = repo.loadTransactionSubcategoryLinks()
                let series     = repo.loadRecurringSeries()
                let occ        = repo.loadRecurringOccurrences()
                return (txs, accs, cats, subs, catLinks, txLinks, series, occ)
            }.value

        // Back on @MainActor — single assignment cycle triggers one @Observable update.
        accounts  = AccountOrderManager.shared.applyOrders(to: accs)
        transactions = txs
        categories = CategoryOrderManager.shared.applyOrders(to: cats)
        subcategories = subs
        categorySubcategoryLinks = catLinks
        transactionSubcategoryLinks = txLinks
        recurringSeries = series
        recurringOccurrences = occurrences

        // Set totalTransactionCount from CoreData — not from `txs` which is windowed.
        // viewContext COUNT is O(1) (SQLite COUNT(*)) and safe to call on MainActor.
        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "TransactionEntity")
        totalTransactionCount = (try? CoreDataStack.shared.viewContext.count(for: countRequest)) ?? txs.count

        // Note: baseCurrency will be set via updateBaseCurrency() from AppCoordinator
    }

    /// Lightweight startup load: only accounts + categories (fast-path for instant UI).
    /// Full data is loaded by loadData() called afterwards in the background.
    func loadAccountsOnly() async throws {
        let bgContext = CoreDataStack.shared.newBackgroundContext()
        let (accs, cats) = try await bgContext.perform {
            let accs = try bgContext.fetch(AccountEntity.fetchRequest()).map { $0.toAccount() }
            let cats = try bgContext.fetch(CustomCategoryEntity.fetchRequest()).map { $0.toCustomCategory() }
            return (accs, cats)
        }
        accounts = AccountOrderManager.shared.applyOrders(to: accs)
        categories = CategoryOrderManager.shared.applyOrders(to: cats)
    }

    /// Update base currency (for currency conversions)
    func updateBaseCurrency(_ currency: String) {
        baseCurrency = currency
        cache.invalidateAll() // Currency change affects all cached calculations
        // Phase 22: Rebuild aggregates — all amounts must be re-converted to new base currency.
        // FIX: load ALL transactions from CoreData (self.transactions is windowed to last 3 months,
        // so using it would wipe historical aggregates for pre-window data, e.g. 2015-2023).
        let repo = repository
        let newCurrency = currency
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let allTx = repo.loadTransactions(dateRange: nil)
            self.categoryAggregateService.rebuild(from: allTx, baseCurrency: newCurrency)
            self.monthlyAggregateService.rebuild(from: allTx, baseCurrency: newCurrency)
        }
    }

    // MARK: - CRUD Operations

    /// Add a new transaction
    /// Phase 1: Complete implementation with validation, balance updates, and persistence
    /// Returns the created transaction with generated ID
    func add(_ transaction: Transaction) async throws -> Transaction {
        // 1. Validate transaction
        try validate(transaction)

        // 2. Generate ID if needed
        let tx: Transaction
        if transaction.id.isEmpty {
            let newId = TransactionIDGenerator.generateID(for: transaction)
            tx = Transaction(
                id: newId,
                date: transaction.date,
                description: transaction.description,
                amount: transaction.amount,
                currency: transaction.currency,
                convertedAmount: transaction.convertedAmount,
                type: transaction.type,
                category: transaction.category,
                subcategory: transaction.subcategory,
                accountId: transaction.accountId,
                targetAccountId: transaction.targetAccountId,
                accountName: transaction.accountName,
                targetAccountName: transaction.targetAccountName,
                targetCurrency: transaction.targetCurrency,
                targetAmount: transaction.targetAmount,
                recurringSeriesId: transaction.recurringSeriesId,
                recurringOccurrenceId: transaction.recurringOccurrenceId,
                createdAt: transaction.createdAt
            )
        } else {
            tx = transaction
        }

        // 3. Create event
        let event = TransactionEvent.added(tx)

        // 4. Apply event (updates state, balances, cache, persistence)
        try await apply(event)


        // 5. Return the created transaction with ID
        return tx
    }

    /// Add multiple transactions in a single batch (optimized for CSV import)
    /// Phase 8: Batch import without per-transaction persistence
    func addBatch(_ transactions: [Transaction]) async throws {
        guard !transactions.isEmpty else { return }

        // 1. Validate all transactions
        for transaction in transactions {
            try validate(transaction)
        }

        // 2. Generate IDs for transactions that need them
        let txsWithIds = transactions.map { tx -> Transaction in
            if tx.id.isEmpty {
                let newId = TransactionIDGenerator.generateID(for: tx)
                return Transaction(
                    id: newId,
                    date: tx.date,
                    description: tx.description,
                    amount: tx.amount,
                    currency: tx.currency,
                    convertedAmount: tx.convertedAmount,
                    type: tx.type,
                    category: tx.category,
                    subcategory: tx.subcategory,
                    accountId: tx.accountId,
                    targetAccountId: tx.targetAccountId,
                    accountName: tx.accountName,
                    targetAccountName: tx.targetAccountName,
                    targetCurrency: tx.targetCurrency,
                    targetAmount: tx.targetAmount,
                    recurringSeriesId: tx.recurringSeriesId,
                    recurringOccurrenceId: tx.recurringOccurrenceId,
                    createdAt: tx.createdAt
                )
            } else {
                return tx
            }
        }

        // 3. Create bulk event
        let event = TransactionEvent.bulkAdded(txsWithIds)

        // 4. Apply event (updates state, balances, cache)
        // Note: If in import mode, persistence is deferred
        try await apply(event)

    }

    /// Begin import mode (defers persistence until finishImport)
    func beginImport() {
        isImporting = true
    }

    /// Finish import mode and persist all changes
    func finishImport() async throws {
        let txCount = transactions.count
        print("📥 [TransactionStore] finishImport START — tx:\(txCount) acc:\(accounts.count) cat:\(categories.count)")

        // CRITICAL: Use synchronous save to ensure data is persisted before returning
        // This prevents data loss if app is terminated immediately after import
        // IMPORTANT: Save in correct order - accounts FIRST, then transactions (for relationships)
        do {
            if let coreDataRepo = repository as? CoreDataRepository {
                // ✨ Phase 10: Save accounts BEFORE transactions (required for Core Data relationships)
                print("📥 [TransactionStore] finishImport: saving accounts…")
                try coreDataRepo.saveAccountsSync(accounts)
                print("📥 [TransactionStore] finishImport: saving categories…")
                try coreDataRepo.saveCategoriesSync(categories)

                // ✨ Phase 10: Save subcategory data synchronously
                try coreDataRepo.saveSubcategoriesSync(subcategories)
                try coreDataRepo.saveCategorySubcategoryLinksSync(categorySubcategoryLinks)

                // ✨ Phase 10: Save transactions AFTER accounts (so account relationships can be established)
                print("📥 [TransactionStore] finishImport: saving \(txCount) transactions via saveTransactionsSync…")
                try coreDataRepo.saveTransactionsSync(transactions)
                print("📥 [TransactionStore] finishImport: saveTransactionsSync DONE")
                try coreDataRepo.saveTransactionSubcategoryLinksSync(transactionSubcategoryLinks)
            } else {
                // Fallback to async save for non-CoreData repositories
                repository.saveAccounts(accounts)
                repository.saveCategories(categories)

                // ✨ Phase 10: Save subcategory data
                repository.saveSubcategories(subcategories)
                repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)

                repository.saveTransactions(transactions)
                repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
            }

            // Save recurring data (these are less critical, can be async)
            repository.saveRecurringSeries(recurringSeries)
            repository.saveRecurringOccurrences(recurringOccurrences)

        } catch {
            print("❌ [TransactionStore] finishImport FAILED: \(error)")
            throw TransactionStoreError.persistenceFailed(error)
        }

        // Mark import done ONLY after all saves have succeeded.
        // Setting this earlier would fire ContentView observers while CoreData writes are still in progress.
        isImporting = false

        print("✅ [TransactionStore] finishImport: all saves complete, rebuilding aggregates…")

        // Phase 22: After import, rebuild persistent aggregates.
        // FIX: load ALL transactions from CoreData after saving, not self.transactions which is
        // windowed to last 3 months. A partial re-import (e.g. only 2024 data) would otherwise
        // wipe 2015-2023 aggregates because those years aren't in the in-memory window.
        let repo = repository
        let currency = baseCurrency
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let allTx = repo.loadTransactions(dateRange: nil)
            self.categoryAggregateService.rebuild(from: allTx, baseCurrency: currency)
            self.monthlyAggregateService.rebuild(from: allTx, baseCurrency: currency)
        }

        print("✅ [TransactionStore] finishImport DONE")
    }

    /// Update an existing transaction
    /// Phase 2: Complete implementation
    func update(_ transaction: Transaction) async throws {
        guard let old = transactions.first(where: { $0.id == transaction.id }) else {
            throw TransactionStoreError.transactionNotFound
        }

        // Validate
        try validate(transaction)

        // Additional validation for update
        guard old.id == transaction.id else {
            throw TransactionStoreError.idMismatch
        }

        // Cannot change recurring series to non-recurring
        if old.recurringSeriesId != nil && transaction.recurringSeriesId == nil {
            throw TransactionStoreError.cannotRemoveRecurring
        }

        // Create event
        let event = TransactionEvent.updated(old: old, new: transaction)

        // Apply event
        try await apply(event)

    }

    /// Delete a transaction
    /// Phase 3: Complete implementation
    func delete(_ transaction: Transaction) async throws {
        guard transactions.contains(where: { $0.id == transaction.id }) else {
            throw TransactionStoreError.transactionNotFound
        }

        // Validate deletion
        if transaction.category == "Deposit Interest" {
            throw TransactionStoreError.cannotDeleteDepositInterest
        }

        // Create event
        let event = TransactionEvent.deleted(transaction)

        // Apply event
        try await apply(event)

    }

    /// Transfer between accounts (convenience method)
    /// Phase 4: Complete implementation
    func transfer(
        from sourceId: String,
        to targetId: String,
        amount: Double,
        currency: String,
        targetAmount: Double? = nil,
        targetCurrency: String? = nil,
        date: String,
        description: String
    ) async throws {
        // Validate accounts exist
        guard accounts.contains(where: { $0.id == sourceId }) else {
            throw TransactionStoreError.accountNotFound
        }

        guard accounts.contains(where: { $0.id == targetId }) else {
            throw TransactionStoreError.targetAccountNotFound
        }

        // Create transfer transaction
        let transaction = Transaction(
            id: "",  // Will be generated
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            type: .internalTransfer,
            category: TransactionType.transferCategoryName,
            accountId: sourceId,
            targetAccountId: targetId,
            targetCurrency: targetCurrency ?? currency,
            targetAmount: targetAmount ?? amount
        )

        // Use add operation
        _ = try await add(transaction)

    }

    // MARK: - Account CRUD Operations (Phase 3)

    /// Add a new account
    /// Phase 3: TransactionStore is now Single Source of Truth for accounts
    func addAccount(_ account: Account) {
        // Check if account already exists
        if accounts.contains(where: { $0.id == account.id }) {
            return
        }

        accounts.append(account)

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccounts()

            // ✅ Save order to UserDefaults (UI preference)
            if let order = account.order {
                AccountOrderManager.shared.setOrder(order, for: account.id)
            }

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
            // @Observable automatically notifies SwiftUI when accounts array changes
        }

    }

    /// Update an existing account
    /// Phase 3: TransactionStore is now Single Source of Truth for accounts
    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        accounts[index] = account

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccounts()

            // ✅ Save order to UserDefaults (UI preference, separate from repository)
            if let order = account.order {
                AccountOrderManager.shared.setOrder(order, for: account.id)
            }

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
        }

    }

    /// Delete an account
    /// Phase 3: TransactionStore is now Single Source of Truth for accounts
    func deleteAccount(_ accountId: String) {
        accounts.removeAll { $0.id == accountId }

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistAccounts()

            // ✅ Remove order from UserDefaults
            AccountOrderManager.shared.removeOrder(for: accountId)

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
        }

    }

    /// Deletes all transactions associated with an account (where accountId or targetAccountId matches).
    /// Call this before deleteAccount when you want to remove an account with all its transactions.
    /// Each deletion goes through apply(.deleted) so aggregates, cache, and persistence are all updated.
    func deleteTransactions(forAccountId accountId: String) async {
        let toDelete = transactions.filter {
            $0.accountId == accountId || $0.targetAccountId == accountId
        }
        for transaction in toDelete {
            let event = TransactionEvent.deleted(transaction)
            try? await apply(event)
        }
    }

    /// Deletes all transactions matching the given category name and type.
    /// Call this before deleteCategory when you want to remove a category with all its transactions.
    /// Each deletion goes through apply(.deleted) so aggregates, cache, and persistence are all updated.
    func deleteTransactions(forCategoryName categoryName: String, type: TransactionType) async {
        let toDelete = transactions.filter {
            $0.category == categoryName && $0.type == type
        }
        for transaction in toDelete {
            let event = TransactionEvent.deleted(transaction)
            try? await apply(event)
        }
    }

    // MARK: - Category CRUD Operations (Phase 3)

    /// Add a new category
    /// Phase 3: TransactionStore is now Single Source of Truth for categories
    func addCategory(_ category: CustomCategory) {
        // Check if category already exists
        if categories.contains(where: { $0.id == category.id }) {
            return
        }

        // Assign order if not set
        var categoryToAdd = category
        if categoryToAdd.order == nil {
            // Get max order for this type
            let maxOrder = categories
                .filter { $0.type == category.type }
                .compactMap { $0.order }
                .max() ?? -1
            categoryToAdd.order = maxOrder + 1
        }

        categories.append(categoryToAdd)

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistCategories()

            // ✅ Save order to UserDefaults (UI preference)
            if let order = categoryToAdd.order {
                CategoryOrderManager.shared.setOrder(order, for: categoryToAdd.id)
            }

            // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore
        }

    }

    /// Update an existing category
    /// Phase 3: TransactionStore is now Single Source of Truth for categories
    func updateCategory(_ category: CustomCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else {
            return
        }

        categories[index] = category
        persistCategories()

        // ✅ Save order to UserDefaults (UI preference, separate from CoreData)
        if let order = category.order {
            CategoryOrderManager.shared.setOrder(order, for: category.id)
        }

        // ✅ FIX: Invalidate style cache so icon/color changes reflect immediately.
        // CategoryDisplayDataMapper reads icon data through CategoryStyleCache.
        // Without this, the singleton cache may serve stale icon data until next restart.
        CategoryStyleCache.shared.invalidateCache()

        // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore

    }

    /// Delete a category
    /// Phase 3: TransactionStore is now Single Source of Truth for categories
    func deleteCategory(_ categoryId: String) {
        categories.removeAll { $0.id == categoryId }
        persistCategories()

        // ✅ Remove order from UserDefaults
        CategoryOrderManager.shared.removeOrder(for: categoryId)

        // Phase 16: No sync needed — ViewModels use computed properties from TransactionStore

    }

    // MARK: - Subcategory CRUD Operations (Phase 10: CSV Import Fix)

    /// Add a new subcategory
    /// Phase 10: TransactionStore is now Single Source of Truth for subcategories
    func addSubcategory(_ subcategory: Subcategory) {
        subcategories.append(subcategory)

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategories()
        }

    }

    /// Update subcategories array (for bulk operations)
    /// Phase 10: Used by CategoriesViewModel during CSV import
    func updateSubcategories(_ newSubcategories: [Subcategory]) {
        subcategories = newSubcategories

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistSubcategories()
        }

    }

    /// Update category-subcategory links (for bulk operations)
    /// Phase 10: Used by CategoriesViewModel during CSV import
    func updateCategorySubcategoryLinks(_ newLinks: [CategorySubcategoryLink]) {
        categorySubcategoryLinks = newLinks

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistCategorySubcategoryLinks()
        }

    }

    /// Update transaction-subcategory links (for bulk operations)
    /// Phase 10: Used by CategoriesViewModel during CSV import
    func updateTransactionSubcategoryLinks(_ newLinks: [TransactionSubcategoryLink]) {
        transactionSubcategoryLinks = newLinks

        // Don't persist during import mode - will be done in finishImport()
        if !isImporting {
            persistTransactionSubcategoryLinks()
        }

    }

    // MARK: - Computed Properties with Caching

    /// Summary of income/expense/transfers
    /// Phase 6: Cached computed property
    var summary: Summary {
        // Try cache first
        if let cached: Summary = cache.summary {
            return cached
        }

        // Calculate
        let result = calculateSummary(transactions: transactions)

        // Cache result
        cache.setSummary(result)

        return result
    }

    /// Expenses grouped by category
    /// Phase 6: Cached computed property
    var categoryExpenses: [CachedCategoryExpense] {
        // Try cache first
        if let cached: [CachedCategoryExpense] = cache.categoryExpenses {
            return cached
        }

        // Calculate
        let result = calculateCategoryExpenses(transactions: transactions)

        // Cache result
        cache.setCachedCategoryExpenses(result)

        return result
    }

    /// Daily expenses for a specific date
    /// Phase 6: Cached computed property
    func expenses(for date: Date) -> Double {
        let dateString = DateFormatters.dateFormatter.string(from: date)

        // Try cache first
        if let cached = cache.dailyExpenses(for: dateString) {
            return cached
        }

        // Calculate
        let result = calculateDailyExpenses(for: dateString, transactions: transactions)

        // Cache result
        cache.setDailyExpenses(result, for: dateString)

        return result
    }

    // MARK: - Calculation Methods

    /// Calculate summary from transactions
    private func calculateSummary(transactions: [Transaction]) -> Summary {
        var totalIncome: Double = 0
        var totalExpenses: Double = 0
        var totalInternal: Double = 0

        let dateFormatter = DateFormatters.dateFormatter
        var minDate: Date?
        var maxDate: Date?

        for tx in transactions {
            let amountInBase = convertToBaseCurrency(amount: tx.amount, from: tx.currency)

            switch tx.type {
            case .income:
                totalIncome += amountInBase
            case .expense:
                totalExpenses += amountInBase
            case .internalTransfer:
                totalInternal += amountInBase
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                // Deposit transactions - handle separately
                // For now, treat like internal transfers
                totalInternal += amountInBase
            }

            // Track date range
            if let txDate = dateFormatter.date(from: tx.date) {
                if minDate == nil || txDate < minDate! {
                    minDate = txDate
                }
                if maxDate == nil || txDate > maxDate! {
                    maxDate = txDate
                }
            }
        }

        let startDate = minDate.map { dateFormatter.string(from: $0) } ?? ""
        let endDate = maxDate.map { dateFormatter.string(from: $0) } ?? ""

        return Summary(
            totalIncome: totalIncome,
            totalExpenses: totalExpenses,
            totalInternalTransfers: totalInternal,
            netFlow: totalIncome - totalExpenses,
            currency: baseCurrency,
            startDate: startDate,
            endDate: endDate,
            plannedAmount: 0  // NOTE: Planned amount calculation not implemented (future feature)
        )
    }

    /// Calculate category expenses from transactions
    private func calculateCategoryExpenses(transactions: [Transaction]) -> [CachedCategoryExpense] {
        var categoryMap: [String: Double] = [:]

        for tx in transactions where tx.type == .expense && !tx.category.isEmpty {
            let amountInBase = convertToBaseCurrency(amount: tx.amount, from: tx.currency)
            categoryMap[tx.category, default: 0] += amountInBase
        }

        return categoryMap.map { CachedCategoryExpense(name: $0.key, amount: $0.value, currency: baseCurrency) }
            .sorted { $0.amount > $1.amount }  // Sort by amount descending
    }

    /// Calculate daily expenses for a specific date
    private func calculateDailyExpenses(for dateString: String, transactions: [Transaction]) -> Double {
        return transactions
            .filter { $0.date == dateString && $0.type == .expense }
            .reduce(0.0) { sum, tx in
                sum + convertToBaseCurrency(amount: tx.amount, from: tx.currency)
            }
    }

    /// Convert amount to base currency
    private func convertToBaseCurrency(amount: Double, from currency: String) -> Double {
        return convertToCurrency(amount: amount, from: currency, to: baseCurrency)
    }

    // MARK: - Private Helpers

    /// Apply an event to the store
    /// Phase 1-4: Core event processing - validates, updates state, balances, cache, persists
    /// ✨ Phase 9: Made internal for access from TransactionStore+Recurring extension
    /// 🗄️ Phase 22: Added incremental aggregate updates for CategoryAggregateEntity + MonthlyAggregateEntity
    internal func apply(_ event: TransactionEvent) async throws {
        // 1. Update state (SSOT)
        updateState(event)

        // 2. Update balances (incremental)
        updateBalances(for: event)

        // 3. Phase 20: Granular cache invalidation — only invalidate what changed
        invalidateCache(for: event)

        // 4. Phase 22: Incremental aggregate updates (O(1) per transaction)
        // Skip during import — a full rebuild is triggered after finishImport()
        if !isImporting {
            updateAggregates(for: event)
        }

        // 5. Phase 28-C: Incremental persist — O(1) per event (no await needed)
        if !isImporting {
            persistIncremental(event)
        }

        // 6. Phase 17: Debounced sync — coalesces rapid mutations (e.g., batch adds)
        // @Observable automatically notifies SwiftUI for TransactionStore property changes.
        // Debounced sync handles cache invalidation and insights recompute.
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000) // ~1 frame (16ms)
            guard !Task.isCancelled else { return }
            // Pass batchMode=true during import so InsightsVM isn't invalidated on every batch.
            self?.coordinator?.syncTransactionStoreToViewModels(batchMode: self?.isImporting ?? false)
        }
    }

    /// Phase 22: Incremental aggregate maintenance.
    /// Dispatches O(1) updates to CategoryAggregateService and MonthlyAggregateService.
    /// Bulk events trigger a full rebuild (same O(N) cost, but once instead of per-view).
    private func updateAggregates(for event: TransactionEvent) {
        let currency = baseCurrency
        switch event {
        case .added(let tx):
            categoryAggregateService.applyAdded(tx, baseCurrency: currency)
            monthlyAggregateService.applyAdded(tx, baseCurrency: currency)

        case .deleted(let tx):
            categoryAggregateService.applyDeleted(tx, baseCurrency: currency)
            monthlyAggregateService.applyDeleted(tx, baseCurrency: currency)

        case .updated(let old, let new):
            categoryAggregateService.applyUpdated(old: old, new: new, baseCurrency: currency)
            monthlyAggregateService.applyUpdated(old: old, new: new, baseCurrency: currency)

        case .bulkAdded:
            // Bulk add: rebuild aggregates from the full transaction set.
            // FIX: load from CoreData via Task.detached (runs after persistIncremental saves the
            // batch) so pre-window historical data (e.g. 2015-2023) is included in the rebuild.
            let repo = repository
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let allTx = repo.loadTransactions(dateRange: nil)
                self.categoryAggregateService.rebuild(from: allTx, baseCurrency: currency)
                self.monthlyAggregateService.rebuild(from: allTx, baseCurrency: currency)
            }

        case .seriesCreated, .seriesUpdated, .seriesStopped, .seriesDeleted:
            // Recurring events don't directly change individual transactions here;
            // the transaction mutations go through .added/.deleted/.bulkAdded paths.
            break
        }
    }

    /// Update state based on event
    private func updateState(_ event: TransactionEvent) {
        switch event {
        case .added(let tx):
            transactions.append(tx)
            totalTransactionCount += 1

        case .updated(let old, let new):
            if let index = transactions.firstIndex(where: { $0.id == old.id }) {
                transactions[index] = new
            }

        case .deleted(let tx):
            transactions.removeAll { $0.id == tx.id }
            totalTransactionCount = max(0, totalTransactionCount - 1)

        case .bulkAdded(let txs):
            transactions.append(contentsOf: txs)
            totalTransactionCount += txs.count

        // MARK: - Recurring Series Events (Phase 9)

        case .seriesCreated(let series):
            updateStateForSeriesCreated(series)

        case .seriesUpdated(let old, let new):
            updateStateForSeriesUpdated(old: old, new: new)

        case .seriesStopped(let seriesId, let fromDate):
            updateStateForSeriesStopped(seriesId: seriesId, fromDate: fromDate)

        case .seriesDeleted(let seriesId, let deleteTransactions):
            updateStateForSeriesDeleted(seriesId: seriesId, deleteTransactions: deleteTransactions)
        }
    }

    // MARK: - Recurring State Update Helpers (Phase 9)

    /// Update state when a recurring series is created
    private func updateStateForSeriesCreated(_ series: RecurringSeries) {
        // Simply add series to array
        // Transaction generation is handled in TransactionStore+Recurring.createSeries()
        recurringSeries.append(series)

    }

    /// Update state when a recurring series is updated
    private func updateStateForSeriesUpdated(old: RecurringSeries, new: RecurringSeries) {
        // Update series in array
        if let index = recurringSeries.firstIndex(where: { $0.id == old.id }) {
            recurringSeries[index] = new
        }


        // Note: Transaction regeneration is handled in TransactionStore+Recurring.updateSeries()
    }

    /// Update state when a recurring series is stopped
    private func updateStateForSeriesStopped(seriesId: String, fromDate: String) {
        // Update series status to inactive
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            var updatedSeries = recurringSeries[index]
            updatedSeries.isActive = false
            recurringSeries[index] = updatedSeries
        }


        // Note: Transaction cleanup is handled in TransactionStore+Recurring.stopSeries()
        // before calling apply()
    }

    /// Update state when a recurring series is deleted
    private func updateStateForSeriesDeleted(seriesId: String, deleteTransactions: Bool) {
        // Remove series from array
        recurringSeries.removeAll { $0.id == seriesId }


        // Note: Transaction cleanup and occurrence removal is handled in
        // TransactionStore+Recurring.deleteSeries() before calling apply()
    }

    // MARK: - Recurring Transaction Generation (Phase 9)

    /// Generate and add transactions for a recurring series
    /// Helper method used by createSeries and updateSeries
    /// - Parameters:
    ///   - series: The recurring series to generate transactions for
    ///   - horizonMonths: Number of months ahead to generate (default: 3)
    internal func generateAndAddTransactions(for series: RecurringSeries, horizonMonths: Int = 3) async throws {
        let existingTransactionIds = Set(transactions.map { $0.id })
        let result = recurringGenerator.generateTransactions(
            series: [series],
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: existingTransactionIds,
            accounts: accounts,
            baseCurrency: baseCurrency,
            horizonMonths: horizonMonths
        )

        // Add generated transactions via bulkAdded event
        if !result.transactions.isEmpty {
            let bulkEvent = TransactionEvent.bulkAdded(result.transactions)
            try await apply(bulkEvent)

            // Track occurrences
            recurringOccurrences.append(contentsOf: result.occurrences)

            // Persist occurrences
            repository.saveRecurringOccurrences(recurringOccurrences)

        }
    }

    /// Validate a transaction before adding/updating
    /// Phase 1: Complete validation logic
    private func validate(_ transaction: Transaction) throws {
        // Amount validation
        guard transaction.amount > 0 else {
            throw TransactionStoreError.invalidAmount
        }

        // Account exists (if specified)
        // Allow transactions without accountId (e.g., recurring subscriptions without account)
        if let accountId = transaction.accountId, !accountId.isEmpty {
            guard accounts.contains(where: { $0.id == accountId }) else {
                throw TransactionStoreError.accountNotFound
            }
        }

        // Target account exists (for transfers)
        if let targetId = transaction.targetAccountId, !targetId.isEmpty {
            guard accounts.contains(where: { $0.id == targetId }) else {
                throw TransactionStoreError.targetAccountNotFound
            }
        }

        // Category exists (for expense/income)
        if transaction.type != .internalTransfer && !transaction.category.isEmpty {
            guard categories.contains(where: { $0.name == transaction.category }) else {
                throw TransactionStoreError.categoryNotFound
            }
        }
    }

    /// Update balances for affected accounts
    /// ✅ REFACTORED: Use incremental updates instead of full recalculation
    /// This fixes the balance doubling bug by applying transaction deltas instead of recalculating from initialBalance
    private func updateBalances(for event: TransactionEvent) {
        // Get affected account IDs from event
        let affectedAccounts = event.affectedAccounts

        guard !affectedAccounts.isEmpty else {
            return
        }

        // ✅ FIX: Use updateForTransaction() for incremental updates
        // instead of recalculateAccounts() which recalculates from initialBalance
        Task {
            switch event {
            case .added(let transaction):
                // Apply transaction incrementally (O(1) instead of O(n))
                await balanceCoordinator.updateForTransaction(
                    transaction,
                    operation: .add(transaction)
                )

            case .deleted(let transaction):
                // Revert transaction incrementally
                await balanceCoordinator.updateForTransaction(
                    transaction,
                    operation: .remove(transaction)
                )

            case .updated(let old, let new):
                // Update transaction (revert old, apply new)
                await balanceCoordinator.updateForTransaction(
                    new,
                    operation: .update(old: old, new: new)
                )

            case .bulkAdded(let transactions):
                // Bulk add - apply each transaction
                for transaction in transactions {
                    await balanceCoordinator.updateForTransaction(
                        transaction,
                        operation: .add(transaction)
                    )
                }

            // Handle other event types (recurring series events, etc.)
            default:
                // For other events, do nothing - they don't affect balances directly
                break
            }

        }
    }

    /// Update balance when adding a transaction
    // TEMPORARILY REMOVED: Balance update methods
    // These will be reimplemented to work with BalanceCoordinator in Phase 7.1
    // See updateBalances(for:) method above for details

    /// Phase 28-C: Incremental persist — O(1) per transaction event.
    /// Replaces `saveTransactions([all transactions])` which was O(3N) = ~57,000 ops for 19k records.
    /// - .added: insertTransaction — creates one CoreData entity (O(1))
    /// - .deleted: no-op — deleteTransactionImmediately already called in invalidateCache(for:)
    /// - .updated: updateTransactionFields — fetches by PK and updates fields (O(1))
    /// - .bulkAdded: batchInsertTransactions — NSBatchInsertRequest (O(N) but fast)
    /// - series events: keep full save (small datasets, infrequent)
    private func persistIncremental(_ event: TransactionEvent) {
        switch event {
        case .added(let tx):
            repository.insertTransaction(tx)

        case .deleted:
            // deleteTransactionImmediately already called in invalidateCache(for:) — no-op here
            break

        case .updated(_, let new):
            repository.updateTransactionFields(new)

        case .bulkAdded(let txs):
            repository.batchInsertTransactions(txs)

        case .seriesCreated, .seriesUpdated, .seriesStopped, .seriesDeleted:
            // Recurring series are small datasets; use the existing full-save path
            repository.saveRecurringSeries(recurringSeries)
            repository.saveRecurringOccurrences(recurringOccurrences)
        }
    }

    /// Persist current state to repository
    /// Phase 1: Persistence for transactions only (accounts handled separately)
    /// Phase 9: Added recurring series and occurrences persistence
    private func persist() async {
        // Save transactions
        repository.saveTransactions(transactions)

        // ✨ Phase 9: Save recurring data
        repository.saveRecurringSeries(recurringSeries)
        repository.saveRecurringOccurrences(recurringOccurrences)

        // Note: Accounts are not saved here - balance is managed by BalanceCoordinator
        // and will trigger its own save when balances are recalculated

    }

    /// Persist accounts to repository
    /// Phase 3: TransactionStore now manages account persistence
    private func persistAccounts() {
        repository.saveAccounts(accounts)

    }

    /// Persist categories to repository
    /// Phase 3: TransactionStore now manages category persistence
    private func persistCategories() {
        repository.saveCategories(categories)

    }

    /// Persist subcategories to repository
    /// Phase 10: TransactionStore now manages subcategory persistence
    private func persistSubcategories() {
        repository.saveSubcategories(subcategories)

    }

    /// Persist category-subcategory links to repository
    /// Phase 10: TransactionStore now manages category-subcategory link persistence
    private func persistCategorySubcategoryLinks() {
        repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)

    }

    /// Persist transaction-subcategory links to repository
    /// Phase 10: TransactionStore now manages transaction-subcategory link persistence
    private func persistTransactionSubcategoryLinks() {
        repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)

    }

    /// Phase 20: Granular cache invalidation based on event type
    /// Only invalidates affected cache keys instead of clearing everything
    private func invalidateCache(for event: TransactionEvent) {
        // Summary is always affected by any transaction change
        cache.remove(UnifiedTransactionCache.Key.summary)
        cache.remove(UnifiedTransactionCache.Key.summaryFiltered)

        // Category expenses always affected
        cache.remove(UnifiedTransactionCache.Key.categoryExpenses)

        // Phase 36: Removed synchronous invalidateCaches() call — the debounced
        // syncTransactionStoreToViewModels() handles invalidation. Calling it both
        // here and in the debounced path caused double-invalidation on every mutation.
        // @Observable tracking on `transactions` array ensures dependent computed
        // properties in QuickAddCoordinator recompute automatically.

        switch event {
        case .added(let tx):
            cache.remove(UnifiedTransactionCache.Key.dailyExpenses(date: tx.date))

        case .deleted(let tx):
            cache.remove(UnifiedTransactionCache.Key.dailyExpenses(date: tx.date))
            // Immediately delete from CoreData so the deletion is persisted
            // even if the app is killed before the async saveTransactions() Task completes.
            repository.deleteTransactionImmediately(id: tx.id)

        case .updated(let old, let new):
            cache.remove(UnifiedTransactionCache.Key.dailyExpenses(date: old.date))
            if old.date != new.date {
                cache.remove(UnifiedTransactionCache.Key.dailyExpenses(date: new.date))
            }

        case .bulkAdded:
            // Bulk operations affect too many keys — full invalidation
            cache.invalidateAll()

        case .seriesCreated, .seriesUpdated, .seriesStopped, .seriesDeleted:
            // Recurring events may affect multiple dates — full invalidation for safety
            cache.invalidateAll()
        }
    }

    /// Convert amount between currencies
    private func convertToCurrency(amount: Double, from: String, to: String) -> Double {
        // Same currency - no conversion
        if from == to {
            return amount
        }

        // Use currency converter (sync version for computed properties)
        return CurrencyConverter.convertSync(amount: amount, from: from, to: to) ?? amount
    }

    /// Convert amount to base currency

    // MARK: - Category Synchronization

    /// Synchronize categories from CategoriesViewModel during CSV import
    /// This ensures TransactionStore knows about newly created categories
    /// before transactions are added
    /// ✨ Phase 10: Updated to just update in-memory array, persistence happens in finishImport()
    func syncCategories(_ newCategories: [CustomCategory]) async {

        categories = newCategories

        // ✨ Phase 10: Don't persist during import - will be done in finishImport()
        // This ensures all categories are saved synchronously at once
        if !isImporting {
            // Only persist if not in import mode (e.g., manual sync)
            repository.saveCategories(newCategories)
        } else {
        }
    }
}

// MARK: - Debug Helpers

