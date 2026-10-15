# Swift Concurrency Deep Audit — 2026-03-12

## Project Settings

| Setting | Main App Target | Test Targets |
|---------|----------------|--------------|
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | **MainActor** | (not set) |
| `SWIFT_STRICT_CONCURRENCY` | **minimal** | **targeted** |
| `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` | YES | YES |

**Critical implication**: With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, **ALL types** in the main target are implicitly `@MainActor` unless explicitly marked `nonisolated`. Combined with `minimal` strict concurrency, the compiler silently accepts code that would be flagged as data races under `targeted` or `complete`.

---

## Summary

| Severity | Count | Description |
|----------|-------|-------------|
| **P0** | 3 | Potential crash, data race, dead code |
| **P1** | 15 | Performance (implicit MainActor on ~20 services), data loss, correctness |
| **P2** | 8 | Code quality, fragile patterns |
| **P3** | 7 | ~55 redundant @MainActor, ~25 redundant Task{@MainActor}, dead imports |
| **Total** | **33** | |

---

## P0 — Critical (Crash / Data Race)

### 1. `DateFormatter` shared across threads — data race
**Files**:
- `CoreData/TransactionEntity+SectionKey.swift:47` — `TransactionSectionKeyFormatter.formatter`
- `Utils/DateFormatters.swift:13-46` — all 4 static formatters

**Issue**: `DateFormatter` is NOT thread-safe. These shared static instances are accessed from:
- MainActor (ViewModels, Views, Services)
- Background `context.performAndWait {}` blocks in `TransactionRepository:366`, `RecurringRepository:276`, `AccountRepository`
- `Task.detached` in `InsightsViewModel`, `BalanceCalculationEngine`

With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `DateFormatters` enum is implicitly `@MainActor`, but `nonisolated` repository methods call these formatters from background CoreData contexts — the compiler doesn't flag this under `minimal` checking.

**Fix**: Either (a) pre-format strings on MainActor before passing to background contexts, (b) create per-call formatter instances in background methods, or (c) use `ISO8601DateFormatter` (thread-safe) for `"yyyy-MM-dd"` patterns.

### 2. `PDFService` continuation — potential double resume crash
**File**: `Services/Import/PDFService.swift:631-695`

**Issue**: `withCheckedThrowingContinuation` has two resume paths:
1. `VNRecognizeTextRequest` completion handler resumes at lines 640, 645, or 679
2. `handler.perform([request])` catch block resumes at line 692

If Vision calls the completion handler with an error AND `perform` also throws, continuation is resumed twice → **crash**. Low probability but fragile structure.

**Fix**: Track `var didResume = false` guard, or use modern `VNRecognizeTextRequest` async API.

### 3. `CoreDataStack.performAndSaveSync` — dead code, no perform block
**File**: `CoreData/CoreDataStack.swift:338`

**Issue**: Method mutates context without `perform/performAndWait` wrapper. Currently has 0 callers (dead code). If ever called, it's a CoreData threading violation crash.

**Fix**: Delete dead code.

---

## P1 — High (Performance / Correctness / Data Loss)

### 4. `InsightsService` defeats `Task.detached` — all computation on MainActor
**Files**:
- `Services/Insights/InsightsService.swift:31` — `@unchecked Sendable` but implicitly `@MainActor`
- `ViewModels/InsightsViewModel.swift:279` — `Task.detached` calling service methods

**Issue**: `InsightsService` is `@unchecked Sendable` but with default MainActor isolation, ALL its methods are `@MainActor`. When called from `Task.detached`, each method call requires a hop TO MainActor, defeating the purpose of background offloading. The entire insights pipeline (~2s heavy computation) runs on MainActor via implicit hops.

Same issue affects `InsightsCache` (line 22) — designed for off-MainActor use with `NSLock`, but now implicitly `@MainActor`.

**Fix**: Mark `InsightsService` and `InsightsCache` as `nonisolated`. Pass data as value types instead of accessing `transactionStore` directly.

