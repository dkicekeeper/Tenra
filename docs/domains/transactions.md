# Transactions Domain

Deep details on `TransactionStore` CRUD, FRC, and pagination patterns. For high-level role of TransactionStore see [architecture.md](../architecture.md).

## CRUD Pipeline

`TransactionStore.apply()` pipeline runs on every mutation event:

```
updateState → updateBalances → invalidateCache → persistIncremental
```

- Debounced sync with **16ms coalesce window**
- Granular cache invalidation per event type
- Event-driven via `TransactionStoreEvent` (`added` / `updated` / `deleted` / `bulkAdded`)

## Deletion Semantics

- ⚠️ **`allTransactions` setter is a no-op** — to delete, use `TransactionStore.deleteTransactions(for...)` which routes through `apply(.deleted)`
- **`updateState .deleted` uses index-based removal**: `firstIndex(where:) + remove(at:)` instead of `removeAll{ $0.id == tx.id }`. The latter never short-circuits and was the silent quadratic source for batch deletes.

## Index Maintenance

- `transactionById: [String: Transaction]` — synced inside `updateState()` for every event
- Use this instead of `transactions.first(where: { $0.id == ... })` on the 19k-element array

## Batch Operations

### `addBatch` fallback pattern

`TransactionStore.addBatch()` validates ALL transactions; one failure rejects the entire batch. `CSVImportCoordinator` retries individual `add()` calls after batch rejection.

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

⚠️ **`TransactionStore.update()` blocks removing `recurringSeriesId`** — throws `cannotRemoveRecurring`. To unlink (e.g. bulk unlink from subscription), use `apply(.updated(old: tx, new: updatedTx))` directly. See `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift`.

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
