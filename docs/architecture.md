# Architecture

Deep dive on core architectural components. For high-level overview see CLAUDE.md.

## MVVM + Coordinator Pattern

- **Models**: CoreData entities representing domain objects
- **ViewModels**: `@Observable` classes marked `@MainActor` for UI state
- **Views**: SwiftUI views that observe ViewModels
- **Coordinators**: Manage dependencies and initialization (`AppCoordinator`)
- **Stores**: Single source of truth for specific domains (`TransactionStore`)

## AppCoordinator

Central dependency injection point. Located at [Tenra/ViewModels/AppCoordinator.swift](../Tenra/ViewModels/AppCoordinator.swift).

- Manages all ViewModels, Repository, Stores, and feature Coordinators
- **Two-phase startup**:
  - `initializeFastPath()` — loads accounts + categories (<50ms) → UI visible instantly
  - `initialize()` — full 19k-transaction load runs in background
- ⚠️ **The load window.** Until the full load lands, and while any later `loadData` runs (restore, reset), memory is provisional: the load would replace it with rows fetched before the user's change. Every change in that window is recorded (`loadJournal`, ids only; series and occurrences in `RecurringStore`) and `loadData` folds it into what it fetched: edited rows keep their in-memory version, deleted rows stay deleted, new rows are appended. Changed transactions also force the aggregate rebuild, since the persisted aggregate table predates them. Whole-table saves (accounts, categories, subcategories, both link tables, series, occurrences) wait while memory does not hold the whole table (`holdsCompleteTable`): accounts and categories are complete after the fast path, the rest only after `loadData`; a held save runs when the load lands. Loads run one at a time. A new whole-table save path must go through `mayWriteWholeTable`, and a new mutation path must record its change (`noteProvisionalChange`; account changes are recorded by `rebuildAccountById`, which every account mutation already calls). See [TransactionStore+LoadMerge.swift](../Tenra/ViewModels/TransactionStore+LoadMerge.swift); pinned by `LoadWindowMergeTests`.
- Observable flags `isFastPathDone` / `isFullyInitialized` drive per-section content reveal (staggered fade-in via `ContentRevealModifier`)
- **`TransactionStore.loadAccountsOnly()` is misnamed** — it also loads categories. Both are needed for the home screen's first paint.
- **`SettingsViewModel.loadSettingsOnly()`** is the fastPath variant (UserDefaults read only). `loadInitialData()` additionally decodes the full-resolution wallpaper UIImage on MainActor and is heavy — only `SettingsView.task` should call it.

### Launch gate: a store that fails to open is never built on

- `TenraApp.bootstrap()` awaits `CoreDataStack.openStoreIfNeeded()` (off main) **before** building `AppCoordinator`. A failure (`StoreLoadFailure`: migration / disk full / other, plus the `domain code` reference) shows the blocking [StoreUnavailableView](../Tenra/Views/Diagnostics/StoreUnavailableView.swift): what happened, that the data is still on the device, Retry (`CoreDataStack.retryOpeningStore()`, reuses the loaded model, never touches the file) and Contact Support (`SupportContact`, error code in the e-mail).
- No coordinator in that state means no repository runs, so nothing falls back to the legacy `UserDefaultsRepository` copy and nothing saves over, backs up or replaces the store. The other entry points check too: `IntentEnvironment.services()` throws `IntentStoreUnavailableError` (Siri shows "open the app"), `BackgroundInsightsRefresher.refresh()` skips its pass.
- A failed full load (`TransactionStore.loadData()` throwing) sets `AppCoordinator.startupFailure`: same screen, `initialize()` stops before maturation/migrations, ContentView skips the automatic backup, intents refuse. Retry clears it and ContentView's `.task` runs `initialize()` again.
- ⚠️ Read `isCoreDataAvailable` / `openStoreIfNeeded()`, never `_loadFailure` directly: before the first load the field is nil, which would read as "open".

### Diagnostics (no backend)