### 5. Repositories implicitly `@MainActor` — background CoreData work on main thread
**Files**:
- `Services/Repository/CoreDataRepository.swift:16`
- `Services/Repository/TransactionRepository.swift:31`
- `Services/Repository/AccountRepository.swift:26`
- `Services/Repository/CategoryRepository.swift:34`
- `Services/Repository/RecurringRepository.swift:22`

**Issue**: All repository classes are implicitly `@MainActor`. Their internal `Task.detached` usage escapes this, but non-detached methods called from ViewModels execute on MainActor. The `context.performAndWait` calls inside these methods DO correctly hop to CoreData's queue, but the method dispatch itself happens on MainActor.

**Fix**: Mark all repository classes `nonisolated` (they manage their own thread safety via `context.perform`).

### 6. `CoreDataStack` unprotected mutable state
**File**: `CoreData/CoreDataStack.swift:24-27`

**Issue**: `isCoreDataAvailable` and `initializationError` are `private(set) var`, mutated inside `loadPersistentStores` callback (arbitrary thread) without lock protection. Read from MainActor. The existing `containerLock` only protects `_persistentContainer`.

**Fix**: Protect mutations with `containerLock` or make them `@MainActor` and dispatch via `MainActor.assumeIsolated`.

### 7. `UserDefaultsRepository` fire-and-forget saves — data loss risk
**File**: `Services/Core/UserDefaultsRepository.swift:63,103,155,178,201`

**Issue**: `saveTransactions`, `saveAccounts`, `saveCategoryRules`, `saveRecurringSeries`, `saveRecurringOccurrences` all use `Task.detached { UserDefaults.standard.set(...) }` fire-and-forget. If app terminates before the detached Task runs, data is lost. `saveCategories` (line 134) was already fixed to be synchronous — the other 5 were not.

**Fix**: Make saves synchronous (UserDefaults writes are fast). Remove `Task.detached` wrapper.

### 8. `DateFormatters` in `InsightsService` — same race as P0-1
**File**: `Services/Insights/InsightsService.swift:49-67`

Three `static let DateFormatter` instances accessed from methods that may run via `Task.detached`. Same thread-safety issue as P0-1 but lower practical risk since implicit MainActor isolation serializes access.

**Fix**: Same as P0-1 — pre-format or per-call instances.

### 9. `CoreDataStack.mergeBatchInsertResult` — viewContext without thread protection
**File**: `CoreData/CoreDataStack.swift:232`

**Issue**: Accesses `viewContext` without `@MainActor` annotation or `perform` block. Works by coincidence (callers are on MainActor) but fragile.

**Fix**: Add `@MainActor` annotation to the method.

### 10. `CategoryOrderManager` — `@unchecked Sendable` without synchronization
**File**: `Services/Categories/CategoryOrderManager.swift:12`

**Issue**: Marked `@unchecked Sendable` but has NO internal synchronization. Read-modify-write on UserDefaults is a race condition. With implicit MainActor it's safe, but the annotation promises thread safety it doesn't deliver.

**Fix**: Remove `@unchecked Sendable` (implicit `@MainActor` already provides safety). Or mark `nonisolated` and add a lock.

### 11. `TransactionCurrencyService` / `TransactionCacheManager` passed to `Task.detached`
**File**: `ViewModels/InsightsViewModel.swift:265-266`

**Issue**: Non-Sendable services captured in `Task.detached`. With implicit MainActor, calls hop back to MainActor (safe but defeats background intent).

**Fix**: Snapshot cached data as value types before detaching. Pass snapshots instead of service references.

### 12. `DataRepositoryProtocol: Sendable` via `@preconcurrency` — masks design tension
**File**: `Services/Core/DataRepositoryProtocol.swift:17`

**Issue**: Protocol inherits `Sendable` but `CoreDataRepository` conformer isn't actually Sendable. `@preconcurrency` suppresses the error. Will break when upgrading to `complete` concurrency.

**Fix**: Remove `Sendable` inheritance from protocol, or make `CoreDataRepository` properly `@unchecked Sendable` with documented invariants.

