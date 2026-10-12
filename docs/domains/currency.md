# Currency / FX Rates Domain

Currency conversion and rate management (`Services/Currency/`).

## Architecture

```
CurrencyConverter (static facade, public API)
   ↓
CurrencyRateStore (lock-protected cache + UserDefaults persistence + CurrencyRatesNotifier)
   ↓
Services/Currency/Providers/* (CurrencyRateProviderChain)
       ↓
   JsDelivrCurrencyProvider (primary, jsDelivr CDN + Cloudflare mirror, 200+ currencies)
   NationalBankKZProvider (XML fallback, 8 currencies)
```

## Public API (`CurrencyConverter`)

- `convertSync(amount:from:to:)`: synchronous, cache only, hot-path safe; nil when a rate is missing
- `getExchangeRate(for:on:)`: async, fetches on a miss
- `convert(amount:from:to:on:)`: async conversion with fetch
- `getAllRates()`: full snapshot
- `prewarm()`: launch fetch
- `currentRatesAreFresh`: cache non-empty and under 24 h old

## `RateSnapshot` for bulk loops

⚠️ **Inside any walk over the transaction set, use [`RateSnapshot`](../../Tenra/Services/Currency/RateSnapshot.swift), not `convertSync`.** Take one before the loop, use it for every conversion inside, discard it after.

```swift
let rates = RateSnapshot()
for tx in transactions {
    let base = rates.convert(tx.amount, from: tx.currency, to: baseCurrency)
    …
}
```

1. **Lock traffic.** `convertSync` takes `CurrencyRateStore`'s `NSLock` twice per call (once per currency): 38 000 acquisitions per 19k pass, plus memory barriers that stop the optimiser hoisting anything out of the loop. Several such walks run concurrently on detached tasks at launch, so the lock is contended.
2. **Consistency.** `convertSync` reads live state: a prewarm response landing mid-loop converts part of the set at old rates and the rest at new ones. `aggregatesAreFXStale` catches a *cold* cache, not this. A snapshot pins one rate table for the whole computation.

`convert` returns `nil` on a missing rate exactly like `convertSync`, so callers keep their fallback and FX-stale flagging. `CategoryBudgetCurrency.toBase(amount:from:base:rates:)` is the snapshot-taking overload that keeps the `usedStaleFallback` contract. Single conversions keep calling `convertSync`.

Bulk call sites: `SummaryCalculator.compute` / `computeTopExpenseWeights`; `TransactionStore+LoadSnapshot` (`computeCategoryAggregates`, `computeAccountAggregates`); `TransactionStore.rebuildAccountAggregates`, `rebuildCategoryIndexes`, `runRealizedAggregatesRebuild`, `rollBackLoanPayment`; `TransactionCategoryPickerCoordinator.computeCategoryExpenses`; `InsightsService.generateBudgetInsights` (→ `CategoryBudgetService.calculateSpentLegacy(rates:)`); `InsightsViewModel.categoryDeepDivePages`; the loan month statuses (`LoansListView`, `LoanDetailView`).

## KZT-Pivot Storage

⚠️ **Internal storage is always KZT-pivot**: `cachedRates[X] = "KZT per 1 X"`.

KZT itself is implicit (1.0) and is **NEVER a key** in the dict.

Providers with a different native pivot (jsDelivr = USD) re-pivot via `ExchangeRates.normalized(toPivot: "KZT")` before reaching the store, so a new provider returns whatever pivot is natural to it.

## Persistence

Persisted to UserDefaults under key `currency.rates.cache.v1`.

`CurrencyRateStore.init()` restores synchronously so `convertSync` works at T=0 on warm launch.

⚠️ **Bump the key version** when changing the on-disk format.

## Pre-Warm Behavior

`CurrencyConverter.prewarm()` runs on a detached task in parallel with `loadData()` in `AppCoordinator.initialize()`.

- Idempotent: skipped when `hasFreshRates` (cache under 24 h old)
- The wait for it is capped at **2.5 s via a `withTaskGroup` race** so a slow network never holds up the rest of startup
- After the wait, `bumpCurrencyRatesVersion()` and `transactionsViewModel.invalidateCaches()` run only when the cache was not fresh at launch