- [DiagnosticsCenter](../Tenra/Services/Diagnostics/DiagnosticsCenter.swift) registers a MetricKit subscriber in `didFinishLaunching`; diagnostic payloads (crashes, hangs, disk writes, CPU, slow launches) are kept as MetricKit JSON in Application Support/Diagnostics (latest 20, excluded from backup).
- Launch health check, 2 s after the first frame: store opened + a COUNT reads, saved `AppSettings` decode (SettingsStorageService otherwise swaps in defaults silently), current RevenueCat offering has packages. Failures log as `os.Logger` errors (subsystem `Tenra`, category `Diagnostics`).
- Settings → About → Diagnostics lists both and shares them (a summary `.txt` + the payload JSON) with `ShareLink`.

## TransactionStore

**THE** single source of truth for transactions, accounts, and categories.

- Loads **all** transactions in memory (`dateRange: nil`). ~7.6 MB for 19k tx — no windowing.
- ViewModels use computed properties reading directly from TransactionStore
- Debounced sync with 16ms coalesce window; granular cache invalidation per event type
- Event-driven architecture with `TransactionStoreEvent`
- Handles subscriptions and recurring transactions
- `apply()` pipeline: `updateState` → `updateBalances` → `invalidateCache` → `persistIncremental`
- ⚠️ **`allTransactions` setter is a no-op** — to delete, use `TransactionStore.deleteTransactions(for...)` which routes through `apply(.deleted)`

### O(1) lookup indexes

Maintained alongside the canonical arrays — read-only, never mutate from outside:

- **`transactionById: [String: Transaction]`** — synced inside `updateState()` for every event (added/updated/deleted/bulkAdded). Use this instead of `transactions.first(where: { $0.id == ... })` on the 19k-element array.
- **`accountById: [String: Account]`** — rebuilt by `rebuildAccountById()` whenever `accounts` mutates (load/add/update/delete/reorder in `TransactionStore+AccountCRUD.swift`). Adding new account-mutation paths MUST call `rebuildAccountById()`.
- **`seriesById: [String: RecurringSeries]`** (forwarded from `RecurringStore`) — synced inside RecurringStore's `handleSeries*` helpers.
- **`accountsMutationVersion: Int`** — bumped by `rebuildAccountById()`. Downstream caches (e.g. `AccountsViewModel.regularAccounts/depositAccounts/loanAccounts`) compare this against their last-seen value to detect invalidation cheaply.
- **`parsedDateByDateString: [String: Date]`** — cached `FastDateParser.date(from:)`, keyed by the date **string** (~1.8k entries for 19k tx, since many transactions share a day), not by `tx.id`. Never evicted on delete: siblings on the same date still need the entry.

### Grouping indexes (id-based)

The three grouping indexes are **computed [`TransactionIndex`](../Tenra/Models/TransactionIndex.swift) views, not stored dictionaries**. Storage holds ids only; values resolve through `transactionById` on subscript.

| Read as | Backed by |
|---|---|
| `transactionsByAccount` | `transactionIdsByAccount: [String: [String]]` (both legs — transfers appear under `accountId` and `targetAccountId`) |
| `transactionsByCategoryName` | `transactionIdsByCategoryName: [String: [String]]` (aggregatable types only) |
| `transactionsBySeriesId` | `transactionIdsBySeriesId: [String: [String]]` |

Why: `Transaction` has a 256-byte stride, so storing values in all three duplicated the 19k set ~3 extra times (~15 MB) on top of `transactions` + `transactionById`.

Read shape is unchanged (`index[key] ?? []` still yields `[Transaction]`), with two rules:

- **Bind a bucket to a `let` before using it twice** — every subscript re-resolves, O(bucket).
- ⚠️ **A cold rebuild driven off the `transactions` array must call `ensureTransactionByIdInSync()` first**, else buckets resolve to nothing. `rebuildCategoryIndexes`, `rebuildSeriesAndDateIndexes` and `seedCategoryAggregates` already do; it is O(1) when in sync.

Editing a transaction needs **no** bucket rewrite: `updateState` refreshes `transactionById` before the index-maintenance helpers run, so the new field values resolve automatically. Pinned by `TransactionIndexTests`.

### Deletion semantics

