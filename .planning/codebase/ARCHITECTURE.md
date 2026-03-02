# Architecture

**Analysis Date:** 2026-03-02

## Pattern Overview

**Overall:** MVVM + Coordinator Pattern with Single Source of Truth (SSOT) for transactions, layered service architecture

**Key Characteristics:**
- Central `AppCoordinator` for dependency injection and initialization
- `TransactionStore` as single source of truth for all transaction-related data (transactions, accounts, categories, recurring series)
- Observable state management using Swift 5.0 `@Observable` macro with strict concurrency (`SWIFT_STRICT_CONCURRENCY = targeted`)
- Repository pattern abstracting CoreData persistence through `DataRepositoryProtocol`
- Domain-organized services (Balance, Categories, CSV, Voice, Import, etc.)
- Event-driven mutation pipeline with cache invalidation
- Progressive initialization (fast-path: accounts+categories in ~50ms, full load: ~1-3s)

## Layers

**Presentation (Views):**
- Purpose: SwiftUI user interface and navigation
- Location: `AIFinanceManager/Views/`
- Contains: Feature views, view coordinators, components, shared UI elements
- Depends on: ViewModels, AppCoordinator, Models (value types)
- Used by: End users; observable to state changes in ViewModels

**State Management (ViewModels):**
- Purpose: UI state management and business logic orchestration
- Location: `AIFinanceManager/ViewModels/`
- Contains: `@Observable @MainActor` classes like `AppCoordinator`, `TransactionStore`, `TransactionsViewModel`, `AccountsViewModel`, `InsightsViewModel`, `CategoriesViewModel`
- Key coordinator: `AppCoordinator` (`AIFinanceManager/ViewModels/AppCoordinator.swift`) — central DI container initializing all ViewModels, Stores, and Coordinators
- Depends on: Repository (DataRepositoryProtocol), Services (Balance, Import, etc.), Models
- Used by: Views (via @Environment)

**Business Logic (Services):**
- Purpose: Domain-specific operations and computations
- Location: `AIFinanceManager/Services/`
- Contains: Transaction filtering, balance calculations, category management, CSV import, voice input, PDF parsing, recurring transaction generation, insights computation, caching
- Patterns: Facade coordinators (BalanceCoordinator), value-based calculations (BalanceCalculationEngine), validation services, generator services
- Depends on: Repository, Models
- Used by: ViewModels, TransactionStore

**Data Persistence (Repository):**
- Purpose: Abstract CoreData access; provide clean data interface to upper layers
- Location: `AIFinanceManager/Services/Repository/` and `AIFinanceManager/Services/Core/`
- Core Protocol: `DataRepositoryProtocol` (`AIFinanceManager/Services/Core/DataRepositoryProtocol.swift`) — defines all persistence operations
- Facade: `CoreDataRepository` (`AIFinanceManager/Services/Repository/CoreDataRepository.swift`) — delegates to specialized repos
- Specialized Repositories:
  - `TransactionRepository` — transaction CRUD, batch insert, field updates
  - `AccountRepository` — account management, balance updates
  - `CategoryRepository` — category, subcategory, link management
  - `RecurringRepository` — recurring series and occurrences
- Depends on: CoreDataStack, Models, CoreData entities
- Used by: Services, TransactionStore, ViewModels

**Data Models (Models + CoreData Entities):**
- Purpose: Domain object definitions and value types
- Location: `AIFinanceManager/Models/` (value types) and `AIFinanceManager/CoreData/Entities/` (CoreData entities)
- Value Types: `Transaction`, `Account`, `CustomCategory`, `Subcategory`, `RecurringSeries`, `RecurringOccurrence`, `InsightModels`, `TimeFilter`, etc.
- CoreData Entities: `TransactionEntity`, `AccountEntity`, `CustomCategoryEntity`, `SubcategoryEntity`, `RecurringSeriesEntity`, `RecurringOccurrenceEntity`, etc. (auto-generated from `.xcdatamodeld`)
- Pattern: Value models are Codable, Equatable, Identifiable; repositories map CoreData entities ↔ value models

**Persistence Infrastructure:**
- Purpose: Core Data stack management and initialization
- Location: `AIFinanceManager/CoreData/`
- Contains: `CoreDataStack` (singleton, thread-safe via `NSLock`), `.xcdatamodeld` schema, entity auto-generation, `CoreDataSaveCoordinator`
- Features: Pre-warm initialization (off-MainActor), store reset notification broadcast, automatic save on app lifecycle events
- Entry: `AIFinanceManager/AIFinanceManagerApp.swift` pre-warms CoreData, then creates AppCoordinator

