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
7. `Services/Recurring/SubscriptionChargeMatcher.swift` (`realChargeWindowDays`)

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

## Looks like a subscription

The subscriptions screen offers up to five merchants that charge about once a month and no
series tracks ([`SubscriptionCandidateDetector`](../../Tenra/Services/Recurring/SubscriptionCandidateDetector.swift),
run off the main actor over the whole history): grouped by normalized merchant and currency, the
latest charges, at least three, follow each other every 26 to 35 days, each within 15 % of the
latest amount, and the latest is at most 40 days old. A second charge inside the month breaks the
run, so a shop visited weekly never qualifies. Only one-off expenses count (no `recurringSeriesId`).
A merchant sharing a brand word with any series description is skipped, the billing company
included (`WalletPaymentResolver.billedWords`: "iCloud+" covers "APPLE.COM/BILL").

Tapping a candidate opens `SubscriptionEditView(draft:)`: the latest amount, category, account,
the merchant's clean name and logo (`MerchantLogoStore`), and the next expected charge as
`startDate`, so the generator records nothing that is already in the history. "Not a
subscription" (context menu) stores the normalized merchant in `SubscriptionCandidateDismissals`
(UserDefaults), and so does saving the draft (`SubscriptionEditView.onCreated`): a renamed
subscription shares no word with the merchant, and its charges stay one-offs. The draft's amount
goes through its text (`Decimal(string:)`), never `Decimal(Double)`'s binary noise. The refresh key holds `mutationVersion`, every series description and today's
date. Pinned by `SubscriptionCandidateDetectorTests`.

## Real charges

