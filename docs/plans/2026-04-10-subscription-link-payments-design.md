# Subscription Transaction Linking — Design

**Date:** 2026-04-10
**Status:** Approved

## Problem

Users who create a subscription (e.g. Netflix) often have months of manually entered expense transactions for that service. These historical transactions are not associated with the subscription because they were created before it. The user wants to retroactively link them.

## Approach

Set `recurringSeriesId` on existing transactions to point to the subscription. No type conversion, no accountId change — lightweight and non-destructive. Mirrors the loan link-payments UI pattern.

## New Files

### `Services/Recurring/SubscriptionTransactionMatcher.swift`

`nonisolated enum` with static method:

```swift
static func findCandidates(
    for subscription: RecurringSeries,
    in transactions: [Transaction],
    tolerance: Double = 0.10
) -> [Transaction]
```

Filters:
- `type == .expense`
- `currency == subscription.currency`
- `amount` within +/-10% of subscription amount
- `date >= subscription.startDate`
- `recurringSeriesId == nil` (not already linked to any series)
- Sorted chronologically

### `Views/Subscriptions/SubscriptionLinkPaymentsView.swift`

Mirrors `LoanLinkPaymentsView` layout:
- `let subscription: RecurringSeries`
- Dependencies: `categoriesViewModel`, `accountsViewModel`
- `@Environment(TransactionStore.self)` for transactions
- Searchable list with date sections, checkbox multi-select via `TransactionCard`
- Account filter chips when candidates span multiple accounts
- Action bar with "Link N Payments" button + progress + error banner
- Toolbar principal shows selected count + total amount

## Modified Files

### `TransactionStore+Recurring.swift`

New method:

```swift
func linkTransactionsToSubscription(
    seriesId: String,
    transactions: [Transaction]
) async throws
```

For each transaction: create updated copy with `recurringSeriesId = seriesId`, call `update()`. No type or account changes.

### `SubscriptionDetailView.swift`

Add to toolbar menu (after Edit, before Pause/Resume):

```swift
Button {
    showingLinkPayments = true
} label: {
    Label("Link Payments", systemImage: "link.badge.plus")
}
```

Navigation via `.navigationDestination(isPresented: $showingLinkPayments)` to `SubscriptionLinkPaymentsView`.

## What stays unchanged

- `SubscriptionDetailView.transactionsSection` — already filters by `recurringSeriesId == subscription.id`
- `TransactionCard`, `DateSectionHeaderView`, `UniversalFilterButton` — reused as-is
- No new transaction types, no CoreData model changes

## Reused from loan pattern

| Loan component | Subscription equivalent |
|---|---|
| `LoanTransactionMatcher` | `SubscriptionTransactionMatcher` |
| `LoanLinkPaymentsView` | `SubscriptionLinkPaymentsView` |
| `LoansViewModel.linkTransactions()` | `TransactionStore.linkTransactionsToSubscription()` |
