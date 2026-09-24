# Plan 016: Recurring occurrences on the 29th–31st keep their day (no drift to the 28th), and reminders use the same dates

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Services/Recurring/RecurringTransactionGenerator.swift Tenra/Services/Notifications/SubscriptionNotificationScheduler.swift TenraTests/Services/Transactions/RecurringTransactionGeneratorTests.swift`

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (generation of real money transactions; a mistake duplicates or skips an occurrence)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

The generator computes each occurrence as "previous occurrence + 1 period". `Calendar` clamps
Jan 31 + 1 month to Feb 28, and every later step starts from the 28th: Mar 28, Apr 28, ... So a
subscription or salary series on the 29th–31st drifts to the 28th forever after the first short
month, and the "planned" payment appears days early. Subscription reminders are computed
differently (`start + n periods`, which gives Mar 31), so reminders and the recorded occurrence
disagree. Yearly series on Feb 29 have the same problem.

The fix: compute occurrence k as `start + k × period` (anchored to the series start), in ONE
function used by both the generator and the reminder scheduler.

## Current state

- `Tenra/Services/Recurring/RecurringTransactionGenerator.swift`:
  - `init(dateFormatter: DateFormatter, calendar: Calendar = .current)`; stores `calendar`.
  - `generateTransactions(series:existingOccurrences:existingTransactionIds:accounts:baseCurrency:horizonMonths:)`
    (line ~37): per series, loops `currentDate = startDate ... while currentDate <= horizonDate`, advancing with
    `calculateNextDate(from: currentDate, frequency:)` (step inside `generateTransactionsForSeries`, ~line 111 and the
    advance ~line 194: `guard let nextDate = calculateNextDate(...)`, `if nextDate <= currentDate { break }`, `currentDate = nextDate`).
  - `private func calculateNextDate(from:frequency:)` (lines 235-249): `.daily` +1 day, `.weekly` +7 days,
    `.monthly` +1 month, `.quarterly` +3 months, `.yearly` +1 year, all relative to the given date.
  - `generateUpToNextFuture(...)` (line ~268): finds `latestOccurrenceDate` for the series among existing
    occurrences; `candidateDate = calculateNextDate(from: latest)` or `startDate` when none; then loops
    backfilling past occurrences and exactly one future one, advancing with `calculateNextDate(from: candidateDate)`.
- `Tenra/Services/Notifications/SubscriptionNotificationScheduler.swift:159-227` — `calculateNextChargeDate(for:)`
  computes `start + (periodsPassed + 1) periods` per frequency using `dateComponents([.month], from: start, to: today)`.
  Called from `TransactionStore+Recurring.swift` (lines 64, 129, 268, 322, 529).
- Tests: `TenraTests/Services/Transactions/RecurringTransactionGeneratorTests.swift` (plain struct, helpers
  `makeFormatter()`, `makeSeries(id:startDate:frequency:isActive:)`, calls `generateTransactions(... horizonMonths:)`).
  Existing pins that must keep passing: Jan 31 → Feb 28 (2025) and Feb 29 (2024); Feb 29 yearly → Feb 28 next year;
  horizon inclusion; occurrence-key dedup; DST daily continuity.
- Existing data: already-generated occurrences may sit on the 28th. They must NOT get a second occurrence in the
  same period when generation resumes.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Suites | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/RecurringTransactionGeneratorTests -only-testing:TenraTests/RecurringDateMathTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| All tests | `-only-testing:TenraTests`; count `' failed on'` | 0 |

## Scope

**In scope**: `Tenra/Services/Recurring/RecurringDateMath.swift` (create),
`Tenra/Services/Recurring/RecurringTransactionGenerator.swift`,
`Tenra/Services/Notifications/SubscriptionNotificationScheduler.swift` (`calculateNextChargeDate` body only),
`TenraTests/Services/Recurring/RecurringDateMathTests.swift` (create), `RecurringTransactionGeneratorTests.swift` (add cases).

**Out of scope**: rewriting already-stored occurrences on the 28th (they are history); loan dates (plan 017);
`RecurringFrequency` cases.

## Git workflow

Commit directly on `main`; do not push. Message: `fix(recurring): anchor occurrences to the start date so month-end series keep their day`.

## Steps

### Step 1: One date function

`Tenra/Services/Recurring/RecurringDateMath.swift`:
```swift
nonisolated enum RecurringDateMath {
    /// Occurrence `index` (0 = start) anchored to the start date. Month-based frequencies
    /// clamp per occurrence (Jan 31 → Feb 28 → Mar 31), never cumulatively.
    static func occurrence(_ index: Int, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Date?

    /// Index of the period that contains `date` (for daily/weekly: days/7-day blocks since start;
    /// for month-based: whole months between the start's (year, month) and the date's (year, month),
    /// divided by the period length, IGNORING the day). Used to resume after an existing occurrence
    /// without creating a second one in the same period, even if the stored one drifted to the 28th.
    static func periodIndex(of date: Date, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Int

    /// First occurrence strictly after `date` (anchored).
    static func nextOccurrence(after date: Date, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Date?
}
```
Month-based step lengths: monthly 1, quarterly 3, yearly 12 (use `.month` arithmetic for yearly so Feb 29 → Feb 28 → Feb 29).
Daily: `.day` × index. Weekly: `.day` × 7 × index.

**Verify**: build SUCCEEDED.

### Step 2: Tests for the math

`TenraTests/Services/Recurring/RecurringDateMathTests.swift` (plain struct; build dates with an `en_US_POSIX`
`yyyy-MM-dd` formatter and `Calendar(identifier: .gregorian)` with `TimeZone.current`):
1. Monthly from 2025-01-31: indices 0..4 → 01-31, 02-28, 03-31, 04-30, 05-31.
2. Monthly from 2024-01-31: index 1 → 2024-02-29.
3. Yearly from 2024-02-29: index 1 → 2025-02-28, index 4 → 2028-02-29.
4. Quarterly from 2025-11-30: index 1 → 2026-02-28, index 2 → 2026-05-30.
5. `periodIndex` of 2025-03-28 (drifted) with start 2025-01-31 monthly → 2; `nextOccurrence(after: 2025-03-28)` → 2025-04-30 (NOT 2025-03-31).
6. Weekly/daily unchanged vs simple addition.

### Step 3: Use it in the generator

- `generateTransactionsForSeries`: iterate `index = 0, 1, 2...` with `currentDate = RecurringDateMath.occurrence(index, ...)`
  instead of cumulative `calculateNextDate`; keep the horizon / maxIterations / dedup logic identical.
- `generateUpToNextFuture`: when a latest occurrence exists, start from
  `RecurringDateMath.nextOccurrence(after: latest, start:, frequency:, calendar:)`; then advance by index
  (`periodIndex(of: candidate) + 1`) instead of `calculateNextDate(from: candidate)`.
- Delete `calculateNextDate` if unused afterwards.

**Verify**: Suites → SUCCEEDED (all existing generator tests still pass).

### Step 4: Generator regression tests

Add to `RecurringTransactionGeneratorTests`:
1. Start 2025-01-31 monthly, `generateTransactions` with enough horizon: dates include 2025-03-31 and 2025-04-30, never 2025-03-28.
2. Resume case: existing occurrences on 2025-01-31, 2025-02-28, 2025-03-28 (drifted); `generateUpToNextFuture` with
   `today` after 2025-04-30 generates 2025-04-30 and does NOT generate 2025-03-31.
   (If `generateUpToNextFuture` reads `Date()` directly for "today" and the test cannot control it, choose start dates
   relative to the real current date instead, and document that in the test.)

### Step 5: Reminders use the same function

Rewrite `SubscriptionNotificationScheduler.calculateNextChargeDate(for:)` to: parse the start (keep existing guards),
return the start if it is in the future, else `RecurringDateMath.nextOccurrence(after: startOfToday - 1 second ... )`
such that a charge due TODAY is returned as today (match current behavior for today: if today equals an occurrence,
the current code returns the NEXT one; keep that behavior and state it in a comment). Keep the signature.

**Verify**: All tests → 0 failed.

## Done criteria

- [ ] New math suite (6+ tests) and 2 new generator tests pass; all existing generator tests pass; full TenraTests 0 failed
- [ ] `grep -n "calculateNextDate(from" Tenra/Services/Recurring/RecurringTransactionGenerator.swift` → none (or only inside RecurringDateMath)
- [ ] `plans/README.md` row 016 updated

## STOP conditions

- An existing generator test fails in a way that suggests the old behavior was intentional (read its comment first).
- `RecurringFrequency` has cases beyond daily/weekly/monthly/quarterly/yearly (update `docs/domains/recurring.md` checklist first, then report).

## Maintenance notes

- Device check: create a monthly subscription starting on the 31st of a past month; the History shows the 30th/31st in
  30/31-day months and the 28th/29th only in February; the reminder arrives before the same date.
- `docs/domains/recurring.md` lists 6 files with frequency switches; add `RecurringDateMath.swift` to that list.
