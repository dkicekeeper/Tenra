# Categories & Budgets

Single-source guide for category management, subcategories, budget progress, and the per-category aggregate indexes that make all of this O(1) at read time.

## Read-time complexity contract

All consumer paths (Views, ViewModels, services that run on `@MainActor`) must hit the in-memory indexes — never scan `transactions: [Transaction]`.

| Read | Source | Complexity |
|---|---|---|
| Live category by id | `TransactionStore.categoryById[id]` | O(1) |
| Category id by case-folded name | `TransactionStore.categoryIdByName[name.lowercased()]` | O(1) |
| All tx for a category name | `TransactionStore.transactionsByCategoryName[name]` | O(1) lookup |
| Budget spent in current period | `CategoryBudgetService.calculateSpent(for:store:)` | O(≤31) bucket reads |
| Period / all-time / avg6 aggregates | `CategoryAggregatesCalculator.compute(...)` | O(≤40) bucket reads |
| Subcategory by id | `TransactionStore.subcategoryById[id]` | O(1) |
| Subcategories for category id | `TransactionStore.subcategoryIdsByCategoryId[catId]` | O(M), M ≤ ~20 |
| Subcategories for transaction id | `TransactionStore.subcategoryIdsByTransactionId[txId]` | O(M), M ≤ ~5 |
| Subcategory usage count / last-used | `TransactionStore.subcategoryUsageCountById` / `subcategoryLastUsedById` | O(1) |

`InsightsService` is the **only** consumer allowed to do O(N_tx) scans of the snapshot array — it runs `nonisolated` on a background actor and can't read MainActor-isolated indexes. It uses `CategoryBudgetService.budgetProgress(for:transactions:baseCurrency:rates:)` (static legacy API) for that path, once per refresh (the budget insights are shared across granularities, see [insights.md](insights.md)).

## Index maintenance contract

All indexes are maintained incrementally inside `TransactionStore`. The funnel is `updateState(_:)` (see [TransactionStore.swift](../../Tenra/ViewModels/TransactionStore.swift)) for transaction events, and `TransactionStore+CategoryCRUD.swift` for category / subcategory CRUD.

Touch points that must keep indexes in sync:

| Event | Function | Calls |
|---|---|---|
| `.added(tx)` | `updateState` | `indexAdd` + `categoryIndexAdd` + `subcategoryIndexAdd` |
| `.updated(old, new)` | `updateState` | `indexUpdate` + `categoryIndexUpdate` + `subcategoryIndexUpdate` |
| `.deleted(tx)` | `updateState` | `indexRemove` + `categoryIndexRemove` + `subcategoryIndexRemove` |
| `.bulkAdded(txs)` | `updateState` | per-tx `indexAdd` + `categoryIndexAdd` + `subcategoryIndexAdd` |
| `.bulkUpdated(changes)` / `.bulkDeleted(txs)` | `updateState` → `updateStateForBulkUpdate/Delete` | buckets filtered once (`removeIds`), aggregate deltas per row in row order, ONE persist (`categoryIndexUpdateBulk` / `categoryIndexRemoveBulk`) |
| `addCategory(_:)` | `TransactionStore+CategoryCRUD` | seed `categoryById`/`categoryIdByName`, bump `categoriesMutationVersion` |
| `updateCategory(_:)` | `TransactionStore+CategoryCRUD` | replace in `categoryById`; on rename → `renameCategoryIndexKeys`; bump |
| `deleteCategory(_:)` | `TransactionStore+CategoryCRUD` | drop from `categoryById`/`categoryIdByName` + `dropAggregates`; bump |
| `addSubcategory(_:)` / `updateSubcategories(_:)` / link updates | `TransactionStore+CategoryCRUD` | rebuild affected subcategory maps; bump `subcategoriesMutationVersion` |
| `loadData()` | `TransactionStore` | `buildLoadSnapshot` off main (lookups, subcategory indexes, cold-start aggregates) |
| `updateBaseCurrency(_:)` | `TransactionStore` | `rebuildCategoryIndexes` — synchronous: the old totals are in the wrong unit |
| `bumpCurrencyRatesVersion()` | `TransactionStore` | if `aggregatesAreFXStale` → `rebuildRealizedAggregates()` off main |
| day rollover with a matured tx | `recalculateLedgerIfDayChanged` | `rebuildRealizedAggregates()` off main, then `recalculateAll` |

### Full rebuilds run off the main actor

⚠️ **Never rebuild the aggregates with a per-transaction loop on the main actor**: a date parse, a `startOfDay` and a persist per transaction over 19k rows freezes the UI. `rebuildRealizedAggregates()` ([TransactionStore+RealizedAggregates](../../Tenra/ViewModels/TransactionStore+RealizedAggregates.swift)) runs the cold-load builders (`computeCategoryAggregates` / `computeAccountAggregates` in TransactionStore+LoadSnapshot) in a detached task over a Sendable copy and only assigns on the main actor (one `categoriesMutationVersion` bump, one persist per map). It is single-flight, and assigns only if `RealizedAggregatesStamp` (transactions, accounts, categories, rates, base currency, today, other wholesale writes) is unchanged when it lands; otherwise it reruns. The synchronous `rebuildCategoryIndexes()` / `rebuildAccountAggregates()` use the same builders. Matured rows are not applied as per-row deltas: which rows the incremental state already counts is not tracked (one added after midnight before the check is counted already). Pinned by `RealizedAggregatesRebuildTests`.

