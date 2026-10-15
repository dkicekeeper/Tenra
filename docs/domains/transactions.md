# Transactions Domain

Deep details on `TransactionStore` CRUD, FRC, and CoreData patterns. For the role of TransactionStore and its lookup indexes see [architecture.md](../architecture.md).

## CRUD Pipeline

Every mutation is a `TransactionEvent` ([Models/TransactionEvent.swift](../../Tenra/Models/TransactionEvent.swift): `added` / `updated` / `deleted` / `bulkAdded` / `bulkUpdated` / `bulkDeleted`, plus the series events) run through `TransactionStore.apply(_:)`:

```
updateState → updateBalances → rollBackLoanPayment (.deleted only) → invalidateCache → persistIncremental → persistBulkChange → debounced sync
```

- `updateState` maintains every index: lookup maps ([architecture.md](../architecture.md#o1-lookup-indexes)), grouping indexes ([gotchas.md](../gotchas.md#grouping-indexes-store-ids-not-values)), category and account aggregates ([categories.md](categories.md), [accounts.md](accounts.md)).
- Granular cache invalidation per event type.
- `persistIncremental` writes single-row events (skipped while `isImporting`); `persistBulkChange` writes a bulk event in one awaited background save.
- Debounced sync: 16 ms after the last mutation, `AppCoordinator.syncTransactionStoreToViewModels` runs once (view-model caches, subcategory sync, insights recompute).

Entry points: `add(_:)`, `addBatch(_:)`, `update(_:allowSeriesDetach:)`, `delete(_:)`, and for many rows `updateBatch(_:)` / `deleteTransactionsInBulk(_:deletingAccountIds:)` (below).

## Deletion Semantics

- ⚠️ **`TransactionsViewModel.allTransactions` has a no-op setter**: assigning it deletes nothing. Delete through `TransactionStore`: `delete(_:)`, or `deleteTransactions(forAccountId:)` / `(forAccountIds:)` / `(forCategoryName:type:)` (one `.bulkDeleted`).
- **`updateState .deleted` removes by index**: `firstIndex(where:) + remove(at:)`, which stops at the match; never `removeAll { $0.id == tx.id }`, which scans the whole array.
- **A deleted loan payment rolls its loan back**: `apply(.deleted)` calls `rollBackLoanPayment` (`TransactionStore+LoanPayments.swift`) after the balances, which undoes the payment's effect on `LoanInfo` and the loan's balance. `.bulkDeleted` does not, so `deleteTransactionsInBulk` sends payments to a live loan through `.deleted` (below); any new delete path must do the same. See [loans.md](loans.md) §Deleting a Payment.

## Batch Operations

### `addBatch` fallback pattern

`TransactionStore.addBatch()` validates ALL transactions; one failure rejects the entire batch. `CSVImportCoordinator` retries individual `add()` calls after batch rejection.

### Bulk edits and deletes (`.bulkUpdated` / `.bulkDeleted`)

⚠️ **Never loop `update(_:)`, `apply(.updated)` or `apply(.deleted)` over many rows.** Each row pays an O(N) `firstIndex` scan of `transactions`, its own CoreData save, a balance update and a merge into the view context (a history-list rebuild). Use the bulk entry points ([TransactionStore+BulkMutations](../../Tenra/ViewModels/TransactionStore+BulkMutations.swift)):

- `updateBatch(_:)` — several edits, one `.bulkUpdated`. Each row gets `update(_:)`'s checks; a failing row is left out (not the whole batch). Used by `recategorize`.
- `deleteTransactionsInBulk(_:deletingAccountIds:)` — several deletes, one `.bulkDeleted`. Used by `deleteTransactions(forAccountId:)` / `(forAccountIds:)` / `(forCategoryName:type:)` and the series flows (`stopSeries`, `deleteSeries`, `pauseSubscription`, `updateSeries`). Series link/unlink/detach apply `.bulkUpdated` directly, without `validate`.

A bulk event runs the pipeline once: one pass over `transactions` and each index bucket, the aggregate deltas per row in row order (totals identical to the per-row path) with one debounced persist, one exact recalculation of the touched accounts (`recalculateAccounts` over just their rows, or `recalculateAll` when cheaper; skipped when the per-row path would have applied zero deltas: future-dated deletes, edits that keep every field `BalanceCalculationEngine.contribution` reads), full cache invalidation, and ONE awaited background save (`deleteTransactions(ids:)` / `updateTransactionsFields(_:)`: chunked `id IN` fetch, `context.delete`, one `save()`). Pinned against the per-row path by `BulkTransactionMutationTests`.

⚠️ **A payment to a live loan never goes into `.bulkDeleted`.** `.deleted` rolls the payment off its loan, and the rollback reads the loan's other payments, so `deleteTransactionsInBulk` deletes those payments one at a time through `.deleted` (in order) and the rest in one bulk event. `updateStateForBulkDelete` asserts it. The one exception is a loan deleted together with its rows (`deletingAccountIds`, passed by `deleteTransactions(forAccountId:)` / `(forAccountIds:)`, whose callers all delete the accounts): its payments join the bulk, since a loan that is about to go needs no rollback (the assert reads those accounts from `accountsDeletedWithBulkRows`, set for the one event).

## CoreData gotchas

### FRC (NSFetchedResultsController)

FRC delegate must rebuild **synchronously**:

```swift
// ✅ CORRECT — no async hop
MainActor.assumeIsolated { rebuildSections() }

// ❌ WRONG — creates async hop allowing stale section access
Task { @MainActor in rebuildSections() }
```

- `performFetch() + rebuildSections()` are synchronous on MainActor — sections fully updated before the next line.
- `CoreDataStack.resetAllData()`, `reloadContainer()` and a backup restore (`swapStore`) replace the persistent store, which invalidates every FRC. FRC holders must observe `CoreDataStack.storeDidResetNotification` and call `setup()` to recreate. See `TransactionPaginationController.handleStoreReset()`.

### Predicates and contexts

- ⚠️ **OR-per-month predicate crash**: Never build `NSCompoundPredicate(orPredicateWithSubpredicates:)` with one subpredicate per calendar month — exceeds SQLite expression tree depth limit (1000). Use a constant 7-condition range predicate instead.
- ⚠️ **NEVER use `NSBatchDeleteRequest` then `context.save()` on the SAME context** when deleted objects have inverse relationships. Use `context.delete()` instead.
- **`viewContext.perform { }` runs on MainActor** — viewContext is MainActor-bound, so its perform queue blocks UI. Use `newBackgroundContext()` for heavy ops (purgeHistory, batch deletes, large fetches that don't need UI synchronicity).
- **`NSDecimalNumber.compare()` gotcha**: `number.compare(.zero)` doesn't compile — always write `number.compare(NSDecimalNumber.zero)`.

### Entity resolution

- **Case-sensitivity**: `resolveCategoryByName` (`EntityMappingService`, CSV import) must use case-insensitive comparison. When cache HITs on a case-variant, return the **stored** entity name (not the input name).

## Update Restrictions

⚠️ **`TransactionStore.update()` blocks removing a LIVE `recurringSeriesId`** — throws `cannotRemoveRecurring`. Scope of the guard:
- it fires only when the old series still exists in `recurringStore.seriesById`. A **dangling** link (series deleted/lost while its transactions survived) may be cleared, so such a transaction stays editable (e.g. an auto-posted deposit-interest accrual, whose edit screen hides the recurring control and always saves `nil`).
- pass `update(tx, allowSeriesDetach: true)` for a deliberate unlink of a single transaction (the edit screen's explicit "Never"). Never pass it just to silence the error.
- ⚠️ A caller that rebuilds a `Transaction` MUST carry `recurringSeriesId` over. `TransactionEditCoordinator` only nils it when `transaction.type.allowsRecurring` **and** the user picked "Never"; for types whose recurring control is hidden it copies the existing link through. Pinned by `TransactionSeriesDetachTests`.

To unlink in bulk, build `TransactionChange`s and apply one `.bulkUpdated`, as `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift` does.

## Edit-Screen Field Gating by Type

`TransactionEditView` field visibility is driven by `TransactionType` computed properties (in `Models/Transaction.swift`), NOT scattered `if type ==` in the view: `allowsCategoryPicker`, `allowsSubcategoryPicker`, `allowsRecurring`, `allowsOnlyAmountAndDescription`. To restrict fields for a type, extend the relevant property. System-generated `.depositInterestAccrual` is amount+description-only (fixed account+category); `allowsRecurring` is false for all loan/deposit-op types (the recurring engine only replays income/expense).

## Per-Type Icon Override in `TransactionCard`

`TransactionCard.subscriptionIconSource` (despite the name) is the **generic icon override channel** consumed by `TransactionCardView` (the icon of DesignKit's `TransactionRow`). `TransactionCard` is its only production caller. Precedence inside `TransactionCard.body`:

1. Linked subscription series logo (Netflix, Spotify, …) when `series.kind == .subscription`.
2. `.loanPayment` / `.loanEarlyRepayment` → `targetAccount.iconSource` (the loan account == `targetAccountId`; source = funding bank).
3. Fallback → category SF Symbol resolved by `TransactionCardView` from `styleData.iconName`.

When adding a new typed override (e.g. transfer-source brand), extend the `switch transaction.type` in `TransactionCard.body` rather than threading a new parameter through `TransactionCardView`.
