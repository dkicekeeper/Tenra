# Accounts

Single-source guide for the account domain: maintenance of `accountAggregatesByAccountId`, fast paths in `AccountDetailView` and `AccountRankingService`, and the relationship to the broader TransactionStore index family.

## Read-time complexity contract

| Read | Source | Complexity |
|---|---|---|
| Live account by id | `TransactionStore.accountById[id]` | O(1) |
| All tx for an account | `TransactionStore.transactionsByAccount[id]` | O(1) lookup |
| Income / expense / count per account | `TransactionStore.accountAggregatesByAccountId[id]` | O(1) |
| Parsed date for a tx | `TransactionStore.parsedDateById[tx.id]` | O(1) |
| Per-series transactions (subscriptions, recurring) | `TransactionStore.transactionsBySeriesId[seriesId]` | O(1) lookup |

These are MainActor-isolated. Background actors (Insights, services running via `Task.detached`) use snapshot-based legacy APIs — see `AccountAggregatesCalculator.compute(accountId:accountCurrency:transactions:)` (nonisolated static).

## Index maintenance

All indexes are maintained inside `TransactionStore.updateState(_:)` alongside the category and subcategory indexes. New mutations must funnel through `apply(_:)` so every index stays consistent.

Per event:

| Event | Calls (added in second audit) |
|---|---|
| `.added(tx)` | `seriesIndexAdd`, `accountAggregatesAdd` |
| `.updated(old, new)` | `seriesIndexUpdate`, `accountAggregatesUpdate` |
| `.deleted(tx)` | `seriesIndexRemove`, `accountAggregatesRemove` |
| `.bulkAdded(txs)` | per-tx `seriesIndexAdd` + `accountAggregatesAdd` |

On cold start (`loadData()`):
- `rebuildSeriesAndDateIndexes()` — one O(N_tx) walk over the loaded array.
- `rebuildAccountAggregates()` — one O(N_tx) walk.

On `updateBaseCurrency(_:)`: category aggregates rebuild (totals are in base currency); account aggregates are **not** affected because each account's aggregate is stored in the account's own currency.

On `bumpCurrencyRatesVersion()`: if any apply-time delta was applied while the FX cache was cold, both category and account aggregate maps rebuild from scratch.

## Currency semantics

`accountAggregatesByAccountId` stores `totalIncome` / `totalExpense` in **the owning account's currency**, NOT the base currency. Cross-currency transactions (different currency from the account) are converted at apply-time via `CurrencyConverter.convertSync(amount:from:to:)`. If the FX cache is cold the patch falls back to `tx.convertedAmount ?? tx.amount` — same fallback as the pre-refactor calculator — and a `bumpCurrencyRatesVersion` rebuild will heal it.

## AccountAggregatesCalculator API

```swift
// New, O(1) path — preferred everywhere that has a TransactionStore reference.
static func compute(accountId: String, store: TransactionStore) -> AccountAggregates

// Legacy nonisolated snapshot scan — for background consumers only.
nonisolated static func compute(
    accountId: String,
    accountCurrency: String,
    transactions: [Transaction]
) -> AccountAggregates
```

Both return byte-for-byte equivalent results for the same input. The store-backed path is read in `AccountDetailView.refreshData()`; the array path stays for Insights and tests.

## View-layer subscriptions

`AccountDetailView` subscribes to scalar mutation counters and never reads the full transactions array directly:

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

`accountsById` is a `@State` snapshot refreshed via `.task(id: accountsMutationVersion)`. Empty-state UI is **not** gated on the snapshot — gate on the source of truth (`store.accounts.contains(...)`) to avoid first-render flash. Same pattern as `CategoriesManagementView.hasCategoriesForCurrentType`.

## Account ranking

`AccountRankingService.suggestedAccount(forCategory:)` is the hot path for the "which account did the user last use for this category?" picker on the add-transaction screen. The store-backed call site (`AccountsViewModel.suggestedAccount`) now passes:

- `transactionsByAccount: store.transactionsByAccount` — replaces per-account `firstIndex(where:)` in the ranking loop.
- `transactionsByCategoryName: store.transactionsByCategoryName` — replaces `transactions.filter { $0.category == X && $0.type == .expense }`. Bucket is already filtered by name; the service only filters by type → O(M) where M is tx in the category.

The legacy `accounts: [Account]` parameter still exists for back-compat; internally we build a one-shot `accountById` map so the `accounts.first(where:)` lookups inside the loop are O(1).

### Transfer targets are pair-shaped, not per-account

⚠️ **Do NOT reuse `rankAccounts` to pick a transfer target.** It scores each account in isolation, so the globally busiest account always wins regardless of the selected source — the reason the transfer form used to insist on the wrong account ("Freedom deposit → Freedom card" kept suggesting a third account).

`AccountRankingService.suggestedTransferCounterpart(forSource:)` scores *counterparts of that specific source* from `.internalTransfer` history, with the same `Decay.tau` recency weighting. Incoming transfers count at `reverseDirectionWeight` (0.35) — still evidence the two accounts are paired, weaker evidence about where money goes when it leaves.

Call site: `AccountsViewModel.suggestedTransferTarget(forSource:)` → `AccountActionViewModel.defaultTargetAccountId(for:)`, which falls back to the carousel neighbour when there's no transfer history. Once the user picks a target themselves (`userPickedTarget`), source changes stop re-suggesting and only nudge on a source == target clash.

## Caveats

- `accountAggregatesByAccountId` is `@ObservationIgnored`; reads in a SwiftUI body must "touch" `transactionStore.mutationVersion` (or use the scalar refresh key pattern) to register a subscription.
- The aggregate map intentionally excludes `.income` transactions on the target leg (mirror of pre-refactor `AccountAggregatesCalculator` semantics) — an income tx targets the account that earned it, the calculator treats it as a single source-side credit.
- `transactionsByAccount` already contains BOTH source and target legs (a transfer appears under both accounts' buckets). Callers that need only one side must filter further.

## See also

- [docs/architecture.md](../architecture.md) — TransactionStore index pattern.
- [docs/domains/categories.md](categories.md) — sibling domain with the same index family (categoryAggregatesByKey).
- [docs/domains/transactions.md](transactions.md) — TransactionStore mutation funnel.
- [docs/domains/currency.md](currency.md) — `CurrencyConverter.convertSync` and the FX cache.