⚠️ **Keep the cap**: rates that land after it reach every consumer through the observer below.

## Reactivity for `convertSync` Consumers

Every rate update bumps `CurrencyRatesNotifier.shared.version` (`@Observable`). `AppCoordinator.startObservingCurrencyRateChanges` reacts with `transactionStore.bumpCurrencyRatesVersion()` (bumps the observable `currencyRatesVersion` and rebuilds aggregates flagged FX-stale, followed by `balanceCoordinator.recalculateAll` when it did), `transactionsViewModel.invalidateCaches()` and `insightsViewModel.invalidateAndRecompute()`.

Views that aggregate with converted amounts fold the version into their `.task(id:)` key, e.g.:
- `ContentView.SummaryTrigger`
- `AccountDetailView.refreshTrigger`
- `CategoryDetailView.RefreshKey`
- `GroupedTransactionList.SectionsKey` (day totals; reads `CurrencyRatesNotifier.shared.version`, plus each account's currency)

⚠️ **Adding a new aggregator that reads `convertSync`**: fold `currencyRatesVersion` into its `.task(id:)` key.

## Per-Transaction Amount Aggregation

⚠️ **`Transaction.convertedAmount` is denominated in the *account*'s currency**, not the app's base currency: it is the `tx.currency → accountCurrency` conversion captured when the transaction was saved.

So **summing `convertedAmount ?? amount` across multi-currency transactions is wrong** when the result is meant to be in base currency (`$20 + $100 = "120 KZT"` in day totals, budget progress, insights).

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
    // Last-resort fallback: rate cache cold. Wrong unit, but self-corrects once
    // rates land and the caches invalidate.
    amountInBase = tx.convertedAmount ?? tx.amount
}
```

Used by `TransactionCurrencyService`, `SummaryCalculator`, `CategoryBudgetService`, `InsightsService.resolveAmount` / `resolveAmountStatic` / `resolveAmountToBase`, `GroupedTransactionList` and `LinkPaymentsView` (`amountInBaseCurrency` for the selected total, an inline closure for its list's `summaryAmountFor`).

### Writing the conversion fields: `TransactionConversion`

Every path that creates or rewrites a transaction's `convertedAmount` / `targetCurrency` / `targetAmount` goes through [`TransactionConversion`](../../Tenra/Services/Transactions/TransactionConversion.swift) (add screen, edit screen, recurring occurrences, subscription edits):

| Case | `convertedAmount` | `targetCurrency` / `targetAmount` |
|------|-------------------|-----------------------------------|
| one account, tx currency ≠ account | amount in account currency | account currency / same value (the row's equivalent) |
| one account, tx currency = account ≠ base | nil | base currency / base value (display only) |
| transfer | amount in SOURCE account currency, nil when the transfer is entered in it | target account currency / what it receives |

- ⚠️ **A missing rate refuses the save** (`currency.error.conversionFailed`) on user-driven paths: add, edit, transfer (`AccountActionViewModel`), voice (`ConversionPolicy.provided(nil)` is `.needsFXConversion`), subscription save, loan payments; saved without a conversion, the balance would move by the raw foreign amount. Try the cache first (`TransactionConversion.cachedRate`), load rates (`loadRates`) only on a miss.
- **Recurring occurrences**: `extendAllActiveSeriesHorizons` loads the missing rates first, and a series whose occurrence still has no rate waits for the next pass instead of posting (`TransactionStore+Recurring.swift`, `seriesMissingRate`).
- **Edits keep the stored rate** (`TransactionConversion.storedRate`): a currency pair the transaction already holds a conversion for is scaled by the new amount instead of re-priced at today's rate, so editing only the description changes nothing, and an import's bank figure survives.
- Loan payments are in the loan's currency; `LoansViewModel.convertingSourceLeg` sets `convertedAmount` for a paying card in another currency, and the payment forms convert an amount typed in another currency (`LoanPaymentService.amountInLoanCurrency`).
- Transfers created from an account (`AccountActionViewModel`) store the source leg as `convertedAmount` too (`TransactionStore.transfer(convertedAmount:)`).
- Imports write them too: CSV through [`CSVConversionColumns`](../../Tenra/Services/CSV/CSVConversionColumns.swift) (column contract in [csv.md](csv.md)); a statement import that merges a row into a saved expense/income keeps that transaction's conversion on its leg (`ImportCommitPlanner`, `ImportRowDecision.transferAccountCurrency`), so the saved side's account stays moved by what the engine already counted (`TransactionConversion.balanceAmount`).
- Pinned by `TransactionConversionTests`, `TransactionCurrencyEditTests`, `RecurringOccurrenceCurrencyTests`, `LoanPaymentCurrencyTests`, `LinkPaymentsSelectedTotalTests`, `TransactionDraftResolverTests.providedNilConversionBlocks`.

### Reading the fields: `TransactionConversion`

Some rows carry only `convertedAmount`: Siri / App Intents drafts (`TransactionDraftService`), income added from an account (`AccountActionViewModel`), statement and CSV imports, and rows saved by older app versions; the engine reads `targetAmount`, then `convertedAmount`, whatever their label. Three read rules, all in `TransactionConversion`:

| Rule | Used by | What it returns |
|------|---------|-----------------|
| `displayedEquivalent(of:accountCurrency:)` | the row's "≈" line (`TransactionCardView`), CSV export | `targetAmount` in `targetCurrency` when it is another currency than the transaction's; else, with no `targetAmount`, `convertedAmount` in the account's currency. Nil for transfers (`TransferAmountView` shows both legs). |
| `recordedAmount(of:inAccountCurrency:)` | account-detail totals (`accountAggregatesByAccountId`, cold rebuild included), day totals of an account's history (`GroupedTransactionList`) | what the transaction moved its account by, as recorded: the amount in that currency, else `targetAmount` labelled with it, else `convertedAmount` unless `targetCurrency` names a third currency (an account whose currency changed after the save). A transfer's source leg is its `convertedAmount`. Nil means "convert at today's rate". |
| `balanceAmount(of:inAccountCurrency:)` | the statement-import merge | exactly `BalanceCalculationEngine.getTransactionAmount`: for code that must leave a balance where the engine put it and can't call the MainActor engine. |

- ⚠️ **Account-detail totals count the recorded conversion, not today's rate**, so "Total expense" agrees with the balance. Today's rate is only the fallback for a transaction without a conversion into the account's currency. `accountAggregatesUpdate` re-patches on `convertedAmount` and `date` changes too.
- `TransactionStore.accountAggregatesRuleVersion` (UserDefaults `accountAggregates.ruleVersion`, written by a flush after the full load) makes the next full load rebuild totals saved under an older rule. Bump it whenever the valuation of a leg changes.
- Pinned by `TransactionConversionReadingTests`, `AccountAggregatesRecordedConversionTests`, `ImportCommitterTests.mergeKeepsTheSavedSidesConversion*`.

### When `convertedAmount` IS the right field

- **Balance updates** (`BalanceCalculationEngine.getSourceAmount` / `getTargetAmount`): per account, in account currency.
- **Deposit principal walk** (`DepositInterestService.principalDelta`): runs in deposit currency (see [deposits.md](deposits.md)).
- **Single transaction display** (`TransactionCardView`, `TransactionConversion.displayedEquivalent`): the "≈" line shows the tx in its account's currency.
- **Account-detail totals** (`TransactionConversion.recordedAmount`): in the account's own currency, the recorded value is what the balance moved by.

The aggregation pattern depends on the rate cache being populated; after a cold launch the `currencyRatesVersion` trigger above recomputes it.

## In-Flight De-Duplication

Concurrent fetches for the same day share one `Task` through the `inflight` dict (keyed by the date, or `__today__` for current rates) in `fetchRatesDeduped`: **never bypass it**.

## Test Isolation

⚠️ `CurrencyRateStore.shared` persists across test runs via UserDefaults.

Tests that assert `convertSync` returns nil (cross-currency matchers, e.g. `SubscriptionTransactionMatcherTests.findCandidates_matchesCrossCurrencyViaConvertedAmount`) MUST call `CurrencyRateStore.shared.clearAll()` in their suite `init()`; otherwise rates leaked from a previous suite cause spurious matches within the 30% default tolerance.