## Data Flow

**Initialization Flow:**

1. **App Launch** (`AIFinanceManager/AIFinanceManagerApp.swift`)
   - AppDelegate started
   - CoreDataStack.preWarm() called (background thread) — touches persistentContainer to load stores
   - MainTabView waits for CoreDataStack initialization

2. **Coordinator Creation** (after CoreData ready)
   - AppCoordinator created
   - All ViewModels initialized in dependency order
   - TransactionStore created and linked to BalanceCoordinator

3. **Data Loading** (AppCoordinator.initialize(), called from TransactionStore)
   - Fast-path (blocking): Accounts + categories loaded in ~50ms via repository
   - Full-path (background): All transactions (up to 19k) loaded from CoreData on background context
   - Recurring transactions generated for future dates
   - UI shows skeleton loader during full-path

**Mutation Flow (TransactionStore-driven):**

1. **User Action** (View calls coordinator/store method)
   - Example: `transactionStore.add(transaction:)` called from AddTransactionView

2. **Event Dispatch** (in `TransactionStore.apply()`)
   - Event created (e.g., `.added(transaction)`)
   - State updated (e.g., `transactions.append(transaction)`)
   - Balances updated via BalanceCoordinator (`updateForTransaction()`)
   - Caches invalidated (UnifiedTransactionCache)
   - Persisted to CoreData (reposit.insertTransaction or updateTransactionFields)
   - Pipeline: `updateState` → `updateBalances` → `invalidateCache` → `persistIncremental` (4 steps, debounced 16ms)

3. **Persistence** (Incremental, O(1) per event)
   - `persistIncremental(_ event:)` routes to specialized repo methods:
     - `.added` → `repository.insertTransaction()` (O(1) insert)
     - `.updated` → `repository.updateTransactionFields()` (O(1) field update)
     - `.deleted` → `repository.deleteTransactionImmediately()` (O(1) delete)
     - `.batchAdded` → `repository.batchInsertTransactions()` (O(N) NSBatchInsertRequest)
   - No full-save of 19k transactions; only touched entity mutated

4. **ViewModel Sync** (Automatic via @Observable)
   - TransactionStore state observable by ViewModels
   - ViewModels read-through computed properties: `transactionStore.transactions`, `transactionStore.accounts`, etc.
   - No manual sync needed; SwiftUI tracks observable property access

**Insights Computation Flow (Progressive):**

1. **User opens Insights tab**
   - InsightsView.onAppear triggers `InsightsViewModel.loadInsightsBackground()`

2. **Phase 1: Progressive Loading (Fast)**
   - Compute only currentGranularity (week/month/quarter/year/allTime) — ~200-300ms
   - Update UI with real data immediately
   - User sees results; other granularities load in background

3. **Phase 2: Complete Granularities** (Background)
   - Compute remaining 4 granularities (if not currentGranularity)
   - Compute health score (5 weighted components)
   - Write final UI update

4. **Data Aggregation** (PreAggregatedData pattern, Phase 42)
   - Single O(N) pass builds: monthlyTotals (grouped by year,month), categoryMonthExpenses, txDateMap (string→Date cache), accountTransactionCounts, lastAccountDates
   - Date parse cache eliminates DateFormatter overhead (~16μs/call) across all generators
   - All generators accept PreAggregatedData? and use pre-computed fields via dictionary lookups (O(1)) instead of O(N) scans
   - Shared insights (spendingSpike, categoryTrend, subscriptionGrowth, etc.) computed once, merged into subsequent granularities
   - Files: `Services/Insights/InsightsService.swift` (PreAggregatedData struct, generateAllInsights), `ViewModels/InsightsViewModel.swift` (two-phase progressive)

**State Management (Observable Pattern):**

**@Observable Usage:**
- `AppCoordinator` — holds all ViewModels, observable (isFullyInitialized, isFastPathDone)
- `TransactionStore` — holds transactions, accounts, categories, recurring data; observable (application state)
- Feature ViewModels — `TransactionsViewModel`, `AccountsViewModel`, `CategoriesViewModel`, `InsightsViewModel`, etc.

**@ObservationIgnored Rule (Phase 23):**
- ALL dependencies (repositories, services, caches, other VMs) marked `@ObservationIgnored`
- Only UI state exposed as observable properties
- Prevents SwiftUI from re-rendering when service internals change
- Example: `@Observable @MainActor class TransactionStore { @ObservationIgnored let repository: DataRepositoryProtocol; ... }`