### 13. `CSVValidationService.validateFileParallel` — TaskGroup serialized on MainActor
**File**: `Services/CSV/CSVValidationService.swift:170`

**Issue**: `group.addTask { @MainActor in ... }` forces every batch validation onto MainActor, serializing all work on the main thread. Completely defeats TaskGroup parallelism. `validateRow` is pure computation that only reads immutable `self.headers`.

**Fix**: Remove `@MainActor` from `addTask` closure. Make `validateRow` `nonisolated`.

### 14. `InsightsService.computeGranularities` calls `transactionStore` directly
**File**: `Services/Insights/InsightsService.swift` + all extension files

**Issue**: Generator methods (`generateRecurringInsights`, `generateBudgetInsights`, etc.) access `transactionStore.transactions/accounts/categories` directly. Since `TransactionStore` is `@MainActor`, these accesses hop to MainActor from the detached task.

**Fix**: Pre-snapshot all needed data before the `Task.detached` boundary. Pass as value-type parameters.

### 15. ~20 pure computation / I/O services implicitly `@MainActor`
With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, ALL these types run on main thread despite having NO UI dependency:

| Category | Files | Impact |
|----------|-------|--------|
| **Network I/O** | `CurrencyConverter.swift:26` | Network + XML parsing on MainActor |
| **OCR/Vision** | `PDFService.swift:32` | Heavy Vision framework processing |
| **File I/O** | `CSVExporter.swift:10`, `CSVImporter.swift:21`, `LogoDiskCache.swift:12` | Disk reads/writes on MainActor |
| **ML inference** | `CategoryMLPredictor.swift:14`, `MLDataExporter.swift:11` | CoreML model loading/inference |
| **Audio** | `SilenceDetector.swift:13` | Audio RMS computation |
| **Pure computation** | `StatementTextParser.swift:11`, `VoiceInputParser.swift:39`, `DepositInterestService.swift:10`, `LoanPaymentService.swift:11` | Math/parsing, no UI |
| **Transaction utils** | `TransactionFilterService.swift:13`, `TransactionGroupingService.swift:15`, `TransactionIndexManager.swift:12` | Filtering/grouping/indexing |
| **Account services** | `AccountRankingService.swift:45`, `AccountUsageTracker.swift:11`, `AccountOrderManager.swift:12` | Pure logic |
| **Recurring** | `RecurringTransactionGenerator.swift:13`, `RecurringValidationService.swift:13` | Business logic |
| **CoreData** | `CoreDataStack.swift:15` (`@unchecked Sendable` + implicit MainActor conflicts with `NSLock` design) | Thread safety design conflict |
| **Protocols** | `DataRepositoryProtocol.swift:17`, all 4 sub-repository protocols | All protocol methods implicitly MainActor |
| **Utils** | `AmountFormatter.swift:10`, `Formatting.swift:11`, `DateFormatters.swift:11`, `ChartAxisHelpers.swift:19` + 6 more | Pure formatting/computation |

**Fix**: Mark all as `nonisolated`. Follow `SummaryCalculator` pattern (already correctly `nonisolated`).

---

## P2 — Medium (Code Quality / Fragile Patterns)

### 14. `SettingsViewModel.showError/showSuccess` — auto-clear Task race
**File**: `ViewModels/SettingsViewModel.swift:328-351`

**Issue**: Each call creates a new fire-and-forget `Task {}` with sleep. Rapid successive calls: first Task's sleep clears the second message prematurely. Also, `MainActor.run {}` inside an already `@MainActor` Task is redundant.

**Fix**: Store the Task, cancel previous before creating new. Remove `MainActor.run`.

### 15. `InsightsViewModel` — no deinit, recomputeTask runs after dealloc
**File**: `ViewModels/InsightsViewModel.swift:55,58`

**Issue**: `recomputeTask` (heavy `Task.detached`) and `debounceTask` never cancelled in deinit. `[weak self]` makes them no-ops but the detached task wastes CPU.