### Rename caveats

`categoryAggregatesByKey` is keyed by *category name* (see `CategoryAggregate.makeId`). Renaming a category MUST re-key:
- `transactionsByCategoryName` (move the array under the new name)
- `categoryIdByName` (drop old lowercase, insert new)
- Every aggregate key matching `"<oldName>_*"` prefix

This is centralised in `renameCategoryIndexKeys(from:to:)` and called from `updateCategory(_:)` when `old.name != new.name`.

Right after it, `updateCategory` calls `TransactionStore.renameCategoryInTransactions(from:to:type:)`, which rewrites the
stored name on every transaction of that category type (`categoryPickerSourceType`) and on recurring series, and persists
it in one background save (`renameTransactionsCategory(ids:to:)`). Categories are referenced by NAME everywhere: a
transaction whose stored name matches no category fails `validate` with `categoryNotFound` when edited, and appears in the
category filter (`CategoryFilterView`) under "Deleted" (`categoryFilter.deletedCategories`). Pinned by `CategoryRenameTests`.

## Aggregate buckets

`CategoryAggregate` keys are 4-granularity: `daily`, `monthly`, `yearly`, `all-time` (see [Models/CategoryAggregate.swift](../../Tenra/Models/CategoryAggregate.swift)).

Each transaction touches 4 keys (`applyAggregateDelta`):

```
"<category>_<""/sub>_<year>_<month>_<day>"   // daily
"<category>_<""/sub>_<year>_<month>_0"        // monthly
"<category>_<""/sub>_<year>_0_0"               // yearly
"<category>_<""/sub>_0_0_0"                   // all-time
```

All amounts are stored in `baseCurrency`. Conversion happens once at `applyAggregateDelta` via `CategoryBudgetCurrency.toBase` (uses `CurrencyConverter.convertSync`). If the rate cache is cold:
- the converted amount falls back to the raw amount (proportional, not exact)
- `aggregatesAreFXStale = true` is set
- on the next `bumpCurrencyRatesVersion()` the whole index is rebuilt

⚠️ Per CLAUDE.md ⚠️ #6, `Transaction.convertedAmount` is in account currency — DO NOT use it as a base-currency proxy.

⚠️ **Persistence is whole-table and is the next launch's warm start.** `saveAggregates` / `saveAccountAggregatesSync` delete every row not in the snapshot, and `loadData` seeds from a non-empty table instead of rebuilding. Before the full load (`hasCompletedInitialLoad == false`: a process launched only for an App Intent, the first seconds of launch) the in-memory maps hold only the deltas applied since launch, so `categoryAggregatesToPersist()` / `accountAggregatesToPersist()` return empty: the table is cleared and the next full load rebuilds from the transactions. Persisting the partial map would cut category totals, budget "spent" and account totals down to those few deltas.

The warm start also checks the saved category table before using it (`TransactionStore.persistedCategoryAggregatesMatch`, inside `buildLoadSnapshot`, off main): each category's all-time bucket must count exactly the realized aggregatable transactions. A mismatch (e.g. a table saved before a future-dated transaction came due) rebuilds the totals as on a first launch and persists them. Pinned by `PersistedCategoryAggregatesCheckTests`.

## Style cache contract

`CategoryStyleCache.shared` is keyed by `"<name>_<type.rawValue>"`.

- A hit is O(1); a miss is one O(N_cat) lookup against the passed `customCategories` array.
- Invalidation is **explicit and surgical**: `TransactionStore.updateCategory` calls `CategoryStyleCache.shared.invalidate(name:type:)` only when icon / colour / name / type actually changed (both keys on a rename). Budget edits don't touch the cache.
- `invalidateCache()` (nuclear option) is reserved for wholesale category-array replacements (CSV import, `syncCategories`).

## View-layer subscriptions

Views key snapshot rebuilds on scalar mutation counters, not on the underlying arrays:

| Key on | Source | Note |
|---|---|---|
| Category list changes | `transactionStore.categoriesMutationVersion` | observable scalar; doesn't move on tx mutations |
| Subcategory data changes | `transactionStore.subcategoriesMutationVersion` | observable scalar; doesn't move on category mutations |
| Transaction changes | `transactionStore.mutationVersion` | ⚠️ `@ObservationIgnored`: reading it registers nothing. The body must also read an observable that moves on every transaction mutation, `transactionStore.transactions` (`_ = transactionStore.transactions.count`, as `SubscriptionDetailView` does) |
| FX refresh | `transactionStore.currencyRatesVersion` | observable scalar |
| Snapshot rebuilds | `.task(id: <CompositeKey>)` | rebuild on key change, off the body |