**View State Binding:**
- Views access ViewModels via `@Environment(AppCoordinator.self)` or `@Environment(TransactionStore.self)`
- Computed properties in views extract needed state: `var viewModel: TransactionsViewModel { coordinator.transactionsViewModel }`
- `.onChange(of: observable.property)` for reactive updates (replacing manual onChange chains)
- `.task(id: trigger)` for deferred loading (replaces onAppear + manual state tracking)

## Key Abstractions

**TransactionStore (SSOT):**
- Purpose: Single source of truth for all transaction-domain data
- Location: `AIFinanceManager/ViewModels/TransactionStore.swift` (1383 LOC, needs splitting in future)
- State: transactions[], accounts[], categories[], subcategories[], recurringSeries[], recurringOccurrences[]
- Methods: add(), update(), delete(), transfer(), generateRecurringTransactions(), addBatch()
- Event-driven: TransactionStoreEvent enum (.added, .updated, .deleted, .batchAdded)
- Caching: UnifiedTransactionCache (category groupings, recurring state, balance cache)
- Debounced sync: 16ms coalesce window (syncDebounceTask)

**BalanceCoordinator (Balance SSOT):**
- Purpose: Single entry point for balance calculations and updates
- Location: `AIFinanceManager/Services/Balance/BalanceCoordinator.swift`
- Composed of: BalanceStore (account registration), BalanceCalculationEngine (computation logic)
- State: balances: [String: Double] (observable)
- Methods: registerAccounts(), updateForTransaction(), updateForTransactions()
- Operations: TransactionUpdateOperation enum (.add, .remove, .update)

**DataRepositoryProtocol:**
- Purpose: Abstract persistence interface
- Location: `AIFinanceManager/Services/Core/DataRepositoryProtocol.swift`
- Methods: loadTransactions(), saveTransactions(), insertTransaction(), updateTransactionFields(), batchInsertTransactions(), deleteTransactionImmediately(), and similar for accounts/categories/recurring/etc.
- Implementation: CoreDataRepository (facade) + 4 specialized repos (Transaction, Account, Category, Recurring)

**AppCoordinator (DI Container):**
- Purpose: Central dependency injection, initialization orchestration
- Location: `AIFinanceManager/ViewModels/AppCoordinator.swift`
- Dependencies: repository (DataRepositoryProtocol), all ViewModels, transactionStore, balanceCoordinator, transactionPaginationController
- Observable: isFastPathDone, isFullyInitialized (drive per-section skeleton display)
- Lifecycle: created after CoreData pre-warm; calls initialize() to load data

**TimeFilterManager (UI State):**
- Purpose: Shared time filter state across tabs (Home, History, Insights, Categories)
- Location: `AIFinanceManager/ViewModels/TimeFilterManager.swift`
- Type: @Observable @MainActor
- State: currentFilter: TimeFilter (week/month/quarter/year/allTime/custom)
- Allows filter selection to affect all tabs simultaneously

**InsightsService:**
- Purpose: Financial insights computation (spending, income, budgets, recurring, cash flow, wealth, savings, forecasting, health score)
- Location: `AIFinanceManager/Services/Insights/InsightsService.swift` (782 LOC main + 9 extensions)
- Architecture: Split into 10 domain files (main + 9 extensions: Spending, Income, Budget, Recurring, CashFlow, Wealth, Savings, Forecasting, HealthScore)
- Generators accept PreAggregatedData? and use O(1) dictionary lookups instead of O(N) scans
- Returns: InsightResult (insights: [InsightType], metadata: metadata)

## Entry Points

**App Launch:**
- Location: `AIFinanceManager/AIFinanceManagerApp.swift`
- Triggers: @main struct initialization on app start
- Responsibilities: Set up AppDelegate, create MainTabView, manage CoreData pre-warm, coordinate AppCoordinator creation

**Main Tab View (Root Navigation):**
- Location: `AIFinanceManager/Views/Home/MainTabView.swift`
- Triggers: Displayed when coordinator becomes non-nil
- Responsibilities: Tab bar navigation (Home, Transactions, Categories, Insights, Subscriptions, Settings)

**Home Screen (Primary Destination):**
- Location: `AIFinanceManager/Views/Home/ContentView.swift`
- Triggers: Opens on app launch
- Responsibilities: Display summary card, account cards, quick-add button, navigation to History/Subscriptions/Account detail

