# Tenra - Project Guide for Claude

## gstack

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools directly.

Available gstack skills:
- `/plan-ceo-review` — review plan from a CEO/product perspective
- `/plan-eng-review` — review plan from an engineering perspective
- `/review` — code review
- `/ship` — ship a feature end-to-end
- `/browse` — web browsing (use this instead of chrome MCP tools)
- `/qa` — QA testing
- `/setup-browser-cookies` — configure browser session cookies
- `/retro` — run a retrospective

## Quick Start

```bash
# Open project (requires Xcode 26+ beta)
open Tenra.xcodeproj

# Build via CLI
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run unit tests
xcodebuild test \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests

# Available destinations (Xcode 26 beta): iPhone 17 Pro (iOS 26.2), iPhone Air, iPhone 16e
# Physical device: name:Dkicekeeper 17

# Quickly isolate build errors (skip swiftc log noise)
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

## Project Overview

Tenra is a native iOS finance management application built with SwiftUI and CoreData. The app helps users track accounts, transactions, budgets, deposits, and recurring payments with a modern, user-friendly interface.

**Tech Stack:**
- SwiftUI (iOS 26+ with Liquid Glass adoption)
- Swift 5.0 (project setting), targeting Swift 6 patterns; `SWIFT_STRICT_CONCURRENCY = minimal`; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- CoreData for persistence
- Observation framework (@Observable)
- MVVM + Coordinator architecture

## Project Structure

```
Tenra/
├── Models/              # CoreData entities and business models
├── ViewModels/          # Observable view models (@MainActor)
│   └── Balance/         # Balance calculation helpers
├── Views/               # SwiftUI views and components
│   ├── Components/      # Shared reusable components
│   │   ├── Cards/       # Standalone card views (AnalyticsCard, TransactionCard, …)
│   │   ├── Rows/        # List and form row views (UniversalRow, InfoRow, …)
│   │   ├── Forms/       # Form containers (FormSection, EditSheetContainer, …)
│   │   ├── Icons/       # Icon display and picking (IconView, IconPickerView)
│   │   ├── Input/       # Interactive input (AmountInput, CategoryGrid, Carousel, …)
│   │   ├── Charts/      # Data visualization (DonutChart, PeriodBarChart, …)
│   │   ├── Headers/     # Section headers and hero displays (HeroSection, …)
│   │   └── Feedback/    # Banners, badges, status, content reveal (MessageBanner, StatusBadge, ContentRevealModifier)
│   ├── Accounts/        # Account management views
│   ├── Transactions/    # Transaction views
│   ├── Categories/      # Category views
│   ├── Subscriptions/   # Subscription views
│   ├── History/         # History views
│   ├── Deposits/        # Deposit views
│   ├── Settings/        # Settings views
│   ├── VoiceInput/      # Voice input views
│   ├── CSV/             # CSV views
│   ├── Import/          # Import views
│   └── Home/            # Home screen
├── Services/            # Business logic organized by domain
│   ├── Repository/      # Data access layer (5 specialized repositories)
│   ├── Balance/         # Balance calculation services
│   ├── Transactions/    # Transaction-specific services
│   ├── Categories/      # Category and budget services
│   ├── CSV/             # CSV import/export services
│   ├── Voice/           # Voice input services
│   ├── Import/          # PDF and statement parsing
│   ├── Recurring/       # Recurring transaction services
│   ├── Cache/           # Caching services
│   ├── Settings/        # Settings management
│   ├── Core/            # Core shared services (protocols, coordinators)
│   ├── Utilities/       # Utility services
│   ├── Audio/           # Audio services
│   └── ML/              # Machine learning services
├── Protocols/           # Protocol definitions
├── Extensions/          # Swift extensions (7 files)
├── Utils/               # Helper utilities and formatters
└── CoreData/            # CoreData stack and entities
```

## Architecture Principles

### MVVM + Coordinator Pattern
- **Models**: CoreData entities representing domain objects
- **ViewModels**: @Observable classes marked @MainActor for UI state
- **Views**: SwiftUI views that observe ViewModels
- **Coordinators**: Manage dependencies and initialization (AppCoordinator)
- **Stores**: Single source of truth for specific domains (TransactionStore)

### Key Architectural Components

#### AppCoordinator
- Central dependency injection point
- Manages all ViewModels and their dependencies
- Located at: `Tenra/ViewModels/AppCoordinator.swift`
- Provides: Repository, all ViewModels, Stores, and Coordinators
- Two-phase startup: `initializeFastPath()` loads accounts+categories (<50ms) → UI visible instantly; full 19k-transaction load runs in background via `initialize()`
- Observable flags `isFastPathDone` / `isFullyInitialized` drive per-section content reveal (staggered fade-in via `ContentRevealModifier`)
- **`TransactionStore.loadAccountsOnly()` is misnamed — it also loads categories.** Both are needed for the home screen's first paint.
- **`SettingsViewModel.loadSettingsOnly()` is the fastPath variant** (UserDefaults read only). `loadInitialData()` additionally decodes the full-resolution wallpaper UIImage on MainActor and is heavy — only `SettingsView.task` should call it.

#### TransactionStore
- **THE** single source of truth for transactions, accounts, and categories
- Loads **all** transactions in memory (`dateRange: nil`). ~7.6 MB for 19k tx — no windowing.
- ViewModels use computed properties reading directly from TransactionStore
- Debounced sync with 16ms coalesce window; granular cache invalidation per event type
- Event-driven architecture with TransactionStoreEvent
- Handles subscriptions and recurring transactions
- `apply()` pipeline: `updateState` → `updateBalances` → `invalidateCache` → `persistIncremental`
- **⚠️ `allTransactions` setter is a no-op** — to delete, use `TransactionStore.deleteTransactions(for...)` which routes through `apply(.deleted)`
- **O(1) lookup indexes** (maintained alongside the canonical arrays — read-only, never mutate from outside):
  - `transactionById: [String: Transaction]` — synced inside `updateState()` for every event (added/updated/deleted/bulkAdded). Use this instead of `transactions.first(where: { $0.id == ... })` on the 19k-element array.
  - `accountById: [String: Account]` — rebuilt by `rebuildAccountById()` whenever `accounts` mutates (load/add/update/delete/reorder in `TransactionStore+AccountCRUD.swift`). Adding new account-mutation paths MUST call `rebuildAccountById()`.
  - `seriesById: [String: RecurringSeries]` (forwarded from `RecurringStore`) — synced inside RecurringStore's `handleSeries*` helpers.
  - `accountsMutationVersion: Int` — bumped by `rebuildAccountById()`. Downstream caches (e.g. `AccountsViewModel.regularAccounts/depositAccounts/loanAccounts`) compare this against their last-seen value to detect invalidation cheaply.
- **`updateState .deleted` uses index-based removal**: `firstIndex(where:) + remove(at:)` instead of `removeAll{ $0.id == tx.id }`. The latter never short-circuits and was the silent quadratic source for batch deletes.

#### InsightsService — nonisolated, Background Computation
- `nonisolated final class` — explicitly opts out of implicit MainActor, runs on background thread via `Task.detached` in InsightsViewModel
- `DataSnapshot` struct (`Sendable`): bundles MainActor-isolated data (transactions, categories, recurringSeries, accounts, balanceFor closure) — built on MainActor before `Task.detached`, threaded through entire computation chain
- Three static helpers: `computeMonthlyTotals`, `computeLastMonthlyTotals`, `computeCategoryMonthTotals`
- All return lightweight value-type structs (`InMemoryMonthlyTotal`, `InMemoryCategoryMonthTotal`)
- `PreAggregatedData` struct: single O(N) pass builds monthly totals, category-month expenses, `txDateMap`, per-account counts. All generators use O(M) dictionary lookups.
- Split into 10 files: main service (~1095 LOC) + 9 domain extensions (`+Spending`, `+Income`, `+Budget`, `+Recurring`, `+CashFlow`, `+Wealth`, `+Savings`, `+Forecasting`, `+HealthScore`)
- **⚠️ No `transactionStore` access in extension methods** — all data comes via parameters (snapshot fields). Adding new generators must follow this pattern.
- **Severity sorting**: `InsightsViewModel` sorts insights by severity (`critical` > `warning` > `neutral` > `positive`) within each section via `sortedBySeverity()`
- **Deleted metrics (2026-04 audit)**: `incomeSeasonality`, `spendingVelocity`, `savingsMomentum` removed (low signal, duplicated by other generators)
- **`spendingSpike`**: uses relative threshold (1.5x category average) not absolute amount
- **`accountDormancy`**: excludes deposit accounts (they accrue interest without transactions)
- **Health Score components**: Cash Flow score uses gradient 0-100 (not binary); Emergency Fund baseline is 3 months (not 6); Budget Adherence excluded and weight redistributed when no budgets exist
- **`PreAggregatedData.seriesMonthlyEquivalents`**: pre-computed `[seriesId: monthlyEquivalent]` map built once in `PreAggregatedData.build(…, recurringSeries:)`. Generators (HealthScore, Recurring growth/duplicates, Forecasting) pass it via `seriesMonthlyEquivalent(_:baseCurrency:cache:)` to skip per-series `CurrencyConverter.convertSync` calls. **⚠️ When adding a new generator that calls `seriesMonthlyEquivalent`, always pass `cache: preAggregated?.seriesMonthlyEquivalents`**.
- **`filterByTimeRange(_:start:end:txDateMap:)` overload**: legacy MoM paths (Spending/Income) and `computeMonthlyPeriodDataPoints` accept an optional `txDateMap` to skip `DateFormatter.date(from:)` (~16μs/tx). Always thread `preAggregated?.txDateMap` through new generators that filter by date range.

#### BalanceCoordinator
- Single entry point for balance operations
- Manages balance calculation and caching
- Includes: Store, Engine
- **⚠️ `self.balances` sync rule**: All public methods that modify store balance MUST also (1) update `self.balances` dict (the `@Observable` published property) and (2) call `persistBalance()`. Private methods (`processAddTransaction`, etc.) do this correctly. When adding new public balance mutation methods, follow the same pattern: `var updated = self.balances; updated[id] = newBal; self.balances = updated; persistBalance(...)`

#### Recurring Transactions — Single-Next-Occurrence Model
- `generateUpToNextFuture()` backfills all past occurrences + creates exactly 1 future occurrence
- `extendAllActiveSeriesHorizons()` called on `loadData` and foreground resume
- `isActive: Bool` gates occurrence generation; `status: SubscriptionStatus?` controls Pause/Resume UI — both must be updated in tandem by `stopSeries`/`resumeSeries`

#### Deposits — Interest Accrual & Capitalization
- `Account.isDeposit` is a **computed property** (`depositInfo != nil`), not a stored flag
- `DepositInfo` persisted via `depositInfoData: Data?` (JSON-encoded Binary) on `AccountEntity` (CoreData v6)
- Interest formula: `principalBalance × (rate/100) / 365` per day — simple daily, compound monthly at posting
- `DepositInterestService.reconcileDepositInterest()`: triggered on view appear (`.task {}`), walks days since `lastInterestCalculationDate`, creates `.depositInterestAccrual` transaction on posting day
- Capitalization: if enabled → `principalBalance += postedAmount`; if disabled → `interestAccruedNotCapitalized += postedAmount`
- `calculateInterestToToday()`: read-only calculation for UI display (no side effects)
- **Account → Deposit conversion**: `DepositEditView` handles 3 modes (new, edit, convert) via `isConverting` computed property
- **⚠️ Initial date computation**: New/converted deposits MUST use `DepositEditView.computeInitialDates(postingDay:)` to set `lastInterestCalculationDate` to the most recent posting date — otherwise interest shows 0 (default is today → `calculateInterestToToday()` loop never executes)
- **⚠️ Don't decompose Account for addDeposit**: Use `AccountsViewModel.addDepositAccount(_ account:)` to preserve computed DepositInfo dates. Decomposing into fields loses `lastInterestCalculationDate`/`lastInterestPostingMonth`.
- **Deposit balance model**: `balance = initialPrincipal + sum(events with date > startDate)`. Events = `.depositTopUp` (+), `.depositWithdrawal` (−), `.depositInterestAccrual` (+ iff `capitalizationEnabled`). `principalBalance` is a cached result of `DepositInterestService.reconcileDepositInterest` — never mutate it outside that service. Link-interest flow reclassifies tx type only; it must NOT touch `principalBalance` / `interestAccruedNotCapitalized`.
- **`startDate` on DepositInfo** marks when the deposit "exists for calculation". Events dated on/before `startDate` are assumed baked into `initialPrincipal` and filtered out of the reconcile walk — prevents double-counting when converting a regular account with past income into a deposit.
- **Auto-posted interest tx id prefix `di_`**: deterministic djb2 hash of `(depositId, month, amount, currency)`. Survives process restarts → use for idempotency and bulk cleanup. `DepositsViewModel.recalculateInterest` deletes only `.depositInterestAccrual` with `di_` prefix so user-linked interest stays.
- **`DepositsViewModel.linkTransactionsAsInterest(depositId:transactions:transactionStore:)`**: converts `.income` on the deposit's account into `.depositInterestAccrual`. Pure reclassification — no balance/deposit-info mutation. UI wrapper: `DepositLinkInterestView` (uses shared `LinkPaymentsView` with `Options.deposit`).

#### Loans — Payment Tracking & Reconciliation
- `LoanInfo` persisted via `loanInfoData: Data?` (JSON-encoded Binary) on `AccountEntity` (CoreData v6), mirrors `DepositInfo` pattern
- `LoanPaymentService` (`nonisolated enum`): annuity formula, amortization schedule, payment breakdown, early repayment, reconciliation
- `LoanInfo.init` auto-calculates `monthlyPayment` when `nil` is passed — pass `nil` to force recalculation after principal/rate/term changes
- **Reconciliation**: `reconcileLoanPayments` is synchronous with `onTransactionCreated` callback. Callers MUST collect transactions in array, then batch-persist via `transactionStore.add()` after reconciliation completes. Do NOT spawn fire-and-forget `Task {}` inside the callback — creates race condition where loan state diverges from transaction records.
- **AccountsManagementView**: centralized reconciliation point for both deposits AND loans on `.task {}` appear
- **Every financial mutation MUST create a transaction**: `makeManualPayment` → `.loanPayment`, `makeEarlyRepayment` → `.loanEarlyRepayment`. Both return `Transaction?` for the caller to persist.
- **⚠️ `reconcileAllLoans` must be called globally** — not just per-loan in detail view. If user doesn't visit each loan's detail screen, reconciliation is skipped.

#### Logo Provider Chain (jsDelivr → LogoDev → GoogleFavicon → Lettermark)
- `JsDelivrLogoProvider` auto-indexes the `dkicekeeper/tenra-assets` GitHub repo via the jsDelivr packages API (`https://data.jsdelivr.com/v1/packages/gh/dkicekeeper/tenra-assets@main?structure=flat`), fuzzy-matches normalized filenames (strips spaces/underscores/hyphens/dots + common affixes like "bank"). Index cached to disk (`jsdelivr_logo_index.json`), refreshed daily. Empty index retries every 60s. Files served from `https://cdn.jsdelivr.net/gh/dkicekeeper/tenra-assets@main/logos/<file>`.
- `LogoDevProvider` uses logo.dev API with 5s timeout, checks `LogoDevConfig.isAvailable` internally
- `GoogleFaviconProvider` uses Google Favicon API (`sz=128`), rejects responses <1KB or images ≤16x16
- `LettermarkProvider` generates letter icons with djb2 deterministic colors — **never cached to disk** (so real logos can override later)
- `LogoProviderChain.fetch()` returns `LogoProviderResult` with `providerName` + `shouldCacheToDisk`
- `LogoDiskCache` has `cacheVersion` — bump it to invalidate stale cache on next launch
- Repo `dkicekeeper/tenra-assets` must stay public (jsDelivr serves only public GH repos). To force-refresh after edits use jsDelivr purge API; for full version pinning swap `@main` for a tag (`@v1`) in `JsDelivrLogoProvider.packageAPI` + `cdnBase`.
- No auth/keys required — public CDN, no Info.plist entries.
- `ServiceLogoRegistry` (`nonisolated enum`): `allServices` (170+), `domainMap`, `aliasMap`, `resolveDomain(from:)`, `search(query:)`
- `ServiceLogoEntry`: `domain`, `displayName`, `category`, `aliases` — no logoFilename, no bankLogo
- `ServiceCategory` has `.banks`, `.localServices`, `.telecom`, `.cis` + original 7 categories
- **⚠️ IconStyle rename**: `.bankLogo()` → `.roundedLogo()`, `.bankLogoLarge()` → `.roundedLogoLarge()`