Pattern is established in:
- [CategoriesManagementView.swift](../../Tenra/Views/Categories/CategoriesManagementView.swift): `budgetProgressMap` + `filteredCategories` as `@State`, rebuilt via `.task(id: listKey)` (categories, `mutationVersion`, rates, base currency, selected type).
- [CategoryDetailView.swift](../../Tenra/Views/Categories/CategoryDetailView.swift): `refreshTrigger` keys on `mutationVersion`, `categoriesMutationVersion`, `currencyRatesVersion`, the time filter and the budget, and reads `transactionStore.transactions.count` so that every transaction edit re-evaluates the body (`mutationVersion` alone is `@ObservationIgnored`).

## Reorder

`TransactionStore.reorderCategories(orderedIds:)` performs ONE batch persist for a drag operation. Calling `updateCategory(_:)` per moved category would run a full `saveCategoriesSync(...)` each, O(N²) CoreData writes per drag. Always go through the batch entry point.

## Subcategory tagging surfaces

Subcategories are **type-agnostic**: the catalog is global, `CategorySubcategoryLink` and
`TransactionSubcategoryLink` carry no transaction type, and `TransactionType
.allowsSubcategoryPicker` is true for everything except internal transfers and interest
accruals. Income transactions tag exactly like expenses.

Every composer that writes a transaction must therefore also write the links itself — there is
no central hook. The contract is: `transactionStore.add(...)` first (it assigns the id when you
pass `id: ""`), then `linkSubcategoryToCategory` per id (so the tag joins that category's
carousel next time), then `linkSubcategoriesToTransaction`. Reference implementation:
[TransactionAddCoordinator.linkSubcategories](../../Tenra/Views/Transactions/TransactionAddCoordinator.swift);
also implemented in [AccountActionViewModel](../../Tenra/ViewModels/AccountActionViewModel.swift) (the "Пополнение"
top-up flow) and the statement import (`ImportCommitter` in `ImportCommitPlanner.swift`, one batch for all rows; the
subcategory is suggested from history per merchant and category, see [import.md](import.md)). Loan payments and early
repayments are linked by `LoanDetailView.linkSubcategories(_:to:)` after `onPayment` / `onRepayment` add the
transaction (the forms `LoanPaymentView` / `LoanEarlyRepaymentView` only return the selected ids); it resolves the
expense category by name and type, as the top-up flow does.

⚠️ **Link many transactions in ONE call: `batchLinkSubcategoriesToTransaction`.** Every link-table write
(`updateTransactionSubcategoryLinks`) rebuilds `subcategoryIdsByTransactionId` and the usage stats over all
transactions, so linking per occurrence of a back-dated series pays that once per occurrence. The add / edit /
subscription flows batch it.

⚠️ Resolve the category id by **name + type**, not through `categoryIdByName` — that index is
keyed by lowercased name alone, so an income and an expense category sharing a name collide and
the tag would attach to the wrong one.

⚠️ **Never link through `CategoriesViewModel` before `TransactionStore.hasCompletedInitialLoad`.**
`saveTransactionSubcategoryLinks` replaces the whole table: it deletes every row not in the list it
gets. Before the full load (a process launched only for an App Intent stops after
`initializeFastPath()`) the in-memory link list is empty, so linking one transaction there would
wipe every other transaction's subcategories. `TransactionDraftService.commit` checks the flag and
inserts rows one at a time through [IntentSubcategoryStore](../../Tenra/Services/Intents/IntentSubcategoryStore.swift)
instead; intent-side subcategory reads go to CoreData through the same helper. When the app's own
full load is in flight in the same process, the commit waits for it (`waitForLoadInFlight`) and links
through memory: the load might not have fetched a row written around it, and the next whole-table save
would delete it. Inside the app the store holds whole-table saves until the load lands (see
[architecture.md §The load window](../architecture.md#the-load-window)), so linking during the load doesn't
wipe the table, but the in-memory list is complete only once the load lands.

Selection is per category: clear `selectedSubcategoryIds` whenever the picked category (or the
form's mode) changes. `CategoryCardSelectorView`/`CategorySelectorView` write the binding
*before* invoking `onSelectionChange`, so a handler comparing the new value against the current
selection never fires — clear unconditionally.

## When to read this doc

- Before mutating `categories` / `subcategories` / link arrays directly (don't — go through `TransactionStore` CRUD).
- Before adding a new "give me X for category Y" read in any View — check the existing index first.
- Before adding a new mutation path (importer, sync, recurring) — make sure it funnels through `apply(_:)` so all indexes update.
- When you see `customCategories.first(where:)` or `transactions.filter { $0.category == ... }` in user-facing code paths — that's a bug.

## See also

- [docs/architecture.md](../architecture.md) — TransactionStore lookup indexes.
- [docs/concurrency.md §Cross-File Extension Access Control](../concurrency.md#cross-file-extension-access-control) — why the category indexes are plain `var`, not `private(set)`.
- [docs/domains/currency.md](currency.md) — FX cache and `CurrencyConverter.convertSync` semantics.
- [docs/domains/insights.md §Metric catalogue](insights.md#metric-catalogue) — Insights budget metrics (uses the legacy array-scan path).