**TransactionStore Initialization:**
- Method: `TransactionStore.loadData()` (called from AppCoordinator.initialize())
- Triggers: After AppCoordinator creation
- Responsibilities: Load all transactions from repository on background context, build in-memory state

**AppCoordinator Initialization:**
- Method: `AppCoordinator.initialize()`
- Triggers: On app launch (from ContentView.task)
- Responsibilities: Load accounts/categories (fast-path), start background load of transactions, set isFastPathDone, set isFullyInitialized when complete

## Error Handling

**Strategy:** Throwable errors at persistence layer; graceful degradation at UI layer

**Patterns:**

**Repository Errors (Throwable):**
- `TransactionStoreError` — invalid amount, account not found, category not found, persistence failed
- `RecurringTransactionError` — invalid amount, invalid start date, series not found
- Thrown by: TransactionStore methods (add, update, delete, transfer, addBatch)
- Caught by: Views via `.alert(isPresented:presenting:actions:)` or `.errorAlert`

**Service Errors (Logged, Propagated):**
- `PDFError` — invalid document, no text found, OCR error
- `CSVImportError` — various parsing/validation errors
- Logged via `os.Logger` with `.error` level
- Propagated to UI as MessageBanner.error()

**CoreData Errors:**
- Caught during `context.save()` in repository methods
- Logged with full NSError details (code, domain, localizedDescription)
- Propagated upward as `TransactionStoreError.persistenceFailed`

**Graceful Degradation:**
- CSV import: batch validation fails → retry individual adds (salvages valid rows, skips invalid)
- Store reset: FRC (NSFetchedResultsController) stale reference crashes → observe storeDidResetNotification, rebuild FRC on new store
- CoreData unavailable: fallback to UserDefaults (transient state)

## Cross-Cutting Concerns

**Logging:**
- Framework: `os.Logger` (Apple's unified logging)
- Usage: Subsystem = "AIFinanceManager", category = domain/class name
- Examples:
  - `AppCoordinator`: subsystem "AIFinanceManager", category "AppCoordinator"
  - `TransactionStore`: subsystem "AIFinanceManager", category "TransactionStore"
  - `CoreDataStack`: subsystem "AIFinanceManager", category "CoreDataStack"
- Levels: .debug (detailed), .info (milestones), .error (failures)
- Performance: `PerformanceProfiler.swift` (#if DEBUG, 30+ call sites for startup/view render metrics)

**Validation:**
- Transaction validation: amount > 0, account exists, category exists
- Recurring validation: amount > 0, startDate valid, endDate >= startDate
- Category validation: name non-empty, color valid hex
- Services: `RecurringValidationService`, `CategoryValidationService`, etc.
- Applied at: TransactionStore.add(), TransactionStore.transfer(), recurring creation

**Authentication:**
- No authentication implemented (personal finance app, single user)
- Settings managed via AppSettings model (persistent UserDefaults)

**Caching:**
- UnifiedTransactionCache: category groupings, recurring state, balance amounts (LRU, capacity 1000)
- LRUCache<String, [Transaction]>: recurring transaction pre-computation (capacity 100)
- CategoryStyleCache: category colors, icons (per-transaction cached style)
- AmountDisplayConfiguration.formatter: cached NumberFormatter (hot path optimization)
- DateFormatters: static singletons for consistency and performance
- Granular invalidation: on each event, only affected cache entries cleared

**Concurrency:**
- Swift 6 strict concurrency: `SWIFT_STRICT_CONCURRENCY = targeted`
- Main Actor: All UI state (ViewModels, Views, UI operations) marked `@MainActor`
- Background contexts: Repository methods fetch on `newBackgroundContext()` (off-main), then `performAndWait` to merge
- Sendable: Repository protocol marked `@preconcurrency`; CoreDataStack `@unchecked Sendable` (internal synchronization via NSLock)
- Task isolation: dateFormatter as `@MainActor private static let`, formatted strings passed to Task.detached (not formatter itself)

**Persistence:**
- Write pattern: `persistIncremental(_ event:)` (O(1) per event, debounced 16ms)
- Read pattern: Repository load methods on background context, mapped to value types
- CoreData schema: 12 entities (Transaction, Account, Category, Subcategory, CategorySubcategoryLink, TransactionSubcategoryLink, RecurringSeries, RecurringOccurrence, and deprecated aggregates)
- Migrations: Deprecated MonthlyAggregateEntity, CategoryAggregateEntity left in schema (no read/write, no migration needed per Phase 40)

---

*Architecture analysis: 2026-03-02*
