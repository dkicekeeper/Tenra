# Cache Audit & Remediation Plan

**Date:** 2026-06-03
**Scope:** Every memoization / cached-value / invalidation path in the app.
**Trigger:** Repeated stale-data bugs after the move to CoreData + in-memory single-source-of-truth (`TransactionStore`) + O(1) indexes. Most recent: `CategoryDisplayDataMapper`'s cache key omitted category `order`, so reorders only showed after restart (fixed).

---

## 1. Executive summary

The recurring bug is **one defect class**, not many unrelated bugs:

> **A memoization / refresh key (or invalidation trigger) omits a dimension that the cached value actually depends on.** When only that dimension changes, the key looks identical, the cache serves a stale hit, and the data "only updates after restart" (a fresh process = empty cache).

The dimensions repeatedly forgotten across the codebase:

| Forgotten dimension | Where it bit us |
|---|---|
| category `order` | `CategoryDisplayDataMapper` (fixed) |
| icon / color / budget | `CategoryDisplayDataMapper` (still open) |
| `currencyRatesVersion` (FX refresh) | balance cache, `SubscriptionDetailView`, `DateSectionExpensesCache` |
| `baseCurrency` | home summary, per-filter category-expenses cache |
| `mutationVersion` vs `txCount` | home summary card (in-place edits) |
| account mutations | Insights |
| "today" (date rollover) | balance ledger, Insights |

There is also a **second, structural problem**: post-CoreData/O(1), several caches now *duplicate* the `TransactionStore` indexes — and **four are dead code** (never read, or force-invalidated on every read). They add staleness surface area for zero benefit. Deleting them is the cheapest reliability win.

**Verification:** every Critical/High finding below was confirmed by reading the cited source (not just agent report). Low/None items are reported as found.

---

## 2. Findings (ranked)

Severity scale: **Critical** = wrong money shown · **High** = stale until restart on a common action · **Medium** = stale until an unrelated action · **Low** = perf-only / latent / self-heals · **None** = correct.

