# Codebase Concerns

**Analysis Date:** 2026-03-02

## Tech Debt

**RecurringTransactionService — Deprecated Bridge Class (558 LOC):**
- Issue: Entire service marked `⚠️ FULLY DEPRECATED` in file header; contains deadlock-prone code and non-functional methods
- Files: `AIFinanceManager/Services/Transactions/RecurringTransactionService.swift`
- Impact:
  - Contains `DispatchSemaphore.wait()` calls on `@MainActor` (lines 135, 147, 209, 222, 253, 266, 492, 504) → DEADLOCK RISK if called from MainActor context
  - Methods like `updateRecurringSeries()`, `stopRecurringSeries()`, `deleteRecurringSeries()` attempt mutations on read-only `delegate.recurringSeries` property (Phase 9) — execute no-op save+generate calls
  - `generateRecurringTransactions()` still called from `TransactionsViewModel` (~600-650) as post-load trigger, but logic belongs in `TransactionStore.initialize()`
- Fix approach:
  1. Migrate all active call sites in `TransactionsViewModel` to direct `TransactionStore+Recurring.swift` methods
  2. Remove all `DispatchSemaphore` usage (semaphore.wait() on MainActor = always wrong)
  3. Delete entire file once migration is complete

**TransactionConverterService — Dead Code (5 LOC):**
- Issue: Service marked `DEPRECATED — Phase 37: Merged into EntityMappingService`
- Files: `AIFinanceManager/Services/CSV/TransactionConverterService.swift`
- Impact: `convertRow()` functionality moved to `EntityMappingServiceProtocol` but file not removed; creates confusion about where CSV conversion actually happens
- Fix approach: Delete file and grep all imports/call sites to verify no references remain

**Deprecated Protocol: RecurringTransactionServiceProtocol (59 LOC):**
- Issue: One method marked `@available(*, deprecated)` — protocol still exists but implementations not being called
- Files: `AIFinanceManager/Protocols/RecurringTransactionServiceProtocol.swift`
- Impact: Code paths exist for methods that cannot safely execute; unnecessary protocol indirection
- Fix approach: Inline remaining active methods to `TransactionStore+Recurring.swift`, delete protocol

**Unused TransactionConverterServiceProtocol (6 LOC):**
- Issue: Protocol marked `DEPRECATED` with no implementations
- Files: `AIFinanceManager/Protocols/TransactionConverterServiceProtocol.swift`
- Impact: Dead import paths; confuses where CSV entity conversion happens (answer: `EntityMappingService`)
- Fix approach: Delete protocol file

**TransactionCacheManager — Account Balance Cache (77 LOC):**
- Issue: Section marked `MARK: - Account Balance Cache (DEPRECATED — use BalanceCoordinator instead)`
- Files: `AIFinanceManager/Services/Cache/TransactionCacheManager.swift`
- Impact: Legacy cache paths remain but should never be called; creates dead code maintenance burden
- Fix approach: Remove deprecated section; keep only transaction-related cache methods

**UnifiedTransactionCache — Unimplemented TODO (73 LOC):**
- Issue: Line 73: `// TODO: Implement prefix-based invalidation in LRUCache`
- Files: `AIFinanceManager/Services/Cache/UnifiedTransactionCache.swift`
- Impact: Cache invalidation strategy incomplete; partial implementation may miss cache eviction scenarios
- Fix approach: Either implement prefix-based invalidation or simplify cache strategy to full invalidation on relevant events

## Known Bugs

**NSBatchInsertRequest + dateSectionKey = nil (Historical - Mitigated in Phase 28):**
- Symptoms: CSV import or batch inserts result in transactions with `dateSectionKey = nil`, breaking transaction grouping by date section
- Files: `AIFinanceManager/Services/Repository/TransactionRepository.swift` (lines 403-432), `AIFinanceManager/ViewModels/AppCoordinator.swift` (lines 287-341)
- Trigger: `NSBatchInsertRequest` bypasses `willSave()` hook where `dateSectionKey` was previously computed
- Current mitigation:
  - `TransactionRepository.batchInsertTransactions()` explicitly sets `dateSectionKey` before `NSBatchInsertRequest` execution (Phase 28 fix)
  - `AppCoordinator.fixBatchInsertDateSectionKeys()` runs during initialize() to repair legacy data from imports before 2026-02-24
