# Recurring Transactions Domain

Series + occurrence model for subscriptions and recurring payments.

## Single-Next-Occurrence Model

- `generateUpToNextFuture()` — backfills all past occurrences + creates exactly **1 future occurrence**
- `extendAllActiveSeriesHorizons()` — called on `loadData` and foreground resume; collects EVERY series' backfill first, then persists via ONE `apply(.bulkAdded)` (a per-series apply ran one CoreData save + full FRC section rebuild per series — S main-thread hitches at cold start after N days away)

## Active vs Status

Two flags must be updated **in tandem**:

| Field | Controls |
|-------|----------|
| `isActive: Bool` | Gates occurrence generation |
| `status: SubscriptionStatus?` | Pause/Resume UI |

Both are updated by `stopSeries` / `resumeSeries`.

## Adding a `RecurringFrequency` Case

⚠️ **Touches 6+ files** — grep `case .monthly:` to audit all switch sites:

1. `Models/RecurringTransaction.swift`
2. `Services/Recurring/RecurringValidationService.swift`
3. `Services/Recurring/RecurringTransactionGenerator.swift` (2 switches)
4. `Services/Notifications/SubscriptionNotificationScheduler.swift`
5. `Services/Insights/InsightsService.swift` (2 switches)
6. `Services/Insights/InsightsService+Recurring.swift`

## Generator Linking — Subcategories

⚠️ **Fire-and-forget `createRecurringSeries()` is wrong** — generated txs are NOT in the store when `save()` returns.

Always `await transactionStore.createSeries(series)` directly when you need to act on generated transactions (e.g. link subcategories).

### Subcategory linking pattern

`Transaction.subcategory: String?` is legacy. Real subcats live via:

```swift
categoriesViewModel.linkSubcategoriesToTransaction(
    transactionId: ...,
    subcategoryIds: ...
)
```

Generated recurring txs need explicit linking after creation.

## Deprecated APIs

⚠️ **`getPlannedTransactions(horizon:)` deprecated** — filter `transactionStore.transactions` directly.

## TransactionStore Interaction

⚠️ **`TransactionStore.update()` blocks removing `recurringSeriesId`** — throws `cannotRemoveRecurring`.

To unlink (e.g. bulk unlink from subscription), use `apply(.updated(old: tx, new: updatedTx))` directly. See `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift`.

## SubscriptionTransactionMatcher

Accepts `AmountMatchMode` (`.all` / `.tolerance` / `.exact`) — defined in `Services/Recurring/SubscriptionTransactionMatcher.swift`.

Both `SubscriptionTransactionMatcher` and `LoanTransactionMatcher` conform; new matchers should follow the same signature to plug into `LinkPaymentsView`.

## Categories ViewModel Threading in Views

`SubscriptionDetailView` and `SubscriptionsListView` require `CategoriesViewModel` passed as parameter from `ContentView`.

## Link-Payments UI Reuse

UI wrapper: `SubscriptionLinkPaymentsView` — uses shared `LinkPaymentsView` (`Views/Components/LinkPayments/LinkPaymentsView.swift`).

⚠️ **Don't duplicate the state machine** — wrap `LinkPaymentsView` with `findCandidates` + `performLink` `@Sendable` closures. See also [loans.md](loans.md).
