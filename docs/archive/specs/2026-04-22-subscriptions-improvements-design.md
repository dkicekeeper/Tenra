# Subscriptions Improvements — Design

**Date:** 2026-04-22
**Scope:** 8 focused improvements to the subscriptions feature
**Primary files touched:** `RecurringTransaction.swift`, `SubscriptionTransactionMatcher.swift`, `SubscriptionEditView.swift`, `SubscriptionDetailView.swift`, `SubscriptionLinkPaymentsView.swift`, `TransactionStore` (series CRUD)

---

## 1. Quarterly Frequency

Add `.quarterly` case to `RecurringFrequency` in [Models/RecurringTransaction.swift](../../../Tenra/Models/RecurringTransaction.swift).

- Raw value: `"quarterly"`
- `nextDate`: `calendar.date(byAdding: .month, value: 3, to: date)`
- `displayName`: `String(localized: "frequency.quarterly")`
- Add localization keys to all `.lproj/Localizable.strings`
- Existing stored records unaffected (enum decoded by rawValue; unknown values already fall back in decoder)

## 2. Base-Currency Equivalent in SubscriptionEditView

Add a `ConvertedAmountView` below the hero amount row in `SubscriptionEditView`, shown only when `currency != appSettings.baseCurrency`. Mirrors the existing pattern in `SubscriptionDetailView.subscriptionInfoCard`. Reactive to both `amountText` and `currency` changes.

## 3. Matcher Tolerance Raised to ±30%

In `SubscriptionTransactionMatcher`:
- `defaultTolerance: Double = 0.30` (was 0.10)
- UI label on the toggle in link-payments header: `"±30%"` instead of `"±10%"`

Rationale: historical price drift (Apple Music 1450 → 1690 → 2290 KZT over 2 years ≈ ~58% range). ±30% covers typical annual price hikes; users who want tighter matching use the `Exact` toggle.

## 4. Cross-Currency Matching

Rewrite `SubscriptionTransactionMatcher.findCandidates` to convert subscription amount into each transaction's currency before comparison, using `CurrencyConverter`.

**New logic (per tx):**
1. Skip non-expense or already-linked.
2. Compute `subAmountInTxCurrency = convert(subscription.amount, from: subscription.currency, to: tx.currency)`.
3. Match if `tx.amount ∈ [subAmountInTxCurrency ± tolerance]`.
4. Fallback: also check `tx.convertedAmount` / `tx.targetAmount` against subscription amount in subscription currency (existing behavior, retained for multi-currency transfer records).

This fixes the case: $20 USD figma subscription → a KZT transaction of ~10000 KZT is now recognized via rate conversion.

## 5. "Spent All Time" Row in SubscriptionDetailView

Add an `InfoRow` in `subscriptionInfoCard` showing the sum of linked transaction amounts.