- Workaround: Fixed in codebase; legacy imports before 2026-02-24 may have orphaned rows; migration runs on first launch

**CSV Import Crash — "persistent store is not reachable" (Fixed in Phase 35):**
- Symptoms: App crash with `NSError: The operation couldn't be completed. (Cocoa error 134080.)`; Object reference becomes invalid during CSV import
- Files: `AIFinanceManager/Services/Repository/TransactionRepository.swift` (lines 239-257)
- Trigger: `NSBatchDeleteRequest` + immediate `context.save()` when deleted objects have inverse relationships (e.g., `TransactionEntity.account` → `AccountEntity.transactions`); CoreData tries to read deleted row from SQLite to nullify inverse, but row already gone
- Fix applied (Phase 35):
  - Replaced `NSBatchDeleteRequest` with `context.delete(entity)` for each stale transaction
  - Added explicit `fetchBatchSize = 0` to ensure all entities materialized in memory before deletes
  - Documented exact scenario and why the old code failed (lines 239-257)
- Verification: CSV import of 19,444 rows now: 19,444 succeeds (0 skipped), 0 crashes

**CoreData FRC — Stale References on Store Reset (Fixed in Phase 35):**
- Symptoms: Crash on `NSManagedObject.fault` fire after data reset (e.g., "Delete all data" → import new file)
- Files: `AIFinanceManager/CoreData/CoreDataStack.swift`, `AIFinanceManager/ViewModels/TransactionPaginationController.swift`
- Trigger: `CoreDataStack.resetAllData()` destroys/recreates persistent store (new UUID). Existing `NSFetchedResultsController` retains stale object references from old store
- Fix applied (Phase 35):
  - `CoreDataStack` posts `storeDidResetNotification` synchronously after store recreation
  - `TransactionPaginationController.handleStoreReset()` observes notification and calls `setup()` to recreate FRC on new store
  - `FRC.delegate` callbacks rebuild sections synchronously via `MainActor.assumeIsolated { }` (not async Task)
- Verification: Reset → import cycle works without crashes

**DateFormatter Race in TransactionQueryService:**
- Symptoms: Unpredictable date parsing failures in filtering operations under concurrent load
- Files: `AIFinanceManager/Services/Transactions/TransactionQueryService.swift`
- Trigger: `DateFormatter` is not thread-safe; if multiple threads call `date(from:)` simultaneously, results are undefined
- Current mitigation: Phase 38 audit identified the issue; fix approach documented but not yet fully applied
- Safe approach:
  - Use `@MainActor private static let dateFormatter` in any service that parses dates
  - Format all dates on MainActor before passing to `Task.detached` (pass String, not formatter)
  - Never create `DateFormatter` inside `Task.detached`

## Security Considerations

**No Explicit Input Validation on User-Supplied Amounts:**
- Risk: User enters extremely large amounts (e.g., `99999999999999.99`) → could overflow `Decimal` → silent truncation or undefined behavior
- Files:
  - `AIFinanceManager/Views/Transactions/Components/AmountInputView.swift` (no upper bound check)
  - `AIFinanceManager/Utils/AmountFormatter.swift` (parses any Decimal.max)
- Current mitigation: `AmountFormatter.validate()` exists but is not enforced at input boundary
- Recommendations:
  1. Add upper bound check in `AmountInputView` (e.g., `amount <= Decimal(999_999_999.99)`)
  2. Call `AmountFormatter.validate()` before accepting user input
  3. Log/alert if user attempts to enter amount exceeding bounds

**CSV Import — No Whitelist for Column Names:**
- Risk: User-supplied CSV headers (`columnMapping`) used directly to map transactions; malicious CSV could define arbitrary columns
- Files: `AIFinanceManager/Services/CSV/CSVValidationService.swift`, `AIFinanceManager/Services/CSV/EntityMappingService.swift`
- Current mitigation: Column names are validated against a finite set (`CSVColumnMapping` enum), but validation not always enforced
- Recommendations:
  1. Verify all `columnMapping` keys exist in `CSVColumnMapping.allCases` before processing
  2. Reject CSVs with unknown columns (or warn user)
  3. Document supported column names in UI

