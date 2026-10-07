# Transactions Domain

Deep details on `TransactionStore` CRUD, FRC, and pagination patterns. For high-level role of TransactionStore see [architecture.md](../architecture.md).

## CRUD Pipeline

`TransactionStore.apply()` pipeline runs on every mutation event:

```
updateState → updateBalances → invalidateCache → persistIncremental
```

- Debounced sync with **16ms coalesce window**
- Granular cache invalidation per event type
- Event-driven via `TransactionEvent` (`added` / `updated` / `deleted` / `bulkAdded` / `bulkUpdated` / `bulkDeleted`)

## Deletion Semantics

- ⚠️ **`allTransactions` setter is a no-op** — to delete, use `TransactionStore.deleteTransactions(for...)` which routes through `apply(.deleted)`
- **`updateState .deleted` uses index-based removal**: `firstIndex(where:) + remove(at:)` instead of `removeAll{ $0.id == tx.id }`. The latter never short-circuits and was the silent quadratic source for batch deletes.
- **A deleted loan payment rolls its loan back**: `apply(.deleted)` calls `rollBackLoanPayment` (`TransactionStore+LoanPayments.swift`) after the balances, which undoes the payment's effect on `LoanInfo` and the loan's balance. Any new delete path (e.g. a bulk-delete event) must call it too. See [loans.md](loans.md) §Deleting a Payment.

## Index Maintenance

- `transactionById: [String: Transaction]` — synced inside `updateState()` for every event
- Use this instead of `transactions.first(where: { $0.id == ... })` on the 19k-element array

## Batch Operations

### `addBatch` fallback pattern

`TransactionStore.addBatch()` validates ALL transactions; one failure rejects the entire batch. `CSVImportCoordinator` retries individual `add()` calls after batch rejection.

### Bulk edits and deletes (`.bulkUpdated` / `.bulkDeleted`)

⚠️ **Never loop `update(_:)`, `apply(.updated)` or `apply(.deleted)` over many rows.** Each row paid an O(N) `firstIndex` scan of `transactions`, a blocking `performAndWait` fetch + save on a fresh context, a detached balance save and a merge into the view context (a history-list rebuild): "apply to similar" on 200 rows took 1–2 s, deleting a 5k-transaction account hung 25–50 s. Use the bulk entry points ([TransactionStore+BulkMutations](../../Tenra/ViewModels/TransactionStore+BulkMutations.swift)):

- `updateBatch(_:)` — several edits, one `.bulkUpdated`. Each row gets `update(_:)`'s checks; a failing row is left out (not the whole batch). Used by `recategorize`.
- `deleteTransactionsInBulk(_:deletingAccountIds:)` — several deletes, one `.bulkDeleted`. Used by `deleteTransactions(forAccountId:)` / `(forAccountIds:)` / `(forCategoryName:type:)` and the series flows (`stopSeries`, `deleteSeries`, `pauseSubscription`, `updateSeries`). Series link/unlink/detach apply `.bulkUpdated` directly, like their per-row versions skipped `validate`.

A bulk event runs the pipeline once: one pass over `transactions` and each index bucket, the aggregate deltas per row in row order (totals identical to the per-row path) with one debounced persist, one exact recalculation of the touched accounts (`recalculateAccounts` over just their rows, or `recalculateAll` when cheaper; skipped when the per-row path would have applied zero deltas: future-dated deletes, edits that keep every field `BalanceCalculationEngine.contribution` reads), full cache invalidation, and ONE awaited background save (`deleteTransactions(ids:)` / `updateTransactionsFields(_:)`: chunked `id IN` fetch, `context.delete`, one `save()`). Pinned against the per-row path by `BulkTransactionMutationTests`.

⚠️ **A payment to a live loan never goes into `.bulkDeleted`.** `.deleted` rolls the payment off its loan, and the rollback reads the loan's other payments, so `deleteTransactionsInBulk` deletes those payments one at a time through `.deleted` (in order) and the rest in one bulk event. `updateStateForBulkDelete` asserts it. The one exception is a loan deleted together with its rows (`deletingAccountIds`, passed by `deleteTransactions(forAccountId:)` / `(forAccountIds:)`, whose callers all delete the accounts): its payments join the bulk, since a loan that is about to go needs no rollback (the assert reads those accounts from `accountsDeletedWithBulkRows`, set for the one event).

## FRC (NSFetchedResultsController)

### Synchronous rebuild on delegate

FRC delegate must rebuild **synchronously**:

```swift
// ✅ CORRECT — no async hop
MainActor.assumeIsolated { rebuildSections() }

// ❌ WRONG — creates async hop allowing stale section access
Task { @MainActor in rebuildSections() }
```

### `performFetch()` is synchronous on MainActor

`performFetch() + rebuildSections()` are synchronous on MainActor — sections fully updated before the next line.

### Reset handling

`resetAllData()` invalidates FRC: destroys/recreates the persistent store. FRC holders must observe `storeDidResetNotification` and call `setup()` to recreate. See `TransactionPaginationController.handleStoreReset()`.

## CoreData Predicate Gotchas

- ⚠️ **OR-per-month predicate crash**: Never build `NSCompoundPredicate(orPredicateWithSubpredicates:)` with one subpredicate per calendar month — exceeds SQLite expression tree depth limit (1000). Use a constant 7-condition range predicate instead.
- ⚠️ **NEVER use `NSBatchDeleteRequest` then `context.save()` on the SAME context** when deleted objects have inverse relationships. Use `context.delete()` instead.
- **`viewContext.perform { }` runs on MainActor** — viewContext is MainActor-bound, so its perform queue blocks UI. Use `newBackgroundContext()` for heavy ops (purgeHistory, batch deletes, large fetches that don't need UI synchronicity).
- **`NSDecimalNumber.compare()` gotcha**: `number.compare(.zero)` doesn't compile — always write `number.compare(NSDecimalNumber.zero)`.

## Entity Resolution

- **Case-sensitivity**: `resolveCategoryByName` must use case-insensitive comparison. When cache HITs on a case-variant, return the **stored** entity name (not the input name).

## Update Restrictions

⚠️ **`TransactionStore.update()` blocks removing a LIVE `recurringSeriesId`** — throws `cannotRemoveRecurring`. Scope of the guard:
- it fires only when the old series still exists in `recurringStore.seriesById`. A **dangling** link (series deleted/lost while its transactions survived) is allowed to be cleared — refusing it made such a transaction permanently uneditable (the "cannot remove recurring series" error when editing an auto-posted deposit-interest accrual, whose edit screen hides the recurring control and therefore always saves `nil`).
- pass `update(tx, allowSeriesDetach: true)` for a deliberate unlink of a single transaction (the edit screen's explicit "Never"). Never pass it just to silence the error.
- ⚠️ A caller that rebuilds a `Transaction` MUST carry `recurringSeriesId` over. `TransactionEditCoordinator` only nils it when `transaction.type.allowsRecurring` **and** the user picked "Never"; for types whose recurring control is hidden it copies the existing link through. Pinned by `TransactionSeriesDetachTests`.

To unlink in bulk, use `apply(.updated(old: tx, new: updatedTx))` directly. See `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift`.

## Edit-Screen Field Gating by Type

`TransactionEditView` field visibility is driven by `TransactionType` computed properties (in `Models/Transaction.swift`), NOT scattered `if type ==` in the view: `allowsCategoryPicker`, `allowsSubcategoryPicker`, `allowsRecurring`, `allowsOnlyAmountAndDescription`. To restrict fields for a type, extend the relevant property. System-generated `.depositInterestAccrual` is amount+description-only (fixed account+category); `allowsRecurring` is false for all loan/deposit-op types (the recurring engine only replays income/expense).

## Per-Type Icon Override in `TransactionCard`

`TransactionCard.subscriptionIconSource` (despite the name) is the **generic icon override channel** consumed by `TransactionIconView`. Precedence inside `TransactionCard.body`:

1. Linked subscription series logo (Netflix, Spotify, …) when `series.kind == .subscription`.
2. `.loanPayment` / `.loanEarlyRepayment` → `targetAccount.iconSource` (the loan account == `targetAccountId`; source = funding bank).
3. Fallback → category SF Symbol resolved by `TransactionIconView` from `styleData.iconName`.

When adding a new typed override (e.g. transfer-source brand), extend the `switch transaction.type` in `TransactionCard.body` rather than threading a new parameter through `TransactionCardView`. Renaming the parameter to `overrideIconSource` is out of scope for incremental changes — 12+ call sites reference the current name.

## Performance

- ⚠️ **Reading `.count`/`.isEmpty`/`dict[key]` on `@Observable` collection subscribes to whole collection** — for hot paths over 19k transactions, maintain a separate Observable scalar mirror (e.g. `TransactionStore.transactionsCount`) and read that instead.
