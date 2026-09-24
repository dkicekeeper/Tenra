# Plan 011: Siri "How much did I spend" counts the same spending as the home screen

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Services/Intents/SpendingQueryService.swift Tenra/Models/SummaryContribution.swift TenraTests/Services/Intents/SpendingQueryServiceTests.swift`

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

CLAUDE.md Red Flag 11: all income/expense summary totals must derive from
`TransactionType.summaryContribution(isFuture:)`, which counts `.expense`, `.loanPayment` and
`.loanEarlyRepayment` as spending. The Siri/Shortcuts spending query fetches `type == expense`
only, so for anyone with a loan Siri reports less than the home screen for the same period.

## Current state

- `Tenra/Services/Intents/SpendingQueryService.swift:43-48`:
  ```swift
  let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
  request.predicate = NSPredicate(
      format: "date >= %@ AND date <= %@ AND type == %@",
      start as NSDate,
      now as NSDate,
      TransactionType.expense.rawValue
  )
  ```
  Rows are then converted to base currency one by one.
- `Tenra/Models/SummaryContribution.swift` — `nonisolated func summaryContribution(isFuture: Bool) -> SummaryContribution`
  on `TransactionType`; for `isFuture == false`, `.expense, .loanPayment, .loanEarlyRepayment` → `.expense`.
- Raw values: `TransactionType(rawValue:)` (`Tenra/Models/Transaction.swift:10-18`), e.g. `"loan_payment"`, `"loan_early_repayment"`.
- Tests: `TenraTests/Services/Intents/SpendingQueryServiceTests.swift` (`@MainActor`,
  `@Suite(.serialized, .sharedProcessState)`, in-memory CoreData, `seedExpense(in:amount:currency:dateKey:)`).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/SpendingQueryServiceTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |

## Scope

**In scope**: `Tenra/Services/Intents/SpendingQueryService.swift`, `TenraTests/Services/Intents/SpendingQueryServiceTests.swift`.
**Out of scope**: the intent's dialog/snippet; other summary paths.

## Git workflow

Commit directly on `main`; do not push. Message: `fix(intents): Siri spending total follows the summary rule`.

## Steps

### Step 1: Derive the fetched types from the rule

Replace the `type == %@` clause with `type IN %@`, where the array is every `TransactionType`
case whose `summaryContribution(isFuture: false) == .expense`, mapped to `rawValue`. Build the
list by iterating all cases (add `CaseIterable` to `TransactionType` only if it is not already
conforming AND no switch elsewhere breaks; otherwise list the cases explicitly with a comment that
it must mirror `summaryContribution`). Keep the date bounds and conversion loop unchanged.

**Verify**: `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"` → SUCCEEDED.

### Step 2: Tests

Add to `SpendingQueryServiceTests` (generalize `seedExpense` to take a `type` parameter with default `.expense`):
1. A `loan_payment` row in the period is included in the total.
2. An `internal` transfer and an `income` row are excluded.
3. A test that, for every `TransactionType`, inclusion in the query equals
   `summaryContribution(isFuture: false) == .expense` (pins the two rules together).

**Verify**: Suite → SUCCEEDED.

## Done criteria

- [ ] Suite passes with the new cases; full TenraTests 0 failed
- [ ] `grep -n "type == %@" Tenra/Services/Intents/SpendingQueryService.swift` → no output
- [ ] `plans/README.md` row 011 updated

## STOP conditions

- `summaryContribution` semantics changed (then re-read CLAUDE.md Red Flag 11 and report).

## Maintenance notes

Any new `TransactionType` is picked up automatically if Step 1 derived the list from the rule.