**CoreData Store File Permissions:**
- Risk: CoreData SQLite store file (`*.sqlite`) may be readable/writable by other apps depending on FileProtection setting
- Files: `AIFinanceManager/CoreData/CoreDataStack.swift` (store creation at lines ~70-100)
- Current mitigation: Not observed; default iOS protection may apply, but not explicitly set
- Recommendations:
  1. Set `NSFileProtectionKey: .complete` on store options during creation
  2. Verify file is not accessible via document picker or file sharing in Info.plist

## Performance Bottlenecks

**TransactionStore — Single 1213-LOC Class (SSOT Monolith):**
- Problem: All transaction, account, category, recurring, and persistence operations in one class; becoming hard to navigate and test
- Files: `AIFinanceManager/ViewModels/TransactionStore.swift` (1213 LOC, largest non-View class)
- Cause: Phase 7+ Single Source of Truth consolidation; every new feature adds methods to this class
- Impact:
  - Testing individual operations requires mocking entire 1213-LOC class
  - Code review: hard to find related methods due to size
  - Load time: `initialize()` is sequential (accounts → categories → transactions → recurring)
- Improvement path:
  1. Split into separate stores: `TransactionStore` (tx only), `AccountStore`, `RecurringStore`, `CachedMetadata`
  2. Keep shared `TransactionStoreEvent` for cross-store invalidation
  3. Phase the refactor: extract `RecurringStore` first (most self-contained)

**InsightsService — 1169 LOC + 9 Extension Files (Phase 38 Split Incomplete):**
- Problem: Even after splitting into extensions, main service + extensions = 2000+ LOC total; still monolithic
- Files:
  - `AIFinanceManager/Services/Insights/InsightsService.swift` (782 LOC post-split)
  - 9 extensions: `+Spending`, `+Income`, `+Budget`, `+Recurring`, `+CashFlow`, `+Wealth`, `+Savings`, `+Forecasting`, `+HealthScore`
- Cause: Each granularity + category of insight requires its own generator; shared helpers (Phase 42 PreAggregatedData) partially mitigate
- Impact:
  - `.allTime` granularity still ~307ms (16k transactions grouped by category)
  - Health score computation + period comparison = 3-4ms each
  - Multiple O(N) passes over transaction list (one per generator, though Phase 42 batched into PreAggregatedData)
- Improvement path:
  1. Pre-aggregate category totals at load time (instead of O(N) per granularity)
  2. Cache category expense rollups for each month (reuse across granularities)
  3. Consider lazy evaluation: only compute insight types user is viewing

**SwiftUI List with 3,530 Sections (History View) — O(N) Eager Render (DOCUMENTED LIMITATION):**
- Problem: `HistoryTransactionsList` uses `visibleSectionLimit = 100` infinite scroll; SwiftUI renders all `Section` headers eagerly, not lazily
- Files: `AIFinanceManager/Views/History/HistoryTransactionsList.swift`, `AIFinanceManager/Views/History/HistoryView.swift`
- Cause: SwiftUI's `List` + `@FetchedResultsController` pattern doesn't defer section header rendering
- Impact: Scroll to bottom (3530 sections loaded) = 10-12s UI freeze; only first 100 sections are visible
- Current mitigation: `HistoryTransactionsList` limits visible sections to 100 with `.onAppear { visibleSectionLimit += 100 }` infinite scroll pattern
- Improvement path (NOT TODO — by design):
  1. Use custom `ScrollView` + lazy grid instead of `List` (requires reimplementing FRC integration)
  2. Or: Further limit visible sections (e.g., 50 instead of 100) and require user scroll/filter more
  3. Alternative: Remove by-date grouping for history; use flat paginated list instead

