# Architecture

Deep dive on core architectural components. For high-level overview see CLAUDE.md.

## MVVM + Coordinator Pattern

- **Models**: domain value types (`Tenra/Models/`) persisted through CoreData entities (`Tenra/CoreData/Entities/`)
- **ViewModels**: `@Observable` classes (MainActor through the default isolation) for UI state
- **Views**: SwiftUI views that observe ViewModels
- **Coordinators**: Manage dependencies and initialization (`AppCoordinator`)
- **Stores**: Single source of truth for specific domains (`TransactionStore`, `RecurringStore`)

## AppCoordinator

Central dependency injection point. Located at [Tenra/ViewModels/AppCoordinator.swift](../Tenra/ViewModels/AppCoordinator.swift).

- Manages all ViewModels, Repository, Stores, and feature Coordinators
- **Two-phase startup**:
  - `initializeFastPath()` — loads accounts + categories → UI visible instantly
  - `initialize()` — full 19k-transaction load runs in background
- Observable flags `isFastPathDone` / `isFullyInitialized` drive per-section content reveal (staggered fade-in via DesignKit's `.contentReveal(isReady:)`)
- **`TransactionStore.loadAccountsOnly()` is misnamed** — it also loads categories. Both are needed for the home screen's first paint.
- **`SettingsViewModel.loadSettingsOnly()`** is the fastPath variant (UserDefaults read only). `loadInitialData()` also loads the current wallpaper and the wallpaper history (file reads and decoding run off the main actor in `WallpaperFileIO`); only `SettingsView.task` calls it.

### The load window

Until the full load lands, and while any later `loadData` runs (restore, reset), memory is provisional: the load would replace it with rows fetched before the user's change. Every change in that window is recorded (`loadJournal`, ids only; series and occurrences in `RecurringStore`) and `loadData` folds it into what it fetched: edited rows keep their in-memory version, deleted rows stay deleted, new rows are appended. Changed transactions also force the aggregate rebuild, since the persisted aggregate table predates them.

- ⚠️ **Never save a table from memory that does not hold all of it.** Whole-table saves (accounts, categories, subcategories, both link tables, series, occurrences) wait while memory does not hold the whole table (`holdsCompleteTable`): accounts and categories are complete after the fast path, the rest only after `loadData`; a held save runs when the load lands. A new whole-table save path must go through `mayWriteWholeTable`.
- A new mutation path must record its change (`noteProvisionalChange`; account changes are recorded by `rebuildAccountById`, which every account mutation already calls).
- Loads run one at a time.

See [TransactionStore+LoadMerge.swift](../Tenra/ViewModels/TransactionStore+LoadMerge.swift); pinned by `LoadWindowMergeTests`.

### Launch gate: a store that fails to open is never built on

- `TenraApp.bootstrap()` awaits `CoreDataStack.openStoreIfNeeded()` (off main) **before** building `AppCoordinator`. A failure (`StoreLoadFailure`: migration / disk full / other, plus the `domain code` reference) shows the blocking [StoreUnavailableView](../Tenra/Views/Diagnostics/StoreUnavailableView.swift): what happened, that the data is still on the device, Retry (`CoreDataStack.retryOpeningStore()`, reuses the loaded model, never touches the file) and Contact Support (`SupportContact`, error code in the e-mail).
- No coordinator in that state means no repository runs, so nothing falls back to the legacy `UserDefaultsRepository` copy and nothing saves over, backs up or replaces the store. The other entry points check too: `IntentEnvironment.services()` throws `IntentStoreUnavailableError` (Siri shows "open the app"), `BackgroundInsightsRefresher.refresh()` skips its pass.
- A failed full load (`TransactionStore.loadData()` throwing) sets `AppCoordinator.startupFailure`: same screen, `initialize()` stops before maturation/migrations, ContentView skips the automatic backup, intents refuse. Retry clears it and ContentView's `.task` runs `initialize()` again.
- ⚠️ Read `isCoreDataAvailable` / `openStoreIfNeeded()`, never `_loadFailure` directly: before the first load the field is nil, which would read as "open".

### Diagnostics (no backend)

- [DiagnosticsCenter](../Tenra/Services/Diagnostics/DiagnosticsCenter.swift) registers a MetricKit subscriber in `didFinishLaunching`; diagnostic payloads (crashes, hangs, disk writes, CPU, slow launches) are kept as MetricKit JSON in Application Support/Diagnostics (latest 20, excluded from backup).
- Launch health check, 2 s after the first frame: store opened + a COUNT reads, saved `AppSettings` decode (SettingsStorageService otherwise swaps in defaults silently), current RevenueCat offering has packages. Failures log as `os.Logger` errors (subsystem `Tenra`, category `Diagnostics`).
- Settings → About → Diagnostics lists both and shares them (a summary `.txt` + the payload JSON) with `ShareLink`.
- The same screen shows what the automations recorded (`WalletCaptureStore.activity()`: Apple Pay
  payments and bank notifications in the last 7 and 30 days, To review, waiting for a rate, the last
  capture), so a phone in hand answers whether auto-capture keeps working. Not shared, not sent.

## TransactionStore

**THE** single source of truth for transactions, accounts, and categories.

- Loads **all** transactions in memory (`loadTransactions(dateRange: nil)`), no windowing.
- ViewModels use computed properties reading directly from TransactionStore
- Every mutation is a `TransactionEvent` ([Models/TransactionEvent.swift](../Tenra/Models/TransactionEvent.swift)) run through `apply(_:)`; the pipeline, bulk events and deletion rules are in [domains/transactions.md](domains/transactions.md).
- Recurring series and occurrences live in `RecurringStore`; the store forwards them (`recurringSeries`, `seriesById`, `recurringOccurrences`).

### O(1) lookup indexes

Maintained alongside the canonical arrays — read-only, never mutate from outside:

- **`transactionById: [String: Transaction]`** — synced inside `updateState()` for every transaction event. Use this instead of `transactions.first(where: { $0.id == ... })` on the 19k-element array.
- **`accountById: [String: Account]`** — rebuilt by `rebuildAccountById()` whenever `accounts` mutates (load/add/update/delete/reorder in `TransactionStore+AccountCRUD.swift`). Adding new account-mutation paths MUST call `rebuildAccountById()`.
- **`seriesById: [String: RecurringSeries]`** (forwarded from `RecurringStore`) — synced inside RecurringStore's `handleSeries*` helpers.
- **`accountsMutationVersion: Int`** — bumped by `rebuildAccountById()`. `@ObservationIgnored`: downstream caches (e.g. `AccountsViewModel.regularAccounts/depositAccounts/loanAccounts`) compare it against their last-seen value; reading it in a view body registers nothing.
- **`parsedDateByDateString: [String: Date]`** — cached `FastDateParser.date(from:)`, keyed by the date **string** (~1.8k entries for 19k tx, since many transactions share a day), not by `tx.id`. Never evicted on delete: siblings on the same date still need the entry.
- **Grouping indexes** (`transactionsByAccount`, `transactionsByCategoryName`, `transactionsBySeriesId`) are computed `TransactionIndex` views over id buckets: rules in [gotchas.md §Grouping indexes store ids, not values](gotchas.md#grouping-indexes-store-ids-not-values).

## BalanceCoordinator

Single entry point for balance operations. Located in `Services/Balance/`.

- Manages balance calculation and caching
- Owns `BalanceStore`, `BalanceCalculationEngine` and the `BalancePersistQueue` writer
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

Saves with the same operation name run one at a time; none is dropped.

- **Whole-table saves are ticketed.** Take `saveCoordinator.nextTicket()` synchronously where the data is captured, then pass it to `performSave(operation:ticket:)` from the detached task. Saves run in ticket order; one still waiting when a newer one arrives is skipped (its caller waits for the newer one), and a ticket older than one already started is skipped. Tickets fix the order in which the data was produced, not the order detached tasks reach the actor.
- **Unticketed saves** run in arrival order, all of them. Use them for writes that don't replace each other; `updateAccountBalancesSync`, `updateInitialBalancesSync` and `saveAccountAggregatesSync` use a unique operation name per call, so they don't queue behind each other.
- The throwing `*Sync` saves (`saveAccountsSync`, `saveCategoriesSync`, `saveSubcategoriesSync`, the two link-table `*Sync`, `saveTransactionsSync`) bypass the coordinator: each writes on its own background context inside `performAndWait`.

## CoreData Schema

**Current version**: v17 (lightweight migration only; the bump checklist is the `/coredata-schema-bump` skill).

| Version | Changes |
|---------|---------|
| v6 | `AccountEntity.isLoan` / `loanInfoData` |
| v7 | Uniqueness constraints dropped; required attributes get default values |
| v8 | Fetch indexes: `byIdIndex` on TransactionEntity / AccountEntity / RecurringSeriesEntity; `byAccountIdIndex` / `byRecurringSeriesIdIndex` on TransactionEntity; `bySeriesIdIndex` / `byTransactionIdIndex` on RecurringOccurrenceEntity |
| v9 | `AccountAggregateEntity` (per-account totals, `byAccountIdIndex`) |
| v10 | `CategoryAggregateEntity.expenseAmount` / `expenseAmountSet` |
| v11 | `CategorySubcategoryLinkEntity.sortOrder` |
| v12 | `AccountEntity.includeInBalance` (accounts excluded from the Finances total and insights aggregates) |
| v13 | `AgentThreadEntity` (the assistant's threads as JSON, `byUpdatedAtIndex`; `AgentThreadStore`, [domains/assistant.md](domains/assistant.md) §5) |
| v14 | `AgentFactEntity` (the facts the assistant remembers, `byCreatedAtIndex`; `AgentFactStore` under `AgentMemory`, [domains/assistant.md](domains/assistant.md) §5) |
| v15 | `GoalEntity`, `DebtEntity` (savings goals and personal debts, history as JSON; `GoalRepository` / `DebtRepository` under `GoalStore` / `DebtStore`, [domains/goals-and-debts.md](domains/goals-and-debts.md)) |
| v16 | `DebtEntity.order`, `RecurringSeriesEntity.order` (optional: the person's place for a debt and a subscription in their lists, DesignKit 8's drag to reorder) |
| v17 | `AssetEntity` (assets: valuations and category links as JSON; `AssetRepository` under `AssetStore`, [domains/assets.md](domains/assets.md)) |

`CategoryAggregateEntity` and `AccountAggregateEntity` hold the persisted aggregate tables that the next launch warm-starts from (see [domains/categories.md](domains/categories.md)). `MonthlyAggregateEntity` remains in the model but nothing reads or writes it.

## Backups and restore

[CloudBackupService](../Tenra/Services/Utilities/CloudBackupService.swift) drives them; the store-level work is in [CoreDataStack+Backup.swift](../Tenra/CoreData/CoreDataStack+Backup.swift), `CoreDataStack.swapStore` and [PersistentStoreFiles](../Tenra/CoreData/PersistentStoreFiles.swift) (file steps, no Core Data, tested on plain SQLite).

- ⚠️ **Never copy the live store with FileManager.** The newest saves can live only in `Tenra.sqlite-wal`, and a save between copying `.sqlite` and its `-wal` pairs files from two moments.
- **Backup**: `snapshotStore` copies the live store through `replacePersistentStore` (SQLite's own copy: one consistent state, WAL included, while the app keeps writing) into a scratch folder as one rollback-journal `Tenra.sqlite`. The copy must be a Core Data store of the current model, pass `PRAGMA quick_check`, and open and count every entity; only then is it copied into `Backups/<timestamp>/`, size-checked, and `metadata.json` written last, so a backup that failed half-way is never listed. Any failure throws `CloudBackupError` to the Backups screen's error banner; a failed automatic backup is shown there once, the next time the screen opens.
- **Restore**: the backup's `.sqlite` (plus its `-wal` when non-empty; never the `-shm`) is copied into `RestoreWork-<uuid>/staged` beside the store and must be a non-empty Core Data store that the current model opens directly or by lightweight migration, pass `quick_check`, and open and count every entity (which migrates an older backup in the copy). Only then is the live store removed from the coordinator, its files moved to `RestoreWork-<uuid>/previous`, the staged ones moved in and the store re-added. Any failure moves the previous files back and reopens them (`restoreFailed`: the data is unchanged). The work folder is deleted, except when that rollback fails too: then it may hold the only copy of the previous store (logged as critical with its path).
- **Where they live**: iCloud Drive (`CloudBackupService.isICloudEnabled`) or the app's Documents. A new install turns iCloud on when onboarding ends (`CloudSyncViewModel.adoptICloudForNewInstall`, owner's decision 2026-10-22); an older install with iCloud off is asked once on Home (`ICloudBackupAskCard`, `shouldAskForICloud`, key `backups.iCloud.decided`).
- **Restore on a new phone**: the welcome screen lists the backups iCloud Drive holds whatever the preference (`listICloudBackups`, a few polls while iCloud fetches the folder) and offers "Restore from a backup" (`OnboardingRestoreSheet`). `restoreFromOnboarding` turns iCloud on, swaps the store, reloads, and sets the base currency to the restored accounts' (`dominantCurrency`): settings live in UserDefaults, outside the backup.
- **Retention**: `BackupMetadata.isAutomatic`; the 5 newest manual and the 4 newest automatic backups are kept (`maxManualBackups` / `maxAutomaticBackups`), and each kind only evicts its own. Backups without the field count as manual, so the weekly automatic backup never deletes one the user made. `settings.cloud.autoBackup.footer` states the 4. An automatic backup's row carries an "Auto" `Badge` (`settings.cloud.autoBackup.badge`). Tests: `CloudBackupServiceTests`, `PersistentStoreFilesTests`, `BackupRetentionTests`.

## State Reactivity

- ContentView reactivity via `.task(id: SummaryTrigger)` — no manual `onChange` chains
- Per-element staggered fade-in during initialization (DesignKit's `ContentRevealModifier` — preserves view identity, no layout recalc spike)
- `IconSource` (DesignKit, `DesignSupport/IconSource.swift`) has 2 cases: `.sfSymbol(String)` and `.brandService(String)`. `displayIdentifier` produces `"sf:\(name)"` / `"brand:\(name)"` format; `from(displayIdentifier:)` decodes it. All logos go through the provider chain via `.brandService(domain)`; see [domains/logos.md](domains/logos.md).

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
- `Services/Cache/` — transaction caches (`TransactionCacheManager`, `UnifiedTransactionCache`, `LRUCache`, `DateSectionExpensesCache`)
