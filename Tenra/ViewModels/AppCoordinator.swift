//
//  AppCoordinator.swift
//  Tenra
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
    @ObservationIgnored let depositsViewModel: DepositsViewModel
    @ObservationIgnored let loansViewModel: LoansViewModel
    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let settingsViewModel: SettingsViewModel
    @ObservationIgnored let insightsViewModel: InsightsViewModel
    @ObservationIgnored let cloudSyncViewModel: CloudSyncViewModel

    // MARK: - Store

    /// Single Source of Truth for all transaction and recurring operations.
    @ObservationIgnored let transactionStore: TransactionStore

    // MARK: - Coordinators

    /// Single entry point for balance operations.
    @ObservationIgnored let balanceCoordinator: BalanceCoordinator

    // MARK: - Pagination (Task 9)

    /// Read-optimised paginated view over TransactionEntity via NSFetchedResultsController.
    /// TransactionStore remains SSOT for mutations; this controller is presentation-only.
    @ObservationIgnored private(set) var transactionPaginationController: TransactionPaginationController

    // MARK: - Private Properties

    private var isInitialized = false
    private var isFastPathStarted = false

    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "AppCoordinator")

    // Observable loading stage outputs — views bind to these for per-element skeletons
    private(set) var isFastPathDone = false       // accounts + categories ready (~50ms)
    private(set) var isFullyInitialized = false   // transactions + all data ready (~1-3s)

    /// Deep-link target set when the user taps a subscription push notification.
    /// FinancesView observes this and pushes the corresponding subscription detail
    /// once `transactionStore.subscriptions` contains a matching series. Cleared
    /// after navigation via `consumePendingSubscription()`.
    private(set) var pendingSubscriptionSeriesId: String?

    /// Cold-launch stash: when iOS launches the app from a notification tap, the
    /// `userNotificationCenter(_:didReceive:)` handler runs BEFORE `AppCoordinator`
    /// is constructed (the coordinator waits for CoreData prewarm). AppDelegate
    /// writes here so `init()` can consume the deep-link as soon as the
    /// coordinator exists. MainActor-isolated via the enclosing class isolation.
    static var pendingDeepLinkSeriesIdOnLaunch: String?

    func setPendingSubscription(seriesId: String) {
        pendingSubscriptionSeriesId = seriesId
    }

    func consumePendingSubscription() {
        pendingSubscriptionSeriesId = nil
    }

    // MARK: - Onboarding gate

    /// True on first launch (until the user completes onboarding). Mutated by
    /// `completeOnboarding()` and `resetOnboarding()`. Read by `TenraApp.swift`
    /// to decide whether to show `OnboardingFlowView` or `MainTabView`.
    private(set) var needsOnboarding: Bool = !OnboardingState.isCompleted

    func completeOnboarding() {
        OnboardingState.markCompleted()
        needsOnboarding = false
        logger.info("onboarding_finished")
    }

    func resetOnboarding() {
        OnboardingState.reset()
        needsOnboarding = true
        logger.info("onboarding_reset")
    }

    /// iCloud-restore mitigation: if accounts already exist after the fast path
    /// finishes (e.g. user restored from an iCloud backup on a new device),
    /// auto-mark onboarding as completed and skip the flow.
    func reconcileOnboardingAfterFastPath() {
        guard !OnboardingState.isCompleted else { return }
        guard !accountsViewModel.accounts.isEmpty else { return }
        OnboardingState.markCompleted()
        needsOnboarding = false
        logger.info("onboarding_skipped_due_to_existing_data accountsCount=\(self.accountsViewModel.accounts.count, privacy: .public)")
    }

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol? = nil) {
        self.repository = repository ?? CoreDataRepository()

        // Task 9: Pagination controller — uses CoreDataStack.shared viewContext for FRC.
        self.transactionPaginationController = TransactionPaginationController(stack: CoreDataStack.shared)

        // Initialize ViewModels in dependency order
        // 1. Accounts (no dependencies)
        self.accountsViewModel = AccountsViewModel(repository: self.repository)

        // 2. Initialize BalanceCoordinator FIRST (before TransactionsViewModel to avoid circular dependencies)
        self.balanceCoordinator = BalanceCoordinator(
            repository: self.repository,
            cacheManager: nil  // Will be set later after TransactionsViewModel is created
        )

        // 3. Transactions — create first to access currencyService and appSettings
        self.transactionsViewModel = TransactionsViewModel(repository: self.repository)

        // 3.1 Initialize TransactionStore (single source of truth for transactions + recurring)
        // RecurringStore created first; TransactionStore owns it.
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

        // 5. Deposits (depends on Accounts)
        self.depositsViewModel = DepositsViewModel(repository: self.repository, accountsViewModel: accountsViewModel)

        // 6. Loans (depends on Accounts) — mirrors DepositsViewModel pattern
        self.loansViewModel = LoansViewModel(repository: self.repository, accountsViewModel: accountsViewModel)

        // 7. Setup SettingsViewModel
        let storageService = SettingsStorageService()
        let wallpaperService = WallpaperManagementService()
        let validationService = SettingsValidationService()

        // Initialize coordinators for dangerous operations
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

        // CSVImportCoordinator created lazily in ImportFlowCoordinator (requires csvFile headers)
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
        // Initialize InsightsService and InsightsViewModel
        let insightsFilterService = TransactionFilterService()
        let insightsQueryService = TransactionQueryService()

        // Insights uses CategoryBudgetService only as a namespace for static
        // array-scan helpers (legacy path). It runs nonisolated on background
        // and cannot read the MainActor-isolated aggregate indexes; the store
        // reference is therefore unused here.
        let insightsBudgetService = CategoryBudgetService(store: nil)
        let insightsService = InsightsService(
            filterService: insightsFilterService,
            queryService: insightsQueryService,
            budgetService: insightsBudgetService
        )
        self.insightsViewModel = InsightsViewModel(
            insightsService: insightsService,
            transactionStore: self.transactionStore,
            transactionsViewModel: self.transactionsViewModel
        )

        // Backups VM. CloudKit DB sync removed 2026-04-22; backups live in Documents/Backups
        // or, when the user opts in, the iCloud Drive ubiquity container.
        let cloudBackupService = CloudBackupService()
        self.cloudSyncViewModel = CloudSyncViewModel(backupService: cloudBackupService)
        self.cloudSyncViewModel.appCoordinator = self
        // Prime the iCloud container URL off the main thread (first resolve can block).
        Task.detached(priority: .utility) { cloudBackupService.prepareICloud() }

        // @Observable handles change propagation automatically - no manual observer setup needed

        // TransactionsViewModel subscribes to CategoriesViewModel for category updates
        transactionsViewModel.setCategoriesViewModel(categoriesViewModel)

        // Inject BalanceCoordinator into ViewModels
        accountsViewModel.balanceCoordinator = balanceCoordinator
        transactionsViewModel.balanceCoordinator = balanceCoordinator
        depositsViewModel.balanceCoordinator = balanceCoordinator
        loansViewModel.balanceCoordinator = balanceCoordinator

        // Inject TransactionStore into ViewModels
        transactionsViewModel.transactionStore = transactionStore

        accountsViewModel.transactionStore = transactionStore
        categoriesViewModel.transactionStore = transactionStore

        // Set coordinator reference in TransactionStore for automatic sync after mutations
        transactionStore.coordinator = self

        // Back-reference so SettingsViewModel can call coordinator.resetOnboarding()
        // after resetAllData() — set after all stored properties are initialized.
        settingsViewModel.coordinator = self

        categoriesViewModel.setupTransactionStoreObserver()

        // Cold-launch deep link: AppDelegate may have stashed a tapped subscription
        // notification's seriesId before this coordinator existed. Pick it up so the
        // first MainTabView render can react to it via .onChange(initial: true).
        if let stashed = Self.pendingDeepLinkSeriesIdOnLaunch {
            self.pendingSubscriptionSeriesId = stashed
            Self.pendingDeepLinkSeriesIdOnLaunch = nil
        }

        // No initial sync here — TransactionStore is empty at this point. The first
        // useful sync happens in initialize() after loadData() populates the store.
        // Calling sync here just resets InsightsVM's empty caches and dirties Observable
        // dependencies before the first frame is even rendered.
    }

    // MARK: - Public Methods

    /// Fast-path startup: loads accounts + categories + settings (<50ms combined).
    /// Call this first so the UI can appear. Full initialization continues via initialize().
    func initializeFastPath() async {
        guard !isFastPathStarted else { return }
        isFastPathStarted = true

        // Run accounts/categories fetch and settings read in parallel — they share no
        // state and used to be serialized through three sequential awaits.
        async let accountsLoad: Void = {
            try? await self.transactionStore.loadAccountsOnly()
        }()
        async let settingsLoad: Void = self.settingsViewModel.loadSettingsOnly()
        _ = await (accountsLoad, settingsLoad)

        // Sync the store's base currency from settings. It was previously hardcoded to
        // "KZT" and never updated, so non-KZT users had aggregates/insights computed in
        // the wrong currency. Set before loadData()/maturation so any (re)build uses the
        // correct unit; the day-change repair then rebuilds any stale persisted snapshot.
        transactionStore.baseCurrency = settingsViewModel.settings.baseCurrency

        // Calling without transactions so accounts briefly show their persisted balance.
        // initialize() will register accounts again after full transaction load.
        await balanceCoordinator.registerAccounts(transactionStore.accounts)

        reconcileOnboardingAfterFastPath()
        isFastPathDone = true

        // Populate backup count/storage so the Settings row doesn't read 0 until the user
        // navigates into CloudBackupsView. Deliberately AFTER isFastPathDone: this whole
        // method is awaited by TenraApp.task BEFORE the coordinator is published, so
        // anything left above blocks the first frame. loadBackups() is a synchronous
        // directory scan, and when iCloud backups are enabled it routes through
        // CloudBackupService.resolveICloudDocumentsURL() — documented there as blocking
        // for hundreds of ms on first call. The prepareICloud() prewarm in init() runs at
        // .utility priority and usually loses that race, so the cost landed on MainActor
        // during launch. Nothing on the first frame reads these values.
        Task(priority: .utility) { [weak self] in
            self?.cloudSyncViewModel.loadBackups()
        }
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

        // 1. Load data and run FRC setup concurrently. FRC.setup() is MainActor-bound
        // but loadData() releases MainActor while its detached fetches run in background;
        // SwiftUI's MainActor schedules frcSetupTask on that idle window, overlapping its
        // 50–200 ms cost with the dominant transaction fetch.
        let frcSetupTask = Task { @MainActor [weak self] in
            self?.transactionPaginationController.setup()
        }
        // Pre-warm the currency rate cache in parallel with loadData(). Skipped
        // if disk-restored cache is already <24h old. Runs on a detached task so
        // it shares no MainActor time with the SwiftUI rendering work that just
        // started rendering the home screen.
        //
        // Capture the freshness snapshot BEFORE kicking off prewarm so we can gate
        // the post-wait `bumpCurrencyRatesVersion()` on whether rates actually
        // changed during this launch (see Phase 5.3 in audit report).
        let ratesFreshBeforePrewarm = CurrencyConverter.currentRatesAreFresh
        let prewarmTask = Task.detached(priority: .userInitiated) {
            await CurrencyConverter.prewarm()
        }
        let t0 = CACurrentMediaTime()
        try? await transactionStore.loadData()
        let t1 = CACurrentMediaTime()
        logger.debug("📦 [INIT] loadData()            : \(String(format: "%.0f", (t1-t0)*1000))ms — tx:\(self.transactionStore.transactions.count) acc:\(self.transactionStore.accounts.count)")

        // 2. Sync subcategory data and invalidate caches (no array copies)
        syncTransactionStoreToViewModels(batchMode: true)
        let t2 = CACurrentMediaTime()
        logger.debug("🔄 [INIT] syncToViewModels()    : \(String(format: "%.0f", (t2-t1)*1000))ms")

        // 3. Register accounts with BalanceCoordinator only if FastPath didn't already
        // do it for the full set. account.balance is kept accurate by persistIncremental()
        // on every mutation, so re-registering with the same accounts is a no-op that just
        // re-publishes BalanceCoordinator.balances → all AccountCards needlessly re-render.
        let storeAccountIds = Set(transactionStore.accounts.map { $0.id })
        let registeredIds = Set(balanceCoordinator.balances.keys)
        if !storeAccountIds.isSubset(of: registeredIds) {
            await balanceCoordinator.registerAccounts(transactionStore.accounts)
        }
        let t3 = CACurrentMediaTime()
        logger.debug("💰 [INIT] registerAccounts()    : \(String(format: "%.0f", (t3-t2)*1000))ms — skipped:\(storeAccountIds.isSubset(of: registeredIds))")

        // FRC setup was kicked off above in parallel with loadData — wait for it now.
        // The FRC reads CoreData directly via viewContext (independent of TransactionStore),
        // so the two fetches don't share state and overlap cleanly during the loadData await.
        await frcSetupTask.value
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

        // Yield one render frame so SwiftUI commits the history-link reveal animation
        // BEFORE we hammer MainActor with the rest of the work (prewarm wait, FX bump,
        // deposit reconcile, ledger maturation, insights recompute). Without this
        // yield those mutations can land on the same render cycle as the reveal,
        // causing a visible stutter in the easeOut(0.35) transition.
        // 16ms ≈ one 60fps frame — slightly conservative for the ProMotion 120fps
        // display but cheap enough that the latency cost is unnoticeable.
        try? await Task.sleep(for: .milliseconds(16))

        // 5. Load settings (only if fast path hasn't already loaded them).
        // Wallpaper image decode is intentionally NOT loaded here — SettingsView's
        // own .task handles it lazily when the user navigates there.
        if !isFastPathStarted {
            await settingsViewModel.loadSettingsOnly()
        }
        // Defensive: ensure the store's base currency matches settings even if the
        // fast path was skipped (it loads settings only above in that case).
        transactionStore.baseCurrency = settingsViewModel.settings.baseCurrency

        PerformanceProfiler.end("AppCoordinator.initialize")

        // Wait for the pre-warm fetch (started in parallel with loadData()) to
        // finish so the first insights recompute uses fresh KZT-pivot rates.
        // Cap the wait to keep startup responsive even if the network is slow:
        // if rates haven't landed in 2.5s, fire insights with whatever cache we
        // have and let the recompute trigger again on the rate-store update.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await prewarmTask.value }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(2500))
            }
            await group.next()
            group.cancelAll()
        }
        let t6 = CACurrentMediaTime()
        logger.debug("💱 [INIT] currency prewarm wait : \(String(format: "%.0f", (t6-t5)*1000))ms — fresh:\(CurrencyConverter.currentRatesAreFresh)")

        // Bump rate version only when prewarm actually moved the rate cache —
        // i.e. when the disk-restored cache was cold/stale at launch and prewarm
        // brought new data. If rates were already fresh at start, prewarm is a
        // documented no-op (`CurrencyConverter.prewarm()` returns early on
        // `hasFreshRates`), so bumping here would invalidate every FX-dependent
        // cache (TransactionsVM, Insights) for no reason — and triggers a wave
        // of re-renders right when the home screen has just settled.
        //
        // Future rate changes (manual refresh, late provider response) are
        // handled by `startObservingCurrencyRateChanges()` below, so we don't
        // lose any reactivity by gating this initial bump.
        if !ratesFreshBeforePrewarm {
            transactionStore.bumpCurrencyRatesVersion()
            transactionsViewModel.invalidateCaches()
        }

        // Post any deposit interest that came due while the app was closed. This used to
        // run only when a deposit screen appeared, so interest could be late if the user
        // didn't open it on the posting day. Idempotent — posts nothing when nothing is due.
        // Runs before the recalc below so newly-posted interest is folded into balances.
        await reconcileDepositsOnLaunch()

        // Maturation + one-time repair: if the day advanced since the last run (or this
        // is the first launch after update), recompute realized balances/aggregates so
        // newly-matured future transactions are folded in and any pre-existing drift is
        // healed. Runs after the prewarm wait so multi-currency conversion uses fresh FX.
        await transactionStore.recalculateLedgerIfDayChanged()

        #if DEBUG
        // Screenshot demo: seeded Account.balance values are placeholders — fold the
        // seeded transactions into real balances via the canonical full recalc once
        // (tiny dataset, so the all-accounts rescan is cheap here).
        if ScreenshotDemoMode.isActive {
            transactionsViewModel.recalculateAccountBalances()
        }
        #endif

        // Insights recompute — non-essential for first frame; debounced internally.
        insightsViewModel.invalidateAndRecompute()

        // Date section key backfill — runs on a bg CoreData context, doesn't touch MainActor.
        Task(priority: .background) { [weak self] in
            await self?.backfillDateSectionKeysIfNeeded()
        }

        // One-time migration: flip orientation of legacy loan-payment transactions.
        // Runs on MainActor because TransactionStore is MainActor-bound. Idempotent —
        // gated by UserDefaults flag; safe to no-op on every subsequent launch.
        Task { [weak self] in
            await self?.flipLoanPaymentOrientationIfNeeded()
        }

        // Purge persistent history older than 7 days — prevents unbounded DB growth.
        // Runs on a bg CoreData context (see CoreDataStack.purgeHistory).
        Task(priority: .background) {
            CoreDataStack.shared.purgeHistory(olderThan: 7)
        }

        // Keep reconciling on any FX-rate change after the initial prewarm bump above.
        startObservingCurrencyRateChanges()
        // Recompute Insights when categories/budgets change — e.g. a newly added budget
        // should immediately count toward the health score's budget-adherence component
        // instead of reading "not configured" until the next launch.
        startObservingCategoryChanges()
        // Recompute Insights when accounts change (add/edit/delete, includeInBalance toggle,
        // balance/currency edit). balance-runway / projected-balance / emergency-fund /
        // wealth-breakdown and the health-score totalBalance all derive from accounts, and
        // previously stayed stale until an unrelated tx/FX/category mutation (cache audit #5).
        startObservingAccountChanges()
    }

    // MARK: - Private Methods

    /// Observe the single FX-rate notifier so EVERY rate change — a late prewarm landing
    /// (past the 2.5s wait), a manual refresh, or a second provider response — bumps the
    /// store's currency version. That reconciles FX-stale aggregates and refreshes Insights;
    /// previously only the one post-prewarm bump did this, so late rates left multi-currency
    /// aggregates/insights stale until the next launch (M-9). Re-arms after each change.
    private func startObservingCurrencyRateChanges() {
        withObservationTracking {
            _ = CurrencyRatesNotifier.shared.version
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let didHealStaleAggregates = self.transactionStore.bumpCurrencyRatesVersion()
                self.transactionsViewModel.invalidateCaches()
                self.insightsViewModel.invalidateAndRecompute()
                self.startObservingCurrencyRateChanges()  // re-arm before any async work
                // Cached balances for cross-currency accounts were computed at the
                // old/cold rate. Aggregates self-healed in bumpCurrencyRatesVersion;
                // the balance cache must heal on the same trigger (cache audit #1).
                if didHealStaleAggregates {
                    await self.balanceCoordinator.recalculateAll(
                        accounts: self.transactionStore.accounts,
                        transactions: self.transactionStore.transactions
                    )
                }
            }
        }
    }

    /// Observe category mutations (add/edit/delete, including budget changes) so the
    /// Insights feed — notably the budget-adherence health component — recomputes without
    /// waiting for the next launch. Re-arms after each change.
    private func startObservingCategoryChanges() {
        withObservationTracking {
            _ = transactionStore.categoriesMutationVersion
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.insightsViewModel.invalidateAndRecompute()
                self.startObservingCategoryChanges()  // re-arm for the next change
            }
        }
    }

    /// Observe account mutations (add/edit/delete, includeInBalance toggle, balance/currency
    /// edit) so balance-derived Insights recompute without waiting for the next launch.
    /// Tracks the observable `accounts` array — account CRUD replaces elements there.
    /// Balance recalcs flow through BalanceCoordinator, not this array, so this does NOT
    /// fire on every per-tx balance write. Re-arms after each change.
    private func startObservingAccountChanges() {
        withObservationTracking {
            _ = transactionStore.accounts
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.insightsViewModel.invalidateAndRecompute()
                self.startObservingAccountChanges()  // re-arm for the next change
            }
        }
    }

    /// Reconcile all deposits at launch so interest that came due while the app was
    /// closed is posted promptly (previously only happened when a deposit view appeared).
    /// Collects the generated `.depositInterestAccrual` transactions and persists them
    /// through the standard pipeline, which updates the deposit balance incrementally.
    private func reconcileDepositsOnLaunch() async {
        guard transactionStore.accounts.contains(where: { $0.isDeposit }) else { return }
        var created: [Transaction] = []
        depositsViewModel.reconcileAllDeposits(
            allTransactions: transactionStore.transactions,
            onTransactionCreated: { created.append($0) }
        )
        guard !created.isEmpty else { return }
        do {
            // One bulk event: single CoreData batch insert + single FRC rebuild.
            // The previous per-tx add() ran insertTransaction's performAndWait on the
            // main thread once per posted interest day — a visible stall after a
            // multi-day absence with several deposits.
            try await transactionStore.addBatch(created)
        } catch {
            // addBatch rejects the whole batch if one tx fails validation — retry
            // individually so one bad tx can't drop the rest (CSV import precedent).
            for tx in created {
                _ = try? await transactionStore.add(tx)
            }
        }
    }

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
        let completedKey = Self.backfillCompletedKey

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
                UserDefaults.standard.set(true, forKey: completedKey)
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
                UserDefaults.standard.set(true, forKey: completedKey)
            }
        }
    }

    // MARK: - Loan Payment Orientation Flip Migration

    /// UserDefaults key gating the one-time orientation flip for loan-payment transactions.
    /// Pre-flip convention: `accountId = LOAN, targetAccountId = SOURCE bank`.
    /// Post-flip convention: `accountId = SOURCE bank, targetAccountId = LOAN`
    /// (mirrors `.expense` semantics so UI lookups treat the bank as the user-facing
    /// "from" account).
    private static let loanOrientationFlipKey = "tenra.migration.loanOrientationFlip.v1"

    /// One-time migration: rewrites every existing `.loanPayment` / `.loanEarlyRepayment`
    /// transaction so `accountId` points at the source bank and `targetAccountId` points
    /// at the loan. Detects pre-flip rows by checking whether `accountId` resolves to a
    /// loan account; rows already in the new orientation are skipped, so the migration
    /// is safe to re-run if the flag is ever cleared.
    private func flipLoanPaymentOrientationIfNeeded() async {
        if UserDefaults.standard.bool(forKey: Self.loanOrientationFlipKey) {
            return
        }

        let candidates = transactionStore.transactions.filter {
            $0.type == .loanPayment || $0.type == .loanEarlyRepayment
        }

        var flippedCount = 0
        for tx in candidates {
            // Skip rows already in post-flip orientation:
            // accountId either nil (orphaned) or pointing at a non-loan account.
            guard let accId = tx.accountId,
                  let acc = transactionStore.accountById[accId],
                  acc.isLoan else {
                continue
            }

            let flipped = Transaction(
                id: tx.id,
                date: tx.date,
                description: tx.description,
                amount: tx.amount,
                currency: tx.currency,
                convertedAmount: tx.convertedAmount,
                type: tx.type,
                category: tx.category,
                subcategory: tx.subcategory,
                accountId: tx.targetAccountId,
                targetAccountId: tx.accountId,
                accountName: tx.targetAccountName,
                targetAccountName: tx.accountName,
                targetCurrency: tx.targetCurrency,
                targetAmount: tx.targetAmount,
                recurringSeriesId: tx.recurringSeriesId,
                recurringOccurrenceId: tx.recurringOccurrenceId,
                createdAt: tx.createdAt
            )
            do {
                try await transactionStore.update(flipped)
                flippedCount += 1
            } catch {
                logger.error("⚠️ [LOAN-FLIP] failed to flip \(tx.id): \(error.localizedDescription)")
            }
        }

        UserDefaults.standard.set(true, forKey: Self.loanOrientationFlipKey)
        if flippedCount > 0 {
            logger.debug("🔄 [LOAN-FLIP] migrated \(flippedCount) loan transactions to new orientation")
            transactionsViewModel.recalculateAccountBalances()
        }
    }

    /// Lightweight sync — invalidates caches and triggers insights recompute.
    /// ViewModels read directly from TransactionStore via computed properties.
    /// - Parameter batchMode: When true, skips insights recompute (for CSV imports, bulk operations)
    func syncTransactionStoreToViewModels(batchMode: Bool = false) {
        self.transactionsViewModel.invalidateCaches()

        // Sync subcategory data to CategoriesViewModel (not yet computed properties)
        self.categoriesViewModel.syncCategoriesFromStore()

        // Invalidate insights cache and schedule background recompute
        if !batchMode {
            self.insightsViewModel.invalidateAndRecompute()
        }
    }
}
