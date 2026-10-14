# Recurring Transactions Domain

Series + occurrence model for subscriptions and recurring payments.

## Single-Next-Occurrence Model

- `generateUpToNextFuture()`: backfills all past occurrences and creates exactly **1 future occurrence**
- `extendAllActiveSeriesHorizons()`: runs after `loadData` and on return to the foreground (reentrancy-guarded). It loads the FX rates a series in another currency than its account needs; a series still without a rate waits for the next pass ([currency.md](currency.md)). It then collects EVERY due series' backfill and persists it with ONE `apply(.bulkAdded)`: a CoreData save and history rebuild per series would stall the main thread at startup.

## Occurrence dates are anchored to the start

`RecurringDateMath` computes occurrence k as `start + k × period`, used by both the generator (`generateTransactions`, `generateUpToNextFuture`) and `SubscriptionNotificationScheduler`, so a series started on Jan 31 lands on Feb 28, then Mar 31, and reminders target the same days. Resuming after the latest stored occurrence goes to the NEXT period (`periodIndex + 1`, day ignored), so a series whose stored occurrences drifted never gets a second occurrence in the same month. Pinned by `RecurringDateMathTests` and the month-end cases in `RecurringTransactionGeneratorTests`.

## Active vs Status

Two flags must be updated **in tandem**:

| Field | Controls |
|-------|----------|
| `isActive: Bool` | Gates occurrence generation |
| `status: SubscriptionStatus?` | Pause/Resume UI |

Both are updated by `stopSeries` / `resumeSeries`.

## Adding a `RecurringFrequency` Case

⚠️ The switches over `series.frequency` (the compiler flags each, they are exhaustive):

1. `Models/RecurringTransaction.swift` (on the enum itself)
2. `Services/Recurring/RecurringValidationService.swift` (`case .daily, .weekly, .monthly, …`)
3. `Services/Recurring/RecurringTransactionGenerator.swift` (max iterations)
4. `Services/Recurring/RecurringDateMath.swift` (occurrence dates for the generator and the reminders)
5. `Services/Insights/InsightsService.swift` (2 switches)
6. `Services/Insights/InsightsService+Recurring.swift` (2 switches)

Other `case .monthly` hits (`CategoryBudgetService`, `InsightsService+Budget`, …) switch over a budget period, not a frequency.

## Generator Linking — Subcategories

⚠️ **Fire-and-forget `createRecurringSeries()` is wrong**: generated transactions are NOT in the store when it returns.

Always `await transactionStore.createSeries(series)` directly when you need to act on generated transactions (e.g. link subcategories).

### Subcategory linking pattern

`Transaction.subcategory: String?` is legacy. Real subcategories live in links:

```swift
categoriesViewModel.linkSubcategoriesToTransaction(
    transactionId: ...,
    subcategoryIds: ...
)
```

Generated recurring transactions need explicit linking after creation.

## Creating a subscription: one path

[`SubscriptionCreationService`](../../Tenra/Services/Recurring/SubscriptionCreationService.swift) creates a
subscription the way `SubscriptionEditView` always did, and the screen's create path and the
assistant's `draft_recurring` both go through it: the rate check for a series in another currency
than its account (`hasAccountRate`, no rate = no save), the series (`createSeries`, awaited), and
for a subscription the subcategory named after it, linked to its category and to every generated
transaction in one batch. A generic recurring payment gets the rate check and the series. The
screen's edit path reuses `resolveOrCreateSubcategory` and `linkSubcategory`. Pinned by
`SubscriptionCreationServiceTests`.

## Making an Existing Transaction Recurring

⚠️ **Never `createSeries(_:)` and then link an existing transaction to the new series.** The generator emits occurrence 0 on `startDate`, which is that transaction's own date, so the date would end up with two transactions. Use `createSeries(_:firstOccurrence:)`: it links the transaction, records it as the occurrence on `series.startDate`, and the generator resumes from the next period (generates nothing more when that date is already in the future). The transaction keeps its id, so its subcategory links survive. `TransactionEditCoordinator.handleRecurringSeries` uses it and aborts the save with the error if the series cannot be created. Pinned by `RecurringFirstOccurrenceTests` and `TransactionEditCoordinatorTests`.

The add screen saves no separate one-off when a frequency is picked: the generated occurrence on the chosen date is the user's transaction (plus the next occurrence ahead, per the single-next-occurrence model). Pinned by `TransactionAddCoordinatorTests`.

Occurrence records, not transaction ids, are what stop regeneration across launches: `TransactionIDGenerator` hashes with Swift's per-process `Hasher` seed, so the generator's `existingTransactionIds` check only matches ids made in the same process.

`TransactionStore.getPlannedTransactions(for:horizon:)` has no callers: to list a series' transactions, filter `transactionStore.transactions` (or use `transactionsBySeriesId`).

## TransactionStore Interaction

⚠️ **`TransactionStore.update()` blocks removing a LIVE `recurringSeriesId`**: throws `cannotRemoveRecurring`. Scope of the guard:
- it fires only when the old series still exists in `recurringStore.seriesById`. A **dangling** link (series deleted while its transactions survived) can be cleared; otherwise such a transaction could never be saved again (e.g. an auto-posted deposit-interest accrual, whose edit screen hides the recurring control and always saves `nil`).
- pass `update(tx, allowSeriesDetach: true)` for a deliberate unlink of a single transaction (the edit screen's explicit "Never"). Never pass it just to silence the error.
- ⚠️ A caller that rebuilds a `Transaction` MUST carry `recurringSeriesId` over. `TransactionEditCoordinator` only nils it when `transaction.type.allowsRecurring` **and** the user picked "Never"; for types whose recurring control is hidden it copies the existing link through. Pinned by `TransactionSeriesDetachTests`.

To unlink in bulk, apply one `.bulkUpdated` event, as `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift` does (it bypasses `update()`'s guard).

## Link-Payments UI and Matchers

`SubscriptionLinkPaymentsView` wraps the shared `LinkPaymentsView` with `SubscriptionTransactionMatcher`; the view, the matchers and `AmountMatchMode` are documented in [loans.md](loans.md) §Link-Payments UI.

## Categories ViewModel Threading in Views

`SubscriptionDetailView` and `SubscriptionsListView` take `CategoriesViewModel` as a parameter (`SubscriptionsListView` gets it from `FinancesView`).
