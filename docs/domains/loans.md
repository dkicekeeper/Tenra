# Loans Domain

Payment tracking, reconciliation, and amortization.

## Persistence

`LoanInfo` persisted via `loanInfoData: Data?` (JSON-encoded Binary) on `AccountEntity` (CoreData v6) — mirrors [DepositInfo pattern](deposits.md).

## LoanPaymentService

`nonisolated enum` providing:
- annuity formula
- amortization schedule
- payment breakdown
- early repayment
- reconciliation

## Auto-Calculate `monthlyPayment`

`LoanInfo.init` auto-calculates `monthlyPayment` when `nil` is passed.

⚠️ **Pass `nil` to force recalculation** after principal/rate/term changes.

## No Auto-Reconciliation

Loan payments are **never** generated automatically. The user must record every payment manually via `makeManualPayment` (or link an existing expense via `LoanLinkPaymentsView`).

Rationale: real-world loan payments rarely match the calculated annuity exactly (users round up, pay early, vary amounts). Auto-generated phantom payments diverged from real bank withdrawals and confused state. Deposits still auto-reconcile interest accrual — only loans are user-driven.

## Every Financial Mutation Creates a Transaction

| Method | Transaction Type |
|--------|------------------|
| `makeManualPayment` | `.loanPayment` |
| `makeEarlyRepayment` | `.loanEarlyRepayment` |

Both return `Transaction?` for the caller to persist.

## LoanTransactionMatcher

Conforms to the same matcher signature as `SubscriptionTransactionMatcher` — accepts `AmountMatchMode` (`.all` / `.tolerance` / `.exact`). Defined alongside `SubscriptionTransactionMatcher` in `Services/Recurring/SubscriptionTransactionMatcher.swift`.

New matchers should follow the same signature to plug into `LinkPaymentsView`.

## Link-Payments UI

UI wrapper: `LoanLinkPaymentsView` — uses shared `LinkPaymentsView` (`Views/Components/LinkPayments/LinkPaymentsView.swift`).

Provides full linking UX (filters, sheets, search, caches, background scan, haptic).

⚠️ **Don't duplicate the state machine** — wrap `LinkPaymentsView` with `findCandidates` + `performLink` `@Sendable` closures.
