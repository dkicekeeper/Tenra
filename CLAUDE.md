# AIFinanceManager - Project Guide for Claude

## Quick Start

```bash
# Open project (requires Xcode 26+ beta)
open AIFinanceManager.xcodeproj

# Build via CLI
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run unit tests
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIFinanceManagerTests

# Available destinations (Xcode 26 beta): iPhone 17 Pro (iOS 26.2), iPhone Air, iPhone 16e
# Physical device: name:Dkicekeeper 17

# Quickly isolate build errors (skip swiftc log noise)
xcodebuild build -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

## Project Overview

AIFinanceManager is a native iOS finance management application built with SwiftUI and CoreData. The app helps users track accounts, transactions, budgets, deposits, and recurring payments with a modern, user-friendly interface.

**Tech Stack:**
- SwiftUI (iOS 26+ with Liquid Glass adoption)
- Swift 5.0 (project setting), targeting Swift 6 patterns; `SWIFT_STRICT_CONCURRENCY = targeted`
- CoreData for persistence
- Observation framework (@Observable)
- MVVM + Coordinator architecture

## Project Structure

```
AIFinanceManager/
├── Models/              # CoreData entities and business models
├── ViewModels/          # Observable view models (@MainActor)
│   └── Balance/         # Balance calculation helpers
├── Views/               # SwiftUI views and components
│   ├── Components/      # Shared reusable components (no extra nesting)
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
├── Extensions/          # Swift extensions (6 files)
├── Utils/               # Helper utilities and formatters
└── CoreData/            # CoreData stack and entities
```

**Note:** All directories contain files - no empty directories remain.

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
- Located at: `AIFinanceManager/ViewModels/AppCoordinator.swift`
- Provides: Repository, all ViewModels, Stores, and Coordinators

#### TransactionStore (Phase 7+, Enhanced Phase 9, Performance Phase 16-22)
- **THE** single source of truth for transactions, accounts, and categories
- ViewModels use computed properties reading directly from TransactionStore (Phase 16)
- Debounced sync with 16ms coalesce window (Phase 17)
- Granular cache invalidation per event type (Phase 20)
- Event-driven architecture with TransactionStoreEvent
- Handles subscriptions and recurring transactions
- Phase 22: Owns `categoryAggregateService` and `monthlyAggregateService` — persistent aggregate maintenance

#### CategoryAggregateService (Phase 22)
- Maintains `CategoryAggregateEntity` records in CoreData (already had schema, now active)
- Incremental O(1) updates on each transaction mutation
- Stores spending totals per (category, year, month) — monthly, yearly, and all-time granularity
- `fetchRange(from:to:currency:)` used by InsightsService for O(M) category breakdown instead of O(N) scan
- Located at: `Services/Categories/CategoryAggregateService.swift`

#### MonthlyAggregateService (Phase 22)
- New `MonthlyAggregateEntity` CoreData entity (added Phase 22)
- Stores (totalIncome, totalExpenses, netFlow) per (year, month, currency)
- InsightsService `computeMonthlyDataPoints()` reads these — O(M) instead of O(N×M)
- Graceful fallback: if aggregates not ready (first launch), uses original O(N×M) transaction scan
- Located at: `Services/Balance/MonthlyAggregateService.swift`

#### BudgetSpendingCacheService (Phase 22)
- Caches current-period spending totals in `CustomCategoryEntity.cachedSpentAmount`
- `CategoryBudgetService.calculateSpent()` reads cache first (O(1)), falls back to O(N) scan
- Invalidated on any transaction mutation in the relevant category
- Located at: `Services/Categories/BudgetSpendingCacheService.swift`

#### BalanceCoordinator (Phase 1-4)
- Single entry point for balance operations
- Manages balance calculation and caching
- Includes: Store, Engine, Queue, Cache

### Recent Refactoring Phases

**Phase 25** (2026-02-22): ChartDisplayMode — Consistent Chart API
- Replaced `compact: Bool` with `ChartDisplayMode` enum (`.compact` / `.full`) across all 7 chart components
- New `Utils/ChartDisplayMode.swift` — `showAxes` and `showLegend` computed helpers
- Each struct uses `private var isCompact: Bool { mode == .compact }` — minimal body diff
- `InsightsCardView` → `.compact`, all detail/section views → `.full` (explicit at every call site)
- Fixed: `InsightDetailView` previously omitted the parameter entirely (relied on default `false`)
- Design doc: `docs/plans/2026-02-22-chart-display-mode-design.md`

**Phase 39** (2026-03-02): ContentView Reactivity — `.task(id:)` replaces manual `onChange` chains
- 5 `onChange` + `summaryUpdateTask`/`wallpaperLoadingTask` @State handles + 4 функции (`updateSummary`, `loadWallpaperOnce`, `reloadWallpaper`, `startWallpaperLoad`) → 2 `.task(id:)` (~160 LOC removed)
- `SummaryTrigger: Equatable` struct (`txCount`, `filterName`, `isImporting`, `isFullyInitialized`) — параметр `.task(id: summaryTrigger)`; SwiftUI отменяет/перезапускает автоматически
- Дебаунс-условие: `try? await Task.sleep(for: .milliseconds(80))` только внутри `if !coordinator.isFullyInitialized` — при завершении инициализации карточка обновляется немедленно
- Обои: `HomePersistentState.wallpaperImageName` хранит имя загруженного файла; `guard homeState.wallpaperImageName != targetName` в `.task(id:)` исключает перезагрузку при возврате назад
- `@MainActor private static let summaryDateFormatter` — форматируем даты на MainActor, передаём `String` (Sendable) в `Task.detached`; `DateFormatter` нельзя создавать внутри detached-задач (не Sendable)
- `HomePersistentState.hasAppearedOnce` удалён — больше не нужен; `.task(id:)` перезапуск при re-appear дёшев

**Phase 38** (2026-02-28): InsightsService Split — 2832 LOC Monolith → 10 Domain Files
- `InsightsService.swift` shrunk to 782 LOC — retains: class decl, init, public API, granularity API, period data points, shared helpers
- 9 new extension files: `+Spending`, `+Income`, `+Budget`, `+Recurring`, `+CashFlow`, `+Wealth`, `+Savings`, `+Forecasting`, `+HealthScore`
- **Access control rule**: cross-file extensions need `internal` (no modifier) — changed `private let/static let/func` on logger, deps, formatters, `PeriodSummary`, shared helpers (`resolveAmount`, `startOfMonth`, `seriesMonthlyEquivalent`, `monthlyRecurringNet`)
- **Import rule**: each extension file needs its own `import os` (for `Self.logger`) and `import CoreData` (for `NSFetchRequest`) — not inherited from main file
- Service audit also completed: deleted 3 dead protocols, merged `TransactionConverterService` → `EntityMappingService`, fixed `TransactionQueryService` dateFormatter race, documented `CurrencyConverter` vs `TransactionCurrencyService`, marked `RecurringTransactionService` deprecations

**Phase 36** (2026-02-28): Reactivity Audit — Dead Code Removal, Cache Simplification, Instant UI Updates
- **~800 LOC deleted**: `BalanceCacheManager.swift`, `BalanceUpdateQueue.swift`, `BalanceUpdateCoordinator.swift`, `CategoryAggregateCacheStub.swift`, `CategoryAggregateCacheProtocol.swift` — all were dead after Phase 22 aggregate caching
- **Double-invalidation fixed**: Removed synchronous `invalidateCaches()` from `TransactionStore.invalidateCache(for:)` — only the debounced path now runs
- **Category grid reactivity**: Removed `@ObservationIgnored` from `QuickAddCoordinator.timeFilterManager` — grid totals now update on filter change
- **Sheet identity fixed**: `CategorySelection` uses stable `name`-based `id` instead of `UUID()` — no more spurious sheet dismiss/reopen
- **ForEach identity fixed**: `CategoryDisplayDataMapper` uses `"\(name)_\(type.rawValue)"` fallback id instead of `UUID().uuidString`
- **Insights staleness fixed**: `InsightsViewModel.isStale` is now observable (no `@ObservationIgnored`); `InsightsView` adds `.onChange(of: insightsViewModel.isStale)` to reload while tab is open
- **Budget period rollover fixed**: `BudgetSpendingCacheService.cachedSpent(for:currency:budgetPeriodStart:)` returns `nil` if cached data predates the current budget period
- **Minor**: `InsightsViewModel.baseCurrency` reads `transactionStore.baseCurrency` directly; `DateSectionExpensesCache` drops `@Observable`; `BalanceStore.updateHistory` → `@ObservationIgnored`; `DateFormatter` cached as static in `CategoryBudgetService`/`MonthlyAggregateService`

**Phase 35** (2026-02-27): CSV Import Crash Fix + Case-Sensitivity Fix
- **FRC stale reference crash fixed**: `CoreDataStack.storeDidResetNotification` posted synchronously after `resetAllData()`. `TransactionPaginationController.handleStoreReset()` tears down old FRC and recreates on new store.
- **FRC sync rebuild**: `controllerDidChangeContent` uses `MainActor.assumeIsolated { rebuildSections() }` instead of async `Task` — eliminates window for stale object access.
- **Category case-sensitivity bug fixed**: `resolveCategoryByName` now uses case-insensitive comparison (like accounts/subcategories). Cache HIT returns stored name, not input name.
- **addBatch fallback**: When batch validation fails, CSVImportCoordinator retries individual `add()` — salvages valid transactions instead of rejecting entire batch.
- **Result**: CSV import of 19,444 rows: 18,444 → 19,444 (0 skipped). Zero crashes on store reset.

**Phase 34** (2026-02-26): Utils Cleanup — Dead Code & Design System Split
- **Deleted `PerformanceLogger.swift`** (390 LOC dead code) — все 18 call sites удалены из HistoryView, InsightsViewModel, InsightsService. Единственный активный профайлер: `PerformanceProfiler.swift` (#if DEBUG, 30+ call sites).
- **`AppTheme.swift` (743 LOC) → 6 файлов**: `AppColors.swift`, `AppSpacing.swift`, `AppTypography.swift`, `AppShadow.swift`, `AppAnimation.swift`, `AppModifiers.swift` (все View extensions + TransactionRowVariant).
- **Deleted `Colors.swift`** — `CategoryColors` struct (palette + hexColor) перенесён в `AppColors.swift`.
- **`AmountFormatter.swift`**: убран мёртвый `import Combine`.
- **`CategoryStyleCache.swift` НЕ удалён** — активно используется через `CategoryStyleHelper.cached()` в 4 view-файлах (TransactionCard, TransactionRowContent, CategoryChip, TransactionCardComponents). Не удалять.

**Phase 33** (2026-02-26): Component Extraction — `BudgetProgressCircle` (`Views/Components/`), `StatusIndicatorBadge` + `EntityStatus` enum (`.active/.paused/.archived/.pending`), `RecurringSeries.entityStatus` bridge. `.futureTransactionStyle(isFuture:)` modifier added — use instead of inline `.opacity(0.5)`.

**Phase 32** (2026-02-26): Design System Hardening — new `AppColors` tokens (`transfer` cyan-teal, `planned` blue, `statusActive/Paused/Archived`); new `AppSize`/`AppAnimation` constants; 27 hardcoded colors eliminated across 13 files. Critical localization fix: `AccountRow.swift` line 43 `Text("account.interestTodayPrefix")` → `String(localized:defaultValue:)`.

**Phase 31** (2026-02-26): SwiftUI Anti-Pattern Sweep — `@ObservationIgnored` added to service deps in `InsightsViewModel` + `TransactionsViewModel`; `AnyView` → `@ViewBuilder` in 4 style modifiers; `InsightDetailView` made generic `<CategoryDestination: View>` (no `AnyView` in nav callback); `DispatchQueue` → structured concurrency in 2 views + 2 repos.

**Phase 30** (2026-02-23): Per-Element Skeleton — `SkeletonLoadingModifier` (`Views/Components/SkeletonLoadingModifier.swift`), shimmer background/duration/blendMode fixes. `AppCoordinator` gains observable `isFastPathDone` / `isFullyInitialized` flags driving per-section skeleton display.

**Phase 29** (2026-02-23): Initial skeleton attempt — superseded by Phase 30 bug fixes.

**Phase 28** (2026-02-23): Instant Launch — Startup Performance
- **Progressive UI**: `initializeFastPath()` loads accounts+categories only (<50ms) → UI visible instantly; full 19k-transaction load runs in background via `initialize()`
- **Background CoreData fetch**: All 8 `load*()` repository methods moved from `viewContext` (main thread) to `newBackgroundContext() + performAndWait` — unblocks MainActor during 19k entity materialization. `loadData()` wrapped in `Task.detached` in TransactionStore.
- **Two-phase balance registration**: Phase A reads persisted `account.balance` instantly (zero-delay UI). Phase B recalculates `shouldCalculateFromTransactions` accounts in background via `Task.detached` using only value-type captures (excludes deposit accounts). `@ObservationIgnored` applied to all 5 `let` dependencies in BalanceCoordinator.
- **Deferred recurring generation**: `generateRecurringTransactions()` moved to `Task(priority: .background)` after full data load — removed from startup critical path.
- **Incremental persist O(1)**: `persistIncremental(_ event:)` replaces `await persist()` (which called `saveTransactions([all 19k])` = O(3N) = ~57k ops). Routes to `insertTransaction`/`updateTransactionFields`/`batchInsertTransactions` per event type.
- **Targeted repository methods**: Added `insertTransaction`, `updateTransactionFields`, `batchInsertTransactions` to `DataRepositoryProtocol`, `TransactionRepository`, `CoreDataRepository` (with no-op stubs in `UserDefaultsRepository`). Full error logging via `os.Logger`.
- **NSBatchInsertRequest + viewContext merge**: `batchInsertTransactions` uses `NSBatchInsertRequest` (bypasses NSManagedObject overhead). `CoreDataStack.mergeBatchInsertResult(_:)` merges inserted IDs into viewContext via `NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)`.
- Design doc: `docs/plans/2026-02-23-startup-performance-instant-launch.md`

**Performance improvements (Phase 28):**
- Time to first pixel: ~2-4s (full spinner) → <100ms (fast-path)
- CoreData fetch thread: main thread (blocks UI) → background context
- Ops per single transaction mutation: ~57,000 (O(3N)) → ~3 (O(1))
- Balance display at startup: after O(N×M) recalc → instant (persisted value)
- CSV import 1000 rows: ~10s → <1s (NSBatchInsertRequest)

**Phase 27** (2026-02-23): Insights Performance — SQLite Crash Fix + Progressive Loading
- **Root cause fixed**: `CategoryAggregateService.fetchRange()` and `MonthlyAggregateService.fetchRange()` were building `NSCompoundPredicate(orPredicateWithSubpredicates:)` with one subpredicate per calendar month — exceeds SQLite expression tree depth limit (1000) for ranges > ~80 months. Fixed with a constant 7-condition range predicate.
- **InsightsService batching**: `computeGranularities(_ granularities: [InsightGranularity], ...)` added — computes any subset of granularities in one call; `computeAllGranularities` delegates to it. Reduces 5 `@MainActor` hops → 1 from `Task.detached`.
- **firstDate hoisted**: O(N) date-parse scan for earliest transaction moved out of per-granularity loop into `loadInsightsBackground()`, passed as `firstTransactionDate` parameter.
- **Two-phase progressive loading**: Phase 1 computes only `currentGranularity` → writes to UI immediately (user sees real data after ~1/5 of total time). Phase 2 computes remaining 4 granularities + health score → final UI write.
- Design doc: `docs/plans/2026-02-22-insights-performance-optimization.md`

**Phase 24** (2026-02-22): Full Intelligence Suite — 10 new `InsightType` cases; `.savings` + `.forecasting` categories; `FinancialHealthScore` (0-100, 5 weighted components). `InsightsViewModel` gains `savingsInsights`, `forecastingInsights`, `healthScore`.

**Phase 23** (2026-02-20): @ObservationIgnored sweep — rule now in Dev Guidelines. Reference implementations: `AppCoordinator`, `TransactionStore`, `AddTransactionCoordinator`.

**Phase 22** (2026-02-19): Persistent Aggregate Caching — `CategoryAggregateEntity` activated; `MonthlyAggregateEntity` + `BudgetSpendingCacheService` added. `TransactionStore.apply()` calls `updateAggregates(for:)` after each mutation. Performance: Insights O(N×M) → O(M), budget read O(N) → O(1). Startup rebuild if aggregates empty.

**Phase 16-21** (2026-02-19): Performance — ViewModels use computed properties from TransactionStore (SSOT); debounced sync (16ms); InsightsViewModel lazy. **⚠️ `allTransactions` setter is a no-op** — to delete use `TransactionStore.deleteTransactions(for...)` which routes through `apply(.deleted)` for proper aggregate/cache/persistence.

**Phase 15** (2026-02-16): `MessageBanner` — unified `.success`/`.error`/`.warning`/`.info` (see `Views/Components/MessageBanner.swift`).
**Phase 14** (2026-02-16): `UniversalFilterButton` — `.button(onTap)` + `.menu(content)` modes (see `Views/Components/UniversalFilterButton.swift`).
**Phase 13** (2026-02-16): `UniversalCarousel` — presets `.standard/.compact/.filter/.cards/.csvPreview` (see `Views/Components/UniversalCarousel.swift`).
**Phase 12** (2026-02-16): `UniversalRow` — generic row with `IconConfig`; `.navigationRow()`, `.actionRow()`, `.selectableRow()` (see `Views/Components/UniversalRow.swift`).
**Phase 11** (2026-02-15): Swift 6 concurrency — ~164 warnings fixed; patterns in Dev Guidelines.
**Phase 10** (2026-02-15): Repository split — `CoreDataRepository` facade + 4 specialized repos; `Services/` reorganized.
**Phase 9**: `SubscriptionsViewModel` removed; recurring ops moved to `TransactionStore`.
**Phase 7**: TransactionStore introduction. **Phase 1-4**: BalanceCoordinator foundation.

## Development Guidelines

### Swift 6 Concurrency Best Practices

**Critical for thread safety - follow these patterns:**

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

### @Observable — Правила точечных обновлений (Phase 23)

**Обязательные правила для всех `@Observable` классов:**

#### 1. @ObservationIgnored для зависимостей
Любое свойство, которое является сервисом, репозиторием, кэшем, форматтером или ссылкой на другой VM/Coordinator — **обязано** быть помечено `@ObservationIgnored`:

```swift
// ❌ WRONG — SwiftUI начнёт трекать repository и currencyService
@Observable @MainActor class SomeViewModel {
    let repository: DataRepositoryProtocol
    let currencyService = TransactionCurrencyService()
    var isLoading = false
}

