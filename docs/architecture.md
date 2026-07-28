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
- Observable flags `isFastPathDone` / `isFullyInitialized` drive per-section content reveal (staggered fade-in via `ContentRevealModifier`)
- **`TransactionStore.loadAccountsOnly()` is misnamed** — it also loads categories. Both are needed for the home screen's first paint.
- **`SettingsViewModel.loadSettingsOnly()`** is the fastPath variant (UserDefaults read only). `loadInitialData()` additionally decodes the full-resolution wallpaper UIImage on MainActor and is heavy — only `SettingsView.task` should call it.

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

## Repository Pattern

All persistence goes through `DataRepositoryProtocol`. Specialized repositories under `Services/Repository/`:

- **`CoreDataRepository`** — facade, delegates to specialized repositories
- **`TransactionRepository`** — transaction persistence operations
- **`AccountRepository`** — account operations and balance management
- **`CategoryRepository`** — categories, subcategories, links, aggregates
- **`RecurringRepository`** — recurring series and occurrences

For Repository threading rules (`@unchecked Sendable`, `context.perform`) see [concurrency.md](concurrency.md).

## CoreData Schema

**Current version**: v8 (lightweight migration).

| Version | Changes |
|---------|---------|
| v6 | `depositInfoData` / `isLoan` / `loanInfoData` on AccountEntity; `recurringSeriesId: String` on TransactionEntity |
| v7 | Reorganised aggregate entities |
| v8 (perf-only) | Added `byIdIndex` to TransactionEntity / AccountEntity / RecurringSeriesEntity; `byAccountIdIndex` / `byRecurringSeriesIdIndex` to TransactionEntity; `bySeriesIdIndex` / `byTransactionIdIndex` to RecurringOccurrenceEntity |

Without `byIdIndex`, every `id == %@` predicate (insertTransaction / updateTransactionFields / deleteTransactionImmediately) was a full table scan over 19k rows.

Old aggregate entities (`MonthlyAggregateEntity`, `CategoryAggregateEntity`) remain in `.xcdatamodeld` but are not read/written.

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
