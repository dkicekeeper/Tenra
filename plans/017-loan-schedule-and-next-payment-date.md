# Plan 017: The loan schedule stays correct after a "reduce payment" early repayment, and the next payment date keeps day 29–31

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Services/Loans/LoanPaymentService.swift Tenra/Models/Transaction.swift Tenra/ViewModels/LoansViewModel.swift TenraTests/Services/LoanPaymentServiceTests.swift`
> Read `docs/domains/loans.md` before starting.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (the schedule feeds `markPaymentsPaid`, which writes the loan balance)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

1. **Schedule after "reduce payment".** `applyEarlyRepayment(.reducePayment)` overwrites
   `loanInfo.monthlyPayment` with the new, smaller payment. `generateAmortizationSchedule` then
   replays the WHOLE loan from `originalPrincipal` with that new payment for every month, including
   months before the early repayment. Past rows, remaining balances and "total interest" become wrong.
   `LoansViewModel.markPaymentsPaid` copies `remainingPrincipal` and `totalInterestPaid` straight from
   those rows, and the loan account's balance derives from `remainingPrincipal` (CLAUDE.md Red Flag 8),
   so the user's net worth goes wrong too.
2. **Next payment date.** `nextPaymentDate` clamps the payment day inside the CURRENT month and then adds
   one month to the clamped date: payment day 31 in February gives Feb 28 → Mar 28 (should be Mar 31).
   It also treats a payment due today as already passed.

## Current state

- `Tenra/Services/Loans/LoanPaymentService.swift`:
  - `calculateMonthlyPayment(principal:annualRate:termMonths:)` (lines 16-35): annuity formula, 0% → principal / n.
  - `paymentBreakdown(remainingPrincipal:annualRate:monthlyPayment:)` (40-52).
  - `generateAmortizationSchedule(loanInfo:)` (68-122):
    ```swift
    var remaining = loanInfo.originalPrincipal
    ...
    for i in 1...loanInfo.termMonths {
        guard let paymentDate = calendar.date(byAdding: .month, value: i, to: startDate) else { break }
        let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)
        // apply early repayments dated before this payment
        let applicableKeys = earlyRepaymentsByMonth.keys.filter { $0 < dateStr }
        for erDate in applicableKeys { remaining -= earlyRepaymentsByMonth.removeValue(forKey: erDate) ?? 0 }
        guard remaining > 0 else { break }
        let (interest, principalPart) = paymentBreakdown(
            remainingPrincipal: remaining,
            annualRate: loanInfo.interestRateAnnual,
            monthlyPayment: loanInfo.monthlyPayment   // ← CURRENT payment for every month
        )
        ...
    ```
  - `nextPaymentDate(loanInfo:)` (138-152):
    ```swift
    var components = calendar.dateComponents([.year, .month], from: today)
    components.day = min(loanInfo.paymentDay, daysInMonth(date: today))
    guard let currentMonthDate = calendar.date(from: components) else { return nil }
    if currentMonthDate <= today {
        return calendar.date(byAdding: .month, value: 1, to: currentMonthDate)
    }
    return currentMonthDate
    ```
  - `applyEarlyRepayment(loanInfo:amount:date:type:note:)` (167-220): `.reducePayment` sets
    `loanInfo.monthlyPayment = calculateMonthlyPayment(principal: remainingPrincipal, annualRate:, termMonths: remaining)`
    where `remaining = remainingPayments(loanInfo:)` = `termMonths - paymentsMade` BEFORE the change.
- `Tenra/Models/Transaction.swift:377-389` — `struct EarlyRepayment: Codable, Equatable, Hashable { date, amount, type, note }`
  with an explicit `nonisolated init(date:amount:type:note:)`. `LoanInfo` is JSON-encoded into `AccountEntity.loanInfoData`
  (`Tenra/CoreData/Entities/AccountEntity+CoreDataClass.swift:44-49, 116`). Adding an OPTIONAL stored property to
  `EarlyRepayment` stays backward compatible with synthesized `Codable` (missing key decodes as nil). Verify
  `EarlyRepayment` has no custom `init(from:)`; if it does, use `decodeIfPresent`.
- `Tenra/ViewModels/LoansViewModel.swift:259-275` — `markPaymentsPaid` uses `schedule[target - 1].remainingBalance`
  and sums `interest` of the first `target` rows.
- Tests: `TenraTests/Services/LoanPaymentServiceTests.swift` (helper `makeLoanInfo(...)`, annuity 1M/12%/12m ≈ 88 849).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/LoanPaymentServiceTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| All tests | `-only-testing:TenraTests`; count `' failed on'` | 0 |

## Scope

**In scope**: `LoanPaymentService.swift` (`applyEarlyRepayment`, `generateAmortizationSchedule`, `nextPaymentDate`),
`Tenra/Models/Transaction.swift` (`EarlyRepayment` only), `LoanPaymentServiceTests.swift`.
**Out of scope**: loan UI; `LoansViewModel` (it benefits automatically); interest-rate history handling; rounding mode.

## Git workflow

Commit directly on `main`; do not push. Message: `fix(loans): schedule replays the payment in force; next payment keeps day 29-31`.

## Steps

### Step 1: Record the payment in force

Add to `EarlyRepayment`: `let paymentBefore: Decimal?` (doc: "monthly payment in force before this repayment;
nil for repayments recorded before 2026-09"). Extend the init with `paymentBefore: Decimal? = nil`. In
`applyEarlyRepayment`, pass `paymentBefore: loanInfo.monthlyPayment` when appending (read it BEFORE mutating).

### Step 2: Replay with the right payment

In `generateAmortizationSchedule`:
- Sort early repayments by date. Initial payment:
  - if any `.reducePayment` repayment exists: the `paymentBefore` of the EARLIEST one; if that is nil (legacy),
    `calculateMonthlyPayment(principal: originalPrincipal, annualRate:, termMonths: loanInfo.termMonths)`;
  - otherwise `loanInfo.monthlyPayment` (unchanged since creation).
- When applying an early repayment during the replay (the existing "dated before this payment" rule), if its type is
  `.reducePayment`, switch the payment: use the NEXT reduce-payment repayment's `paymentBefore` if present, else the
  current `loanInfo.monthlyPayment` when it is the last one; for legacy (nil) entries recompute
  `calculateMonthlyPayment(principal: remaining, annualRate:, termMonths: termMonths - (i - 1))` exactly as
  `applyEarlyRepayment` did.
- Use that running payment in `paymentBreakdown`. Keep everything else (last-row clamp, rounding, `isPaid`).

### Step 3: Next payment date

Rewrite `nextPaymentDate` so the day is clamped per target month:
1. candidate = this month with day `min(paymentDay, daysInMonth(this month))`;
2. if candidate < startOfToday → next month with day `min(paymentDay, daysInMonth(next month))`;
3. if candidate == startOfToday → return today (due today).
Keep `guard loanInfo.remainingPrincipal > 0`. Make "today" injectable for tests: add an internal overload
`nextPaymentDate(loanInfo:today:calendar:)` and have the existing function call it with `Date()` / `.current`.

### Step 4: Tests (add to `LoanPaymentServiceTests`)

1. Loan 1 200 000, 12%, 12 months, start 2026-01-01. After payment 6 rows, apply a 300 000 `.reducePayment` early
   repayment dated 2026-07-10 via `applyEarlyRepayment` (set `paymentsMade = 6`, `remainingPrincipal` to row 6's balance
   first). Regenerate the schedule: rows 1–6 equal the rows generated BEFORE the repayment (same payment/interest/balance);
   rows 7+ use the new payment; the final balance is 0.
2. Same with a legacy repayment (construct `EarlyRepayment` with `paymentBefore: nil`): rows 1–6 still match.
3. `.reduceTerm` repayment: schedule unchanged vs current behavior (payment constant).
4. `nextPaymentDate`: paymentDay 31, today 2026-02-28 → 2026-02-28 (due today); today 2026-03-01 → 2026-03-31;
   today 2026-04-30 → 2026-04-30 (due today); paymentDay 15, today 2026-05-16 → 2026-06-15.
5. JSON round-trip: `LoanInfo` with an `EarlyRepayment` encoded WITHOUT `paymentBefore` (hand-written JSON) decodes, `paymentBefore == nil`.

**Verify**: Suite → SUCCEEDED; All tests → 0 failed.

## Done criteria

- [ ] New tests pass; all existing loan tests pass; full TenraTests 0 failed
- [ ] `plans/README.md` row 017 updated

## STOP conditions

- `EarlyRepayment` or `LoanInfo` has a custom decoder that would reject the new field.
- Existing tests encode the current (buggy) replay as expected behavior: read them, report which, do not rewrite silently.

## Maintenance notes

- Loans with legacy reduce-payment repayments are reconstructed by recomputation; if the user entered a custom
  initial payment, rows before the first repayment can still differ slightly. New repayments are exact.
- Device check: loan with a reduce-payment early repayment → schedule rows before it keep their old payment.