### Current State
- **CoreData v8 model** (lightweight migration). v6 added `depositInfoData`/`isLoan`/`loanInfoData` on AccountEntity + `recurringSeriesId` String on TransactionEntity. v7 reorganised aggregate entities. v8 (perf-only) adds `byIdIndex` to TransactionEntity/AccountEntity/RecurringSeriesEntity, `byAccountIdIndex`/`byRecurringSeriesIdIndex` to TransactionEntity, `bySeriesIdIndex`/`byTransactionIdIndex` to RecurringOccurrenceEntity. Without `byIdIndex`, every `id == %@` predicate (insertTransaction/updateTransactionFields/deleteTransactionImmediately) was a full table scan over 19k rows.
- Old aggregate entities (`MonthlyAggregateEntity`, `CategoryAggregateEntity`) remain in `.xcdatamodeld` but are not read/written
- ContentView reactivity via `.task(id: SummaryTrigger)` — no manual `onChange` chains
- Per-element staggered fade-in during initialization (`ContentRevealModifier` — preserves view identity, no layout recalc spike)
- `IconSource` has 2 cases: `.sfSymbol(String)` and `.brandService(String)`. `displayIdentifier` produces `"sf:\(name)"` / `"brand:\(name)"` format; `from(displayIdentifier:)` decodes it
- **⚠️ BankLogo enum deleted** — all logos go through provider chain via `.brandService(domain)`