**HistoryView updateSummary() — ~540ms (DOCUMENTED BUT NOT OPTIMIZED):**
- Problem: Called on every `onAppear` due to complex filtering logic; blocks MainActor briefly
- Files: `AIFinanceManager/Views/Home/ContentView.swift` (smart use of `.task(id:summaryTrigger)` added in Phase 39)
- Cause: Scans all 19k transactions to compute summary totals on every return from detail view
- Impact: User perceives brief UI stutter (not total freeze, under 100ms) on ContentView reappear
- Current mitigation: Phase 39 replaced `onChange` chains with `.task(id:)` + 80ms debounce; debounce skips on `isFullyInitialized = true`
- Improvement path:
  1. Cache summary totals in `TransactionStore` (computed once, invalidated on tx changes)
  2. Or: Pre-compute during `initialize()` phase and expose as observable property

**CSV Import — O(N×M) Validation (N=row count, M=field count):**
- Problem: `CSVValidationService.validateRow()` called for each row; does O(M) column lookups
- Files: `AIFinanceManager/Services/CSV/CSVValidationService.swift`, `AIFinanceManager/Services/CSV/CSVImportCoordinator.swift`
- Cause: Validates every field in every row sequentially before batch insert
- Impact: CSV import of 1000 rows: ~1-2s (acceptable); 19k rows: ~20-40s (unacceptable if attempted)
- Improvement path:
  1. Validate only first 10 rows, assume rest are same format
  2. Or: Multi-threaded validation (split rows into chunks, validate in parallel)
  3. Or: Defer validation to CoreData schema constraints

## Fragile Areas

**Transaction Pagination Controller — Complex FRC Management:**
- Files: `AIFinanceManager/ViewModels/TransactionPaginationController.swift`
- Why fragile:
  - `NSFetchedResultsController` lifecycle tied to CoreData context lifecycle; stale references possible if context resets
  - Section rebuilding happens synchronously in `controllerDidChangeContent` delegate method — any exception crashes delegate chain
  - Batch size tuning (500 vs 0) affects memory vs. performance; wrong setting causes "persistent store not reachable" crashes
- Safe modification:
  1. Never call FRC methods from async contexts (always sync or `MainActor.assumeIsolated`)
  2. Wrap section rebuilds in exception handlers (though should never throw)
  3. Always test with `resetAllData()` → import cycle to verify FRC stays valid
- Test coverage: `TransactionPaginationControllerTests.swift` exists; covers basic scenarios but not all edge cases

**CoreData Merge Policy — Race Between Contexts:**
- Files: `AIFinanceManager/Services/Repository/TransactionRepository.swift` (line 148: `mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy`)
- Why fragile:
  - Background context saves → viewContext merge is async by default (automaticallyMergesChangesFromParent)
  - If app exits before merge completes, old object IDs may persist in memory
  - Sync merge via notification observer (lines 164-170) is workaround, not standard pattern
- Safe modification:
  1. Always capture and merge save notifications before returning from persistence operation
  2. Test crash scenarios: kill app during save, restart (should auto-repair or warn)
  3. Document why `mergePolicy` is set to "property object trump" (property values win over relationships)
- Test coverage: No explicit test for merge behavior; reliance on implicit `saveTransactionsSync()` correctness

**CategorySubcategoryCoordinator — Category Relationship Mutations:**
- Files: `AIFinanceManager/Services/Categories/CategorySubcategoryCoordinator.swift`
- Why fragile:
  - Modifies both `CustomCategoryEntity.subcategories` and `SubcategoryEntity.categories` simultaneously
  - Inverse relationships must stay in sync; out-of-sync state causes FRC crashes
  - No validation that both sides of relationship were updated
- Safe modification:
  1. Use CoreData automatic relationship management (`deleteRule: .cascade` or `.deny`)
  2. Always update both sides within same `context.perform {}` block
  3. Test: add subcategory, delete category, verify subcategory orphaned or deleted correctly
- Test coverage: `CategorySubcategoryCoordinator` not directly tested; integration tests only

**RecurringTransactionGenerator — Date Arithmetic Edge Cases:**
- Files: `AIFinanceManager/Services/Recurring/RecurringTransactionGenerator.swift` (266 LOC)
- Why fragile:
  - Leap year handling: Feb 29 → Mar 1 on non-leap years? (documented but easy to regress)
  - Month-end handling: Jan 31 monthly → Feb 28/29? (Calendar.nextDate does this, but result varies by locale)
  - Timezone changes: Generating transactions across DST boundary (start date in EST, end date in EDT)
