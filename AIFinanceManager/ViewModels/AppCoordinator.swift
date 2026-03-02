//
//  AppCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  Coordinator for managing ViewModel dependencies and initialization

import Foundation
import SwiftUI
import CoreData
import Observation
import os

/// Coordinator that manages all ViewModels and their dependencies
/// Provides a single point of initialization and dependency injection
@Observable
@MainActor
class AppCoordinator {
    // MARK: - Repository

    @ObservationIgnored let repository: DataRepositoryProtocol

    // MARK: - ViewModels

    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    // ✨ Phase 9: Removed SubscriptionsViewModel - recurring operations now in TransactionStore
    @ObservationIgnored let depositsViewModel: DepositsViewModel
    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let settingsViewModel: SettingsViewModel  // NEW: Phase 1 - Settings refactoring
    @ObservationIgnored let insightsViewModel: InsightsViewModel  // NEW: Phase 17 - Financial Insights

    // MARK: - New Architecture (Phase 7)

    /// NEW 2026-02-05: TransactionStore - Single Source of Truth for transactions
    /// ✨ Phase 9: Now includes recurring operations (subscriptions + recurring transactions)
    /// Replaces multiple services: TransactionCRUDService, CategoryAggregateService, etc.
    @ObservationIgnored let transactionStore: TransactionStore

    // MARK: - Coordinators

    // ✨ Phase 9: Removed RecurringTransactionCoordinator - operations now in TransactionStore

    /// REFACTORED 2026-02-02: Single entry point for balance operations
    /// Phase 1-4: Foundation completed - Store, Engine, Queue, Cache, Coordinator
    @ObservationIgnored let balanceCoordinator: BalanceCoordinator

    // MARK: - Pagination (Task 9)

    /// Read-optimised paginated view over TransactionEntity via NSFetchedResultsController.
    /// TransactionStore remains SSOT for mutations; this controller is presentation-only.
    @ObservationIgnored private(set) var transactionPaginationController: TransactionPaginationController

    // MARK: - Private Properties

    private var isInitialized = false
    private var isFastPathStarted = false

    @ObservationIgnored private let logger = Logger(subsystem: "AIFinanceManager", category: "AppCoordinator")

