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

## Paid-off Lifecycle

A loan is **closed** when `LoanInfo.isPaidOff` — i.e. `remainingPrincipal <= LoanInfo.paidOffThreshold` (0.01). There is **no persisted closed flag**: the status is derived so it can never drift from the balance when a payment is edited, unlinked, or the amount is corrected. Threshold rather than `<= 0` because annuity rounding and FX leave sub-cent residue on the final payment, which would pin a loan "active" at a displayed debt of 0.00 forever.

Convenience accessors on `Account`: `isPaidOffLoan`, `isActiveLoan` (both `false` for non-loan accounts).

⚠️ **Every loan aggregate must read `LoansViewModel.activeLoans`, not `loans`.** A closed loan contributes 0 debt but keeps a non-zero `monthlyPayment` forever — summing `loans` inflates "Monthly" and the active count. Current call sites: `LoansListView.loansSummary`, `LoansListView.activeLoans` (Pay All), `LoansCardView`. `LoansCardView` deliberately keys its empty state on `loans.isEmpty` (any loans at all) so a user whose loans are all paid off still sees the card.

Closed loans surface in `LoansListView` under a collapsed "Closed" `DisclosureGroup`, below the active cards and outside the type filter's card list (`filteredClosedLoans` applies the same type filter separately).

`LoanDetailView` when closed: `primaryAction`/`secondaryAction` are `nil` (paying a zero balance would drive `remainingPrincipal` negative and silently reopen the loan), "Change Rate" is hidden, the hero subtitle becomes "Closed <date>" (from `lastPaymentDate`), and a one-shot success banner fires on the `false → true` edge of `isPaidOffLoan`. The amortization schedule and payment history stay fully readable.

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
