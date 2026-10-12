# Accounts

Single-source guide for the account domain: maintenance of `accountAggregatesByAccountId`, fast paths in `AccountDetailView` and `AccountRankingService`, and the relationship to the broader TransactionStore index family.

## Read-time complexity contract

| Read | Source | Complexity |
|---|---|---|
| Live account by id | `TransactionStore.accountById[id]` | O(1) |
| All tx for an account | `TransactionStore.transactionsByAccount[id]` | O(1) lookup |
| Income / expense / count per account | `TransactionStore.accountAggregatesByAccountId[id]` | O(1) |
| Parsed date for a tx | `TransactionStore.parsedDateByDateString[tx.date]` | O(1) |
| Per-series transactions (subscriptions, recurring) | `TransactionStore.transactionsBySeriesId[seriesId]` | O(1) lookup |

These are MainActor-isolated. Background work (Insights, `Task.detached`) can't read them; it works on a `Sendable` snapshot of the transactions ([concurrency.md §DataSnapshot](../concurrency.md#datasnapshot-pattern-capturing-mainactor-data-into-sendable-struct)). The full rebuild of the account totals is the `nonisolated static` builder `computeAccountAggregates` (TransactionStore+LoadSnapshot).

## Index maintenance

All indexes are maintained inside `TransactionStore.updateState(_:)` alongside the category and subcategory indexes. New mutations must funnel through `apply(_:)` so every index stays consistent.

Per event:

| Event | Calls |
|---|---|
| `.added(tx)` | `seriesIndexAdd`, `accountAggregatesAdd` |
| `.updated(old, new)` | `seriesIndexUpdate`, `accountAggregatesUpdate` |
| `.deleted(tx)` | `seriesIndexRemove`, `accountAggregatesRemove` |
| `.bulkAdded(txs)` | per-tx `seriesIndexAdd` + `accountAggregatesAdd` |
| `.bulkUpdated(changes)` | `seriesIndexUpdateBulk` + per-row `accountAggregatesUpdate` |
| `.bulkDeleted(txs)` | `seriesIndexRemoveBulk` + `accountAggregatesRemoveBulk` (one persist) |

Full load (`loadData()`): `buildLoadSnapshot` builds `transactionIdsBySeriesId` and `parsedDateByDateString` off the main actor. Account totals warm-start from the persisted `AccountAggregateEntity` rows; they are rebuilt in the same detached pass (`computeAccountAggregates`) when the table is empty, when transactions changed during the load window, or when the rows were saved under an older valuation rule (`TransactionStore.accountAggregatesRuleVersion`).

After load, a day rollover or an FX heal rebuilds them off the main actor (`rebuildRealizedAggregates()`, see [categories.md](categories.md) §Full rebuilds). `rebuildSeriesAndDateIndexes()` and `rebuildAccountAggregates()` are the synchronous equivalents (same builders), used by tests.

On `updateBaseCurrency(_:)`: category aggregates rebuild (totals are in base currency); account aggregates are **not** affected because each account's aggregate is stored in the account's own currency.

On `bumpCurrencyRatesVersion()`: if any apply-time delta was applied while the FX cache was cold, both category and account aggregate maps rebuild from scratch.

## Currency semantics

`accountAggregatesByAccountId` stores `totalIncome` / `totalExpense` in **the owning account's currency**, NOT the base currency. A cross-currency source leg counts the conversion recorded with the transaction (`TransactionConversion.recordedAmount`, see [currency.md](currency.md) "Reading the fields"), the amount the balance moved by; only without one is it converted at apply-time via `CurrencyConverter.convertSync(amount:from:to:)` (today's rate). A transfer's target leg counts `targetAmount` when it is in the target's currency. If the FX cache is cold the patch falls back to `tx.convertedAmount ?? tx.amount` and a `bumpCurrencyRatesVersion` rebuild will heal it.