- `updateState .deleted` uses **index-based removal**: `firstIndex(where:) + remove(at:)` instead of `removeAll{ $0.id == tx.id }`. The latter never short-circuits and was the silent quadratic source for batch deletes.

For TransactionStore CRUD/threading patterns and FRC details see [domains/transactions.md](domains/transactions.md).

## BalanceCoordinator

Single entry point for balance operations. Located in `Services/Balance/`.

- Manages balance calculation and caching
- Includes: Store, Engine
- ⚠️ **`self.balances` sync rule**: All public methods that modify store balance MUST also (1) update `self.balances` dict (the `@Observable` published property) and (2) call `persistBalance()`. Private methods (`processAddTransaction`, etc.) do this correctly.

When adding new public balance mutation methods, follow the same pattern:

```swift
var updated = self.balances
updated[id] = newBal
self.balances = updated
persistBalance(...)
```

- **Balance writes are serial.** `persistBalance` / `persistBalances` hand the value to one `BalancePersistQueue`: newest value per account, one write at a time, so a burst cannot land out of order (launch shows the persisted balance). Never write `AccountEntity.balance` from a detached task of its own. Tests wait with `waitForPersistedBalances()`.
- **Targeted recalculation reads the per-account index.** `recalculateAccounts(_:accounts:transactionsByAccount:)` sums each account's own bucket of `TransactionStore.transactionsByAccount`; use it (or `TransactionsViewModel.recalculateBalances(for:)`) for a known small set of accounts. The `transactions:` overload is one pass over the array, like `recalculateAll`.

## Repository Pattern

All persistence goes through `DataRepositoryProtocol`. Specialized repositories under `Services/Repository/`:

- **`CoreDataRepository`** — facade, delegates to specialized repositories
- **`TransactionRepository`** — transaction persistence operations
- **`AccountRepository`** — account operations and balance management
- **`CategoryRepository`** — categories, subcategories, links, aggregates
- **`RecurringRepository`** — recurring series and occurrences

For Repository threading rules (`@unchecked Sendable`, `context.perform`) see [concurrency.md](concurrency.md).

### Background saves: `CoreDataSaveCoordinator`

Saves with the same operation name run one at a time; none is dropped (it used to throw `savingInProgress` at the second one, and every caller swallowed it).

- **Whole-table saves are ticketed.** Take `saveCoordinator.nextTicket()` synchronously where the data is captured, then pass it to `performSave(operation:ticket:)` from the detached task. Saves run in ticket order; one still waiting when a newer one arrives is skipped (its caller waits for the newer one), and a ticket older than one already started is skipped. Tickets fix the order in which the data was produced, not the order detached tasks reach the actor.
- **Unticketed saves** run in arrival order, all of them. Use them for writes that don't replace each other (balance batches, `updateInitialBalancesSync`).
- The `*Sync` saves (`saveAccountsSync`, onboarding, import) bypass the coordinator.

## CoreData Schema

**Current version**: v8 (lightweight migration).

| Version | Changes |
|---------|---------|
| v6 | `depositInfoData` / `isLoan` / `loanInfoData` on AccountEntity; `recurringSeriesId: String` on TransactionEntity |
| v7 | Reorganised aggregate entities |
| v8 (perf-only) | Added `byIdIndex` to TransactionEntity / AccountEntity / RecurringSeriesEntity; `byAccountIdIndex` / `byRecurringSeriesIdIndex` to TransactionEntity; `bySeriesIdIndex` / `byTransactionIdIndex` to RecurringOccurrenceEntity |

Without `byIdIndex`, every `id == %@` predicate (insertTransaction / updateTransactionFields / deleteTransactionImmediately) was a full table scan over 19k rows.

Old aggregate entities (`MonthlyAggregateEntity`, `CategoryAggregateEntity`) remain in `.xcdatamodeld` but are not read/written.

## Backups and restore

[CloudBackupService](../Tenra/Services/Utilities/CloudBackupService.swift) drives them; the store-level work is in [CoreDataStack+Backup.swift](../Tenra/CoreData/CoreDataStack+Backup.swift), `CoreDataStack.swapStore` and [PersistentStoreFiles](../Tenra/CoreData/PersistentStoreFiles.swift) (file steps, no Core Data, tested on plain SQLite).

