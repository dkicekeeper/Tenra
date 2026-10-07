# Loans Domain

Payment tracking, manual payments, linking, and amortization.

## Persistence

`LoanInfo` persisted via `loanInfoData: Data?` (JSON-encoded Binary) on `AccountEntity` (CoreData v6) — mirrors [DepositInfo pattern](deposits.md).

## LoanPaymentService

`nonisolated enum` providing:
- annuity formula
- amortization schedule
- payment breakdown
- early repayment
- linking-recalc helpers

## Auto-Calculate `monthlyPayment`

`LoanInfo.init` auto-calculates `monthlyPayment` when `nil` is passed.

⚠️ **Pass `nil` to force recalculation** after principal/rate/term changes.

## No Auto-Reconciliation

Loan payments are **never** generated automatically. The user records every payment manually via `makeManualPayment` (or links an existing expense via `LoanLinkPaymentsView`).

Rationale: real-world loan payments rarely match the calculated annuity exactly (users round up, pay early, vary amounts). Auto-generated phantom payments diverged from real bank withdrawals and confused state. Deposits still auto-reconcile interest accrual — only loans are user-driven.

## Amortization schedule replay

`generateAmortizationSchedule` replays the loan from `originalPrincipal`, applying early repayments in
date order with the monthly payment that was in force in each month. `applyEarlyRepayment` records
`EarlyRepayment.paymentBefore`; repayments recorded before 2026-09-24 have it nil and the replay
recomputes it exactly as `applyEarlyRepayment` did. Before this, every month was replayed with the
CURRENT payment, so after a "reduce payment" repayment all earlier rows were wrong and
`LoansViewModel.markPaymentsPaid` (which copies `remainingBalance` / interest from the rows) wrote a
wrong `remainingPrincipal`. `nextPaymentDate` clamps the payment day inside each month separately
(day 31 → Feb 28 → Mar 31) and returns today when the payment is due today.
Pinned by `LoanScheduleReplayTests`.

## Paid-off Lifecycle

A loan is **closed** when `LoanInfo.isPaidOff` — i.e. `remainingPrincipal <= LoanInfo.paidOffThreshold` (0.01). There is **no persisted closed flag**: the status is derived so it can never drift from the balance when a payment is edited, unlinked, or the amount is corrected. Threshold rather than `<= 0` because annuity rounding and FX leave sub-cent residue on the final payment, which would pin a loan "active" at a displayed debt of 0.00 forever.

Convenience accessors on `Account`: `isPaidOffLoan`, `isActiveLoan` (both `false` for non-loan accounts).

⚠️ **Every loan aggregate must read `LoansViewModel.activeLoans`, not `loans`.** A closed loan contributes 0 debt but keeps a non-zero `monthlyPayment` forever — summing `loans` inflates "Monthly" and the active count. Current call sites: `LoansListView.loansSummary`, `LoansListView.currentMonthStatuses`, `LoansListView.activeLoans` (Pay All), `LoansCardView`. `LoansCardView` deliberately keys its empty state on `loans.isEmpty` (any loans at all) so a user whose loans are all paid off still sees the card.

Closed loans surface in `LoansListView` under a collapsed "Closed" `DisclosureGroup`, below the active cards and outside the type filter's card list (`filteredClosedLoans` applies the same type filter separately).

`LoanDetailView` when closed: `primaryAction`/`secondaryAction` are `nil` (paying a zero balance would drive `remainingPrincipal` negative and silently reopen the loan), "Change Rate" is hidden, the hero subtitle becomes "Closed <date>" (from `lastPaymentDate`), and a one-shot success banner fires on the `false → true` edge of `isPaidOffLoan`. The amortization schedule and payment history stay fully readable.

## This Month's Payment Status

`LoanMonthStatusService` (pure, `Services/Loans/`) gives each active loan `LoanMonthStatus`: `.paid(nextDueDate:)` or `.unpaid(dueDate:isOverdue:)`, shown by `LoanMonthStatusBadge` under the type badge in `LoanCard` and in the `LoanDetailView` hero. Pinned by `LoanMonthStatusTests`.

