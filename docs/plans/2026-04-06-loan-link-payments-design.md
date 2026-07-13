# Loan Link Payments — Design

## Problem

Users have existing expense transactions for monthly loan payments (e.g., car loan since June 2021, 340,000/month). When creating a loan in the app, these transactions remain as regular expenses — no way to retroactively link them to the loan.

## Solution

In-place conversion: existing expense transactions are updated to become `loanPayment` type, linked to the loan account. Original transaction data (id, date, amount, description, notes) is preserved.

## UX Flow

**Entry point:** LoanDetailView → menu (⋯) → "Link Payments"

**Screen: `LoanLinkPaymentsView` (sheet)**

1. **Auto-match** — on open, system finds candidates:
   - `type == .expense` (not already linked to another loan)
   - `amount` within ±10% of `monthlyPayment`
   - `date` between loan `startDate` and today
   - Sorted by date, pre-selected with checkboxes

2. **Manual adjustment:**
   - User toggles checkboxes on/off
   - Search by description/amount to find transactions outside auto-match
   - Filter by source account

3. **Preview summary:**
   - "Will link: 48 payments totaling 16,320,000 ₸"
   - "Paid: 48 of 60 months"
   - "Link" button

4. **Confirmation and apply**

## Transaction Conversion

For each selected transaction, update fields via `TransactionStore.update()`:

```
type: .expense → .loanPayment
accountId: loanAccountId
targetAccountId: original accountId (source account)
category: "Loan Payment"
// Preserved: id, date, amount, currency, description, notes
```

## Loan State Recalculation

After converting all transactions, recalculate LoanInfo:

- **paymentsMade** = count of linked transactions
- **remainingPrincipal** = walk payments chronologically, apply `paymentBreakdown()` for each, subtract principal portion
- **totalInterestPaid** = sum of interest portions from each payment breakdown
- **lastPaymentDate** = date of most recent linked transaction
- **lastReconciliationDate** = today

For installments (0% interest): `remainingPrincipal = originalPrincipal - (monthlyPayment × paymentsMade)`

## Balance Handling

`TransactionStore.update()` handles balance deltas automatically:
- Old account: expense removed → balance increases
- Loan account: loanPayment added → tracked via remainingPrincipal

Net effect on the source account balance is zero (money left the account either way).

## New Files

| File | Type | Purpose |
|------|------|---------|
| `Views/Loans/LoanLinkPaymentsView.swift` | View | Transaction selection screen |
| `Services/Loans/LoanTransactionMatcher.swift` | Service | Auto-matching candidates |

## Modified Files

| File | Change |
|------|--------|
| `LoanDetailView.swift` | Add "Link Payments" menu item |
| `LoansViewModel.swift` | `linkTransactions(toLoan:transactions:)` — conversion + recalculation |
| `Localizable.xcstrings` | New l10n keys |

## Approach

**Chosen: In-place conversion** (over delete+recreate or hybrid). Rationale:
- Preserves user data (descriptions, notes, dates)
- Uses existing `TransactionStore.update()` pipeline
- No duplicate transaction risk
- Reconcile can run separately later for missing months