## Development Guidelines

### Swift 6 Concurrency Best Practices

**Critical for thread safety - follow these patterns:**

#### Implicit MainActor Isolation
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — ALL types are implicitly `@MainActor` unless explicitly `nonisolated`
- `nonisolated` on a type opts it out of implicit MainActor — use for services that must run off main thread
- `Task {}` inside `@MainActor` class inherits MainActor — `Task { @MainActor in }` is redundant
- `Task { @MainActor in }` IS needed inside nonisolated closures, audio callbacks
- **DataSnapshot pattern**: capture MainActor-isolated data into `Sendable` struct before `Task.detached`, pass through nonisolated computation chain (see `InsightsService.DataSnapshot`)
- **Modifier order**: access modifier ALWAYS first — `private nonisolated func`, `private nonisolated(unsafe) var`. NEVER `nonisolated private` or `nonisolated(unsafe) private`
- **`@NSManaged` order**: `@NSManaged public nonisolated var` — attribute first, access level second, `nonisolated` third
- **Sendable types in iOS 26 SDK**: `DateFormatter`, `Logger`, `Calendar`, `NumberFormatter` are all `Sendable` — use plain `nonisolated static let`, NOT `nonisolated(unsafe) static let`
- **`nonisolated(unsafe)`** only for mutable `static var` / stored properties with no actor protection — always add a comment explaining the accepted race

#### CoreData Entity Mutations
All CoreData entity property mutations MUST be wrapped in `context.perform { }`:

```swift
// ❌ WRONG - Causes Swift 6 concurrency violations
func updateAccount(_ entity: AccountEntity, balance: Double) {
    entity.balance = balance
}

// ✅ CORRECT - Thread-safe mutation
func updateAccount(_ entity: AccountEntity, balance: Double) {
    context.perform {
        entity.balance = balance
    }
}
```

#### Sendable Conformance
- Mark actor request types as `Sendable`
- Use `@Sendable` for completion closures
- Use `@unchecked Sendable` for singletons with internal synchronization
- Repository classes use `nonisolated final class … @unchecked Sendable` — safe because all mutations go through `context.performAndWait`
- `CoreDataStack.newBackgroundContext()` must be `nonisolated` — repositories call it from nonisolated context
- Model struct `init` and computed properties accessed from nonisolated services need `nonisolated`

```swift
// ✅ Example: BalanceUpdateRequest
struct BalanceUpdateRequest: Sendable {
    let completion: (@Sendable () -> Void)?
    enum BalanceUpdateSource: Sendable { ... }
}

// ✅ Example: CoreDataStack
final class CoreDataStack: @unchecked Sendable {
    nonisolated(unsafe) static let shared = CoreDataStack()
}
```

#### Main Actor Isolation
- Use `.main` queue for NotificationCenter observers in ViewModels
- Mark static constants with `nonisolated(unsafe)` when needed
- Wrap captured state access in `Task { @MainActor in ... }`

```swift
// ✅ NotificationCenter observers
NotificationCenter.default.addObserver(
    forName: .someNotification,
    queue: .main  // ← Ensures MainActor context
) { ... }

// ✅ Static constants
@MainActor class AppSettings {
    nonisolated(unsafe) static let defaultCurrency = "KZT"
}
```

#### Repository Pattern
All Repository methods that mutate CoreData entities must use `context.perform { }`:

```swift
// ✅ Pattern applied in AccountRepository, CategoryRepository, etc.
func saveAccountsInternal(...) throws {
    context.perform {
        existing.name = account.name
        existing.balance = account.balance
        // ... all mutations inside perform block
    }
}
```

**Reference**: See commit `3686f90` for comprehensive Swift 6 concurrency fixes.

### SwiftUI Best Practices
- Use modern SwiftUI APIs (iOS 26+ preferred)
- Follow strict concurrency (Swift 6.0+)
- Mark ViewModels with @Observable and @MainActor
- Use .onChange(of:) for reactive updates
- Adopt Liquid Glass design patterns where applicable

### State Management
- ViewModels are the source of truth for UI state
- Use @Bindable for two-way bindings
- Avoid @State in views for complex state - delegate to ViewModels
- Use Observation framework, not Combine publishers

### @Observable — Rules for Granular Updates

**Required rules for all `@Observable` classes:**

#### 1. @ObservationIgnored for Dependencies
Any property that is a service, repository, cache, formatter, or reference to another VM/Coordinator **must** be marked `@ObservationIgnored`:

```swift
// ❌ WRONG — SwiftUI will track repository and currencyService
@Observable @MainActor class SomeViewModel {
    let repository: DataRepositoryProtocol
    let currencyService = TransactionCurrencyService()
    var isLoading = false
}

// ✅ CORRECT — only isLoading is tracked
@Observable @MainActor class SomeViewModel {
    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored let currencyService = TransactionCurrencyService()
    var isLoading = false
}
```

**Rule of thumb**: if a property doesn't change after `init` or its change shouldn't trigger UI — use `@ObservationIgnored`.

**Important**: `weak var` dependencies also need `@ObservationIgnored`, not just `let`. SwiftUI tracks accesses at instance level.

**`@ObservationIgnored` only works inside `@Observable` classes**: on a regular `class`, `struct`, or `@MainActor`-class without `@Observable` — the attribute is silently ignored (no compile error, no effect). Remove it if `@Observable` is removed from the class.

#### 2. ViewModel Storage in Views
| Situation | Correct Pattern |
|-----------|----------------|
| VM created inside View | `@State var vm = SomeViewModel()` |
| VM passed from outside (read-only) | `let vm: SomeViewModel` |
| VM passed from outside (need `$binding`) | `@Bindable var vm: SomeViewModel` |
| VM from environment | `@Environment(SomeViewModel.self) var vm` |

Never use `@StateObject`, `@ObservedObject`, `@EnvironmentObject` — those are for old `ObservableObject`.

#### 3. Current Exceptions (intentionally observable)
- `TransactionStore.baseCurrency` — `var` without `@ObservationIgnored`, because currency change must trigger UI recalc
- `DepositsViewModel.balanceCoordinator` — `var?` without `@ObservationIgnored`, assigned after `init` (late injection)