A subscription records its charge ahead (the planned occurrence); the bank reports the real one
(Apple Pay, a bank's notification, an expense entered by hand). One charge stays one transaction:
the real charge is **merged into the planned one**. The occurrence keeps its id, series,
occurrence record, category, name and subcategory links, and takes the real amount, currency,
conversion, date and account (`SubscriptionChargeMatcher.merged`); the real charge is never saved
or is deleted. ⚠️ `targetCurrency`/`targetAmount` come from the real charge too, never the planned
ones: the balance reads `targetAmount` first whenever the currency is not the account's. The
series itself is never touched (red flag 10).

Which planned charge a real one is (`SubscriptionChargeMatcher.match`), within three days of the
planned date, the closest first, never one already taken (`WalletCaptureStore.isMatched`):

1. the subscription remembered for the merchant (`SubscriptionMerchantMemory`, normalized
   merchant → series id), within 30 %;
2. a brand word the merchant shares with the subscription (`WalletPaymentResolver.billedWords`:
   "NETFLIX.COM" and "Netflix", "APPLE.COM/BILL" and "iCloud+"), within 5 % in the same currency,
   10 % across currencies (against the planned account-currency amount when the bank charged in
   the account's currency, else at the cached rate);
3. otherwise the same amount is only a **suggestion**: the payment is recorded and To review asks
   "Looks like X" (Merge, or ✕: never asked again for that merchant). Never for a bank's transfer
   to a person, a merchant remembered for another subscription, or no merchant.

Any account: the real account wins, except when the card's account was only a guess (then the
subscription's). An intent's process holds no history, so a confident match from an automation is
queued (`WalletCaptureStore.chargeMerges`) and applied once the full load lands
(`SubscriptionChargeLinker.applyPending`, one pass at a time, run by the intent when the app is
loaded and by `MainTabView` on the foreground and after the full load). The intent saved nothing
else for the payment, so a queued charge whose planned charge is gone or cannot be updated is saved
as an expense of its own. A reviewed capture under the planned charge's id makes the other
source's report of the same payment a duplicate.

**By hand** (`SubscriptionChargeLinker.link`): "This is a subscription…" in the repeat menu of an
expense's edit screen (`SubscriptionChargePickerView`, subscriptions closest by amount first),
Link payments on the subscription's screen (`linkAll`) and "Merge" in To review. The nearest
generated occurrence within half the period (`RecurringFrequency.realChargeWindowDays`) takes the
expense's values and the expense is deleted (its capture moves to the planned charge); with none
near, the expense is linked as it is. Which planned charges already hold a real one is known for
`WalletCaptureStore.retention` (90 days, on the device) only, so an expense older than that is
linked, never merged. The merchant (the capture's, else the description) is remembered for the
subscription. Pinned by
`SubscriptionChargeMatcherTests` and `SubscriptionChargeLinkerTests`.

## Making an Existing Transaction Recurring

⚠️ **Never `createSeries(_:)` and then link an existing transaction to the new series.** The generator emits occurrence 0 on `startDate`, which is that transaction's own date, so the date would end up with two transactions. Use `createSeries(_:firstOccurrence:)`: it links the transaction, records it as the occurrence on `series.startDate`, and the generator resumes from the next period (generates nothing more when that date is already in the future). The transaction keeps its id, so its subcategory links survive. `TransactionEditCoordinator.handleRecurringSeries` uses it and aborts the save with the error if the series cannot be created. Pinned by `RecurringFirstOccurrenceTests` and `TransactionEditCoordinatorTests`.

The add screen saves no separate one-off when a frequency is picked: the generated occurrence on the chosen date is the user's transaction (plus the next occurrence ahead, per the single-next-occurrence model). Pinned by `TransactionAddCoordinatorTests`.

Occurrence records, not transaction ids, are what stop regeneration across launches: `TransactionIDGenerator` hashes with Swift's per-process `Hasher` seed, so the generator's `existingTransactionIds` check only matches ids made in the same process.

`TransactionStore.getPlannedTransactions(for:horizon:)` has no callers: to list a series' transactions, filter `transactionStore.transactions` (or use `transactionsBySeriesId`).

## Subscriptions order

`RecurringSeries.order` (optional, CoreData v16): the person's place for a subscription, set by
dragging in `SubscriptionsListView` (`TransactionStore.reorderSubscriptions` →
`RecurringStore.reorderSeries`). `TransactionStore.subscriptions` puts the placed ones first by
`order`, the rest after them as they were added.

## TransactionStore Interaction

⚠️ **`TransactionStore.update()` blocks removing a LIVE `recurringSeriesId`**: throws `cannotRemoveRecurring`. Scope of the guard:
- it fires only when the old series still exists in `recurringStore.seriesById`. A **dangling** link (series deleted while its transactions survived) can be cleared; otherwise such a transaction could never be saved again (e.g. an auto-posted deposit-interest accrual, whose edit screen hides the recurring control and always saves `nil`).
- pass `update(tx, allowSeriesDetach: true)` for a deliberate unlink of a single transaction (the edit screen's explicit "Never"). Never pass it just to silence the error.
- ⚠️ A caller that rebuilds a `Transaction` MUST carry `recurringSeriesId` over. `TransactionEditCoordinator` only nils it when `transaction.type.allowsRecurring` **and** the user picked "Never"; for types whose recurring control is hidden it copies the existing link through. Pinned by `TransactionSeriesDetachTests`.

To unlink in bulk, apply one `.bulkUpdated` event, as `unlinkAllTransactions(fromSeriesId:)` in `TransactionStore+Recurring.swift` does (it bypasses `update()`'s guard).

## Link-Payments UI and Matchers

`SubscriptionLinkPaymentsView` wraps the shared `LinkPaymentsView` with `SubscriptionTransactionMatcher`; the view, the matchers and `AmountMatchMode` are documented in [loans.md](loans.md) §Link-Payments UI. Linking goes through `SubscriptionChargeLinker.linkAll`: each payment takes the place of its period's planned charge (§Real charges), so a linked charge is never there twice.

## Categories ViewModel Threading in Views

`SubscriptionDetailView` and `SubscriptionsListView` take `CategoriesViewModel` as a parameter (`SubscriptionsListView` gets it from `FinancesView`).
