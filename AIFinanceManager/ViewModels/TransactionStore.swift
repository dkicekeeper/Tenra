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
    internal(set) var transactions: [Transaction] = []

    /// Pre-maintained set of transaction IDs for O(1) lookups (avoids O(N) Set construction)
    @ObservationIgnored internal var transactionIdSet: Set<String> = []

    /// All accounts - managed alongside transactions for balance updates
    internal(set) var accounts: [Account] = []

    /// All categories - needed for validation
    internal(set) var categories: [CustomCategory] = []

    // MARK: - Subcategory Data (Phase 10: CSV Import Fix - Single Source of Truth)

    /// All subcategories - managed alongside categories
    internal(set) var subcategories: [Subcategory] = []

    /// Links between categories and subcategories
    internal(set) var categorySubcategoryLinks: [CategorySubcategoryLink] = []

    /// Links between transactions and subcategories
    internal(set) var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []

    // MARK: - Dependencies

    @ObservationIgnored internal let repository: DataRepositoryProtocol  // ✨ Phase 9: internal for access from extension
    @ObservationIgnored internal let cache: UnifiedTransactionCache

    // ✅ REFACTORED: Balance coordinator is now REQUIRED (not optional)
    // This ensures balance updates always occur, no silent failures
    @ObservationIgnored private let balanceCoordinator: BalanceCoordinator

    // Phase 03-PERF-02: Recurring state extracted to RecurringStore
    @ObservationIgnored internal let recurringStore: RecurringStore

    // MARK: - Recurring Forwarders (Phase 03-PERF-02)
    // Extensions and callers use these to access RecurringStore state without knowing the indirection.
    var recurringSeries: [RecurringSeries] { recurringStore.recurringSeries }
    var recurringOccurrences: [RecurringOccurrence] { recurringStore.recurringOccurrences }
    internal var recurringGenerator: RecurringTransactionGenerator { recurringStore.recurringGenerator }
    internal var recurringValidator: RecurringValidationService { recurringStore.recurringValidator }
    internal var recurringCache: LRUCache<String, [Transaction]> { recurringStore.recurringCache }

    // Settings
    internal var baseCurrency: String = "KZT"

    // Import mode flag - when true, persistence is deferred until finishImport()
    internal(set) var isImporting: Bool = false

    // Phase 17: Debounce task for coalescing rapid mutations into single sync
    private var syncDebounceTask: Task<Void, Never>?

    // Lifecycle observer token for cleanup in deinit
    @ObservationIgnored private var lifecycleObserver: NSObjectProtocol?

    // Coordinator for syncing changes to ViewModels (with @Observable we need manual sync)
    @ObservationIgnored weak var coordinator: AppCoordinator?


    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol,
        balanceCoordinator: BalanceCoordinator,
        recurringStore: RecurringStore,        // Phase 03-PERF-02
        cacheCapacity: Int = 1000
    ) {
        self.repository = repository
        self.balanceCoordinator = balanceCoordinator
        self.recurringStore = recurringStore
        self.cache = UnifiedTransactionCache(capacity: cacheCapacity)

        // Setup notification observer for app lifecycle
        setupNotificationObservers()
    }

    deinit {
        if let observer = lifecycleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupNotificationObservers() {
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: .applicationDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.rescheduleSubscriptionNotifications()
                // Extend recurring horizons: any series whose future occurrence date has
                // arrived (or was never generated) gets a new next occurrence added.
                await self?.extendAllActiveSeriesHorizons()
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
    /// Phase 40: All transactions are loaded into memory (no window limit).
    /// 19k transactions × ~400 bytes ≈ 7.6 MB — a single source of truth.
    func loadData() async throws {
        // Capture repository before leaving @MainActor — it's a constant (@ObservationIgnored let).
        let repo = self.repository

        // Run ALL repository reads on a background thread.
        // Each repository method uses bgContext.performAndWait internally,
        // so they are safe to call from any thread.
        let (txs, accs, cats, subs, catLinks, txLinks, series, occurrences) =
            try await Task.detached(priority: .userInitiated) {
                let txs        = repo.loadTransactions(dateRange: nil)  // Phase 40: load all
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
        transactionIdSet = Set(txs.map { $0.id })
        categories = CategoryOrderManager.shared.applyOrders(to: cats)
        subcategories = subs
        categorySubcategoryLinks = catLinks
        transactionSubcategoryLinks = txLinks
        recurringStore.load(series: series, occurrences: occurrences)  // Phase 03-PERF-02

        // Note: baseCurrency will be set via updateBaseCurrency() from AppCoordinator

        // Extend recurring horizons in background: generates the next future occurrence
        // for any active series that has no future transaction (e.g. yearly series, or any
        // series whose pre-generated future date has now arrived).
        Task(priority: .background) { [weak self] in
            await self?.extendAllActiveSeriesHorizons()
        }
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

        // Currency change requires full balance recalculation in BalanceCoordinator
        Task {
            await balanceCoordinator.recalculateAll(accounts: accounts, transactions: transactions)
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

            // Save recurring data — Phase 03-PERF-02: delegate to RecurringStore
            recurringStore.saveSeries()
            recurringStore.saveOccurrences()

        } catch {
            print("❌ [TransactionStore] finishImport FAILED: \(error)")
            throw TransactionStoreError.persistenceFailed(error)
        }

        // Mark import done ONLY after all saves have succeeded.
        // Setting this earlier would fire ContentView observers while CoreData writes are still in progress.
        isImporting = false

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


    // MARK: - Private Helpers

    /// Apply an event to the store
    /// Phase 1-4: Core event processing - validates, updates state, balances, cache, persists
    /// ✨ Phase 9: Made internal for access from TransactionStore+Recurring extension
    /// Phase 40: Aggregate services removed — all transactions in memory (single source of truth)
    internal func apply(_ event: TransactionEvent) async throws {
        // 1. Update state (SSOT)
        updateState(event)

        // 2. Update balances (incremental, awaited for consistency)
        await updateBalances(for: event)

        // 3. Phase 20: Granular cache invalidation — only invalidate what changed
        invalidateCache(for: event)

        // 4. Phase 28-C: Incremental persist — O(1) per event (no await needed)
        if !isImporting {
            persistIncremental(event)
        }

        // 5. Phase 17: Debounced sync — coalesces rapid mutations (e.g., batch adds)
        // @Observable automatically notifies SwiftUI for TransactionStore property changes.
        // Debounced sync handles cache invalidation and insights recompute.
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16)) // ~1 frame
            guard !Task.isCancelled else { return }
            // Pass batchMode=true during import so InsightsVM isn't invalidated on every batch.
            self?.coordinator?.syncTransactionStoreToViewModels(batchMode: self?.isImporting ?? false)
        }
    }

    /// Update state based on event
    private func updateState(_ event: TransactionEvent) {
        switch event {
        case .added(let tx):
            transactions.append(tx)
            transactionIdSet.insert(tx.id)

        case .updated(let old, let new):
            if let index = transactions.firstIndex(where: { $0.id == old.id }) {
                transactions[index] = new
            }
            // IDs don't change on update

        case .deleted(let tx):
            transactions.removeAll { $0.id == tx.id }
            transactionIdSet.remove(tx.id)

        case .bulkAdded(let txs):
            transactions.append(contentsOf: txs)
            transactionIdSet.formUnion(txs.map { $0.id })

        // MARK: - Recurring Series Events (Phase 9 / Phase 03-PERF-02: delegated to RecurringStore)

        case .seriesCreated(let series):
            recurringStore.handleSeriesCreated(series)

        case .seriesUpdated(let old, let new):
            recurringStore.handleSeriesUpdated(old: old, new: new)

        case .seriesStopped(let seriesId, _):
            recurringStore.handleSeriesStopped(seriesId: seriesId)

        case .seriesDeleted(let seriesId, _):
            recurringStore.handleSeriesDeleted(seriesId: seriesId)
        }
    }

    // MARK: - Recurring Transaction Generation (Phase 9)

    /// Generate and add transactions for a recurring series
    /// Helper method used by createSeries and updateSeries
    /// - Parameters:
    ///   - series: The recurring series to generate transactions for
    ///   - horizonMonths: Number of months ahead to generate (default: 3)
    internal func generateAndAddTransactions(for series: RecurringSeries, horizonMonths: Int = 3) async throws {
        let existingTransactionIds = transactionIdSet
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

            // Track occurrences — Phase 03-PERF-02: delegate to recurringStore
            recurringStore.appendOccurrences(result.occurrences)
            recurringStore.saveOccurrences()
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

        // Category exists (for expense/income — skip system types with internal category names).
        // Note: Empty category is intentionally allowed — represents "uncategorized" transactions.
        // CSV import and voice input may produce transactions without a category.
        switch transaction.type {
        case .internalTransfer, .loanPayment, .loanEarlyRepayment,
             .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            break
        default:
            if !transaction.category.isEmpty {
                guard categories.contains(where: { $0.name == transaction.category }) else {
                    throw TransactionStoreError.categoryNotFound
                }
            }
        }
    }

    /// Update balances for affected accounts
    /// ✅ REFACTORED: Use incremental updates instead of full recalculation
    /// This fixes the balance doubling bug by applying transaction deltas instead of recalculating from initialBalance
    private func updateBalances(for event: TransactionEvent) async {
        // Get affected account IDs from event
        let affectedAccounts = event.affectedAccounts

        guard !affectedAccounts.isEmpty else {
            return
        }

        // Incremental balance updates — O(1) per transaction via BalanceCoordinator
        switch event {
        case .added(let transaction):
            await balanceCoordinator.updateForTransaction(
                transaction,
                operation: .add(transaction)
            )

        case .deleted(let transaction):
            await balanceCoordinator.updateForTransaction(
                transaction,
                operation: .remove(transaction)
            )

        case .updated(let old, let new):
            await balanceCoordinator.updateForTransaction(
                new,
                operation: .update(old: old, new: new)
            )

        case .bulkAdded(let transactions):
            for transaction in transactions {
                await balanceCoordinator.updateForTransaction(
                    transaction,
                    operation: .add(transaction)
                )
            }

        default:
            break
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
            // Phase 03-PERF-02: delegate to RecurringStore
            recurringStore.saveSeries()
            recurringStore.saveOccurrences()
        }
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


}

// MARK: - Debug Helpers

