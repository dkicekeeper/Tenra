# Currency / FX Rates Domain

Three-file split for currency conversion and rate management.

## Architecture

```
CurrencyConverter (static facade, public API)
   ↓
CurrencyRateStore (lock-protected cache + UserDefaults persistence + CurrencyRatesNotifier)
   ↓
Services/Currency/Providers/* (CurrencyRateProviderChain)
       ↓
   JsDelivrCurrencyProvider (primary, jsDelivr CDN + Cloudflare mirror, 200+ currencies)
   NationalBankKZProvider (legacy XML fallback, 8 currencies)
```

## Public API (`CurrencyConverter`)

- `convertSync(_:from:to:)` — synchronous, hot-path safe (uses cached rates)
- `getExchangeRate(date:)` — async with in-flight de-duplication
- `convert(_:from:to:date:)` — async with rate fetch
- `getAllRates()` — full snapshot
- `prewarm()` — runs on app init

## `RateSnapshot` — for bulk loops

⚠️ **Inside any walk over the transaction set, use [`RateSnapshot`](../../Tenra/Services/Currency/RateSnapshot.swift), not `convertSync`.** Take one before the loop, use it for every conversion inside, discard it after.

```swift
let rates = RateSnapshot()
for tx in transactions {
    let base = rates.convert(tx.amount, from: tx.currency, to: baseCurrency)
    …
}
```

Two reasons, the second more important than the first:

1. **Lock traffic.** `convertSync` takes `CurrencyRateStore`'s `NSLock` twice per call (once per currency) — 38 000 acquisitions per 19k pass, plus memory barriers that stop the optimiser hoisting anything out of the loop. Several such walks run concurrently on detached tasks at launch, so the lock is genuinely contended.
2. **Consistency.** `convertSync` reads live state. A prewarm response landing mid-loop converts the first half of the set at old rates and the second half at new ones, producing a total that corresponds to no point in time. `aggregatesAreFXStale` catches a *cold* cache, not this. A snapshot pins one rate table for the whole computation.

`convert` returns `nil` on a missing rate exactly like `convertSync`, so callers keep their documented fallback and FX-stale flagging. `CategoryBudgetCurrency.toBase(amount:from:base:rates:)` is the snapshot-taking overload that preserves the `usedStaleFallback` contract.

Single conversions should keep calling `convertSync` — there are hundreds and they gain nothing.

Current bulk call sites: `SummaryCalculator.compute` / `computeTopExpenseWeights`, `TransactionStore+LoadSnapshot`'s cold aggregate rebuilds, the Home category grid (`TransactionCategoryPickerCoordinator.computeCategoryExpenses`), Insights budgets (`generateBudgetInsights` → `CategoryBudgetService.calculateSpentLegacy(rates:)`).

## KZT-Pivot Storage

⚠️ **Internal storage is always KZT-pivot**: `cachedRates[X] = "KZT per 1 X"`.

KZT itself is implicit (1.0) and is **NEVER a key** in the dict.

Providers with a different native pivot (jsDelivr=USD) re-pivot via `ExchangeRates.normalized(toPivot: "KZT")` before reaching the store.

**Adding a new provider** — return whatever pivot is natural; the store handles re-pivoting.

## Persistence

Persisted to UserDefaults under key `currency.rates.cache.v1`.

`CurrencyRateStore.init()` restores synchronously so `convertSync` works at T=0 on warm-launch.

⚠️ **Bump the key version** when changing the on-disk format.

## Pre-Warm Behavior

`CurrencyConverter.prewarm()` runs in parallel with `loadData()` in `AppCoordinator.initialize()`.

- Idempotent — skipped when `hasFreshRates` (cache <24h)
- The wait is capped at **2.5s via `withTaskGroup` race** so a slow network never blocks `isFullyInitialized`

⚠️ **Don't remove the cap** — the post-prewarm `invalidateAndRecompute()` re-fires once rates land asynchronously.

## Reactivity for `convertSync` Consumers

`transactionStore.currencyRatesVersion: Int` (`@Observable`) bumps after prewarm.

Aggregator views with `.task(id:)` include it in their trigger so per-currency totals recompute when rates land:
- `ContentView.SummaryTrigger`
- `AccountDetailView.refreshTrigger`
- `CategoryDetailView.RefreshKey`

⚠️ **Adding a new aggregator that reads `convertSync`** — fold `currencyRatesVersion` into its `.task(id:)` key.

## Per-Transaction Amount Aggregation

⚠️ **`Transaction.convertedAmount` is denominated in the *account*'s currency**, not the app's base currency. The field stores `tx.currency → accountCurrency` conversion captured at creation time.