| # | Finding | File:line | Severity |
|---|---|---|---|
| 1 | **Balance cache not invalidated on FX-rate refresh** | `AppCoordinator.swift:469`, `TransactionStore.swift:129` | **Critical** |
| 2 | **Home summary card stale on in-place tx edit & base-currency change** (`SummaryTrigger` keys on `txCount`, not `mutationVersion`/`baseCurrency`) | `ContentView.swift:39` | **High** |
| 3 | **`CategoryDisplayDataMapper` key omits icon/color/budget** (siblings of the fixed `order` bug) | `CategoryDisplayDataMapper.swift:24` | **High** |
| 4 | **`SubscriptionDetailView` "spent all time" omits `currencyRatesVersion`** → wrong-unit total after cold-cache | `SubscriptionDetailView.swift:44` | **High** |
| 5 | **Insights never invalidated on account mutations** (no `accountsMutationVersion` observer) | `AppCoordinator.swift:486`, `TransactionStore+AccountCRUD.swift` | **High** |
| 6 | **Category-lists cache stale after add/delete** (`invalidateCategoryExpenses` doesn't set `categoryListsCacheInvalidated`) | `TransactionCacheManager.swift:92` vs `118` | **High** |
| 7 | **Balance & Insights stale on date rollover** in a live session (recalc/ invalidate only at launch, not on foreground) | `TenraApp.swift:72`, `AppCoordinator.swift:431` | **Medium-High** |
| 8 | **Account currency-only edit doesn't recalc balance** (`AccountBalance.currency` is `let`) | `AccountsViewModel.swift:89`, `BalanceStore.swift:22` | **Medium-High** |
| 9 | **Per-filter category-expenses cache omits `baseCurrency` + `validCategoryNames`** | `TransactionCacheManager.swift:84` | **Medium** |
| 10 | **`DateSectionExpensesCache` not invalidated on late FX-rate load** | `DateSectionExpensesCache.swift:17`, `HistoryView.swift:132` | **Medium** |
| 11 | **`CategoryStyleCache.invalidateCache()` has zero callers** (CSV import / `syncCategories` / delete don't nuke it) | `CategoryStyleCache.swift:89`, `TransactionStore+CategoryCRUD.swift:256` | **Medium** |
| 12 | **Account aggregates rebuild only because the *category* FX-stale flag fires** (own cold-cache fallback sets no flag) | `TransactionStore+AccountAggregates.swift:202` | **Medium** |
| 13 | **DEAD: `TransactionCurrencyService` cache** (`precompute`/`getConvertedAmount`/`invalidate` never called) | `TransactionCurrencyService.swift:34` | Low (cleanup) |
| 14 | **DEAD: `TransactionCacheManager.cachedSummary`** (force-invalidated on every read) | `TransactionCacheManager.swift:80`, `+Queries.swift:23` | Low (cleanup) |
| 15 | **DEAD: `InsightsCache`** (NSLock LRU+TTL, never `get`/`set`; `invalidate(category:)` uses fragile substring match) | `InsightsCache.swift:19` | Low (cleanup) |
| 16 | **DEAD: `CategoryBudgetCoordinator.budgetCache`** (no production callers; superseded by store-backed `CategoryBudgetService`) | `CategoryBudgetCoordinator.swift:31` | Low (cleanup) |
| 17 | `updateBaseCurrency` doesn't bump `currencyRatesVersion` (latent trap; no current victim) | `TransactionStore.swift:519` | Low |
| 18 | `CategoryOrderManager` lacks a `reconcile()` prune (orphan keys grow across onboarding re-runs) | `CategoryOrderManager.swift` | Low |
| 19 | `DateFormatters` display formatters capture `Locale.current` once (stale month names after mid-session language change) | `DateFormatters.swift:35` | Low |

**Confirmed correct (no action):** `parsedDateById` id-keyed date cache (invalidated on date edit), `parsedDateCache` (referentially transparent), `UnifiedTransactionCache` (over-broad `removeAll()` masks its missing-currency keys — safe), FRC `sections` (live CoreData projection), `categoryAggregatesByKey` (well-maintained across add/update/delete/rename/base-currency/FX — the reference implementation), Order managers' UserDefaults map (sole persistent source — `AccountEntity`/`CustomCategoryEntity` have **no** `order` column, so no dual-write divergence is possible), `AmountDisplayConfiguration`/`AmountFormatter`/`Formatting` (locale-independent by design), logo/wallpaper/voice caches (graceful).

---

## 3. Detailed findings (Critical / High)

### #1 — Balance cache not invalidated on FX-rate refresh — **Critical**
`bumpCurrencyRatesVersion()` ([TransactionStore.swift:129](../Tenra/ViewModels/TransactionStore.swift)) rebuilds category **and** account aggregates when `aggregatesAreFXStale`, but never calls `balanceCoordinator.recalculate*`. The rate observer `startObservingCurrencyRateChanges()` ([AppCoordinator.swift:469](../Tenra/ViewModels/AppCoordinator.swift)) calls `bumpCurrencyRatesVersion()` + `invalidateCaches()` + insights recompute — also no balance recalc.
**Effect:** An account holding cross-currency transactions keeps the balance computed at the **cold/stale** FX rate after a mid-session rate refresh (prewarm landing, manual refresh). Aggregate income/expense self-heals, the cached balance does not → they disagree, and the home Finances total is wrong, until next launch or an unrelated mutation to that account. Same class as the documented `$20 + $100 = "120 KZT"` bug, but on the balance cache.
**Fix:** when `aggregatesAreFXStale`, also trigger `balanceCoordinator.recalculateAll()` (or `recalculateAccounts(for:)` for the accounts holding cross-currency tx) — heal balance on the same trigger that already heals aggregates. (`updateBaseCurrency` already recalcs balances; only the *rate-refresh* path misses it.)

### #2 — Home summary card stale on in-place edits & base-currency change — **High**
`SummaryTrigger` ([ContentView.swift:39](../Tenra/Views/Home/ContentView.swift)) = `{txCount, filterStart, filterEnd, isImporting, isFullyInitialized, ratesVersion}`. It has **no `mutationVersion`** and **no `baseCurrency`**.
**Effect:** Editing a transaction's amount / type / category (count unchanged) leaves the home income/expense/net card on pre-edit totals until the filter or count changes. Switching base currency also doesn't refire (`updateBaseCurrency` doesn't bump `currencyRatesVersion` — see #17). In-place edits are extremely common.
**Fix:** add `txVersion: transactionStore.mutationVersion` and `baseCurrency` to `SummaryTrigger`. The category picker's `RefreshTrigger` already does this correctly — mirror it.

### #3 — `CategoryDisplayDataMapper` key omits icon/color/budget — **High**
The `order` omission was fixed; three siblings remain. `mapCategory` reads `styleData.iconName/iconColor` and `budgetProgress` (from `budgetAmount`/`budgetPeriod`) ([CategoryDisplayDataMapper.swift:164](../Tenra/Services/Categories/CategoryDisplayDataMapper.swift)), but `CacheKey` fingerprints none of them.
**Effect:** Editing a category's color/icon/budget bumps `categoriesMutationVersion` → the view re-runs `recompute()`, but the mapper rebuilds an identical key → returns the cached rows with the old color/budget ring, until count/order/totals/filter/currency change (often restart).
**Fix:** add an `appearanceHash` to `CacheKey` — a `Hasher` over each category's `id`, `iconSource`/`colorHex`, `budgetAmount`, `budgetPeriod` (mirror the `orderHash` loop just added).

### #4 — `SubscriptionDetailView` "spent all time" omits FX version — **High**
`RefreshKey` = `{mutationVersion, seriesId}` ([SubscriptionDetailView.swift:44](../Tenra/Views/Subscriptions/SubscriptionDetailView.swift)); the all-time total is summed via `convertSync`. No `currencyRatesVersion`.
**Effect:** Opened during a cold rate cache, multi-currency totals fall back to wrong-unit (`convertedAmount ?? amount`); when rates land (`bumpCurrencyRatesVersion`) every sibling detail view re-derives but this hero figure stays wrong until a tx mutation / re-navigation.
**Fix:** add `ratesVersion: transactionStore.currencyRatesVersion` to `RefreshKey` (mirrors `AccountDetailView`/`CategoryDetailView`).

### #5 — Insights never invalidated on account mutations — **High**
`AppCoordinator` has `startObservingCategoryChanges()` ([:486](../Tenra/ViewModels/AppCoordinator.swift)) but no account analog, and `TransactionStore+AccountCRUD` makes zero `invalidateAndRecompute()` calls.
**Effect:** Toggling `includeInBalance`, editing a balance, or deleting an account leaves balance-runway, projected-balance, emergency-fund, dormancy, wealth-breakdown and the health-score `totalBalance` stale until an unrelated tx/FX/category mutation recomputes. (Editing a tx on that account masks it — why it slips through.)
**Fix:** add an `accountsMutationVersion` scalar to `TransactionStore`, bump it in account CRUD, and add `startObservingAccountChanges()` mirroring the category observer.

### #6 — Category-lists cache stale after add/delete — **High**
The normal mutation path is `invalidateCaches()` → `invalidateCategoryExpenses()` ([+Queries.swift:131](../Tenra/ViewModels/TransactionsViewModel+Queries.swift), [TransactionCacheManager.swift:92](../Tenra/Services/Cache/TransactionCacheManager.swift)), which clears summary + per-filter expenses but **does not** set `categoryListsCacheInvalidated`. Only `invalidateAll()` does. The accessors `expenseCategories`/`incomeCategories`/`uniqueCategories` ([TransactionQueryService.swift:209/231/252](../Tenra/Services/Transactions/TransactionQueryService.swift)) gate on that flag and feed the History category filter + income/expense pickers.
**Effect:** Add a tx with a brand-new category (or delete a category's last tx) → the filter/picker list is stale until an `invalidateAll()`-class event (import, currency change) or restart.
**Fix (cheap):** set `categoryListsCacheInvalidated = true` inside `invalidateCategoryExpenses()`. **Fix (better):** delete these three tx-scan caches and read names from `TransactionStore` category indexes (they duplicate the O(1) source).

### #7 — Balance & Insights stale on date rollover (live session) — **Medium-High**
`LedgerPolicyRule.isRealized` and several insights key on "today", but `recalculateLedgerIfDayChanged()` runs only at launch ([AppCoordinator.swift:431](../Tenra/ViewModels/AppCoordinator.swift)) and the `scenePhase == .active` handler only calls `timeFilterManager.refreshRelativePresetIfNeeded()` ([TenraApp.swift:72](../Tenra/TenraApp.swift)) — it never recalcs the ledger or invalidates insights.
**Effect:** App foregrounded across midnight: a maturing future-dated tx isn't folded into the cached realized balance, and insights (forecast `daysRemaining`, health score, MoM `currentPeriodKey`) stay on yesterday until next cold launch. (Home summary *does* recover, because the time-filter refresh moves its `filterStart/End`.)
**Fix:** in the `.active` handler, if the calendar day changed since last compute, call `recalculateLedgerIfDayChanged()` + `insightsViewModel.invalidateAndRecompute()` (or observe `NSCalendarDayChanged`).

### #8 — Account currency-only edit doesn't recalc balance — **Medium-High**
`AccountsViewModel.updateAccount` recalcs only when `initialBalance` changes ([:89](../Tenra/ViewModels/AccountsViewModel.swift)); `AccountBalance.currency` is a `let` set once at `registerAccounts` ([BalanceStore.swift:22](../Tenra/Services/Balance/BalanceStore.swift)).
**Effect:** Changing an account's currency leaves the cached balance and all later incremental cross-currency `contribution` conversions using the old currency until restart.
**Fix:** treat a `currency` change like a balance change — re-register the account and `recalculateAccounts([id])`.

---

## 4. Detailed findings (Medium / Low / cleanup)

- **#9** Per-filter category-expenses cache ([TransactionCacheManager.swift:84](../Tenra/Services/Cache/TransactionCacheManager.swift)) is keyed only by `TimeFilter.stableCacheKey`. Renaming/deleting a category with the same filter active returns a stale breakdown (self-heals on currency change via `SettingsViewModel`). **Fix:** fold `baseCurrency` + a `validCategoryNames` digest into the key.
- **#10** `DateSectionExpensesCache` ([HistoryView.swift:132](../Tenra/Views/History/HistoryView.swift) wiring) invalidates on `mutationVersion` and `baseCurrency` but not on `currencyRatesVersion`. **Fix:** add `.onChange(of: transactionStore.currencyRatesVersion)`.
- **#11** `CategoryStyleCache.invalidateCache()` ([:89](../Tenra/Utils/CategoryStyleCache.swift)) is documented for "CSV import, syncCategories" but has **zero callers**; `deleteCategory` doesn't invalidate the removed name. **Fix:** call it in `syncCategories` and after CSV `finishImport`; add `invalidate(name:type:)` to delete.
- **#12** Account aggregates' cold-cache fallback ([TransactionStore+AccountAggregates.swift:202](../Tenra/ViewModels/TransactionStore+AccountAggregates.swift)) never sets `aggregatesAreFXStale`, so the FX rebuild fires only because the category path happened to set it. **Fix:** set/propagate the stale flag from the account conversion path too (also in `TransactionStore+LoadSnapshot.swift` `computeAccountAggregates`).
- **#13–16 (DEAD CODE — delete):** `TransactionCurrencyService` cache layer (always falls through to `convertSync`); `TransactionCacheManager.cachedSummary` (force-invalidated every read at `+Queries.swift:23`); `InsightsCache` (~100 lines, never `get`/`set`); `CategoryBudgetCoordinator.budgetCache` (superseded by store-backed `CategoryBudgetService`). All confirmed unreferenced on live paths.
- **#17** `updateBaseCurrency` ([TransactionStore.swift:519](../Tenra/ViewModels/TransactionStore.swift)) should also bump `currencyRatesVersion` (any base-dependent total is as invalid as on a rate change). Closes the home-summary base-change gap symmetrically with #2.
- **#18** Add `CategoryOrderManager.reconcile(withCategoryIds:)` mirroring `AccountOrderManager` to bound orphan-key growth.
- **#19** Switch `DateFormatters.displayDateFormatter`/`displayDateWithYearFormatter` to computed `Date.FormatStyle` (or rebuild on locale change) if live language switching matters.

---

## 5. Remediation plan (phased)

### Phase 0 — Delete dead/redundant caches (low risk, shrinks staleness surface)
Items **#13, #14, #15, #16**. Pure deletion + collapse call sites to the live path. No behavior change; removes ~4 caches that duplicate the O(1) indexes. Do this first — it makes the rest of the audit smaller and is the most direct answer to "we already have a single source of truth, why so many caches?".

### Phase 1 — Critical / High correctness (wrong money & common actions)
- **#1** Balance recalc on FX-rate refresh.
- **#2** `SummaryTrigger` += `mutationVersion` + `baseCurrency`.
- **#3** `CategoryDisplayDataMapper` += `appearanceHash` (icon/color/budget).
- **#4** `SubscriptionDetailView` `RefreshKey` += `currencyRatesVersion`.
- **#5** `accountsMutationVersion` + `startObservingAccountChanges()` for Insights.
- **#6** One-line `categoryListsCacheInvalidated` fix (or delete the tx-scan lists).

Each fix ships with a unit test asserting the cache invalidates on the previously-missing dimension (pattern: `CategoryDisplayDataMapperTests.reorderInvalidatesCache`).

### Phase 2 — Medium
Items **#7, #8, #9, #10, #11, #12**.

### Phase 3 — Low / systemic prevention
Items **#17, #18, #19**, plus the prevention guardrails below.

---

## 6. Systemic prevention (stop the class, not just the instances)

1. **Cache-key checklist.** Every memoization key/refresh trigger must enumerate *all* inputs of the cached value. Standard dimensions to consider for any money/category/account cache: transaction `mutationVersion` (NOT `count`), `baseCurrency`, `currencyRatesVersion`, `categoriesMutationVersion`, `accountsMutationVersion`, active `TimeFilter`, and **today's date** if the value is realized-vs-forecast or period-relative.
2. **Prefer the indexes over new caches.** `TransactionStore` already holds all tx + O(1) `categoryAggregatesByKey` / `accountAggregatesByAccountId` / lookup maps. A new "give me X for entity Y" read should hit an index, not a new snapshot cache. New caches need a written justification (which index is insufficient and why).
3. **Test per dimension.** For each retained memoization cache, a test that mutates one dimension at a time and asserts the output changes. Cheap (the mapper test runs in <10 ms).
4. **Invalidation symmetry.** When a sibling cache is wired into a trigger (e.g. aggregates into the FX observer), every cache depending on the same dimension must be wired into the *same* trigger — #1 and #12 are both "only one of a pair was wired in".
5. **CLAUDE.md note.** Add the "cache key must include every dependency dimension" rule and the standard-dimensions list to the design/architecture docs so it's enforced at review time.

---

## 7. References
- [docs/DATA_INTEGRITY_AUDIT.md](DATA_INTEGRITY_AUDIT.md) — the unified contribution / realized-vs-forecast model (#1, #7 interact with it).
- [docs/domains/categories.md](domains/categories.md) — index maintenance contract & view-layer subscription rules (#3, #6).
- [docs/domains/currency.md](domains/currency.md) — `convertSync` vs `convertedAmount`, FX staleness (#1, #4, #9, #10, #12).
