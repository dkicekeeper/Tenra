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

`InsightsService` is the **only** consumer allowed to do O(N_tx) scans of the snapshot array — it runs `nonisolated` on a background actor and can't read MainActor-isolated indexes. It uses `CategoryBudgetService.budgetProgress(for:transactions:baseCurrency:)` (static legacy API) for that path.

## Index maintenance contract

All indexes are maintained incrementally inside `TransactionStore`. The funnel is `updateState(_:)` (see [TransactionStore.swift](../../Tenra/ViewModels/TransactionStore.swift)) for transaction events, and `TransactionStore+CategoryCRUD.swift` for category / subcategory CRUD.

Touch points that must keep indexes in sync:

| Event | Function | Calls |
|---|---|---|
| `.added(tx)` | `updateState` | `indexAdd` + `categoryIndexAdd` + `subcategoryIndexAdd` |
| `.updated(old, new)` | `updateState` | `indexUpdate` + `categoryIndexUpdate` + `subcategoryIndexUpdate` |
| `.deleted(tx)` | `updateState` | `indexRemove` + `categoryIndexRemove` + `subcategoryIndexRemove` |
| `.bulkAdded(txs)` | `updateState` | per-tx `indexAdd` + `categoryIndexAdd` + `subcategoryIndexAdd` |
| `addCategory(_:)` | `TransactionStore+CategoryCRUD` | seed `categoryById`/`categoryIdByName`, bump `categoriesMutationVersion` |
| `updateCategory(_:)` | `TransactionStore+CategoryCRUD` | replace in `categoryById`; on rename → `renameCategoryIndexKeys`; bump |
| `deleteCategory(_:)` | `TransactionStore+CategoryCRUD` | drop from `categoryById`/`categoryIdByName` + `dropAggregates`; bump |
| `addSubcategory(_:)` / `updateSubcategories(_:)` / link updates | `TransactionStore+CategoryCRUD` | rebuild affected subcategory maps; bump `subcategoriesMutationVersion` |
| `loadData()` | `TransactionStore` | `rebuildCategoryLookups` + `rebuildAllSubcategoryIndexes` + `rebuildCategoryIndexes` |
| `updateBaseCurrency(_:)` | `TransactionStore` | `rebuildCategoryIndexes` (totals are unit-bound) |
| `bumpCurrencyRatesVersion()` | `TransactionStore` | if `aggregatesAreFXStale` → `rebuildCategoryIndexes` |

### Rename caveats

`categoryAggregatesByKey` is keyed by *category name* (see `CategoryAggregate.makeId`). Renaming a category MUST re-key:
- `transactionsByCategoryName` (move the array under the new name)
- `categoryIdByName` (drop old lowercase, insert new)
- Every aggregate key matching `"<oldName>_*"` prefix

This is centralised in `renameCategoryIndexKeys(from:to:)` and called from `updateCategory(_:)` when `old.name != new.name`.

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

## Style cache contract

`CategoryStyleCache.shared` is keyed by `"<name>_<type.rawValue>"`.

- Pre-refactor: every `getStyleData` call rebuilt a `Set<String>` snapshot of all categories — O(N_cat) allocs per row render.
- Now: cache hit is O(1); miss is one O(N_cat) lookup against the passed `customCategories` array.
- Invalidation is **explicit and surgical**: `TransactionStore.updateCategory` calls `CategoryStyleCache.shared.invalidate(name:type:)` only when icon / colour / name / type actually changed. Pure budget edits no longer touch the cache.
- `invalidateCache()` (nuclear option) is reserved for wholesale category-array replacements (CSV import, `syncCategories`).

## View-layer subscriptions

Views should subscribe to scalar mutation counters, not to the underlying observable arrays:

| Subscribe to | Source | Why |
|---|---|---|
| Category list changes | `transactionStore.categoriesMutationVersion` | scalar; doesn't re-eval on tx mutations |
| Subcategory data changes | `transactionStore.subcategoriesMutationVersion` | scalar; doesn't re-eval on category mutations |
| Aggregate freshness | `transactionStore.mutationVersion` + `currencyRatesVersion` | scalar; doesn't subscribe to 19k tx array |
| Snapshot rebuilds | `.task(id: <CompositeKey>)` | rebuild on key change, off the body |

Pattern is established in:
- [CategoriesManagementView.swift](../../Tenra/Views/Categories/CategoriesManagementView.swift): `budgetProgressMap` + `filteredCategories` as `@State`, rebuilt via `.task(id: listKey)`.
- [CategoryDetailView.swift](../../Tenra/Views/Categories/CategoryDetailView.swift): `refreshTrigger` is composed of scalar versions, never reads `transactionStore.transactions`.

## Reorder

`TransactionStore.reorderCategories(orderedIds:)` performs ONE batch persist for a drag operation. Earlier the management view called `updateCategory(_:)` per moved category — each did a full `saveCategoriesSync(...)`, i.e. O(N²) CoreData writes per drag. Always go through the batch entry point.

## When to read this doc

- Before mutating `categories` / `subcategories` / link arrays directly (don't — go through `TransactionStore` CRUD).
- Before adding a new "give me X for category Y" read in any View — check the existing index first.
- Before adding a new mutation path (importer, sync, recurring) — make sure it funnels through `apply(_:)` so all indexes update.
- When you see `customCategories.first(where:)` or `transactions.filter { $0.category == ... }` in user-facing code paths — that's a bug.

## See also

- [docs/architecture.md](../architecture.md) — TransactionStore index pattern (rooted at `transactionsByAccount`).
- [docs/concurrency.md](../concurrency.md) — `@Observable` and `@MainActor` rules; why indexes are `internal(set)` not `private(set)`.
- [docs/domains/currency.md](currency.md) — FX cache and `CurrencyConverter.convertSync` semantics.
- [docs/INSIGHTS_METRICS_REFERENCE.md](../INSIGHTS_METRICS_REFERENCE.md) — Insights budget metrics (uses the legacy array-scan path).