// ✅ CORRECT — трекается только isLoading
@Observable @MainActor class SomeViewModel {
    @ObservationIgnored let repository: DataRepositoryProtocol
    @ObservationIgnored let currencyService = TransactionCurrencyService()
    var isLoading = false
}
```

**Правило большого пальца**: если свойство не меняется после `init` или его изменение не должно триггерить UI — ставь `@ObservationIgnored`.

**Важно**: `weak var` зависимости также обязаны иметь `@ObservationIgnored`, не только `let`. SwiftUI трекает доступы на уровне экземпляра — `transactionStore.property` всё равно отслеживается на TransactionStore напрямую.

#### 2. Хранение VM во View
| Ситуация | Правильный паттерн |
|----------|--------------------|
| VM создаётся внутри View | `@State var vm = SomeViewModel()` |
| VM передаётся снаружи (только чтение) | `let vm: SomeViewModel` |
| VM передаётся снаружи (нужен `$binding`) | `@Bindable var vm: SomeViewModel` |
| VM из environment | `@Environment(SomeViewModel.self) var vm` |

❌ **Никогда не используй** `@StateObject`, `@ObservedObject`, `@EnvironmentObject` — это для старого `ObservableObject`.

#### 3. Текущие исключения (намеренно observable)
- `TransactionStore.baseCurrency` — `var` без `@ObservationIgnored`, т.к. смена базовой валюты должна триггерить пересчёт UI
- `DepositsViewModel.balanceCoordinator` — `var?` без `@ObservationIgnored`, т.к. назначается после `init` (late injection)

### CoreData Usage
- All CoreData operations through DataRepositoryProtocol
- Repository pattern abstracts persistence layer (Services/Repository/)
- Specialized repositories for each domain (Transaction, Account, Category, Recurring)
- CoreDataRepository acts as facade, delegating to specialized repos
- Fetch requests should be optimized with predicates
- Use background contexts for heavy operations
- **⚠️ OR-per-month predicate crash**: Never build `NSCompoundPredicate(orPredicateWithSubpredicates:)` with one subpredicate per calendar month. For ranges > ~80 months SQLite raises `Expression tree too large (maximum depth 1000)`. Use a constant 7-condition range predicate instead: `year > 0 AND month > 0 AND (year > startYear OR (year == startYear AND month >= startMonth)) AND (year < endYear OR (year == endYear AND month <= endMonth))`. See `CategoryAggregateService.fetchRange()` for reference implementation.
- **`NSDecimalNumber.compare()` gotcha**: `number.compare(.zero)` **не компилируется** — Swift не выводит тип из `NSNumber`; всегда пиши `number.compare(NSDecimalNumber.zero)`
- **`performFetch()` + `rebuildSections()` are synchronous on MainActor** — sections fully updated before the next line. Gates like `isHistoryListReady` only protect UI if the section count is already bounded before the flag turns `true`; an unbounded allTime FRC (3,530 sections) will still freeze even with the gate.
- **`resetAllData()` invalidates FRC**: `CoreDataStack.resetAllData()` destroys/recreates the persistent store (new UUID). Any existing `NSFetchedResultsController` retains stale `NSManagedObject` references → crash on fault fire. Fix: `CoreDataStack` posts `storeDidResetNotification`; FRC holders observe it and call `setup()` to recreate on the new store. See `TransactionPaginationController.handleStoreReset()`.
- **FRC delegate must rebuild synchronously**: `controllerDidChangeContent` runs on main thread (viewContext). Use `MainActor.assumeIsolated { rebuildSections() }` — NOT `Task { @MainActor in }` which creates async hop, allowing stale section access between save and rebuild.
- **`addBatch` fallback pattern**: `TransactionStore.addBatch()` validates ALL transactions; one failure rejects the entire batch (500 rows). `CSVImportCoordinator` catches batch errors and retries individual `add()` calls — only truly invalid transactions are skipped.
- **Entity resolution case-sensitivity**: `ImportCacheManager` stores keys as `lowercased()`, but `EntityMappingService.resolveCategoryByName` must ALSO use case-insensitive store lookup (`$0.name.lowercased() == nameLower`). When cache HITs on a case-variant, return the **stored** entity name (not the input name) — otherwise `validate()` fails because the transaction's category name doesn't match the store. Accounts and subcategories already used case-insensitive resolution; categories fixed in Phase 35.

### File Organization Rules ("Where Should I Put This File?")

**Decision Tree:**
```
New file needed?
├─ Is it a SwiftUI View?
│  └─ Yes → Views/FeatureName/ (with Components/ subfolder for reusable elements)
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
- **⚠️ SwiftUI `List` + 500+ sections = hard freeze** — SwiftUI renders all `Section` headers eagerly; 3,530 sections causes 10-12s UI freeze. Always slice: `Array(sections.prefix(visibleSectionLimit))` with `@State var visibleSectionLimit = 100`. Add `ProgressView().onAppear { visibleSectionLimit += 100 }` as the last List row for infinite scroll ("умная подгрузка"). `@State` auto-resets to 100 on each `NavigationStack` push.
- **⚠️ `onAppear` fires on every back-navigation** — не используй `@State var hasAppearedOnce` как заглушку. Вместо этого применяй `.task(id: trigger)`: перезапуск task дёшев (фон + дебаунс), данные всегда актуальны. `ContentView` не использует `onAppear` для загрузки данных (Phase 39).
- **⚠️ Dead code deletion — orphaned call sites**: When deleting a class (e.g. `BalanceUpdateQueue`), grep all `.swift` sources for the class name AND all method names it implemented. Removed parameters silently survive at call sites and only surface at build time as "extra argument" errors. Example: after deleting `BalanceUpdateQueue`, `AccountOperationService` still passed `priority: .immediate` to `coordinator.updateForTransaction()`.
- **`CompileAssetCatalogVariant` failure can be transient** — if the only failing build step is asset catalog compilation and `grep -E "error:"` returns nothing, just retry; it's a Xcode caching artifact, not a code issue.
- **Making an `@Observable` property reactive**: remove `@ObservationIgnored`, change to `private(set) var`; in the observing View add `.onChange(of: vm.property) { ... }`. Used for `InsightsViewModel.isStale` → drives `InsightsView` reload while tab stays open.
- **Cross-file extension access control**: `private` on a class member is file-scoped — extensions in OTHER `.swift` files CANNOT access it. When splitting a class into extension files: change `private let/static let/func` shared helpers and dependencies to `internal` (no modifier). Methods only called within the same extension file can stay `private` within that extension. Rule: caller and callee in different files → `internal`; same file only → `private`.
- **Extension file imports are not inherited**: Each extension file is an independent compilation unit — it does NOT inherit `import os`, `import CoreData`, `import SwiftUI` from the main class file. Every file calling `Self.logger.debug(...)` needs `import os`; every file using `NSFetchRequest` needs `import CoreData`.
- **`.task(id:)` вместо цепочки `onChange`** — объединяй все реактивные входы в `Equatable` struct (`SummaryTrigger`-паттерн); SwiftUI управляет отменой сам. Смешанная срочность: дебаунс внутри `if !isFullyInitialized`, чтобы init-complete-триггер был немедленным.
- **`DateFormatter` не Sendable** — объявляй как `@MainActor private static let`; форматируй строки на MainActor до `Task.detached`; передавай `String`, а не сам форматтер. Никогда не создавай `DateFormatter` внутри `Task.detached`.
- **`Group {}` в `@ViewBuilder` computed var лишний** — если `private var foo: some View` возвращает `if/else`, добавь `@ViewBuilder` и убери `Group`; семантика идентична, один уровень иерархии сэкономлен.

