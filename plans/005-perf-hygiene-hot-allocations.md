# Plan 005: Remove three hot-path allocation/scan inefficiencies (insights fallback formatter, loan-detail full-store scan, time-filter formatter)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 4392be3..HEAD -- Tenra/Services/Insights/InsightsService.swift Tenra/Views/Loans/LoanDetailView.swift Tenra/Views/Components/Input/TimeFilterView.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (three local, behavior-preserving changes)
- **Depends on**: none (001 recommended first for CI coverage)
- **Category**: perf
- **Planned at**: commit `4392be3`, 2026-06-11

## Why this matters

Three confirmed-by-reading inefficiencies, each cheap to fix:

1. `InsightsService.calculateMonthlySummary`'s fallback path allocates a **new `DateFormatter` per transaction inside its loop** — `DateFormatter` construction is one of the most expensive Foundation allocations (~µs each ×N transactions ×M monthly buckets).
2. `LoanDetailView.mostRecentPayment` filters and sorts **all ~19k transactions in the store** inside a computed property that runs on every body re-evaluation — even though the view already maintains `cachedTransactions`, a pre-filtered, pre-sorted (date-descending) subset for this account.
3. `TimeFilterView.customRangeDescription` allocates a `DateFormatter` on every body evaluation; the repo has a canonical `DateFormatters` utility (`Tenra/Utils/DateFormatters.swift`) for exactly this.

The repo's own docs (CLAUDE.md Red Flag #9, `docs/gotchas.md`) treat MainActor sweeps over the 19k-transaction array and per-render formatter allocation as known defect classes; these are three live violations.

## Current state

**Site 1 — `Tenra/Services/Insights/InsightsService.swift` (~line 1100–1125)**, inside `calculateMonthlySummary`'s helper that returns `(income: Double, expenses: Double)`:

```swift
for tx in transactions {
    // Use pre-parsed date when available (O(1) lookup vs O(DateFormatter))
    let txDate: Date?
    if let map = txDateMap {
        txDate = map[tx.date]
    } else {
        // Fallback: allocate a formatter locally (rare path when preAggregated is nil)
        let fallbackDF = DateFormatter()          // ← allocated PER TRANSACTION
        fallbackDF.dateFormat = "yyyy-MM-dd"
        txDate = fallbackDF.date(from: tx.date)
    }
    guard let date = txDate, date <= today else { continue }
    ...
```

Context that matters: `InsightsService` is a `nonisolated final class` running off-MainActor via `Task.detached` — a shared formatter must respect that. The file already has static formatters near its top (e.g. a `yearMonthFormatter`); check their declaration pattern (`nonisolated(unsafe) static let` or similar) and match it. `DateFormatter` is not thread-safe in general, but a formatter confined to this service's detached computations follows the same safety argument as the file's existing statics — match whatever pattern they use rather than inventing a new one.

**Site 2 — `Tenra/Views/Loans/LoanDetailView.swift:77–99`**:

```swift
private var mostRecentPayment: Transaction? {
    transactionStore.transactions                       // ← full 19k array
        .filter {
            ($0.type == .loanPayment || $0.type == .loanEarlyRepayment)
            && ($0.targetAccountId == accountId || $0.accountId == accountId)
        }
        .sorted { $0.date > $1.date }                   // ← O(N log N) on every body eval
        .first
}

private var lastPaidAmount: Decimal? {
    mostRecentPayment.map { Decimal($0.amount) }
}

private var lastUsedCategory: String? {
    guard let category = mostRecentPayment?.category, ...
}
```

The same view already maintains the fix's input (lines 59–63):

```swift
private func refreshTransactions() async {
    cachedTransactions = transactionStore.transactions
        .filter { $0.accountId == accountId || $0.targetAccountId == accountId }
        .sorted { $0.date > $1.date }
}
```

`cachedTransactions` is a **superset** of the payments filter (same account predicate, no type restriction) and is **already sorted date-descending** — so `mostRecentPayment` reduces to a `first(where:)` over it.

**Site 3 — `Tenra/Views/Components/Input/TimeFilterView.swift:105–110`**:

```swift
private var customRangeDescription: String {
    let formatter = DateFormatter()                     // ← per body eval
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return "\(formatter.string(from: customDateRange.lowerBound)) – \(formatter.string(from: customDateRange.upperBound))"
}
```

Canonical utility: `Tenra/Utils/DateFormatters.swift` has `nonisolated static let` formatters and a locale-aware `localizedDisplayFormatter(format:)` cache. Read it before Step 3 and reuse/extend it rather than adding a view-local static, **unless** no existing member produces a `.medium`-date string — in that case a `private static let` on `TimeFilterView` matching the `BackupMetadata.dateFormatter` pattern (`Tenra/Models/BackupMetadata.swift:28–33`) is acceptable.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| grep -E "error:" \| head -30` | no output |
| Insights regression | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightsAggregationTests 2>&1 \| grep -aE "Test case .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | all `passed` |
| Full unit suite | same with `-only-testing:TenraTests` | `** TEST SUCCEEDED **` |

## Scope

**In scope** (the only files you should modify):
- `Tenra/Services/Insights/InsightsService.swift` (the one hoist only)
- `Tenra/Views/Loans/LoanDetailView.swift` (the one computed property only)
- `Tenra/Views/Components/Input/TimeFilterView.swift` (the one formatter only)
- `Tenra/Utils/DateFormatters.swift` (only if Step 3 adds a shared member)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- Any other `DateFormatter()` in the codebase — there are more; this plan fixes the three vetted sites only. A broad sweep without per-site reading is how regressions happen (formatter configs differ subtly).
- `DepositDetailView` — it shares the refresh pattern with LoanDetailView, but its payment-suggestion logic was not audited; don't "fix it while you're there".
- `BalanceCoordinator.processRecalculateAll` — a known, larger MainActor-sweep issue, deliberately deferred (needs the Sendable-snapshot treatment; separate plan if selected).
- Anything in `InsightsService` beyond hoisting the formatter — no refactors of the aggregation logic.

## Git workflow

- Work directly on `main` (owner's preference). Do **NOT** push.
- One commit (or one per site); message style: short descriptive line + `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Steps