- **Paid** = this month's payments add up to the month's amount due (owner's rule, 2026-10-07: by the sum of the operations, not by one operation). The sum covers every `.loanPayment` **and** `.loanEarlyRepayment` with `targetAccountId == loan.id` dated from the 1st through today (future-dated rows are not realized), each in the loan's currency via `LoanPaymentService.recordedPayment`: a payment in another currency converts through the conversion it was saved with (`TransactionConversion.storedRate`: the row's equivalent, or the paying account's leg when that account is in the loan's currency), else at `RateSnapshot`, else unconverted (red flag 6: never `convertedAmount ?? amount` as is). Paid when `amountDue - sum <= LoanInfo.paidOffThreshold`.
- **Amount due** = `amountDue(info, remainingPrincipal:)`: the monthly payment capped at what was owed when the month began plus its interest. "Owed when the month began" is `remainingPrincipal` with this month's payments undone (`LoanPaymentService.remainingBefore`), so paying the last 12 000 in two halves still asks for 12 000 instead of re-capping at what is left after the first half.
- **Partial payments** leave the month `.unpaid(…, leftToPay:)`, `leftToPay` = amount due minus this month's payments, in the loan's currency. The badge still says "Not paid".
- **"Mark as paid"** in the schedule (payments made outside the app, no transaction) makes the month paid through `LoanInfo.markedPaidThrough` (the date of the last row marked paid, written only by `LoansViewModel.markPaymentsPaid`, nil after a reset to nothing paid) on or after the 1st. Marked through a later row, the months up to it are paid too. `lastPaymentDate` plays **no** part any more: payments write it as well, so a partial or deleted payment left the month "Paid". ⚠️ Marks made before 2026-10-07 have no `markedPaidThrough` (it can't be told apart from a payment's `lastPaymentDate`): such a month shows "Not paid" until the row is marked again (Mark as unpaid, then Mark as paid). Stored in the `loanInfoData` JSON, no CoreData schema change.
- **No status (nil)**: paid off, not started (payment `i` falls `startDate + i` months, so payment #1 is the month after the start month), or past the last scheduled month (`termMonths`). These loans are not counted.
- **Due date**: `paymentDay` clamped to the month's length. `nextDueDate` (this month's while unpaid, even when overdue; next month's once paid) replaces `nextPaymentDate` in the card footer and hero subtitle, so a paid loan no longer shows this month's date as "next payment".
- **Summary**: "Unpaid this month" in `LoansListView` = `unpaidTotal`, the `leftToPay` of every `.unpaid` loan (what is still due after this month's partial payments, never below zero), converted to the base currency through `RateSnapshot` (missing rate: unconverted amount, the canonical cold-cache fallback). Hidden when no active loan has a status.
- **Freshness**: computed in `body`, not cached. The views read `transactions` (re-render on any add/edit/delete; `mutationVersion` is `@ObservationIgnored`), `currencyRatesVersion` (statuses and summary: payments in another currency) and `baseCurrency`, and keep `today` in `@State` refreshed by `UIApplication.significantTimeChangeNotification` (midnight, or on return to the foreground after it), so a new month never shows last month's statuses.

## Deleting a Payment — rollback

A loan's state lives in `LoanInfo` (remaining principal, interest paid, payments made, last payment date, early repayments), written when a payment is recorded. Deleting the payment now takes its own effect off the loan: `TransactionStore.apply(.deleted)` calls `rollBackLoanPayment` (`TransactionStore+LoanPayments.swift`), so every delete path is covered: a single delete (row swipe / context menu, history, the loan screen), an account deleted with its transactions (`deleteTransactions(forAccountId:)`, also on the paying card: its loans roll back; the loan's own payments don't when the loan itself is deleted, they go in one bulk delete), series delete / stop / pause (a linked expense keeps its `recurringSeriesId`). Before, the debt stayed reduced (red flag 8: the loan's balance IS `remainingPrincipal`, so the balance was wrong too) and the month kept showing "Paid".

`LoanPaymentService.reversingPayment` (pure, pinned by `LoanPaymentRollbackTests`):

| Deleted | Undone |
|---|---|
| `.loanPayment` | principal part back on the debt, interest part off `totalInterestPaid`, `paymentsMade - 1`; `lastPaymentDate` (only when it was this payment's date) = the latest remaining regular payment or `markedPaidThrough`, else nil |
| `.loanEarlyRepayment` | amount back on the debt, its `EarlyRepayment` entry removed (same date and amount), the term (`EarlyRepayment.termBefore`, recorded since 2026-10-07) or the monthly payment (`paymentBefore`) restored, `endDate` recomputed |

- **Split of a regular payment**: the inverse of `createManualPayment`: owed before = (owed after + amount) / (1 + monthly rate), interest = its rate, rounded like the forward split. The payments dated after the deleted one are undone first (`remainingBefore`) to find what was owed when it was made. Exact for the latest payment; the later payments keep the split they were recorded with (no replay), so deleting an old annuity payment differs slightly from a "never happened" replay.
- **Never above `originalPrincipal`** (a "Mark as unpaid" reset to nothing paid already gave everything back), floors at 0 for the counters.
- An early repayment without `termBefore` / `paymentBefore` (older entries), or with a later one of the same kind on top of it, is re-planned from the restored principal (`monthsToRepay` / `calculateMonthlyPayment`); the next entry of the same kind inherits the removed one's `paymentBefore` / `termBefore`, so the schedule replay stays right.
- "Mark as paid" is untouched (`markedPaidThrough`): the marked month stays paid.
- The loan's balance follows (`BalanceCoordinator.updateForAccount` + `setInitialBalance`, as `updateLoan` does). The accounts are saved by one debounced (300 ms) `persistAccountsToRepository()` per burst (`loanRollbackPersistTask`): a whole-table save per deleted row could still be running when the account delete that follows a bulk delete saves, and `CoreDataSaveCoordinator` drops a second `saveAccounts` in progress (the account came back on relaunch).
- ⚠️ A future bulk-delete event must call `rollBackLoanPayment` for each transaction too.
- ⚠️ Editing a payment's amount or date still doesn't touch `LoanInfo` (only the month status follows, it reads the transactions); deleting an edited payment reverses its current amount.

## Deleting a Loan — two intents

⚠️ **`deleteTransactions(forAccountId:)` matches BOTH `accountId` and `targetAccountId`**, so the old single-button delete wiped every bank-side expense that funded the loan. Loan payments are real expenses on real accounts; losing them is data loss, not cleanup.

`LoanDetailView` now presents a `confirmationDialog` with two paths:

| Action | Behavior |
|---|---|
| **Delete, keep payments** | `LoansViewModel.deleteLoanPreservingPayments` — each `.loanPayment` / `.loanEarlyRepayment` becomes an `.expense` on its original source bank (`targetAccountId` cleared), then the account is deleted. |
| **Delete everything** | `deleteTransactions(forAccountId:)` **first**, then `deleteLoan` (deleting the account first leaves the balance pass with dangling references). |

Conversion rules in `deleteLoanPreservingPayments`:
- Category is preserved **only if it still exists in the expense catalog** — `TransactionStore.validate` rejects an `.expense` whose category isn't in `categories`. Otherwise it falls back to `""` (uncategorized is explicitly allowed).
- A payment with no resolvable bank account is left pointing at the loan and swept by the trailing `deleteTransactions(forAccountId:)`: it had no bank leg, so it can't become an expense and nothing is lost.

## Transaction Orientation Contract

⚠️ **`accountId = SOURCE bank, targetAccountId = LOAN`** for `.loanPayment` and `.loanEarlyRepayment`.

This mirrors `.expense` semantics: the user-facing "from" is the bank where money leaves; the loan is the destination (debt being repaid). All UI lookups assume this orientation:
- Hero / row card "from" account = `accountId`
- Loan brand icon = `targetAccountId`'s account
- `LoansViewModel.linkTransactions` rewrites converted expenses with `accountId = original bank, targetAccountId = loan`
- `BalanceCalculationEngine` decrements both `accountId` (bank) and `targetAccountId` (loan principal)

**Migration:** existing pre-flip rows are rewritten once at app startup via `AppCoordinator.flipLoanPaymentOrientationIfNeeded()`, gated by `tenra.migration.loanOrientationFlip.v1` flag. The migration is idempotent — rows whose `accountId` no longer points at a loan are skipped.

## Loan Account is Technical — never in user pickers

Loan accounts are containers for debt obligations and **must not** appear in user-facing account selectors for `.income`/`.expense`/`.internalTransfer` flows.

✅ Pickers MUST source from `accountsViewModel.regularAccounts` (excludes loans + deposits) when:
- Adding a new income/expense/transfer (`TransactionAddModal`, `TransactionAddCoordinator.rankedAccounts`)
- Voice input quick-save and confirmation (`VoiceInputView`, `VoiceInputConfirmationView`)
- Loan payment "from" picker (`LoanPaymentView.availableAccounts`)

✅ When editing an existing transaction, use `accountsViewModel.accountsForTransactionEdit(tx:)` — this includes the linked loan/deposit when the tx is a system type and otherwise returns regulars only.

Loan accounts are reachable through:
- `LoanDetailView` (their own detail screen)
- `AccountFilterView` (history filter, where loans are explicitly grouped)
- `LinkPaymentsView` (when linking expenses to a loan)

## Category & Hero on Loan Transactions

`Transaction.category` stores a **technical key** (`"Loan Payment"`). UI resolves it through `CategoryDisplay.displayName(for:type:)` so users see localized strings ("Платёж по кредиту" / "Loan payment").

The `TransactionEditView` allows users to override the category with any `.expense`-type custom category (controlled by `TransactionType.categoryPickerSourceType` — loan and most deposit ops surface the expense catalog). Hero icon resolution:

1. If user picked a custom expense category → use that category's icon + color
2. Otherwise → use the linked loan account's brand icon (e.g., `halykbank.kz` logo)
3. Final fallback → `creditcard.fill` SF Symbol

`CategoryStyleCache.systemTypeStyle(category:type:)` provides a baked-in style for system types when the user is on the technical default; the regular custom-category path takes over once a real category is chosen.

**Colour:** loan payments and early repayments have their own type colour, `TransactionDisplayHelper.loanPaymentColor` (`AppColors.warning`, orange: a debt obligation, not an error, and no other type uses it). It tints the row's `creditcard.fill` fallback and the plate behind the loan's own icon (`systemTypeStyle`), and the "Loan payment" slice and icon in Insights (`InsightsService.syntheticCategoryStyle`). Until 2026-10 it was `AppColors.expense` (black / white). The amount stays `.primary`, like every outflow (`TransactionDisplayHelper.amountColor`).

## Every Financial Mutation Creates a Transaction

| Method | Transaction Type |
|--------|------------------|
| `makeManualPayment` | `.loanPayment` |
| `makeEarlyRepayment` | `.loanEarlyRepayment` |

Both return `Transaction?` for the caller to persist.

## Manual Payment Form (`LoanPaymentView`)

- **Default amount** = the most recent linked payment for this loan (real users round up; the prior actual is a better suggestion than the calculated annuity). Falls back to `loanInfo.monthlyPayment`.
- **Optional note** maps to `Transaction.description`.
- **Source picker** lists only `regularAccounts`.
- **Pay All** (`LoanPayAllView`) supports per-loan amount overrides via inline `TextField`s; defaults follow the same "last actual" logic via `LoansListView.lastPaidAmounts(for:)`.

## LoanTransactionMatcher

Conforms to the same matcher signature as `SubscriptionTransactionMatcher` — accepts `AmountMatchMode` (`.all` / `.tolerance` / `.exact`). Defined alongside `SubscriptionTransactionMatcher` in `Services/Recurring/SubscriptionTransactionMatcher.swift`.

New matchers should follow the same signature to plug into `LinkPaymentsView`.

## Link-Payments UI

UI wrapper: `LoanLinkPaymentsView` — uses shared `LinkPaymentsView` (`Views/Components/LinkPayments/LinkPaymentsView.swift`).

Provides full linking UX (filters, sheets, search, caches, background scan, haptic).

⚠️ **Don't duplicate the state machine** — wrap `LinkPaymentsView` with `findCandidates` + `performLink` `@Sendable` closures.