## SwiftUI Layout Gotchas

- **`containerRelativeFrame` wrong container**: Plain `HStack`/`VStack` are NOT qualifying containers; the modifier walks up to the nearest `ScrollView`/`LazyHStack`/`LazyVGrid`. In a List row it resolves to the full screen width — use `GeometryReader` for proportional sizing inside non-lazy containers.
- **`layoutPriority` is not proportional**: Two `frame(maxWidth: .infinity)` views with different `layoutPriority` values do NOT split space proportionally — higher priority takes all remaining space first.
- **`Task.yield()` for focus timing**: Replace `Task.sleep(nanoseconds: 100_000_000)` focus hacks with `await Task.yield()` inside `.task {}` — suspends exactly one MainActor runloop tick, sufficient for SwiftUI layout before `@FocusState` activation.
- **Missing struct `}` after Button wrap**: Wrapping a view's `HStack` body in `Button { }` can accidentally absorb the struct's closing brace — verify brace balance after this refactoring pattern (causes `expected '}'` build errors elsewhere in the file).
- **`.task` vs `.onAppear { Task {} }`**: `.task` is automatically cancelled on view removal (sheet dismiss); unstructured `Task {}` created inside `.onAppear` is unowned and can fire after dismissal.

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

#### MessageBanner Component (`Views/Components/MessageBanner.swift`)
Universal banner: `.success`, `.error`, `.warning`, `.info` with spring animations (scale 0.85→1.0, upward slide, icon bounce) and type-matched haptics via `HapticManager.notification(type:)`.