This means **summing `convertedAmount ?? amount` across multi-currency transactions is wrong** when the result is meant to be in base currency — bug shows as `$20 + $100 = "120 KZT"` in History day-totals, budget progress, insights aggregations, etc.

### Canonical aggregation pattern

```swift
let amountInBase: Double
if tx.currency == baseCurrency {
    amountInBase = tx.amount
} else if let fx = CurrencyConverter.convertSync(
    amount: tx.amount,
    from: tx.currency,
    to: baseCurrency
) {
    amountInBase = fx
} else {
    // Last-resort fallback: rate cache cold (rare). Wrong unit, but matches
    // legacy behaviour and self-corrects once rates land + cache invalidates.
    amountInBase = tx.convertedAmount ?? tx.amount
}
```

This is the pattern enforced in `TransactionCurrencyService`, `SummaryCalculator`, `CategoryBudgetService`, `InsightsService.resolveAmount(Static)`, `GroupedTransactionList`, `LinkPaymentsView.summaryAmountFor` and `LinkPaymentsView.amountInBaseCurrency` (the selected total, which used to prefer `convertedAmount`).

### Writing the conversion fields: `TransactionConversion`

Every path that creates or rewrites a transaction's `convertedAmount` / `targetCurrency` / `targetAmount` goes through [`TransactionConversion`](../../Tenra/Services/Transactions/TransactionConversion.swift) (add screen, edit screen, recurring occurrences, subscription edits):

| Case | `convertedAmount` | `targetCurrency` / `targetAmount` |
|------|-------------------|-----------------------------------|
| one account, tx currency ≠ account | amount in account currency | account currency / same value (the row's equivalent) |
| one account, tx currency = account ≠ base | nil | base currency / base value (display only) |
| transfer | amount in SOURCE account currency, nil when the transfer is entered in it | target account currency / what it receives |

- ⚠️ **A missing rate refuses the save** (`currency.error.conversionFailed`) on user-driven paths: add, edit, transfer (`AccountActionViewModel`), voice (`ConversionPolicy.provided(nil)` is `.needsFXConversion`), subscription save, loan payments. Saved anyway, the balance moved by the raw foreign amount. Try the cache first (`TransactionConversion.cachedRate`), load rates (`loadRates`) only on a miss. Recurring generation can't refuse: on a cold cache it still stores nothing.
- **Edits keep the stored rate** (`TransactionConversion.storedRate`): a currency pair the transaction already holds a conversion for is scaled by the new amount instead of re-priced at today's rate, so editing only the description changes nothing, and an import's bank figure survives.
- Loan payments are in the loan's currency; `LoansViewModel.convertingSourceLeg` sets `convertedAmount` for a paying card in another currency, and the payment forms convert the amount typed in another currency (`LoanPaymentService.amountInLoanCurrency`).
- Transfers created from an account (`AccountActionViewModel`) store the source leg as `convertedAmount` too (`TransactionStore.transfer(convertedAmount:)`).
- Pinned by `TransactionConversionTests`, `TransactionCurrencyEditTests`, `RecurringOccurrenceCurrencyTests`, `LoanPaymentCurrencyTests`, `LinkPaymentsSelectedTotalTests`, `TransactionDraftResolverTests.providedNilConversionBlocks`.

### When `convertedAmount` IS the right field

- **Balance updates** (`BalanceCalculationEngine.getSourceAmount` / `getTargetAmount`) — operates per-account, in account currency. `convertedAmount` is exactly the source-account-denominated value needed.
- **Deposit principal walk** (`DepositInterestService.principalDelta`) — runs in deposit currency; for inflow side `convertedAmount` is already in target currency (the deposit itself).
- **Single transaction display** (`TransactionCardComponents`) — shows the tx in its account's currency.

### Pre-warm reactivity

The aggregation pattern depends on `CurrencyConverter`'s cache being populated. After a cold launch, fold `transactionStore.currencyRatesVersion` into `.task(id:)` triggers — see "Reactivity for `convertSync` Consumers" below.

## In-Flight De-Duplication

Concurrent `getExchangeRate` calls for the same date share one `Task` via the `inflight` dict keyed by date — **never bypass this**.

## Test Isolation

⚠️ `CurrencyRateStore.shared` persists across test runs via UserDefaults.

Tests that assert `convertSync` returns nil (cross-currency matchers, e.g. `SubscriptionTransactionMatcherTests.findCandidates_matchesCrossCurrencyViaConvertedAmount`) MUST call `CurrencyRateStore.shared.clearAll()` in their suite `init()`.

Otherwise leaked rates from a previous suite cause spurious matches within the 30% default tolerance.