### Step 1: Hoist the InsightsService fallback formatter out of the loop

Minimal, behavior-identical change — move the allocation above the `for` loop:

```swift
// Fallback formatter (rare path when preAggregated is nil) — hoisted out of
// the loop; a DateFormatter allocation per transaction is the expensive part.
let fallbackDF: DateFormatter? = txDateMap == nil ? {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df
}() : nil

for tx in transactions {
    let txDate: Date?
    if let map = txDateMap {
        txDate = map[tx.date]
    } else {
        txDate = fallbackDF?.date(from: tx.date)
    }
    ...
```

(If the file's existing static formatters already include a `"yyyy-MM-dd"` one, reuse it instead and skip the local — check first.)

**Verify**: build → no errors; Insights regression suite → all `passed`.

### Step 2: Derive `mostRecentPayment` from `cachedTransactions`

Replace the body of `mostRecentPayment` in `LoanDetailView.swift`:

```swift
/// Derived from cachedTransactions (already account-filtered and sorted
/// date-descending by refreshTransactions) — NOT from the full 19k store array.
private var mostRecentPayment: Transaction? {
    cachedTransactions.first {
        $0.type == .loanPayment || $0.type == .loanEarlyRepayment
    }
}
```

Behavior note to confirm while editing (this is the only semantic risk): `cachedTransactions` filters `accountId == accountId || targetAccountId == accountId` — identical account predicate to the old code — and is sorted `date >` descending, so `.first(where:)` returns the same element the old `filter → sorted → first` chain did. One freshness difference: the old version recomputed live mid-mutation, the new one updates when `.task(id: refreshTrigger)` re-runs `refreshTransactions()` — and `refreshTrigger` already keys on `mutationVersion` (file's own comment, lines 41–57), so any add/edit/delete refreshes it before the user can re-open the payment sheet.

**Verify**: build → no errors. Then `grep -n "transactionStore.transactions$" Tenra/Views/Loans/LoanDetailView.swift` → only the two legitimate sites remain (`refreshTrigger`'s observation touch at ~line 52 and `refreshTransactions()` at ~line 60).

### Step 3: Static formatter for `TimeFilterView`

Read `Tenra/Utils/DateFormatters.swift`. If it (or `localizedDisplayFormatter`) can produce a `.medium`-style localized date, use it. Otherwise add to `TimeFilterView`:

```swift
private static let rangeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()
```

and use `Self.rangeFormatter` in `customRangeDescription`. Keep output identical (medium date, no time) — this string is user-visible in the filter sheet.

**Verify**: build → no errors; `grep -n "DateFormatter()" Tenra/Views/Components/Input/TimeFilterView.swift` → no match inside `customRangeDescription` (a static initializer match is fine).

### Step 4: Full regression run + commit

**Verify**: full `TenraTests` run → `** TEST SUCCEEDED **`; `git status` shows only in-scope files. Report to the owner what to spot-check visually (per repo convention, no Simulator screenshot verification): loan detail → "make payment" sheet pre-fills the last payment's amount/category; time filter → custom range label renders dates.

## Test plan

No new tests — these are behavior-preserving micro-changes guarded by the existing `InsightsAggregationTests` (site 1) and the full suite. Site 2's behavior (payment-sheet defaults) has no existing test and building a LoanDetailView harness is out of proportion; the maintenance note flags it.

## Done criteria

- [ ] `InsightsService.swift`: no `DateFormatter()` inside the `calculateMonthlySummary` per-transaction loop (visual check of the diff)
- [ ] `LoanDetailView.swift`: `mostRecentPayment` reads `cachedTransactions`, not `transactionStore.transactions`
- [ ] `TimeFilterView.swift`: `customRangeDescription` allocates nothing per call
- [ ] Build clean; full `-only-testing:TenraTests` → `** TEST SUCCEEDED **`
- [ ] Only in-scope files modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any excerpt above doesn't match the live code (drift).
- `cachedTransactions`'s filter or sort in `refreshTransactions()` differs from the excerpt (the derivation argument in Step 2 collapses — report instead of adapting).
- `InsightsService`'s existing static formatters use an isolation pattern you can't match for the hoisted formatter (e.g. they're all inside a `@MainActor` region) — report; do not introduce `nonisolated(unsafe)` on your own judgment.
- Fixing any site appears to require changes outside the four in-scope files.

## Maintenance notes

- `DepositDetailView` shares LoanDetailView's structure; if a future change adds payment suggestions there, apply the Step 2 derivation pattern from the start.
- The repo-wide `DateFormatter()`-in-body pattern would suit a SwiftLint custom rule if plans add linting later (a `custom_rules` regex on `DateFormatter()` inside `Views/`).
- Deferred explicitly: `BalanceCoordinator.processRecalculateAll` MainActor sweep (finding #7 in the audit) — needs the `Sendable`-snapshot treatment per CLAUDE.md Red Flag #9; bigger and riskier than this plan's scope.