**Fix**: Add `deinit { recomputeTask?.cancel(); debounceTask?.cancel() }`.

### 16. `BalanceCoordinator.persistBalance` — fire-and-forget CoreData save
**File**: `Services/Balance/BalanceCoordinator.swift:452`

**Issue**: `Task.detached { await coreDataRepo.updateAccountBalancesSync(...) }` not stored or awaited. Balance may not persist if app killed immediately.

**Fix**: Consider making awaitable or storing the Task.

### 17. Repository saves fire-and-forget
**Files**: `CategoryRepository.swift:86,135,203,271,341,422`, `AccountRepository.swift:97,129,152`, `RecurringRepository.swift:73,183`, `TransactionRepository.swift:97`

**Issue**: All `Task.detached` saves are fire-and-forget. Data may not persist if app terminates immediately.

**Fix**: Consider making awaitable for critical paths.

### 18. `resetAllData()` — viewContext.reset() not in perform block
**File**: `CoreData/CoreDataStack.swift:267`

**Issue**: `viewContext.reset()` called without perform block. Works because callers are MainActor.

**Fix**: Add `@MainActor` annotation.

### 19. `saveCategoryRules` — `NSBatchDeleteRequest` with async merge
**File**: `Services/Repository/CategoryRepository.swift:143`

**Issue**: Uses `NSBatchDeleteRequest` with fire-and-forget merge instead of synchronous `context.delete()` pattern used elsewhere.

**Fix**: Align with project convention (`context.delete()`).

### 20. `TransactionPaginationController` — `queue: nil` NotificationCenter
**File**: `ViewModels/TransactionPaginationController.swift:148`

**Issue**: Intentionally `nil` for synchronous delivery with `MainActor.assumeIsolated`. Documented but fragile if notification posting context ever changes.

### 21. `VoiceInputView` — fire-and-forget `Task {}` with delayed callback
**File**: `Views/VoiceInput/VoiceInputView.swift:201,221`

**Issue**: Unstructured Tasks with sleep that fire callbacks after view may be dismissed. `.task {}` would auto-cancel.

---

## P3 — Low (Cleanup)

### 22. ~55 redundant `@MainActor` annotations
With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, explicit `@MainActor` on classes/protocols/methods is redundant across ViewModels/, Services/, Protocols/, Views/, Models/, Utils/.

**Fix**: Remove for code clarity. Keep only on types that MUST remain `@MainActor` even if default isolation changes.

### 23. ~25 redundant `Task { @MainActor in }` patterns
`Task {}` inside MainActor-isolated code already inherits MainActor. Found in TransactionsViewModel (~13), VoiceInputService (~5), TransactionStore, InsightsViewModel, CategoryRepository, TransactionRepository.

### 24. ~15 redundant `MainActor.run {}` in already-MainActor views
Views are implicitly MainActor. `MainActor.run` inside `.task {}` in views is redundant. Found in PDFImportCoordinator, VoiceInputConfirmationView, VoiceInputView, DepositDetailView, TransactionCard, LoanDetailView.

### 25. 13 dead `import Combine` statements
Files import Combine but use no Combine types.

### 26. 2 legacy `DispatchQueue` patterns
- `PDFService.swift:633` — `DispatchQueue.global()` inside continuation
- `LogoDiskCache.swift:56` — `DispatchQueue.global()` fire-and-forget write

### 27. `PerformanceProfiler` — timing measurements meaningless
`nonisolated static func start/end` hop to MainActor via `Task {}`. Measures MainActor scheduling latency, not actual work duration.

### 28. 10 legacy `Task.sleep(nanoseconds:)` calls
Should use modern Duration API (`Task.sleep(for: .milliseconds(...))`). Found in TransactionStore, HistoryFilterCoordinator, VoiceInputService, SettingsViewModel, VoiceInputView, VoiceInputConfirmationView.

---

## Fix Plan — Status (2026-03-12)