**Display rule:**
- Compute `totalInSubCurrency` (sum of `tx.convertedAmount` where available, else FX-converted `tx.amount` → `subscription.currency`)
- Primary line: total in `subscription.currency`
- If `subscription.currency != baseCurrency`: secondary converted line shown via `ConvertedAmountView` (same as the hero's amount treatment)

Reactive to `cachedTransactions` (already reloaded via `task(id:)`).

## 6. Select All / Deselect All in Link Payments

In `SubscriptionLinkPaymentsView` filter header, add a toolbar button (trailing nav bar) that toggles between "Select All" and "Deselect All" based on whether every item in `filteredCandidates` is already selected.

**Behavior:**
- Tap when not all selected → `selectedIds = Set(filteredCandidates.map(\.id))`
- Tap when all selected → `selectedIds.subtract(filteredCandidates.map(\.id))`

Placed as `ToolbarItem(placement: .topBarTrailing)` — visible in navigation bar alongside title.

## 7. Subscription Name → Subcategory

On save (both create and edit):

1. Resolve/create subcategory named `description` in `categoriesViewModel`:
   - Look up by case-insensitive name match in `categoriesViewModel.customSubcategories`
   - If absent → `categoriesViewModel.addSubcategory(name: description)` returns new `Subcategory`
2. Set `series.subcategory = description` (stored on `RecurringSeries`)
3. Link subcategory to all transactions of this series:
   - On create: link after `createSeries` returns (await the call, collect new tx ids)
   - On edit with propagation (see §8): link to affected tx ids

**Subcategory rename on description change:** if the subscription description changes during edit AND the old subcategory was previously auto-linked AND is not used by other subscriptions → rename the subcategory. Otherwise keep the old subcategory intact and create a new one for the new name.

## 8. Edit Propagation to Linked Transactions

Currently editing a subscription only updates the `RecurringSeries` record; existing generated transactions are untouched. Add a confirmation alert on edit save when any field that belongs to generated transactions has changed:

**Tracked fields:** `amount`, `currency`, `description`, `category`, `subcategory` (via §7), `accountId`, `iconSource`

**Alert:** `subscription.edit.propagate.title` = "Update linked transactions?"
**Actions:**
- **"Only subscription"** — save series only (current behavior)
- **"Future transactions"** — update series + transactions where `date >= today` AND `recurringSeriesId == series.id`
- **"All transactions"** — update series + all transactions with matching `recurringSeriesId` (destructive — warns with secondary alert message)
- **"Cancel"** — abort save

Implementation: new method `TransactionStore.updateSeriesAndOccurrences(series:scope:)` where `scope ∈ { .seriesOnly, .future, .all }`. Updates call into `TransactionRepository` on background context, then refresh in-memory state via the standard `apply(.updated)` pipeline in batch.

**Frequency/startDate changes** remain excluded from propagation — regeneration is handled by the existing `generateUpToNextFuture` pipeline.

---

## Non-Goals

- No migration to a separate subscription entity table.
- No batch editing of multiple subscriptions.
- No "auto-adjust subscription amount when linked tx differs" — one-directional only.

## Testing

- Unit: add `quarterly` frequency tests to `RecurringTransactionTests`.
- Unit: matcher with `from: USD, tx in: KZT` verifies FX-based match.
- Unit: edit propagation with each scope (`.seriesOnly`, `.future`, `.all`) — verify correct tx ids updated.
- Manual QA: build, open subscription, edit, confirm alert appears, verify each scope behavior on real data.

## Files Touched

| File | Change |
|------|--------|
| `Models/RecurringTransaction.swift` | add `.quarterly` |
| `Services/Recurring/SubscriptionTransactionMatcher.swift` | cross-currency conversion, 0.30 tolerance |
| `Views/Subscriptions/SubscriptionEditView.swift` | converted amount view, subcategory link on save, propagation alert |
| `Views/Subscriptions/SubscriptionDetailView.swift` | "Spent all time" InfoRow |
| `Views/Subscriptions/SubscriptionLinkPaymentsView.swift` | Select all/deselect all button, "±30%" label |
| `ViewModels/TransactionStore+Recurring*.swift` | `updateSeriesAndOccurrences` scoped method |
| `*.lproj/Localizable.strings` | new keys |

## Localization Keys (new)

- `frequency.quarterly` — "Quarterly" / "Ежеквартально"
- `subscription.linkPayments.selectAll` — "Select All" / "Выбрать все"
- `subscription.linkPayments.deselectAll` — "Deselect All" / "Снять выбор"
- `subscription.linkPayments.amountTolerance` — existing key repointed to "±30%"
- `subscriptions.spentAllTime` — "Spent all time" / "Потрачено за всё время"
- `subscription.edit.propagate.title` — "Update linked transactions?"
- `subscription.edit.propagate.message` — explanation
- `subscription.edit.propagate.seriesOnly` — "Only subscription"
- `subscription.edit.propagate.future` — "Future transactions"
- `subscription.edit.propagate.all` — "All transactions"