### CoreData Usage
- All CoreData operations through DataRepositoryProtocol
- Repository pattern abstracts persistence layer (Services/Repository/)
- Specialized repositories for each domain (Transaction, Account, Category, Recurring)
- CoreDataRepository acts as facade, delegating to specialized repos
- Fetch requests should be optimized with predicates
- Use background contexts for heavy operations
- **⚠️ OR-per-month predicate crash**: Never build `NSCompoundPredicate(orPredicateWithSubpredicates:)` with one subpredicate per calendar month — exceeds SQLite expression tree depth limit (1000). Use a constant 7-condition range predicate instead.
- **`NSDecimalNumber.compare()` gotcha**: `number.compare(.zero)` doesn't compile — always write `number.compare(NSDecimalNumber.zero)`
- **`performFetch()` + `rebuildSections()` are synchronous on MainActor** — sections fully updated before the next line.
- **`resetAllData()` invalidates FRC**: Destroys/recreates the persistent store. FRC holders must observe `storeDidResetNotification` and call `setup()` to recreate. See `TransactionPaginationController.handleStoreReset()`.
- **FRC delegate must rebuild synchronously**: Use `MainActor.assumeIsolated { rebuildSections() }` — NOT `Task { @MainActor in }` which creates async hop allowing stale section access.
- **`addBatch` fallback pattern**: `TransactionStore.addBatch()` validates ALL transactions; one failure rejects the entire batch. `CSVImportCoordinator` retries individual `add()` calls.
- **Entity resolution case-sensitivity**: `resolveCategoryByName` must use case-insensitive comparison. When cache HITs on a case-variant, return the **stored** entity name (not the input name).
- **NEVER use `NSBatchDeleteRequest` then `context.save()` on the SAME context** when deleted objects have inverse relationships. Use `context.delete()` instead.
- **`viewContext.perform { }` runs on MainActor** — viewContext is MainActor-bound, so its perform queue blocks UI. Use `newBackgroundContext()` for heavy ops (purgeHistory, batch deletes, large fetches that don't need UI synchronicity).

### CSV Export/Import Round-Trip Rules
- **All 6 TransactionTypes** must export/import: `expense`, `income`, `internal`, `deposit_topup`, `deposit_withdrawal`, `deposit_interest`. Mappings live in `CSVColumnMapping.typeMappings`.
- **Income column swap**: Export writes `account` column = category, `targetAccount` = account name. Import's `CSVRow.effectiveAccountValue` for income reads `targetAccount`; `effectiveCategoryValue` reads `account`. This swap enables correct round-trip.
- **`targetCurrency`/`targetAmount` dual purpose**: For `internalTransfer` → target account data. For all other types → `convertedAmount`. Determined by `type` column on import (`EntityMappingService.convertRow`).
- **Subcategories export**: `CSVExporter` resolves `TransactionSubcategoryLink` → subcategory names via lookup dictionaries. Falls back to legacy `Transaction.subcategory` field.
- **CSV quote parsing**: RFC 4180 — peek-ahead for `""` (escaped quote). Both `CSVImporter.parseCSVLine` and `CSVParsingService.parseCSVLine` use index-based iteration, not `for char in line`.
- **`validateFileParallel` ordering**: `TaskGroup` doesn't guarantee order — results must be sorted by `globalIndex` after collection.

### File Organization Rules ("Where Should I Put This File?")

**Decision Tree:**
```
New file needed?
├─ Is it a SwiftUI View?
│  ├─ Reusable component (card, row, input, chart, etc.)? → Views/Components/<subdir>/
│  └─ Screen, modal, or coordinator? → Views/FeatureName/
├─ Is it UI state management?
│  └─ Yes → ViewModels/ (mark with @Observable and @MainActor)
├─ Is it business logic?
│  ├─ Transaction operations? → Services/Transactions/
│  ├─ Account operations? → Services/Repository/AccountRepository.swift
│  ├─ Category operations? → Services/Categories/
│  ├─ Balance calculations? → Services/Balance/
│  ├─ CSV import/export? → Services/CSV/
│  ├─ Voice input? → Services/Voice/
│  ├─ PDF parsing? → Services/Import/
│  ├─ Recurring transactions? → Services/Recurring/
│  ├─ Loan operations? → Services/Loans/
│  ├─ Caching? → Services/Cache/
│  ├─ Settings management? → Services/Settings/
│  ├─ Core protocol or shared service? → Services/Core/
│  └─ Generic utility? → Services/Utilities/
├─ Is it a domain model?
│  └─ Yes → Models/
├─ Is it a protocol definition?
│  └─ Yes → Protocols/
└─ Is it a utility/helper?
   ├─ Extension? → Extensions/
   ├─ Formatter? → Utils/
   └─ Theme/styling? → Utils/
```

**Naming Conventions:**
| Type | Suffix | Location | Purpose |
|------|--------|----------|---------|
| **AppCoordinator** | Coordinator | ViewModels/ | Central DI container |
| **Feature Coordinators** | Coordinator | Views/Feature/ | Navigation & feature setup |
| **Service Coordinators** | Coordinator | Services/Domain/ | Orchestrate multiple services |
| **Domain Services** | Service | Services/Domain/ | Business logic operations |
| **Repositories** | Repository | Services/Repository/ | Data persistence |
| **Stores** | Store | ViewModels/ | Single source of truth |
| **ViewModels** | ViewModel | ViewModels/ | UI state management |

### Code Style
- Clear, descriptive variable and function names
- Document complex logic with comments
- Use MARK: comments to organize code sections
- Follow Swift naming conventions (lowerCamelCase for properties/methods)

### Performance Considerations
- Log performance metrics with TransactionsViewModel+PerformanceLogging
- Use background tasks for expensive operations
- Cache frequently accessed data (see BalanceCoordinator cache)
- Optimize CoreData fetch requests with appropriate batch sizes
- **⚠️ SwiftUI `List` + 500+ sections = hard freeze** — SwiftUI renders all `Section` headers eagerly. Always slice: `Array(sections.prefix(visibleSectionLimit))` with `@State var visibleSectionLimit = 100`. Add `ProgressView().onAppear { visibleSectionLimit += 100 }` as the last List row for infinite scroll.
- **Pre-resolve per-row data at ForEach call site**: Passing `[Account]` or `[CustomCategory]` arrays to a row view means any element change forces ALL rows to re-render. Pre-resolve per-row `let` bindings inside `ForEach` and pass `Equatable` scalars.
- **`.onAppear` for synchronous cache warm-up**: Use `.onAppear { rebuildCache() }` (runs synchronously before next frame), NOT `.task { await rebuildCache() }` (async — fires after List body renders).
- **⚠️ `onAppear` fires on every back-navigation** — use `.task(id: trigger)` instead: combine reactive inputs in `Equatable` struct (`SummaryTrigger` pattern); SwiftUI manages cancellation automatically. Use debounce inside `if !isFullyInitialized` so init-complete triggers are immediate.
- **⚠️ Dead code deletion — orphaned call sites**: When deleting a class, grep all `.swift` sources for the class name AND all method names it implemented.
- **`CompileAssetCatalogVariant` failure can be transient** — if `grep -E "error:"` returns nothing, just retry.
- **Making an `@Observable` property reactive**: remove `@ObservationIgnored`, change to `private(set) var`; in the observing View add `.onChange(of: vm.property) { ... }`.
- **Cross-file extension access control**: `private` is file-scoped — extensions in OTHER files can't access it. Shared helpers → `internal` (no modifier); same file only → `private`.
- **Extension file imports are not inherited**: Each file needs its own `import os`, `import CoreData`, etc.
- **`DateFormatter` thread-safety**: on iOS 26+ target `DateFormatter` is `Sendable` — use `nonisolated static let`. On older targets: `@MainActor private static let`; format strings on MainActor before `Task.detached`; pass `String`, not the formatter.
- **`internal(set) var` on internal properties** — redundant (default is already internal), generates compiler warning; just use `var`
- **`defer` at end of scope** — generates "execution is not deferred" warning; replace with direct inline assignment
- **`Group {}` in `@ViewBuilder` computed var is unnecessary** — add `@ViewBuilder` and remove `Group`.
- **PreAggregatedData "piggyback" pattern**: Add fields to `PreAggregatedData.build()` O(N) loop — never add separate O(N) loops when one already exists.
- **`filterService.filterByTimeRange` is expensive** (~16μs/tx due to DateFormatter): use `txDateMap` inline filter when available.
- **⚠️ Recurring: fire-and-forget `createRecurringSeries()`** — generated txs are NOT in the store when `save()` returns. Always `await transactionStore.createSeries(series)` directly when you need to act on generated transactions (e.g. link subcategories).
- **⚠️ `getPlannedTransactions(horizon:)` deprecated** — filter `transactionStore.transactions` directly.
- **Reconciliation callback pattern**: Never spawn `Task {}` inside synchronous `onTransactionCreated` callbacks — collect into array, batch-persist after reconciliation completes. Applies to both deposits and loans.
- **Subcategory CoreData relationship**: `Transaction.subcategory: String?` is legacy; real subcats live via `categoriesViewModel.linkSubcategoriesToTransaction(transactionId:subcategoryIds:)`. Generated recurring txs need explicit linking after creation.
- **`categoriesViewModel` threading in Views**: `SubscriptionDetailView` and `SubscriptionsListView` require `CategoriesViewModel` passed as parameter from `ContentView`.
- **`@State` cache for 2k+ row lists**: Computed props for filter/group-by/lookup re-run per view-body eval and dominate tap latency. Move `filteredX`, `dateSections`, `accountById`, `allSatisfy`-flags into `@State`, rebuild in a single `rebuildDerivedCaches()` pass on input changes. See `SubscriptionLinkPaymentsView` for the pattern.
- **Heavy nonisolated scans off MainActor**: `Task.detached(priority: .userInitiated) { let result = Matcher.scan(...); await MainActor.run { self.baseline = result; self.applyFilters() } }` for O(N_transactions) filters on view open. SwiftUI `View` structs are auto-Sendable — capture is safe.
- **`TransactionStore.update()` blocks removing `recurringSeriesId`**: throws `cannotRemoveRecurring`. To unlink (e.g. bulk unlink from subscription), use `apply(.updated(old: tx, new: updatedTx))` directly. See `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift`.
- **`RecurringFrequency` case additions touch 6+ files**: `Models/RecurringTransaction.swift`, `Services/Recurring/RecurringValidationService.swift`, `Services/Recurring/RecurringTransactionGenerator.swift` (2 switches), `Services/Notifications/SubscriptionNotificationScheduler.swift`, `Services/Insights/InsightsService.swift` (2 switches), `Services/Insights/InsightsService+Recurring.swift`. Grep `case .monthly:` to audit.
- **New `.swift` files auto-register**: Xcode synchronized folders pick up any new file in `Tenra/` subdirectories on next build. Do NOT edit `project.pbxproj` manually for adding files.
- **Link-payments UI is shared**: `Views/Components/LinkPayments/LinkPaymentsView.swift` provides the full linking UX (filters, sheets, search, caches, background scan, haptic). New owner entities wrap it with `findCandidates` + `performLink` `@Sendable` closures — do NOT duplicate the state machine. See `SubscriptionLinkPaymentsView.swift` / `LoanLinkPaymentsView.swift`.
- **Transaction matchers must accept `AmountMatchMode`** (`.all` / `.tolerance` / `.exact`) — defined in `Services/Recurring/SubscriptionTransactionMatcher.swift`. Both `SubscriptionTransactionMatcher` and `LoanTransactionMatcher` conform; new matchers should follow the same signature to plug into `LinkPaymentsView`.
- **Don't profile under attached Xcode debugger** — `os.Logger.debug` flooding alone inflated a real <1s launch into a measured 4–6s. Use Instruments Time Profiler or detach debugger before measuring.
- **Reading `.count`/`.isEmpty`/`dict[key]` on an `@Observable` collection subscribes the body to the whole collection** — for hot paths over 19k transactions, maintain a separate Observable scalar mirror (e.g. `TransactionStore.transactionsCount`) and read that instead.
- **`PerformanceProfiler.start/end` uses `CACurrentMediaTime()` synchronously** — measurements reflect actual elapsed time at the call site. Older logs that captured time via queued `Task { @MainActor }` are not comparable.
- **`String(localized:)` в hot-path body чарта = антипаттерн**: на каждом scroll-кадре пересоздаётся localized string. Кэшировать в `@State` / `static let` вне `body` или использовать stable string keys для `position(by:)` и т.п.
- **Heavy axis-label maps кэшируются через `ChartAxisLabelMapCache`** (MainActor singleton, key=count+first+last). Любые новые heavy chart-формат-функции (`DateFormatter`, `Dictionary` builds) должны идти через аналогичный cache, иначе при scroll/zoom пересборка на 60fps доминирует frame budget.
- **`.animation(value:)` на scroll/zoom-зависимом state = hot-path catastrophe**: каждое scroll-событие запускает spring → накопление анимаций → лаги. Apple Charts сами плавно интерполируют — не нужно spring'а сверху.

## Swift Charts Patterns

- **Native scroll, не SwiftUI ScrollView**: `chartScrollableAxes(.horizontal)` + `chartXVisibleDomain(length:)` + `chartScrollPosition(x:)`. Лучше per-frame, чем `ScrollView { Chart }` с `defaultScrollAnchor`.
- **Scrollable charts должны быть bleed-to-edge** — без `.screenPadding()` на parent, иначе plot area обрезается и первая точка приклеивается к экранному отступу. Padding на header'ы / list'ы соседствующие с chart, не на chart.
- **`MagnifyGesture` конфликтует с NavigationStack swipe-back** — на детальных страницах НЕ использовать pinch zoom, заменять на `+/-` кнопки. Если без MagnifyGesture никак, ставить `.simultaneousGesture(...)` чтобы native chart gestures (selection) не перехватывались.
- **`chartXSelection(value:) + (range:) одновременно`** — value=tap, range=long-press-drag, не конфликтуют. НО оба binding'а должны быть установлены ОДНОВРЕМЕННО, иначе один перекрывает другой.
- **`chartScrollPosition(x:)` требует non-optional `Plottable`** — для `String?` оборачивать через `Binding<String>` с fallback на initial label.
- **Setter race во время range-selection**: Apple вызывает `chartScrollPosition.setter` во время `chartXSelection(range:)` drag → если scroll position управляет dynamic Y → бары прыгают. Решение: блокировать setter и **замораживать dynamic Y** пока `selectedRange != nil`.
- **Multi-series `AreaMark` STACK по умолчанию** — для overlay (income vs expense) нужно `series:` ПЛЮС `stacking: .unstacked` вместе. Без `series:` две areas мерджатся в одну zigzag-серию между x-точками.
- **`AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 6))`** — стандартное прореживание налезающих дат. Применять везде где AxisMarks { } по String x.
- **Initial trailing scroll**: вычислить `initialLeftLabel = dataPoints[max(0, count - visibleCount)].label` из GeometryReader proxy.size.width, передать в `chartScrollPosition(initialX:)`. Чарт по умолчанию открывается на leading.
- **Reusable `ChartZoomControls(zoomScale: $zoomScale, range:)`** — `+/-` кнопки с `step ×1.5` через `Views/Components/Charts/PeriodChartSwitcher.swift`. Используется в `PeriodChartSwitcher` (picker слева, zoom справа в HStack) и в standalone `PeriodLineChart` (свой `zoomToolbar`).
- **`AnyShapeStyle` для условных gradient/color** на `LineMark.foregroundStyle()` — allows switching между solid и `LinearGradient` без overload-конфликтов.

## SwiftUI Layout Gotchas

- **`containerRelativeFrame` wrong container**: Plain `HStack`/`VStack` are NOT qualifying containers — use `GeometryReader` for proportional sizing inside non-lazy containers.
- **`layoutPriority` is not proportional**: Higher priority takes all remaining space first — it's not a ratio.
- **`Task.yield()` for focus timing**: Replace `Task.sleep(nanoseconds:)` focus hacks with `await Task.yield()` inside `.task {}`.
- **Missing struct `}` after Button wrap**: Wrapping a view's body in `Button { }` can absorb the struct's closing brace — verify brace balance.
- **`.task` vs `.onAppear { Task {} }`**: `.task` is automatically cancelled on view removal; unstructured `Task {}` in `.onAppear` is unowned and can fire after dismissal.
- **`Text("localization.key")` renders the raw key**: Always use `Text(String(localized: "some.key"))` for guaranteed localized output.
- **`Task.sleep(nanoseconds:)` → Duration API**: Use `try? await Task.sleep(for: .milliseconds(150))` instead.
- **ForEach identity — never use `UUID()`**: `UUID()` generates a new id every render → spurious animations, sheet dismiss/reopen. Use stable identifiers: name-based id, `"\(name)_\(type.rawValue)"` fallback.
- **Prefer `.searchable(text:placement:.navigationBarDrawer(.always))` over custom TextField**: gives native Cancel for keyboard dismiss + scope/tokens support. Custom search bars in nav stacks typically need manual `@FocusState` + keyboard toolbar that `.searchable` handles for free.
- **Extra toolbar items in `EditSheetContainer`**: container uses `.cancellationAction` (xmark) + `.confirmationAction` (Save). Child views nest `.toolbar { ToolbarItem(placement: .primaryAction) { ... } }` inside the content closure — iOS auto-places `.primaryAction` items LEFT of `.confirmationAction`. Do NOT use `.topBarTrailing` / `.navigationBarTrailing` — they land on the wrong side of Save.
- **`.contentReveal(isReady:)` only hides via opacity — it does NOT skip body evaluation, layout, or render.** For genuinely deferred rendering of heavy sections (glass cards, PackedCircleIconsView, large grids), gate them behind an `if` condition instead.
- **iOS 26 TabView lazy-renders non-active tab content** — verified: `AnalyticsTab.body` and `SettingsTab.body` don't fire on launch when `.home` is selected. Don't worry about non-active tab init being on the launch critical path.

## Common Tasks

### Adding a New Feature
1. Create model (if needed) in Models/
2. Add service logic in Services/ or enhance existing Store
3. Create/update ViewModel in ViewModels/
4. Build SwiftUI view in Views/
5. Wire up dependencies in AppCoordinator

### Working with Transactions
- Use TransactionStore for all transaction operations
- Subscribe to TransactionStoreEvent for reactive updates
- Handle recurring transactions through TransactionStore
- Performance logging available via extension

### Working with Balance
- Use BalanceCoordinator as single entry point
- Balance operations are cached automatically
- Background queue handles expensive calculations

### UI Components
- Reusable components should be in Views/Components/
- Follow existing naming patterns (e.g., MenuPicker)
- Support both light and dark modes
- Test on multiple device sizes
- **IconView vs Image(systemName:)**: Use `IconView` for entity/category icons with styled backgrounds (accounts, categories, subscriptions, brand logos). Use `Image(systemName:)` for semantic indicators (checkmark, chevron, xmark, toolbar actions). Selection state wraps IconView externally (`.frame + .background + .clipShape`), not via IconView params.
- **Category icons MUST tint with `CustomCategory.color`**: For any category icon use explicit tint — `IconView(source: cat.iconSource, style: .circle(size:, tint: .monochrome(cat.color)))`, `IconConfig.custom(source:, style: .circle(... tint: .monochrome(cat.color)))`, `HeroSection(..., iconTint: .monochrome(cat.color))`. Convenience entry points default to accent and are wrong for categories: `IconView(source:size:)` → `.categoryIcon()` (accentMonochrome); `IconConfig.auto(...)` → same; `IconStyle.glassHero(size:)` default tint is `.original`. Source of truth: `CustomCategory.color` (decoded from `colorHex`); for budget-insight rows use the equivalent `BudgetInsightItem.color`.
- **CategoryRow icon is `xxl` (44pt) inside `BudgetProgressCircle` (52pt) ring** — composed, not drift. Compact category contexts (BudgetProgressRow, InsightDetailView, CSV mapping) use `lg` (24pt). Don't "unify" them.
- **IconStyle semantic presets in `Models/IconStyle.swift` are DS API** — `.toolbar`, `.inline`, `.roundedLogoLarge`, `.serviceLogoLarge`, `.glassService`, `.categoryCoin` may not be called in production but are intentional surface of the design system. Don't delete on dead-code grounds.
- **UniversalRow for form rows**: All form rows inside `FormSection(.card)` must use `UniversalRow(config: .standard)`. Optional icons: `icon.map { .sfSymbol($0, color:, size:) }`. Wrapper components (InfoRow, MenuPickerRow, DatePickerRow) delegate to UniversalRow internally.
- **`futureTransactionStyle(isFuture:)`**: Use this modifier instead of inline `.opacity(0.5)` for planned transactions.
- **`TransactionCard` API**: Takes `styleData: CategoryStyleData` (not `customCategories: [CustomCategory]`) and `sourceAccount: Account?` + `targetAccount: Account?` (not `accounts: [Account]`). Pre-compute at ForEach call site.

#### MessageBanner (`Views/Components/Feedback/MessageBanner.swift`)
Universal banner: `.success`, `.error`, `.warning`, `.info` with spring animations and type-matched haptics.

```swift
MessageBanner.success("Transaction saved successfully")
MessageBanner.error("Failed to load data")
```

#### UniversalCarousel (`Views/Components/Input/UniversalCarousel.swift`)
Generic horizontal carousel. Presets: `.standard`, `.compact`, `.filter`, `.cards`, `.csvPreview`. Config: `Utils/CarouselConfiguration.swift`.

#### UniversalFilterButton (`Views/Components/Input/UniversalFilterButton.swift`)
Filter chip in `.button(onTap)` or `.menu(menuContent:)` mode. Styling: `.filterChipStyle(isSelected:)`.

#### UniversalRow (`Views/Components/Rows/UniversalRow.swift`)
Generic row with `IconConfig` leading icons. Presets: `.standard`, `.settings`, `.selectable`, `.info`, `.card`. Modifiers: `.navigationRow {}`, `.actionRow(role:) {}`, `.selectableRow(isSelected:) {}`. `IconConfig`: `.sfSymbol(name, color)`, `.brandService(name)`, `.custom(source, style)`.

#### cardStyle() — Padding Contract
- `cardStyle()` = **pure visual only** (shape + material, NO padding). Never rely on it for spacing.
- **Rows own their padding** — `RowConfiguration` presets: `.standard` V:12 H:16, `.info` V:8 H:0, `.selectable` V:12 H:16, `.sheetList` V:12 H:16, `.settings` V:4 H:0
- **Arbitrary content** (VStack, HStack, custom cards) must add `.padding(AppSpacing.lg)` explicitly before `.cardStyle()`
- **`.info` H:0**: InfoRow always lives inside a container with `.padding(.lg)` — adding own H padding would double it to 32pt
- **`.settings` H:0**: `List`/`Form` apply `listRowInsets` (16pt leading/trailing) automatically — rows inside must NOT add H padding
- **Dividers inside cards**: `.padding(.leading, AppSpacing.lg)` (16pt) to align with row content start

**Design system files** (`Utils/`):
- `AppColors.swift` — semantic colors + `CategoryColors` palette (pre-computed hex→Color)
- `AppSpacing.swift` — `AppSpacing`, `AppRadius` (xs/compact/sm/md/lg/xl/circle), `AppIconSize`, `AppSize`
- `AppTypography.swift` — `AppTypography` (Inter variable font). `bodyEmphasis` for emphasized body text (18pt medium)
- `AppAnimation.swift` — `AppAnimation` constants (`contentSpring`, `gentleSpring`, `spring`, `facepileSpring`, `contentRevealAnimation`), `BounceButtonStyle`
- `AppModifiers.swift` — View style extensions (`cardStyle`, `filterChipStyle`, `futureTransactionStyle`, `chartAppear`, `staggeredEntrance`)
- `AppButton.swift` — `PrimaryButtonStyle`, `SecondaryButtonStyle`
- `AppEmptyState.swift` — empty state view component

### Animation Guidelines

#### Animation Token Usage — Never Use Hardcoded Springs
All animations must use `AppAnimation` constants. Never use inline `.spring(response:dampingFraction:)`.

| Context | Token |
|---------|-------|
| Validation errors, content toggles | `AppAnimation.contentSpring` |
| Amount changes, state transitions | `AppAnimation.gentleSpring` |
| Facepile icon entrance | `AppAnimation.facepileSpring` |
| Chart entrance (opacity+scale) | `AppAnimation.chartAppearAnimation` |
| Chart data updates | `AppAnimation.chartUpdateAnimation` |
| Section fade-in on init | `AppAnimation.contentRevealAnimation` |
| Progress bar expansion | `AppAnimation.progressBarSpring` |
| Bounce effects | `AppAnimation.spring` |

#### Animation Modifiers
- **`.staggeredEntrance(delay:)`** — scale(0.5→1.0) + opacity pop-in. Use for facepile icons, overlapping avatar stacks. Delay per icon: `Double(index) * AppAnimation.facepileStagger`.
- **`.chartAppear(delay:)`** — scale(0.94→1.0) + opacity from bottom. Use for chart containers and card entrances in scrollable lists.
- **`.contentReveal(isReady:delay:)`** — opacity fade-in. Use for staggered section reveals during initialization (home, insights).
- **`.filterChipStyle(isSelected:)`** — includes animated selection transition via `contentSpring`.

#### Card State Transitions (empty↔loaded)
Cards with empty/loaded states must animate the transition:
```swift
if items.isEmpty {
    EmptyStateView(...).transition(.opacity)
} else {
    loadedContent.transition(.opacity)
}
// Outside the conditional:
.animation(AppAnimation.gentleSpring, value: items.isEmpty)
```

#### Reduce Motion
All decorative animations respect `UIAccessibility.isReduceMotionEnabled`. Use `AppAnimation.isReduceMotionEnabled` to check. Reduce Motion-aware variants (`adaptiveSpring`, `fastAnimation`, etc.) return `.linear(duration: 0)` when enabled.

## Testing

- Unit tests: `TenraTests/`
- UI tests: `TenraUITests/`
- Test ViewModels with mock repositories
- Test CoreData operations with in-memory stores

## Git Workflow

Current branch: `main`
- Commit messages should be descriptive and concise
- Follow conventional commits when possible
- Always review changes before committing
- Include co-author tag for AI assistance

## Important Files to Reference

### Core Architecture
- **AppCoordinator.swift**: Central dependency injection and initialization (ViewModels/)
- **TransactionStore.swift**: Single source of truth for transactions and recurring operations (ViewModels/)
- **BalanceCoordinator.swift**: Balance calculation coordination (Services/Balance/)
- **DataRepositoryProtocol.swift**: Repository abstraction layer (Services/Core/)

### Data Persistence (Repository Pattern)
- **CoreDataRepository.swift**: Facade delegating to specialized repositories (Services/Repository/)
- **TransactionRepository.swift**: Transaction persistence operations (Services/Repository/)
- **AccountRepository.swift**: Account operations and balance management (Services/Repository/)
- **CategoryRepository.swift**: Categories, subcategories, links, aggregates (Services/Repository/)
- **RecurringRepository.swift**: Recurring series and occurrences (Services/Repository/)

### Key Services by Domain
- **Services/Transactions/**: Transaction filtering, grouping, pagination
- **Services/Balance/**: Balance calculations, updates, caching
- **Services/Categories/**: Category budgets, CRUD operations
- **Services/CSV/**: CSV import/export coordination (see CSV Export/Import Round-Trip Rules above)
- **Services/Voice/**: Voice input parsing and services

### Voice Input Architecture
- **VoiceInputView is self-contained**: manages its own `.sheet(item:)` for confirmation. No callback chains to parent — data flows directly within the view.
- **VoiceInputConfirmationView has its own `NavigationStack`**: present via `.sheet()`, NEVER via `.navigationDestination()` (nested NavigationStack = empty/broken view).
- **VoiceInputConfirmationView `onUpdate` mode**: pass `onUpdate: ((ParsedOperation) -> Void)?` to get edit-only behavior (returns updated ParsedOperation without saving). `nil` = save mode (legacy).
- **TransactionCard has built-in `.onTapGesture` + `.sheet`**: cannot be used as read-only preview — inner gesture intercepts outer. Build a custom preview card with `Button` + same subcomponents (`IconView`, `FormattedAmountView`).
- **Speech recognition `cancel()` fires callback** with empty/truncated text — guard with `guard self.isRecording || self.isStopping else { return }` and never overwrite `transcribedText` with empty string.
- **Silence detection**: audio-based VAD unreliable with background noise. Use text-based timeout: reset timer on every `transcribedText` change, auto-stop after N seconds of no new text.
- **Amplitude smoothing**: asymmetric — fast attack (`0.6` weight), slow decay (`0.08`). Text-driven spikes via `onChange(of: transcribedText)` blended with `0.4/0.6`.
- **SiriGlowView**: `MeshGradient` (iOS 18+) with `TimelineView(.animation)`. Read `amplitudeRef.value` directly each frame — no `@State` intermediary (causes stale values).

- **Services/Import/**: PDF and statement text parsing
- **Services/Cache/**: Caching coordinators and managers

### Currency / FX Rates Architecture
- **Three-file split**: `CurrencyConverter` (static facade, public API — `convertSync`/`getExchangeRate`/`convert`/`getAllRates`/`prewarm`) → `CurrencyRateStore` (lock-protected cache + UserDefaults persistence + `CurrencyRatesNotifier` for SwiftUI reactivity) → `Services/Currency/Providers/*` (`CurrencyRateProviderChain` over `JsDelivrCurrencyProvider` (primary, jsDelivr CDN + Cloudflare mirror, 200+ currencies, no auth) + `NationalBankKZProvider` (legacy XML fallback, 8 currencies)).
- **Internal storage is always KZT-pivot**: `cachedRates[X] = "KZT per 1 X"`. KZT itself is implicit (1.0) and is NEVER a key in the dict. Providers with a different native pivot (jsDelivr=USD) re-pivot via `ExchangeRates.normalized(toPivot: "KZT")` before reaching the store. Adding a new provider — return whatever pivot is natural; the store handles re-pivoting.
- **Persisted to UserDefaults** under `currency.rates.cache.v1`. `CurrencyRateStore.init()` restores synchronously so `convertSync` works at T=0 on warm-launch. Bump the key version when changing the on-disk format.
- **Pre-warm**: `CurrencyConverter.prewarm()` runs in parallel with `loadData()` in `AppCoordinator.initialize()`. Idempotent — skipped when `hasFreshRates` (cache <24h). The wait is capped at 2.5s via `withTaskGroup` race so a slow network never blocks `isFullyInitialized`. **⚠️ Don't remove the cap** — the post-prewarm `invalidateAndRecompute()` re-fires once rates land asynchronously.
- **Reactivity for `convertSync` consumers**: `transactionStore.currencyRatesVersion: Int` (Observable) bumps after prewarm. Aggregator views with `.task(id:)` (`ContentView.SummaryTrigger`, `AccountDetailView.refreshTrigger`, `CategoryDetailView.RefreshKey`) include it in their trigger so per-currency totals recompute when rates land. Adding a new aggregator that reads `convertSync` — fold `currencyRatesVersion` into its `.task(id:)` key.
- **In-flight de-duplication**: concurrent `getExchangeRate` calls for the same date share one `Task` via the `inflight` dict keyed by date — never bypass this.
- **⚠️ Test isolation**: `CurrencyRateStore.shared` persists across test runs via UserDefaults. Tests that assert `convertSync` returns nil (cross-currency matchers, e.g. `SubscriptionTransactionMatcherTests.findCandidates_matchesCrossCurrencyViaConvertedAmount`) MUST call `CurrencyRateStore.shared.clearAll()` in their suite `init()` — otherwise leaked rates from a previous suite cause spurious matches within the 30% default tolerance.

### Utils — Amount Formatting
| File | Purpose | Decimal places |
|------|---------|----------------|
| `AmountFormatter.swift` | Stored values: format/parse/validate; `minimumFractionDigits=2` | Always 2 ("1 234.50") |
| `AmountDisplayConfiguration.swift` | Global formatter config. **Hot path: `.formatter`** (cached). `makeNumberFormatter()` creates new object — never call in `List`/`ForEach` | Configurable (default 2) |
| `AmountInputFormatting.swift` | Input component mechanics: `cleanAmountString`, `displayAmount(for:)`, `groupDigits()`, `formatLargeNumber()` | 0–2 (no trailing zeros) |

- **`AmountDisplayConfiguration` cache invalidation**: `static var shared = Config() { didSet { _cache = nil } }` — mutating `shared.prop = x` also triggers `didSet` (Swift copies struct and reassigns)

### AnimatedInputComponents.swift
- Contains `BlinkingCursor`, `AmountDigitDisplay`, `AmountInput`
- `AmountDigitDisplay`: animated amount display using single `Text` with `.numericText()` transition. Visual digit grouping via `AttributedString.kern` (not space characters). Font sizing via `.minimumScaleFactor(0.3)`
- `AmountInput`: self-contained amount input (AmountDigitDisplay + hidden TextField + focus management). Configurable: `baseFontSize`, `color`, `placeholderColor`, `autoFocus`, `showContextMenu`, `onAmountChange`
- `AmountInputView`: thin wrapper around `AmountInput` + currency selector + conversion display + error. Conversion display also uses kern-based grouping
- `AnimatedTitleInput` uses `contentTransition(.interpolate)` — intentionally different
- **Kern technique for `.numericText()`**: Space characters in the string shift character positions on grouping change ("1 234" -> "12 345"), causing multiple digits to animate. `AttributedString.kern` is a styling attribute invisible to `.numericText()` — the string stays "12345" but renders as "12 345". Only the actual typed/deleted digit animates.

## AI Assistant Instructions

When working with this project:

1. **Always read before editing**: Use Read tool to understand existing code
2. **Follow architecture**: Respect MVVM + Coordinator patterns
3. **Use existing patterns**: Check similar implementations before creating new ones
4. **Update AppCoordinator**: When adding new ViewModels or dependencies
5. **Maintain consistency**: Follow existing code style and conventions
6. **Performance first**: Consider performance implications of changes
7. **Test changes**: Verify builds and runs after modifications
8. **Document refactoring**: Update this file when architecture changes

### Preferred Tools
- Use SwiftUI Expert skill for SwiftUI-specific tasks
- Use Read/Edit tools for file operations (not Bash cat/sed)
- Use Grep for searching code patterns
- Use Glob for finding files by pattern

### Don't
- Don't create unnecessary abstractions
- Don't ignore existing architectural patterns
- Don't add features without understanding context
- Don't skip reading existing code before modifications
- Don't use Combine when Observation framework is preferred
- Don't flag `#Preview` block inconsistencies as production drifts in audits — distinguish preview-only from production usage when grep'ing

## Questions?

When unsure about architecture decisions:
1. Check existing similar implementations
2. Review AppCoordinator for dependency patterns
3. Look at recent commits for refactoring context
4. Ask user for clarification on business requirements

---

## Reference Docs

Active references in `docs/`:
- `docs/UI_COMPONENTS_GUIDE.md` — design system tokens, components, decision trees, padding contract
- `docs/INSIGHTS_METRICS_REFERENCE.md` — per-metric reference for InsightsService (formulas, granularity, data sources)
- `docs/CORE_DATA_AUDIT_2026_03_12.md` — CoreData threading audit (23 fixes, rationale for patterns)
- `docs/SWIFT_CONCURRENCY_AUDIT_2026_03_12.md` — Swift Concurrency audit (527→0 warnings)

Historical docs (301 files) archived to `docs/archive/`.

---

**Last Updated**: 2026-04-28
**iOS Target**: 26.0+ (requires Xcode 26+ beta)
**Swift Version**: 5.0 project setting; Swift 6 patterns; `SWIFT_STRICT_CONCURRENCY = minimal`; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