- Safe modification:
  1. Always use `Calendar.nextDate(after:matching:)` with time zone explicitly set (don't rely on Calendar.autoupdatingCurrent)
  2. Unit test all edge cases: Feb 29, month-end (31→28/29), DST transitions
  3. Log generated transaction dates to verify against expected
- Test coverage: `RecurringTransactionTests.swift` exists; covers happy path but not edge cases (leap year, DST)

**Voice Input Parser — Ambiguous Amount Parsing:**
- Files: `AIFinanceManager/Services/Voice/VoiceInputParser.swift` (941 LOC)
- Why fragile:
  - User says "two hundred" → could be `200` or `2.00`; no context to disambiguate
  - Decimal separator varies by locale (comma in EU, period in US); parser may misinterpret
  - Edge case: "one point five" in some languages = `1.5`, others = `1` (ambiguous)
- Safe modification:
  1. Always confirm parsed amount with user before transaction is committed
  2. Log parsing confidence score; reject low-confidence parses
  3. Test across multiple locales (FR, DE, RU, ES) with realistic voice inputs
- Test coverage: `VoiceInputParserTests.swift` exists; covers English only; no locale tests

## Scaling Limits

**Transaction Count Scaling:**
- Current capacity: Tested with ~19,000 transactions (7.6 MB in memory)
- Limit: UI begins to degrade around 30k transactions; history list pagination becomes essential
- Scaling path:
  1. Implement true infinite scroll (load 50 sections at a time, not 100)
  2. Consider archiving old transactions (pre-2020) to separate storage
  3. Partition CoreData store by year (multiple .sqlite files) if > 100k transactions needed

**Category Count Scaling:**
- Current capacity: ~500 categories (including subcategories) works fine
- Limit: Search/filter becomes slow > 1000 categories due to string matching
- Scaling path:
  1. Implement fuzzy search (ElasticSearch-like) instead of substring match
  2. Cache category search results (invalidate on add/rename)

**Concurrent Users (Single-Device Limitation):**
- Current: Single-user only; no cloud sync, no multi-device support
- Limit: Cannot sync data across iPhone/iPad without manual export/import
- Scaling path:
  1. Implement iCloud CloudKit sync (requires MAJOR architectural refactor)
  2. Or: Firebase Firestore with offline caching (requires server)

## Dependencies at Risk

**Core Data Persistence Schema — No Explicit Migrations:**
- Risk: Schema changes (add/remove columns, rename entities) require explicit migration Mapping Model
- Files: `AIFinanceManager/CoreData/` (all `.xcdatamodeld` files)
- Status: Phase 40 removed `MonthlyAggregateEntity` and `CategoryAggregateEntity` from persisting code, but schema still in `.xcdatamodeld` (no migration created)
- Impact: If user updates app with new schema and old data can't be faulted, CoreData crashes with "entity not found" or mismatched column error
- Migration plan:
  1. Create explicit `Mapping Model` for version transition (.xcdatamodel → .xcdatamodel with timestamp)
  2. Add migration policy to `CoreDataStack.persistentContainer.persistentStoreCoordinator`
  3. Test: Create old-format DB, upgrade to new version, verify data intact
  4. Document: Include migration notes in release changelog

**Swift 6 Concurrency — Partial Adoption (Strict Mode = false):**
- Risk: Project builds with `SWIFT_STRICT_CONCURRENCY = targeted` (not `strict`); many thread-safety violations hidden
- Files: Every file with `@MainActor`, `Sendable`, weak references
- Current gaps:
  - `NSManagedObject` subclasses not marked `@unchecked Sendable` (but used across threads)
  - `DateFormatter` used from background contexts (not thread-safe)
  - Some `@ObservationIgnored` properties on non-Sendable service instances
- Migration plan:
  1. Gradually increase `SWIFT_STRICT_CONCURRENCY` → `full` in next major version
  2. Fix identified violations: wrap all NSManagedObject mutations in `context.perform {}`, cache DateFormatter on MainActor
  3. Test thoroughly with `Thread Sanitizer` enabled in Xcode

## Missing Critical Features

**No Cloud Backup / Sync:**
- Problem: All data stored locally; no backup, no multi-device sync
- Blocks: Users want to access data on iPad; worried about data loss if iPhone replaced
- Potential solution: iCloud CloudKit sync (Phase 50+)

**No Recurring Transaction Forecasting with Uncertainty:**
- Problem: `InsightsService+Forecasting` assumes recurring series continue unchanged
- Blocks: Users can't plan for potential subscription cancellations or price changes
- Potential solution: Add "confidence interval" to forecasts (optimistic/pessimistic scenarios)

**No Budget Rollover / Carryover:**
- Problem: Monthly budgets reset on calendar month; no carry-forward of unused amounts
- Blocks: Users on irregular spending patterns can't utilize budget flexibility
- Potential solution: Add "carry forward" % to category budget config (Phase 50+)

## Test Coverage Gaps

**Views — No UI Tests (132 SwiftUI Views, 0 UITests):**
- What's not tested:
  - Navigation flows (adding transaction → detail view → edit → delete)
  - Form validation (invalid amount, missing category → error state)
  - Pagination (scroll to end of history → load next section)
  - Dark mode rendering (colors, contrast, layout)
- Files: `AIFinanceManager/Views/` (132 Swift files, 0 test files)
- Risk: UI regressions ship undetected; colors hardcoded (though Phase 34 reduced this); layout breaks on smaller devices
- Priority: Medium — Most critical flows: Add/Edit/Delete Transaction, Category Management

**ViewModels — Partial Test Coverage:**
- What's tested:
  - `TransactionStoreTests.swift` — Basic CRUD and recurring generation
  - `TransactionPaginationControllerTests.swift` — Section management
  - None for `InsightsViewModel`, `SettingsViewModel`, `DepositsViewModel`
- What's not tested:
  - Error handling (repository throws error → ViewModel shows alert)
  - State transitions (loading → loaded → error)
  - Cache invalidation (add transaction → insights become stale)
- Files: `AIFinanceManagerTests/ViewModels/` (2 test files, 4+ ViewModels untested)
- Risk: Invalid state can propagate to View; cache inconsistencies undetected
- Priority: High — Critical: `InsightsViewModel` (complex logic), `DepositsViewModel` (financial accuracy)

**Services — Selective Coverage:**
- What's tested:
  - `BalanceCalculationTests.swift` — Core calculation logic
  - `AmountFormatterTests.swift` — Parsing and formatting
  - `VoiceInputParserTests.swift` — Voice recognition parsing
- What's not tested:
  - `CategoryBudgetService` — budget calculation, period boundary detection
  - `CSVImportCoordinator` — full import workflow, edge cases
  - `DepositInterestService` — interest calculation, date rounding
  - `RecurringTransactionGenerator` — edge cases (leap year, DST)
- Files: `AIFinanceManagerTests/Services/` (7 test files, 30+ services)
- Risk: Business logic errors in budget/interest/recurring go undetected until user reports
- Priority: High — Financial accuracy critical

**CoreData — No Persistence Tests:**
- What's not tested:
  - Save/load round-trip (write transaction → read back → verify fields)
  - Migration (old schema → new schema → data intact)
  - Concurrent writes (background save + viewContext read = no stale faults)
  - Relationship integrity (delete category → orphaned transactions handled)
- Files: No `Tests/CoreData/` directory
- Risk: Silent data corruption during save/merge; undetected after migration
- Priority: High — Data loss = app failure

**CSV Import — Edge Cases Untested:**
- What's not tested:
  - Duplicate rows (same transaction imported twice → only one row persisted)
  - Special characters in description (emoji, unicode, quotes → no parsing errors)
  - Malformed amounts (missing decimal, negative, zero)
  - Out-of-order dates (future date, very old date, same-day duplicates)
  - Encoding issues (UTF-8 BOM, Latin-1, mixed encodings)
- Files: No dedicated CSV integration tests
- Risk: Import fails silently or loses data; user unaware of discrepancy
- Priority: Medium — Affects data integrity but only on CSV import (not daily use)

---

*Concerns audit: 2026-03-02*