```swift
MessageBanner.success("Transaction saved successfully")
MessageBanner.error("Failed to load data")
// With transition:
MessageBanner.success(msg).transition(.move(edge: .top).combined(with: .opacity))
```

#### UniversalCarousel Component (`Views/Components/UniversalCarousel.swift`)
Generic horizontal carousel. Presets: `.standard` (selectors + auto-scroll), `.compact` (chips), `.filter` (tags), `.cards` (large items + `.screenPadding()`), `.csvPreview` (shows scroll indicators). Config: `Utils/CarouselConfiguration.swift`.

```swift
UniversalCarousel(config: .standard, scrollToId: .constant(selectedId)) {
    ForEach(items) { item in ChipView(item).id(item.id) }
}
```

#### UniversalFilterButton Component (`Views/Components/UniversalFilterButton.swift`)
Filter chip in `.button(onTap)` or `.menu(menuContent:)` mode. Styling: `.filterChipStyle(isSelected:)`. Use `CategoryFilterHelper` for category display logic.

```swift
// Button mode
UniversalFilterButton(title: "All Time", isSelected: false, onTap: { showFilter = true }) {
    Image(systemName: "calendar")
}
// Menu mode: add `menuContent: { Button(...) }` trailing closure
```

#### UniversalRow Component (`Views/Components/UniversalRow.swift`)
Generic row with `IconConfig` leading icons. Presets: `.standard`, `.settings`, `.selectable`, `.info`, `.card`. Modifiers: `.navigationRow { Dest() }`, `.actionRow(role:) { }`, `.selectableRow(isSelected:) { }`. `IconConfig`: `.sfSymbol(name, color)`, `.bankLogo(logo)`, `.brandService(name)`, `.custom(source, style)`.

