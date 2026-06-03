//
//  TransactionStore.swift
//  Tenra
//
//  Created on 2026-02-05
//
//  Unified store for all transaction operations.
//  Pattern: Event Sourcing + Single Source of Truth + LRU Cache
//

import Foundation
import CoreData
import Observation
import OSLog

private let logger = Logger(subsystem: "Tenra", category: "TransactionStore")

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
    var transactions: [Transaction] = []

    /// Lightweight Observable mirror of `transactions.count`.
    /// Views that only need to react to "did the count change" (e.g. `summaryTrigger`,
    /// empty-state checks) should observe this instead of reading `transactions.count`
    /// — that read subscribes the surrounding body to the entire 19k-element array,
    /// causing a full body re-eval every time any transaction is added/updated/deleted.
    private(set) var transactionsCount: Int = 0

    /// Pre-maintained set of transaction IDs for O(1) lookups (avoids O(N) Set construction)
    @ObservationIgnored internal var transactionIdSet: Set<String> = []

    /// Pre-maintained id → Transaction map, maintained alongside `transactions` array.
    /// Lets hot-path operations (update/delete/edit) skip the O(N) `.first(where:)` scan
    /// across 19k transactions. Sync rule: every mutation in `updateState()` MUST update
    /// both `transactions` and `transactionById` together.
    @ObservationIgnored private(set) var transactionById: [String: Transaction] = [:]

    /// Pre-maintained id → Account map, maintained alongside the `accounts` array.
    /// Replaces the pervasive `accounts.first(where: { $0.id == … })` linear scans in
    /// validation, transfers, balance recalculation, and recurring generation.
    /// Sync rule: every mutation of `accounts` (add/update/delete/reorder/load) MUST
    /// call `rebuildAccountById()` immediately after.
    @ObservationIgnored private(set) var accountById: [String: Account] = [:]

    /// Per-account transaction index, maintained incrementally by `apply()`.
    /// Lets `AccountRankingService.rankAccounts` skip the O(N) pre-grouping pass.
    /// Includes both `accountId` and `targetAccountId` references (transfers appear under both).
    @ObservationIgnored private(set) var transactionsByAccount: [String: [Transaction]] = [:]

    /// Bumps on every `apply()` call. Consumers (e.g. AccountsViewModel suggestion cache)
    /// use it as a cache key to detect when invalidation is needed without observing every
    /// transaction property. Also bumps for recurring-series events because those mutate
    /// generated transactions through `bulkAdded`, but we keep one counter for simplicity.
    @ObservationIgnored private(set) var mutationVersion: Int = 0

    /// Bumps on every `accounts` mutation (load/add/update/delete/reorder). Used by
    /// AccountsViewModel to invalidate cached filtered slices (regular/deposit/loan)
    /// without observing the whole `accounts` array.
    @ObservationIgnored private(set) var accountsMutationVersion: Int = 0

    /// Bumps every time the FX-rate cache changes (prewarm finishes, manual
    /// refresh, disk-restore on launch). Aggregator views that compute
    /// equivalents via `CurrencyConverter.convertSync` read this in their
    /// body so SwiftUI re-renders them once rates arrive. Mutated by
    /// `AppCoordinator` after `CurrencyConverter.prewarm()`.
    private(set) var currencyRatesVersion: Int = 0

    /// Force-bump the version to trigger re-render of views that observe it.
    /// Called from `AppCoordinator` after currency prewarm completes.
    ///
    /// If any aggregate bucket was filled while the FX-rate cache was cold
    /// (`aggregatesAreFXStale == true`), rebuild the category indexes once now
    /// that rates are available. Rebuild stays O(N_tx) but only runs on the
    /// first successful prewarm of each session.
    ///
    /// - Returns: `true` if cold-cache aggregates were rebuilt with fresh rates.
    ///   The caller must then also recalculate balances — cached balances for
    ///   cross-currency accounts were likewise computed at the cold rate and the
    ///   balance cache does not heal itself (cache audit #1).
    @discardableResult
    func bumpCurrencyRatesVersion() -> Bool {
        currencyRatesVersion &+= 1
        guard aggregatesAreFXStale else { return false }
        rebuildCategoryIndexes()
        // Account aggregates also depend on FX conversion (cross-currency
        // sources / targets). Rebuild together so they self-heal in one pass.
        rebuildAccountAggregates()
        categoriesMutationVersion &+= 1
        return true
    }

    /// All accounts - managed alongside transactions for balance updates
    var accounts: [Account] = []

    /// All categories - needed for validation
    var categories: [CustomCategory] = []

    // MARK: - Subcategory Data

    /// All subcategories - managed alongside categories
    var subcategories: [Subcategory] = []

    /// Links between categories and subcategories
    var categorySubcategoryLinks: [CategorySubcategoryLink] = []

    /// Links between transactions and subcategories
    var transactionSubcategoryLinks: [TransactionSubcategoryLink] = []

    // MARK: - Category Indexes (O(1) lookups)
    // Mirror the `transactionsByAccount` pattern: maintained incrementally inside
    // `updateState(_:)` and the CategoryCRUD funnel so every View can ask
    // "give me X for category Y" in constant time.

    /// O(1) category-by-id lookup — eliminates `customCategories.first(where:)` linear scans.
    /// Sync rule: every mutation of `categories` MUST keep `categoryById` in sync.
    @ObservationIgnored internal(set) var categoryById: [String: CustomCategory] = [:]

    /// Case-folded name → category id. Lets style/icon/color resolvers find a custom
    /// category by name in O(1) without scanning the array with lowercased() per call.
    @ObservationIgnored internal(set) var categoryIdByName: [String: String] = [:]

    /// Per-category-name transaction index — mirrors `transactionsByAccount`.
    /// Lets CategoryDetailView skip the O(N_tx) filter when fetching its history,
    /// and lets aggregate rebuilds run as O(M) where M is the category's own size.
    /// Includes both expense and income transactions; consumers filter by type if needed.
    @ObservationIgnored internal(set) var transactionsByCategoryName: [String: [Transaction]] = [:]

    /// Pre-aggregated category spending, keyed by `CategoryAggregate.makeId(...)`.
    /// 4 granularities per category: daily (last ~90 days) / monthly / yearly / all-time.
    /// Base currency only — conversion happens at apply-time, never at read-time.
    /// See CLAUDE.md ⚠️ #6 — DO NOT use `Transaction.convertedAmount` as a base-currency proxy.
    @ObservationIgnored internal(set) var categoryAggregatesByKey: [String: CategoryAggregate] = [:]

    /// True when at least one tx was added to aggregates while the FX-rate cache was cold.
    /// Cleared after `reconcileCategoryAggregatesForFX()` runs on the next `bumpCurrencyRatesVersion()`.
    @ObservationIgnored internal var aggregatesAreFXStale: Bool = false

    /// Bumps on every `categories` mutation (add/update/delete/rename/reorder). Used by Views
    /// as a cheap scalar Observable cache key — subscribing to this instead of the entire
    /// `categories` array prevents body re-eval on unrelated transaction mutations.
    internal(set) var categoriesMutationVersion: Int = 0

    // MARK: - Subcategory Indexes (O(1) lookups)

    /// O(1) subcategory-by-id lookup.
    @ObservationIgnored internal(set) var subcategoryById: [String: Subcategory] = [:]

    /// Ordered subcategory ids per category, sorted by `CategorySubcategoryLink.sortOrder`.
    @ObservationIgnored internal(set) var subcategoryIdsByCategoryId: [String: [String]] = [:]

    /// Subcategory ids linked to a given transaction.
    @ObservationIgnored internal(set) var subcategoryIdsByTransactionId: [String: [String]] = [:]

    /// O(1) usage count per subcategory — pre-maintained on every tx-subcategory link mutation.
    @ObservationIgnored internal(set) var subcategoryUsageCountById: [String: Int] = [:]

    /// O(1) last-used date per subcategory — pre-maintained on tx mutations.
    /// `Date.distantPast` if no linked transactions are known yet.
    @ObservationIgnored internal(set) var subcategoryLastUsedById: [String: Date] = [:]

    /// Bumps on every subcategory or link mutation. Use as a `.task(id:)` trigger.
    internal(set) var subcategoriesMutationVersion: Int = 0

    // MARK: - Series / Date / Account Aggregate Indexes (O(1) lookups)
    // Same pattern as the category indexes above. See docs/domains/transactions.md
    // for the full read/write contract.

    /// Pre-built id → parsed Date map. Filling once in `loadData()` and maintaining
    /// incrementally on every tx mutation removes the per-call
    /// `DateFormatter.date(from:)` cost (~16 µs × 19k = ~300 ms per filter pass)
    /// from `TransactionFilterService.filterByTimeRange`, deposit reconcile walks,
    /// budget services, etc.
    @ObservationIgnored internal(set) var parsedDateById: [String: Date] = [:]

    /// Per-recurring-series transaction index. Mirrors `transactionsByAccount`/
    /// `transactionsByCategoryName`. Used by SubscriptionEditView, SubscriptionDetailView,
    /// and any "show me linked payments" UI path. Replaces the
    /// `transactions.filter { $0.recurringSeriesId == X }` full scan.
    @ObservationIgnored internal(set) var transactionsBySeriesId: [String: [Transaction]] = [:]

    /// Pre-aggregated income/expense/count per account. Mirrors
    /// `categoryAggregatesByKey` for the account domain — patched on every tx mutation
    /// in `accountAggregatesApplyDelta`. Drives AccountDetailView reads in O(1).
    /// All amounts are in the OWNING account's currency, not base currency — accounts
    /// can have heterogeneous currencies and each detail view shows its own currency.
    @ObservationIgnored internal(set) var accountAggregatesByAccountId: [String: AccountAggregates] = [:]

    // MARK: - Dependencies

    @ObservationIgnored internal let repository: DataRepositoryProtocol
    @ObservationIgnored internal let cache: UnifiedTransactionCache

    // ✅ REFACTORED: Balance coordinator is now REQUIRED (not optional)
    // This ensures balance updates always occur, no silent failures
    @ObservationIgnored private let balanceCoordinator: BalanceCoordinator

    @ObservationIgnored internal let recurringStore: RecurringStore

    // MARK: - Recurring Forwarders
    // Extensions and callers use these to access RecurringStore state without knowing the indirection.
    var recurringSeries: [RecurringSeries] { recurringStore.recurringSeries }
    /// O(1) recurring series lookup. Forwarded from RecurringStore so callers don't
    /// need to know about the indirection. Used by TransactionCard, TransactionStore+Recurring,
    /// and views that resolve a series from a transaction's `recurringSeriesId`.
    var seriesById: [String: RecurringSeries] { recurringStore.seriesById }
    var recurringOccurrences: [RecurringOccurrence] { recurringStore.recurringOccurrences }
    internal var recurringGenerator: RecurringTransactionGenerator { recurringStore.recurringGenerator }
    internal var recurringValidator: RecurringValidationService { recurringStore.recurringValidator }
    internal var recurringCache: LRUCache<String, [Transaction]> { recurringStore.recurringCache }

    // Settings
    internal var baseCurrency: String = "KZT"

    // Import mode flag - when true, persistence is deferred until finishImport()
    var isImporting: Bool = false

    // Debounce task for coalescing rapid mutations into single sync
    private var syncDebounceTask: Task<Void, Never>?

    // Debounce task for category-aggregate persistence. Coalesces a burst of
    // tx mutations (e.g. CSV import, recurring generation) into one CoreData
    // save instead of one per delta.
    @ObservationIgnored internal var aggregatePersistDebounceTask: Task<Void, Never>?

    // Debounce tasks for subcategory link tables. The transaction edit screen
    // commits a Set<String> of subcategory ids on every keystroke, which used
    // to write the entire link table each time. Both maps coalesce now.
    @ObservationIgnored internal var categorySubcategoryLinksPersistTask: Task<Void, Never>?
    @ObservationIgnored internal var transactionSubcategoryLinksPersistTask: Task<Void, Never>?

    /// Debounced AccountAggregateEntity persistence — same 500ms pattern as
    /// `aggregatePersistDebounceTask` for categories. Coalesces a burst of
    /// account aggregate patches into one CoreData write.
    @ObservationIgnored internal var accountAggregatePersistTask: Task<Void, Never>?

    // Lifecycle observer token for cleanup in deinit
    @ObservationIgnored private var lifecycleObserver: NSObjectProtocol?
    @ObservationIgnored private var resignActiveObserver: NSObjectProtocol?

    // Reentrancy guard: prevents concurrent extendAllActiveSeriesHorizons() calls
    // (loadData + applicationDidBecomeActive can race on startup)
    @ObservationIgnored internal var isExtendingHorizons = false

    // Coordinator for syncing changes to ViewModels (with @Observable we need manual sync)
    @ObservationIgnored weak var coordinator: AppCoordinator?


    // MARK: - Initialization

    init(
        repository: DataRepositoryProtocol,
        balanceCoordinator: BalanceCoordinator,
        recurringStore: RecurringStore,
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
        if let observer = resignActiveObserver {
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
                guard let self else { return }
                // Skip if data hasn't been loaded yet — loadData() will extend horizons itself
                guard !self.accounts.isEmpty else { return }
                await self.rescheduleSubscriptionNotifications()
                // Extend recurring horizons: any series whose future occurrence date has
                // arrived (or was never generated) gets a new next occurrence added.
                await self.extendAllActiveSeriesHorizons()
                // If the day rolled over while backgrounded, fold any now-matured
                // future transactions into realized balances/aggregates.
                await self.recalculateLedgerIfDayChanged()
            }
        }

        // Flush debounced aggregate persists before the app may be suspended/killed, so a
        // kill within the 500ms debounce window can't drop the latest category/account
        // aggregate write (which would otherwise read stale on the next cold launch).
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: .applicationWillResignActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.flushAggregatePersist()
                await self.flushAccountAggregatePersist()
            }
        }
    }

    private func rescheduleSubscriptionNotifications() async {
        let activeSubscriptions = subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
        await SubscriptionNotificationScheduler.shared.rescheduleAllActiveSubscriptions(subscriptions: activeSubscriptions)
    }

    // MARK: - Data Loading

    /// Load initial data from repository.
    /// All CoreData fetches run on a background thread via Task.detached.
    /// MainActor is NOT blocked -- it awaits the background result.
    /// All transactions are loaded into memory (no window limit).
    /// 19k transactions x ~400 bytes = 7.6 MB -- a single source of truth.
    func loadData() async throws {
        // Capture repository before leaving @MainActor — it's a constant (@ObservationIgnored let).
        let repo = self.repository

        // Run ALL repository reads in parallel on background threads.
        // Each repository call creates its own newBackgroundContext() and is fully
        // isolated, so concurrent reads share only the persistent store coordinator
        // (SQLite reads parallelize fine with WAL mode). The 19k-transaction fetch
        // dominates wall time; running it alongside the 7 small fetches turns total
        // load time into ~max(individual fetches) instead of sum.
        async let txs        = Task.detached(priority: .userInitiated) { repo.loadTransactions(dateRange: nil) }.value
        async let accs       = Task.detached(priority: .userInitiated) { repo.loadAccounts() }.value
        async let cats       = Task.detached(priority: .userInitiated) { repo.loadCategories() }.value
        async let subs       = Task.detached(priority: .userInitiated) { repo.loadSubcategories() }.value
        async let catLinks   = Task.detached(priority: .userInitiated) { repo.loadCategorySubcategoryLinks() }.value
        async let txLinks    = Task.detached(priority: .userInitiated) { repo.loadTransactionSubcategoryLinks() }.value
        async let series     = Task.detached(priority: .userInitiated) { repo.loadRecurringSeries() }.value
        async let occurrences = Task.detached(priority: .userInitiated) { repo.loadRecurringOccurrences() }.value
        // Cold-load pre-aggregated CategoryAggregateEntity rows. Empty on a
        // fresh install / schema migration — handled below by a one-shot rebuild.
        async let aggregates = Task.detached(priority: .userInitiated) { repo.loadAggregates(year: nil, month: nil, limit: nil) }.value
        // Warm-start AccountAggregateEntity rows (Schema v9+). Same fallback.
        async let accountAggregates = Task.detached(priority: .userInitiated) { repo.loadAccountAggregates() }.value

        let (loadedTxs, loadedAccs, loadedCats, loadedSubs, loadedCatLinks, loadedTxLinks, loadedSeries, loadedOcc, loadedAggregates, loadedAccountAggregates) =
            await (txs, accs, cats, subs, catLinks, txLinks, series, occurrences, aggregates, accountAggregates)

        // Prune any order keys for accounts that no longer exist (M-13): the order
        // map (UserDefaults) and accounts (CoreData) can drift, e.g. an account
        // deleted while importing skips removeOrder. Reconcile against the
        // authoritative loaded set before applying.
        AccountOrderManager.shared.reconcile(withAccountIds: Set(loadedAccs.map { $0.id }))
        CategoryOrderManager.shared.reconcile(withCategoryIds: Set(loadedCats.map { $0.id }))
        let orderedAccounts = AccountOrderManager.shared.applyOrders(to: loadedAccs)
        let orderedCategories = CategoryOrderManager.shared.applyOrders(to: loadedCats)

        // Capture MainActor-bound state once, before detaching.
        let currentBaseCurrency = self.baseCurrency
        var accountsCurrencyById: [String: String] = [:]
        accountsCurrencyById.reserveCapacity(orderedAccounts.count)
        for acc in orderedAccounts { accountsCurrencyById[acc.id] = acc.currency }
        let needsColdStartCategoryAggregates = loadedAggregates.isEmpty
        let needsColdStartAccountAggregates = loadedAccountAggregates.isEmpty

        // Build every pure value-indexed structure off the main actor in one pass.
        // Previously this lived as 5+ separate sweeps over `loadedTxs` on MainActor
        // (Set, Dictionary, rebuildAccountIndex, rebuildAllSubcategoryIndexes,
        // rebuildSeriesAndDateIndexes, transactionsByCategoryName loop) and ran in
        // parallel with the home screen's reveal animation — see TransactionStore+LoadSnapshot.swift.
        //
        // When CoreData has no warm-start aggregates (first launch / schema migration),
        // the cold rebuild of `categoryAggregatesByKey` + `accountAggregatesByAccountId`
        // is also done inside the detached task. Those rebuilds depend on
        // `baseCurrency` + per-account currency + FX cache — all captured above
        // as Sendable values; `CurrencyConverter.convertSync` is actor-safe.
        let snapshot = await Task.detached(priority: .userInitiated) {
            Self.buildLoadSnapshot(
                transactions: loadedTxs,
                categories: orderedCategories,
                subcategories: loadedSubs,
                categorySubcategoryLinks: loadedCatLinks,
                transactionSubcategoryLinks: loadedTxLinks,
                baseCurrency: currentBaseCurrency,
                accountsCurrencyById: accountsCurrencyById,
                needsColdStartCategoryAggregates: needsColdStartCategoryAggregates,
                needsColdStartAccountAggregates: needsColdStartAccountAggregates
            )
        }.value

        // Back on @MainActor — only assignments now, no per-tx loops.
        accounts = orderedAccounts
        rebuildAccountById()  // O(N_accounts), tiny
        transactions = loadedTxs
        transactionsCount = loadedTxs.count
        transactionIdSet = snapshot.transactionIdSet
        transactionById = snapshot.transactionById
        transactionsByAccount = snapshot.transactionsByAccount
        categories = orderedCategories
        subcategories = loadedSubs
        categorySubcategoryLinks = loadedCatLinks
        transactionSubcategoryLinks = loadedTxLinks
        recurringStore.load(series: loadedSeries, occurrences: loadedOcc)

        // Lookup tables — moved off MainActor, just assign.
        categoryById = snapshot.categoryById
        categoryIdByName = snapshot.categoryIdByName
        subcategoryById = snapshot.subcategoryById
        subcategoryIdsByCategoryId = snapshot.subcategoryIdsByCategoryId
        subcategoryIdsByTransactionId = snapshot.subcategoryIdsByTransactionId
        subcategoryUsageCountById = snapshot.subcategoryUsageCountById
        subcategoryLastUsedById = snapshot.subcategoryLastUsedById
        parsedDateById = snapshot.parsedDateById
        transactionsBySeriesId = snapshot.transactionsBySeriesId
        transactionsByCategoryName = snapshot.transactionsByCategoryName

        // Aggregates: warm-start from CoreData if we have a saved snapshot, else
        // use the cold rebuild performed inside the detached snapshot builder.
        // Either path is now MainActor-cheap — only hash-map assignment + persist
        // scheduling, no per-tx loops.
        if !loadedAggregates.isEmpty {
            // `transactionsByCategoryName` is already populated from the snapshot,
            // so the inner loop in `seedCategoryAggregates` is redundant — seed the
            // aggregate map directly to avoid a second O(N_tx) walk on MainActor.
            seedCategoryAggregateBuckets(from: loadedAggregates)
        } else if let coldStart = snapshot.coldStartCategoryAggregates {
            categoryAggregatesByKey = coldStart
            aggregatesAreFXStale = snapshot.coldStartCategoryAggregatesAreFXStale
            scheduleAggregatePersist()  // first launch — write the rebuilt snapshot
        }

        // Account aggregates: warm-start from CoreData when a snapshot exists,
        // else use the cold rebuild from the detached task.
        if !loadedAccountAggregates.isEmpty {
            seedAccountAggregates(from: loadedAccountAggregates)
        } else if let coldStart = snapshot.coldStartAccountAggregates {
            accountAggregatesByAccountId = coldStart
            // OR in the account cold-start FX-stale flag so bumpCurrencyRatesVersion
            // rebuilds account aggregates even when no category leg was FX-stale —
            // previously they relied on the category flag being set (cache audit #12).
            aggregatesAreFXStale = aggregatesAreFXStale || snapshot.coldStartAccountAggregatesAreFXStale
            scheduleAccountAggregatePersist()
        }

        categoriesMutationVersion &+= 1
        subcategoriesMutationVersion &+= 1

        // baseCurrency is synced from settings by AppCoordinator (fast path / initialize)
        // before this point; the day-change repair rebuilds aggregates if it changed.

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
        rebuildAccountById()
        categories = CategoryOrderManager.shared.applyOrders(to: cats)
        rebuildCategoryLookups()
        categoriesMutationVersion &+= 1
    }

    /// Update base currency (for currency conversions)
    func updateBaseCurrency(_ currency: String) {
        let changed = baseCurrency != currency
        baseCurrency = currency
        cache.invalidateAll() // Currency change affects all cached calculations

        if changed {
            // Aggregates are stored in `baseCurrency`. The old totals are now in
            // the wrong unit, so rebuild from scratch — O(N_tx) but only happens
            // when the user explicitly flips the base currency, not on hot paths.
            rebuildCategoryIndexes()
            categoriesMutationVersion &+= 1
            // A base-currency change invalidates every base-denominated total just as a
            // rate change does — bump so views keyed solely on currencyRatesVersion
            // (e.g. detail-view refresh triggers) re-fire too (cache audit #17).
            currencyRatesVersion &+= 1
        }

        // Currency change requires full balance recalculation in BalanceCoordinator
        Task {
            await balanceCoordinator.recalculateAll(accounts: accounts, transactions: transactions)
        }
    }

    private static let lastLedgerRecalcKey = "lastLedgerRecalcDate"

    /// Recompute realized balances + aggregates when the calendar day has advanced
    /// since the last run (and once on first launch after install/update — which also
    /// repairs balances that drifted before the unified ledger path landed).
    ///
    /// Realized figures exclude future-dated transactions (incl. generated recurring
    /// occurrences); this is the trigger that folds them in once their date arrives.
    /// Idempotent and cheap to call repeatedly — gated to run at most once per day.
    ///
    /// - Returns: `true` if the calendar day changed since the last run (whether or not
    ///   a transaction matured). Callers use this to refresh date-relative consumers —
    ///   notably Insights (forecast `daysRemaining`, period keys, health score) which
    ///   depend on "today" even when no tx matured (cache audit #7).
    @discardableResult
    func recalculateLedgerIfDayChanged(now: Date = Date(), defaults: UserDefaults = .standard) async -> Bool {
        guard !accounts.isEmpty else { return false }
        let last = defaults.string(forKey: Self.lastLedgerRecalcKey)
        let todayKey = LedgerMaturation.dayKey(for: now)
        guard last != todayKey else { return false }

        // Targeted-maturation fast path: when we have a prior run AND no transaction matured
        // since then (none dated in `(last, today]`), the incrementally-maintained balances and
        // aggregates are already correct — skip the O(N_tx × N_accounts) recompute entirely.
        // Most day rollovers have no future tx coming due, so this is the common case and is
        // what removes the per-launch ledger-recalc stall. The recompute still runs whenever
        // something actually matured, and on first launch after install/update (`last == nil`),
        // which doubles as a one-time drift repair. The scan below is O(N_tx) cheap string
        // comparisons — orders of magnitude lighter than the rebuild it guards.
        if let last,
           !transactions.contains(where: { LedgerMaturation.isMatured(dateKey: $0.date, since: last, through: todayKey) }) {
            defaults.set(todayKey, forKey: Self.lastLedgerRecalcKey)
            return true // day changed (date-relative consumers stale) though nothing matured
        }

        // Realized aggregates exclude future tx — a matured tx must now be counted.
        rebuildAccountAggregates()
        rebuildCategoryIndexes()
        categoriesMutationVersion &+= 1
        // Balances recomputed from initialBalance + realized tx (also repairs drift).
        await balanceCoordinator.recalculateAll(accounts: accounts, transactions: transactions)

        defaults.set(todayKey, forKey: Self.lastLedgerRecalcKey)
        return true
    }

    // MARK: - CRUD Operations

    /// Add a new transaction.
    /// Returns the created transaction with generated ID.
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
        logger.debug("finishImport START — tx:\(txCount) acc:\(self.accounts.count) cat:\(self.categories.count)")

        // CRITICAL: Use synchronous save to ensure data is persisted before returning
        // This prevents data loss if app is terminated immediately after import
        // IMPORTANT: Save in correct order - accounts FIRST, then transactions (for relationships)
        do {
            if let coreDataRepo = repository as? CoreDataRepository {
                // Save accounts BEFORE transactions (required for Core Data relationships)
                logger.debug("finishImport: saving accounts…")
                try coreDataRepo.saveAccountsSync(accounts)
                logger.debug("finishImport: saving categories…")
                try coreDataRepo.saveCategoriesSync(categories)

                try coreDataRepo.saveSubcategoriesSync(subcategories)
                try coreDataRepo.saveCategorySubcategoryLinksSync(categorySubcategoryLinks)

                // Save transactions AFTER accounts (so account relationships can be established)
                logger.debug("finishImport: saving \(txCount) transactions via saveTransactionsSync…")
                try coreDataRepo.saveTransactionsSync(transactions)
                logger.debug("finishImport: saveTransactionsSync DONE")
                try coreDataRepo.saveTransactionSubcategoryLinksSync(transactionSubcategoryLinks)
            } else {
                // Fallback to async save for non-CoreData repositories
                repository.saveAccounts(accounts)
                repository.saveCategories(categories)

                repository.saveSubcategories(subcategories)
                repository.saveCategorySubcategoryLinks(categorySubcategoryLinks)

                repository.saveTransactions(transactions)
                repository.saveTransactionSubcategoryLinks(transactionSubcategoryLinks)
            }

            // Save recurring data
            recurringStore.saveSeries()
            recurringStore.saveOccurrences()

        } catch {
            logger.error("finishImport FAILED: \(error.localizedDescription)")
            throw TransactionStoreError.persistenceFailed(error)
        }

        // Mark import done ONLY after all saves have succeeded.
        // Setting this earlier would fire ContentView observers while CoreData writes are still in progress.
        isImporting = false

        // Aggregate index was maintained in-memory throughout the import via
        // `categoryIndexAdd`; persist the final snapshot now so the next launch
        // warm-starts from CoreData instead of doing the O(N_tx) rebuild.
        await flushAggregatePersist()

        // Subcategory link persists are debounced on the hot path; flush any
        // pending writes synchronously so the import is fully durable.
        flushSubcategoryLinkPersist()

        // Same for recurring series + occurrences persistence.
        recurringStore.flushPersist()

        // Account aggregates were maintained in-memory via per-tx deltas; persist
        // final state so the next launch warm-starts.
        await flushAccountAggregatePersist()

        logger.debug("finishImport DONE")
    }

    /// Update an existing transaction
    func update(_ transaction: Transaction) async throws {
        guard let old = transactionById[transaction.id] else {
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
    func delete(_ transaction: Transaction) async throws {
        guard transactionById[transaction.id] != nil else {
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
        // Validate accounts exist (O(1) via accountById)
        guard accountById[sourceId] != nil else {
            throw TransactionStoreError.accountNotFound
        }

        guard accountById[targetId] != nil else {
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

    /// Apply an event to the store: updates state, balances, cache, and persists
    internal func apply(_ event: TransactionEvent) async throws {
        // 1. Update state (SSOT)
        updateState(event)
        mutationVersion &+= 1

        // 2. Update balances (incremental, awaited for consistency)
        await updateBalances(for: event)

        // 3. Granular cache invalidation — only invalidate what changed
        invalidateCache(for: event)

        // 4. Incremental persist — O(1) per event (no await needed)
        if !isImporting {
            persistIncremental(event)
        }

        // 5. Debounced sync — coalesces rapid mutations (e.g., batch adds)
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
            transactionsCount = transactions.count
            transactionIdSet.insert(tx.id)
            transactionById[tx.id] = tx
            indexAdd(tx)
            categoryIndexAdd(tx)
            subcategoryIndexAdd(tx)
            seriesIndexAdd(tx)
            accountAggregatesAdd(tx)

        case .updated(let old, let new):
            if let index = transactions.firstIndex(where: { $0.id == old.id }) {
                transactions[index] = new
            }
            // IDs don't change on update
            transactionById[new.id] = new
            indexUpdate(old: old, new: new)
            categoryIndexUpdate(old: old, new: new)
            subcategoryIndexUpdate(old: old, new: new)
            seriesIndexUpdate(old: old, new: new)
            accountAggregatesUpdate(old: old, new: new)

        case .deleted(let tx):
            // O(1) removal via index lookup; replaces O(N) `removeAll { $0.id == tx.id }`.
            if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
                transactions.remove(at: index)
            }
            transactionsCount = transactions.count
            transactionIdSet.remove(tx.id)
            transactionById.removeValue(forKey: tx.id)
            indexRemove(tx)
            categoryIndexRemove(tx)
            subcategoryIndexRemove(tx)
            seriesIndexRemove(tx)
            accountAggregatesRemove(tx)

        case .bulkAdded(let txs):
            transactions.append(contentsOf: txs)
            transactionsCount = transactions.count
            transactionIdSet.formUnion(txs.map { $0.id })
            for tx in txs {
                transactionById[tx.id] = tx
                indexAdd(tx)
                categoryIndexAdd(tx)
                subcategoryIndexAdd(tx)
                seriesIndexAdd(tx)
                accountAggregatesAdd(tx)
            }

        // MARK: - Recurring Series Events (delegated to RecurringStore)

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

    // MARK: - Recurring Transaction Generation

    /// Generate and add transactions for a recurring series.
    /// Helper method used by createSeries and updateSeries.
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

            // Track occurrences
            recurringStore.appendOccurrences(result.occurrences)
            recurringStore.saveOccurrences()
        }
    }

    /// Validate a transaction before adding/updating
    private func validate(_ transaction: Transaction) throws {
        // Amount validation
        guard transaction.amount > 0 else {
            throw TransactionStoreError.invalidAmount
        }

        // Account exists (if specified) — O(1) via accountById dict
        // Allow transactions without accountId (e.g., recurring subscriptions without account)
        if let accountId = transaction.accountId, !accountId.isEmpty {
            guard accountById[accountId] != nil else {
                throw TransactionStoreError.accountNotFound
            }
        }

        // Target account exists (for transfers) — O(1) via accountById dict
        if let targetId = transaction.targetAccountId, !targetId.isEmpty {
            guard accountById[targetId] != nil else {
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
    /// Incremental persist — O(1) per transaction event.
    /// Replaces `saveTransactions([all transactions])` which was O(3N) = ~57,000 ops for 19k records.
    /// - .added: insertTransaction -- creates one CoreData entity (O(1))
    /// - .deleted: no-op -- deleteTransactionImmediately already called in invalidateCache(for:)
    /// - .updated: updateTransactionFields -- fetches by PK and updates fields (O(1))
    /// - .bulkAdded: batchInsertTransactions -- NSBatchInsertRequest (O(N) but fast)
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
            recurringStore.saveSeries()
            recurringStore.saveOccurrences()
        }
    }

    /// Granular cache invalidation based on event type.
    /// Only invalidates affected cache keys instead of clearing everything.
    private func invalidateCache(for event: TransactionEvent) {
        // Summary is always affected by any transaction change
        cache.remove(UnifiedTransactionCache.Key.summary)
        cache.remove(UnifiedTransactionCache.Key.summaryFiltered)

        // Category expenses always affected
        cache.remove(UnifiedTransactionCache.Key.categoryExpenses)

        // The debounced syncTransactionStoreToViewModels() handles cache invalidation.
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

    // MARK: - Account Index Maintenance

    /// Rebuild `accountById` from the current `accounts` array.
    /// Called from `loadData`, `loadAccountsOnly`, and every account CRUD operation
    /// in TransactionStore+AccountCRUD.swift. The accounts array is small (~50 entries)
    /// so a full rebuild is cheap and easier to reason about than incremental sync.
    /// Also bumps `accountsMutationVersion` so downstream caches (AccountsViewModel
    /// regular/deposit/loan filters) can detect invalidation cheaply.
    internal func rebuildAccountById() {
        accountById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        accountsMutationVersion &+= 1
    }

    // MARK: - Per-Account Index Maintenance

    private func rebuildAccountIndex(from txs: [Transaction]) {
        var index: [String: [Transaction]] = [:]
        index.reserveCapacity(accounts.count)
        for tx in txs {
            if let id = tx.accountId { index[id, default: []].append(tx) }
            if let id = tx.targetAccountId { index[id, default: []].append(tx) }
        }
        transactionsByAccount = index
    }

    private func indexAdd(_ tx: Transaction) {
        if let id = tx.accountId { transactionsByAccount[id, default: []].append(tx) }
        if let id = tx.targetAccountId { transactionsByAccount[id, default: []].append(tx) }
    }

    private func indexRemove(_ tx: Transaction) {
        // Index-based removal — replaces O(N) `removeAll` with O(N) scan + O(1) remove.
        // For per-account buckets (typically 100–500 entries) this halves the work
        // since we stop scanning at the first match instead of walking the whole array.
        if let id = tx.accountId,
           let i = transactionsByAccount[id]?.firstIndex(where: { $0.id == tx.id }) {
            transactionsByAccount[id]?.remove(at: i)
            if transactionsByAccount[id]?.isEmpty == true { transactionsByAccount.removeValue(forKey: id) }
        }
        if let id = tx.targetAccountId,
           let i = transactionsByAccount[id]?.firstIndex(where: { $0.id == tx.id }) {
            transactionsByAccount[id]?.remove(at: i)
            if transactionsByAccount[id]?.isEmpty == true { transactionsByAccount.removeValue(forKey: id) }
        }
    }

    private func indexUpdate(old: Transaction, new: Transaction) {
        // Account links may change on edit — remove from old buckets, insert into new ones.
        if old.accountId != new.accountId || old.targetAccountId != new.targetAccountId {
            indexRemove(old)
            indexAdd(new)
            return
        }
        // Same buckets — replace in place to keep the latest tx fields (date/amount/category/etc.)
        if let id = new.accountId,
           let i = transactionsByAccount[id]?.firstIndex(where: { $0.id == new.id }) {
            transactionsByAccount[id]?[i] = new
        }
        if let id = new.targetAccountId,
           let i = transactionsByAccount[id]?.firstIndex(where: { $0.id == new.id }) {
            transactionsByAccount[id]?[i] = new
        }
    }
}

// MARK: - Debug Helpers