- ⚠️ **Never copy the live store with FileManager.** The newest saves can live only in `Tenra.sqlite-wal`, and a save between copying `.sqlite` and its `-wal` pairs files from two moments. Backups before 2026-10 did exactly that (with `try?` on the `-wal`/`-shm`).
- **Backup**: `snapshotStore` copies the live store through `replacePersistentStore` (SQLite's own copy: one consistent state, WAL included, while the app keeps writing) into a scratch folder as one rollback-journal `Tenra.sqlite`. The copy must be a Core Data store of the current model, pass `PRAGMA quick_check`, and open and count every entity; only then is it copied into `Backups/<timestamp>/`, size-checked, and `metadata.json` written last, so a backup that failed half-way is never listed. Any failure throws `CloudBackupError` to the Backups screen's error banner; a failed automatic backup is shown there once, the next time the screen opens.
- **Restore**: the backup's `.sqlite` (plus the `-wal` of a pre-2026-10 backup; never the `-shm`) is copied into `RestoreWork-<uuid>/staged` beside the store and must be a non-empty Core Data store that the current model opens directly or by lightweight migration, pass `quick_check`, and open and count every entity (which migrates an older backup in the copy). Only then is the live store removed from the coordinator, its files moved to `RestoreWork-<uuid>/previous`, the staged ones moved in and the store re-added. Any failure moves the previous files back and reopens them (`restoreFailed`: the data is unchanged). The work folder is deleted, except when that rollback fails too: then it may hold the only copy of the previous store (logged as critical with its path).
- **Retention**: `BackupMetadata.isAutomatic`; the 5 newest manual and the 4 newest automatic backups are kept, and each kind only evicts its own. Backups without the field (made before 2026-10) count as manual, so the weekly automatic backup never deletes one the user made. `settings.cloud.autoBackup.footer` states the 4. Tests: `CloudBackupServiceTests`, `PersistentStoreFilesTests`, `BackupRetentionTests`.

## State Reactivity

- ContentView reactivity via `.task(id: SummaryTrigger)` — no manual `onChange` chains
- Per-element staggered fade-in during initialization (`ContentRevealModifier` — preserves view identity, no layout recalc spike)
- `IconSource` has 2 cases: `.sfSymbol(String)` and `.brandService(String)`. `displayIdentifier` produces `"sf:\(name)"` / `"brand:\(name)"` format; `from(displayIdentifier:)` decodes it
- ⚠️ **BankLogo enum deleted** — all logos go through provider chain via `.brandService(domain)`. See [domains/logos.md](domains/logos.md).

## Important Files

### Core Architecture
- [AppCoordinator.swift](../Tenra/ViewModels/AppCoordinator.swift) — DI and initialization
- [TransactionStore.swift](../Tenra/ViewModels/TransactionStore.swift) — transactions / recurring source of truth
- [BalanceCoordinator.swift](../Tenra/Services/Balance/BalanceCoordinator.swift) — balance ops
- [DataRepositoryProtocol.swift](../Tenra/Services/Core/DataRepositoryProtocol.swift) — repository abstraction

### Repository Layer
- `Services/Repository/CoreDataRepository.swift` — facade
- `Services/Repository/TransactionRepository.swift`
- `Services/Repository/AccountRepository.swift`
- `Services/Repository/CategoryRepository.swift`
- `Services/Repository/RecurringRepository.swift`

### Services by Domain
- `Services/Transactions/` — filtering, grouping, pagination
- `Services/Balance/` — calculations, updates, caching
- `Services/Categories/` — budgets, CRUD
- `Services/CSV/` — see [domains/csv.md](domains/csv.md)
- `Services/Voice/` — see [domains/voice.md](domains/voice.md)
- `Services/Insights/` — see [domains/insights.md](domains/insights.md)
- `Services/Currency/` — see [domains/currency.md](domains/currency.md)
- `Services/Import/` — PDF and statement text parsing
- `Services/Cache/` — caching coordinators