    // Observable loading stage outputs — views bind to these for per-element skeletons
    private(set) var isFastPathDone = false       // accounts + categories ready (~50ms)
    private(set) var isFullyInitialized = false   // transactions + all data ready (~1-3s)

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol? = nil) {
        self.repository = repository ?? CoreDataRepository()

        // Task 9: Pagination controller — uses CoreDataStack.shared viewContext for FRC.
        self.transactionPaginationController = TransactionPaginationController(stack: CoreDataStack.shared)

        // Initialize ViewModels in dependency order
        // 1. Accounts (no dependencies)
        self.accountsViewModel = AccountsViewModel(repository: self.repository)

        // 2. REFACTORED 2026-02-02: Initialize BalanceCoordinator FIRST
        // This is the Single Source of Truth for all balances
        // Created before TransactionsViewModel to avoid circular dependencies
        self.balanceCoordinator = BalanceCoordinator(
            repository: self.repository,
            cacheManager: nil  // Will be set later after TransactionsViewModel is created
        )

        // 3. Transactions (MIGRATED: now independent, uses BalanceCoordinator)
        // Create first to access currencyService and appSettings
        self.transactionsViewModel = TransactionsViewModel(repository: self.repository)

        // 3.1 NEW 2026-02-05: Initialize TransactionStore
        // Single Source of Truth for all transaction operations
        // UPDATED 2026-02-05 Phase 7.1: Added balanceCoordinator for automatic balance updates
        // ✨ UPDATED 2026-02-09 Phase 9: Now includes recurring operations with LRU cache
        // Phase 03-PERF-02: RecurringStore created before TransactionStore; TransactionStore owns it.
        // Views that need recurring data go through TransactionStore.recurringSeries (forwarding computed property).
        let recurringStore = RecurringStore(repository: self.repository)
        self.transactionStore = TransactionStore(
            repository: self.repository,
            balanceCoordinator: self.balanceCoordinator,
            recurringStore: recurringStore,
            cacheCapacity: 1000
        )

        // 3. Categories (depends on TransactionsViewModel for currency conversion)
        self.categoriesViewModel = CategoriesViewModel(
            repository: self.repository,
            currencyService: transactionsViewModel.currencyService,
            appSettings: transactionsViewModel.appSettings
        )

        // ✨ Phase 9: Removed SubscriptionsViewModel initialization - recurring now in TransactionStore

        // 5. Deposits (depends on Accounts)
        self.depositsViewModel = DepositsViewModel(repository: self.repository, accountsViewModel: accountsViewModel)

        // ✨ Phase 9: Removed RecurringTransactionCoordinator initialization - operations now in TransactionStore

        // 7. REFACTORED 2026-02-04: Setup SettingsViewModel (Phase 1)
        // Initialize Settings services with Protocol-Oriented Design
        let storageService = SettingsStorageService()
        let wallpaperService = WallpaperManagementService()
        let validationService = SettingsValidationService()

        // Initialize coordinators for dangerous operations
        // ✨ Phase 9: Use TransactionStore instead of SubscriptionsViewModel
        let dataResetCoordinator = DataResetCoordinator(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            transactionStore: transactionStore,
            depositsViewModel: depositsViewModel
        )

        let exportCoordinator = ExportCoordinator(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel
        )

        // Phase 2: CSVImportCoordinator will be created lazily in ImportFlowCoordinator
        // because it requires csvFile headers during initialization
        let csvImportCoordinator: CSVImportCoordinatorProtocol? = nil

        // Create SettingsViewModel with all dependencies
        self.settingsViewModel = SettingsViewModel(
            storageService: storageService,
            wallpaperService: wallpaperService,
            resetCoordinator: dataResetCoordinator,
            validationService: validationService,
            exportCoordinator: exportCoordinator,
            importCoordinator: csvImportCoordinator,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            initialSettings: transactionsViewModel.appSettings
        )

        // Phase 17: Initialize InsightsService and InsightsViewModel
        let insightsCache = InsightsCache()
        let insightsFilterService = TransactionFilterService(dateFormatter: DateFormatters.dateFormatter)
        let insightsQueryService = TransactionQueryService()

        // Phase 40: Budget cache removed — direct O(N) scan on all-time transactions is fast enough.
        let insightsBudgetService = CategoryBudgetService(
            currencyService: transactionsViewModel.currencyService,
            appSettings: transactionsViewModel.appSettings
        )
        let insightsService = InsightsService(
            transactionStore: self.transactionStore,
            filterService: insightsFilterService,
            queryService: insightsQueryService,
            budgetService: insightsBudgetService,
            cache: insightsCache
        )
        self.insightsViewModel = InsightsViewModel(
            insightsService: insightsService,
            transactionStore: self.transactionStore,
            transactionsViewModel: self.transactionsViewModel
        )

        // @Observable handles change propagation automatically - no manual observer setup needed

        // ✅ CATEGORY REFACTORING: Setup Single Source of Truth for categories
        // TransactionsViewModel subscribes to CategoriesViewModel.categoriesPublisher
        // This eliminates manual sync in 3 places (CategoriesManagementView, deprecated CSVImportService)
        transactionsViewModel.setCategoriesViewModel(categoriesViewModel)

        // ✨ Phase 9: Removed - TransactionStore now handles recurring operations

        // ✅ BALANCE REFACTORING: Inject BalanceCoordinator into ViewModels
        // This establishes Single Source of Truth for balances
        accountsViewModel.balanceCoordinator = balanceCoordinator
        transactionsViewModel.balanceCoordinator = balanceCoordinator
        depositsViewModel.balanceCoordinator = balanceCoordinator

        // Phase 8: Inject TransactionStore into TransactionsViewModel
        // Completes migration to Single Source of Truth for transactions
        transactionsViewModel.transactionStore = transactionStore

        // PHASE 3: Inject TransactionStore into AccountsViewModel and CategoriesViewModel
        // They will observe accounts/categories from TransactionStore instead of owning them
        accountsViewModel.transactionStore = transactionStore
        categoriesViewModel.transactionStore = transactionStore

        // Set coordinator reference in TransactionStore for automatic sync after mutations
        transactionStore.coordinator = self

        // PHASE 3: Setup initial sync from TransactionStore → ViewModels
        // With @Observable, we sync on-demand instead of using Combine subscriptions
        categoriesViewModel.setupTransactionStoreObserver()

        // Initial sync from TransactionStore to ViewModels
        syncTransactionStoreToViewModels()

        // ✅ @Observable: No need for Combine observer
        // SwiftUI automatically tracks changes to BalanceCoordinator.balances

    }

    // MARK: - Public Methods

    /// Fast-path startup: loads accounts + categories + settings (<50ms combined).
    /// Call this first so the UI can appear. Full initialization continues via initialize().
    func initializeFastPath() async {
        guard !isFastPathStarted else { return }
        isFastPathStarted = true
        // Load accounts and categories only (small datasets, needed for first frame)
        try? await transactionStore.loadAccountsOnly()
        // NOTE: Calling without transactions so that shouldCalculateFromTransactions accounts
        // briefly show their persisted balance (Phase A). initialize() will pass the full
        // transaction set for Phase B background recalculation.
        await balanceCoordinator.registerAccounts(transactionStore.accounts)
        // Load settings (UserDefaults read — instant)
        await settingsViewModel.loadInitialData()
        isFastPathDone = true
    }

    /// Initialize all ViewModels asynchronously
    /// Should be called once after AppCoordinator is created
    func initialize() async {
        // Prevent double initialization
        guard !isInitialized else {
            return
        }

        isInitialized = true
        PerformanceProfiler.start("AppCoordinator.initialize")

        let t_init_start = CACurrentMediaTime()
        logger.debug("🚀 [INIT] initialize() START — tx count before load: \(self.transactionStore.transactions.count)")

        // Phase 19: Streamlined startup — no duplicate loads
        // 1. Load all data into TransactionStore (single source of truth)
        let t0 = CACurrentMediaTime()
        try? await transactionStore.loadData()
        let t1 = CACurrentMediaTime()
        logger.debug("📦 [INIT] loadData()            : \(String(format: "%.0f", (t1-t0)*1000))ms — tx:\(self.transactionStore.transactions.count) acc:\(self.transactionStore.accounts.count)")

        // 2. Sync subcategory data and invalidate caches (no array copies)
        syncTransactionStoreToViewModels(batchMode: true)
        let t2 = CACurrentMediaTime()
        logger.debug("🔄 [INIT] syncToViewModels()    : \(String(format: "%.0f", (t2-t1)*1000))ms")

        // 3. Register accounts with BalanceCoordinator.
        // account.balance is kept accurate by persistIncremental() on every mutation,
        // so no transaction list is needed (Phase B removed in Phase 31).
        await balanceCoordinator.registerAccounts(transactionStore.accounts)
        let t3 = CACurrentMediaTime()
        logger.debug("💰 [INIT] registerAccounts()    : \(String(format: "%.0f", (t3-t2)*1000))ms")

        // Task 9: Start FRC after full data is loaded so the initial fetch sees all transactions.
        // Backfill runs concurrently in background — does NOT block History.
        transactionPaginationController.setup()
        let t4 = CACurrentMediaTime()
        logger.debug("📋 [INIT] paginationCtrl.setup(): \(String(format: "%.0f", (t4-t3)*1000))ms — sections:\(self.transactionPaginationController.sections.count) totalCount:\(self.transactionPaginationController.totalCount)")

        // Mark fully initialized AFTER the FRC is ready — History is accessible instantly.
        // Backfill runs in the background Task below; when it saves, the viewContext
        // (automaticallyMergesChangesFromParent = true) receives the changes automatically
        // and the FRC's controllerDidChangeContent fires → sections rebuild without any
        // extra code on our part.
        isFullyInitialized = true
        let t5 = CACurrentMediaTime()
        logger.debug("✅ [INIT] isFullyInitialized=true: total so far \(String(format: "%.0f", (t5-t_init_start)*1000))ms")

        // Phase 41: Trigger insights recompute now that all transactions are in memory.
        // syncTransactionStoreToViewModels(batchMode: true) skipped this to avoid a
        // pre-data compute; here we schedule it after the store is fully loaded.
        insightsViewModel.invalidateAndRecompute()

        // Task 9 / v3 migration: populate dateSectionKey for records that were imported via
        // NSBatchInsertRequest before 2026-02-24 (batch inserts bypass willSave()).
        // Fire-and-forget — History is already open.  The FRC refreshes automatically once
        // the background context saves (viewContext.automaticallyMergesChangesFromParent=true).
        Task(priority: .background) { [weak self] in
            await self?.backfillDateSectionKeysIfNeeded()
        }

        // 4. Generate recurring transactions in background (non-blocking)
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            await self.transactionsViewModel.generateRecurringTransactions()
        }

        // 5. Load settings (only if fast path hasn't already loaded them)
        if !isFastPathStarted {
            await settingsViewModel.loadInitialData()
        }

        // Phase 40: Aggregate rebuild removed — MonthlyAggregateService and CategoryAggregateService
        // deleted. All insights computed in-memory from transactionStore.transactions.

        // Phase 19: Removed transactionsViewModel.loadDataAsync() — was duplicating TransactionStore work
        // (generateRecurringAsync + loadAggregateCacheAsync which was a no-op)

        // Purge persistent history older than 7 days — prevents unbounded DB growth
        Task(priority: .background) {
            CoreDataStack.shared.purgeHistory(olderThan: 7)
        }

        PerformanceProfiler.end("AppCoordinator.initialize")
    }
    
    // MARK: - Private Methods

    /// REMOVED: setupViewModelObservers() - not needed with @Observable
    /// @Observable automatically notifies SwiftUI of changes, no manual propagation needed

    // MARK: - CoreData v3 Migration Backfill

    /// UserDefaults key that records whether the one-time dateSectionKey backfill has
    /// completed for every record in the database.  Once set, `backfillDateSectionKeysIfNeeded`
    /// returns in ~0ms without touching CoreData at all.
    ///
    /// Root-cause note: before batchInsertTransactions was fixed (2026-02-24),
    /// NSBatchInsertRequest bypassed willSave() and left dateSectionKey = nil on every
    /// CSV-imported transaction.  This caused the 747ms backfill to run on every launch.
    /// With the batch-insert fix in place new records always have dateSectionKey set;
    /// this flag lets existing databases skip the expensive COUNT query after the
    /// one-time migration completes.
    private static let backfillCompletedKey = "dateSectionKey_v3_backfill_complete"

    /// One-time backfill: populates `dateSectionKey` for all TransactionEntity records
    /// whose value is nil or empty (first launch after upgrading to CoreData model v3,
    /// where `dateSectionKey` became a stored attribute instead of transient, AND for
    /// records imported via NSBatchInsertRequest before the 2026-02-24 fix).
    ///
    /// Fast-path (0ms): skipped entirely if the UserDefaults completion flag is set.
    /// Medium-path (~5ms): flag not set, but COUNT query returns 0 → sets flag and returns.
    /// Slow-path (one-time, ~700ms for 19k records): backfills all records, then sets flag.
    ///
    /// Runs in a background Task so it does NOT block `isFullyInitialized`.
    /// When the background context saves, `viewContext.automaticallyMergesChangesFromParent`
    /// merges the updated keys and the FRC's `controllerDidChangeContent` rebuilds sections.
    private func backfillDateSectionKeysIfNeeded() async {
        // Zero-cost fast-path: skip the expensive background context creation entirely
        // once we know every record in the database has a dateSectionKey.
        if UserDefaults.standard.bool(forKey: Self.backfillCompletedKey) {
            logger.debug("🗝️  [BACKFILL] skipped — completion flag set (0ms)")
            return
        }

        let stack = CoreDataStack.shared
        let context = stack.newBackgroundContext()

        await context.perform {
            // Check: are there any records without a section key?
            let countRequest = NSFetchRequest<NSNumber>(entityName: "TransactionEntity")
            countRequest.resultType = .countResultType
            countRequest.predicate = NSPredicate(
                format: "dateSectionKey == nil OR dateSectionKey == ''"
            )
            guard let needsBackfill = try? context.count(for: countRequest) else { return }

            guard needsBackfill > 0 else {
                // All records already have dateSectionKey — set the flag so future
                // launches skip this background-context round-trip entirely.
                // UserDefaults.set() is thread-safe; no main-queue dispatch needed.
                UserDefaults.standard.set(true, forKey: Self.backfillCompletedKey)
                return
            }

            // Fetch entities that need backfilling in large batches.
            // returnsObjectsAsFaults = false prefaults the batch so `date` is
            // immediately available without an extra SQL round-trip per object.
            let fetchRequest = TransactionEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "dateSectionKey == nil OR dateSectionKey == ''"
            )
            fetchRequest.fetchBatchSize = 500
            fetchRequest.returnsObjectsAsFaults = false

            guard let entities = try? context.fetch(fetchRequest) else { return }

            for entity in entities {
                let key = entity.date.map {
                    TransactionSectionKeyFormatter.string(from: $0)
                } ?? "0000-00-00"
                entity.dateSectionKey = key
            }

            if (try? context.save()) != nil {
                // Mark complete so the next launch skips this entirely.
                // UserDefaults.set() is thread-safe; call directly on the background queue.
                UserDefaults.standard.set(true, forKey: Self.backfillCompletedKey)
            }
        }
    }

    /// Phase 16: Lightweight sync — no array copies needed
    /// With computed properties, ViewModels read directly from TransactionStore.
    /// This method now only handles cache invalidation and insights.
    /// - Parameter batchMode: When true, skips insights recompute (for CSV imports, bulk operations)
    func syncTransactionStoreToViewModels(batchMode: Bool = false) {
        // Phase 16: No array copies — ViewModels use computed properties from TransactionStore
        // Only invalidate caches that derived computations depend on
        self.transactionsViewModel.invalidateCaches()

        // Sync subcategory data to CategoriesViewModel (not yet computed properties)
        self.categoriesViewModel.syncCategoriesFromStore()

        // Phase 18: Push-model — invalidate cache and schedule background recompute
        if !batchMode {
            self.insightsViewModel.invalidateAndRecompute()
        }
    }
}