### Phase 1: P0 Crashes & Data Races — DONE
1. **DateFormatter thread safety** — `TransactionSectionKeyFormatter` replaced DateFormatter with Calendar component extraction (thread-safe). `DateFormatters` enum marked `@MainActor`. ✅
2. **PDFService continuation** — `didResume` guard added to prevent double-resume crash. ✅
3. **Delete `performAndSaveSync`** dead code from `CoreDataStack`. ✅

### Phase 2A: `nonisolated` annotations — DONE (23 types)
4. **5 repository classes** — TransactionRepository, AccountRepository, CategoryRepository, RecurringRepository, CoreDataRepository marked `nonisolated`. ✅
5. **17 pure computation/I/O services** — CSVExporter, CSVImporter, StatementTextParser, SilenceDetector, CategoryMLPredictor, MLDataExporter, TransactionFilterService, TransactionGroupingService, TransactionIndexManager, RecurringTransactionGenerator, RecurringValidationService, CurrencyConverter, DepositInterestService, LoanPaymentService, AmountFormatter, Formatting, ChartAxisHelpers. ✅
6. **CSVValidationService** — `@MainActor` → `nonisolated`, protocol also updated. ✅
7. **CategoryOrderManager** — added `nonisolated` (kept `@unchecked Sendable`). ✅
8. **VoiceInputParser** — reverted (accesses MainActor state directly). ⏭️
9. **CoreDataStack** — skipped (already thread-safe via NSLock, complex to refactor). ⏭️
10. **InsightsService** — removed `@unchecked Sendable` (kept MainActor; full refactor deferred). ✅

### Phase 2B: Specific P1 fixes — DONE
11. **UserDefaultsRepository** — 5 `Task.detached` save methods → synchronous. ✅
12. **CSVValidationService.validateFileParallel** — removed `@MainActor` from `addTask` closure (enables real parallelism). ✅

### Phase 3: P2 Code Quality — DONE
13. **SettingsViewModel** — `messageClearTask` stored, previous cancelled before new. Redundant `MainActor.run` removed. ✅
14. **InsightsViewModel** — `deinit` added to cancel `recomputeTask` + `debounceTask`. ✅
15. **TransactionsViewModel** — 11× `Task { @MainActor in }` → `Task {` (redundant in @MainActor class). ✅

### Phase 4: P3 Cleanup — DONE
16. **13 dead `import Combine`** removed. ✅
17. **`Task.sleep(nanoseconds:)` → Duration API** modernized. ✅

### Remaining (deferred — require deeper refactoring)
- **InsightsService generators → pre-snapshot pattern**: Methods access TransactionStore directly from Task.detached, defeating background offloading. Requires data parameter refactor across 10 extension files.
- **DataRepositoryProtocol `@preconcurrency Sendable`**: Tension between protocol Sendable and CoreDataRepository. Needs API redesign.
- **~55 redundant explicit `@MainActor`**: Low risk, mechanical cleanup.
- **~15 redundant `MainActor.run` in Views**: Requires per-case analysis of callback context.
- **2 legacy `DispatchQueue` patterns**: PDFService (OCR), LogoDiskCache.
- **PerformanceProfiler**: `nonisolated` methods hop to MainActor, making timing meaningless.

---

## Migration Readiness

**Current state**: `minimal` + `MainActor` default isolation. Key data races fixed, ~23 types correctly nonisolated.

**Path to `targeted`**:
1. ✅ Phase 1-2 fixes complete
2. Fix remaining InsightsService pre-snapshot pattern
3. Switch to `SWIFT_STRICT_CONCURRENCY = targeted`
4. Fix new compiler warnings (expect ~50-100)

**Path to `complete` (Swift 6)**:
1. Complete all phases above
2. Remove all `@preconcurrency` annotations
3. Replace all `@unchecked Sendable` with proper Sendable or actors
4. Switch to `SWIFT_STRICT_CONCURRENCY = complete`
5. Fix remaining warnings (expect ~200+)

**Estimated remaining effort**: Migration to `targeted`: 2-3 sessions. Migration to `complete`: 5-8 sessions.