`accountAggregatesUpdate` re-patches when `amount`, `currency`, `convertedAmount`, `targetAmount`, `targetCurrency`, `type`, `date` (realized or not) or an account changes.

## AccountAggregatesCalculator

```swift
// O(1) read of the maintained index; zeros for an unknown account.
static func compute(accountId: String, store: TransactionStore) -> AccountAggregates
```

[Views/Accounts/AccountAggregates.swift](../../Tenra/Views/Accounts/AccountAggregates.swift); read in `AccountDetailView.refreshData()`.

## View-layer subscriptions

`AccountDetailView` refreshes through `.task(id: refreshTrigger)`:

```swift
private var refreshTrigger: RefreshKey {
    RefreshKey(
        mutationVersion: transactionStore.mutationVersion,
        accountsVersion: transactionStore.accountsMutationVersion,
        ratesVersion: transactionStore.currencyRatesVersion,
        accountId: account.id
    )
}
```

⚠️ `mutationVersion` and `accountsMutationVersion` are `@ObservationIgnored`: reading them registers no subscription, so the key only changes when the body re-evaluates for another reason. In this view that is `currencyRatesVersion` (observable) and the live balance (`balanceCoordinator.balances`, observable). A view that must refresh on every transaction edit also reads `transactionStore.transactions` in the body (`_ = transactionStore.transactions.count`, the precedent is `SubscriptionDetailView`).

`accountsById` is a `@State` snapshot refreshed via `.task(id: transactionStore.accountsMutationVersion)`. Gate empty-state UI on the source of truth (`store.accounts.contains(...)`), never on the snapshot, which is empty on first render. Same pattern as `CategoriesManagementView.hasCategoriesForCurrentType`.

## Account ranking

`AccountRankingService.suggestedAccount(forCategory:)` is the hot path for the "which account did the user last use for this category?" picker on the add-transaction screen. The store-backed call site (`AccountsViewModel.suggestedAccount`) passes:

- `transactionsByAccount: store.transactionsByAccount` — instead of a per-account `firstIndex(where:)` in the ranking loop.
- `transactionsByCategoryName: store.transactionsByCategoryName` — instead of `transactions.filter { $0.category == X && $0.type == .expense }`. Bucket is already filtered by name; the service only filters by type → O(M) where M is tx in the category.

`accounts: [Account]` is still required; the service turns it into a one-shot `accountById` map so the lookups inside the loop are O(1).

### Transfer targets are pair-shaped, not per-account

⚠️ **Do NOT reuse `rankAccounts` to pick a transfer target.** It scores each account in isolation, so the globally busiest account always wins regardless of the selected source.

`AccountRankingService.suggestedTransferCounterpart(forSource:)` scores *counterparts of that specific source* from `.internalTransfer` history, with the same `Decay.tau` recency weighting. Incoming transfers count at `reverseDirectionWeight` (0.35) — still evidence the two accounts are paired, weaker evidence about where money goes when it leaves.

Call site: `AccountsViewModel.suggestedTransferTarget(forSource:)` → `AccountActionViewModel.defaultTargetAccountId(for:)`, which falls back to the carousel neighbour when there's no transfer history. Once the user picks a target themselves (`userPickedTarget`), source changes stop re-suggesting and only nudge on a source == target clash.

## Caveats

- `accountAggregatesByAccountId` is `@ObservationIgnored`; see View-layer subscriptions for what makes a body re-read it.
- The aggregate map excludes `.income` transactions on the target leg: an income transaction credits only its source-side account.
- `transactionsByAccount` already contains BOTH source and target legs (a transfer appears under both accounts' buckets). Callers that need only one side must filter further.

## See also

- [docs/architecture.md](../architecture.md) — TransactionStore index pattern.
- [docs/domains/categories.md](categories.md) — sibling domain with the same index family (categoryAggregatesByKey).
- [docs/domains/transactions.md](transactions.md) — TransactionStore mutation funnel.
- [docs/domains/currency.md](currency.md) — `CurrencyConverter.convertSync` and the FX cache.