**Design system files** (`Utils/`):
- `AppColors.swift` — semantic colors + `CategoryColors` palette (absorbed `Colors.swift`)
- `AppSpacing.swift` — `AppSpacing`, `AppRadius`, `AppIconSize`, `AppSize`
- `AppTypography.swift` — `AppTypography` (Inter variable font)
- `AppShadow.swift` — `AppShadow` enum, `Shadow` struct
- `AppAnimation.swift` — `AppAnimation` constants, `BounceButtonStyle`
- `AppModifiers.swift` — all View style extensions (`cardStyle`, `filterChipStyle`, `transactionRowStyle`, `futureTransactionStyle`, etc.) + `TransactionRowVariant`

## Testing

- Unit tests: `AIFinanceManagerTests/`
- UI tests: `AIFinanceManagerUITests/`
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
- **Services/CSV/**: CSV import/export coordination
- **Services/Voice/**: Voice input parsing and services
- **Services/Import/**: PDF and statement text parsing
- **Services/Cache/**: Caching coordinators and managers

### Utils — Amount Formatting (three formatters, разные назначения)
| File | Purpose | Decimal places |
|------|---------|----------------|
| `AmountFormatter.swift` | Хранимые значения: format/parse/validate; `minimumFractionDigits=2` | Always 2 ("1 234.50") |
| `AmountDisplayConfiguration.swift` | Глобальная конфигурация форматтера. **Hot path: `AmountDisplayConfiguration.formatter`** (кэширован). `makeNumberFormatter()` создаёт новый объект — не вызывать в `List`/`ForEach` | Configurable (default 2) |
| `AmountInputFormatting.swift` | Механика input-компонентов: `cleanAmountString`, `displayAmount(for:)`, `calculateFontSize`. Используется в `AmountInputView` и `AnimatedAmountInput` | 0–2 (no trailing zeros) |

- **`AmountDisplayConfiguration` cache invalidation**: `static var shared = Config() { didSet { _cache = nil } }` — мутация свойства `shared.prop = x` тоже тригерит `didSet` (Swift копирует struct и присваивает обратно)

### AnimatedInputComponents.swift (Phase 30+)
- Содержит **только `BlinkingCursor`** — все AnimatedDigit/AnimatedChar/CharAnimState удалены
- `AmountInputView` + `AnimatedAmountInput` используют `contentTransition(.numericText())` для чисел
- `AnimatedTitleInput` использует `contentTransition(.interpolate)` для текста — намеренно разные

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

## Questions?

When unsure about architecture decisions:
1. Check existing similar implementations
2. Review AppCoordinator for dependency patterns
3. Look at recent commits for refactoring context
4. Ask user for clarification on business requirements

---

## Reference Docs

The `docs/` directory contains 200+ historical analysis and implementation docs from past sessions.
Key references: `docs/PROJECT_BIBLE.md`, `docs/ARCHITECTURE_FINAL_STATE.md`, `docs/COMPONENT_INVENTORY.md`

---

**Last Updated**: 2026-03-02
**Project Status**: Active development - ContentView fully reactive via `.task(id:)` (Phase 39). InsightsService split 2832→782 LOC (Phase 38). Service audit: 3 dead protocols deleted, TransactionConverterService merged, RecurringTransactionService documented. Reactivity audit + dead code removal (Phase 36). ~800 LOC deleted, 7 reactivity bugs fixed (ForEach identity, sheet flicker, insights staleness, budget rollover, double-invalidation, category grid, isStale). CSV import crash fix (Phase 35). Utils cleanup + design system split (Phase 34). Zero hardcoded colors (Phase 32-33). SwiftUI anti-pattern sweep (Phase 31), Per-element skeleton loading (Phase 30), Instant launch (Phase 28), Performance optimized, Persistent aggregate caching, Fine-grained @Observable updates.
**iOS Target**: 26.0+ (requires Xcode 26+ beta)
**Swift Version**: 5.0 project setting; Swift 6 patterns enforced via `SWIFT_STRICT_CONCURRENCY = targeted`
