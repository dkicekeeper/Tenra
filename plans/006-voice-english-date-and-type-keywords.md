# Plan 006: Add English date and income/expense keywords to the voice parser

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 4392be3..HEAD -- Tenra/Services/Voice/VoiceInputParser.swift`
> on `main` must be empty. (Step 0 then merges the plan-004 test branch into
> YOUR worktree branch — that is expected and required, not drift.)

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (additive keyword lists; behavior change only for EN phrases that previously fell through to defaults)
- **Depends on**: plans/004 (its branch `worktree-agent-a441e10a2c89ecd6f` is merged into the executor worktree in Step 0)
- **Category**: bug
- **Planned at**: commit `4392be3`, 2026-06-12

## Why this matters

Voice input is marketed bilingual (EN + RU storefronts; "Add expenses by voice" is the top ASO differentiator per `docs/RELEASE_1.1_PLAN.md`), but the parser's date and operation-type keywords are **Russian-only**:

- `parseDate` recognizes only «сегодня»/«вчера» — "yesterday taxi 20" silently logs **today**.
- `incomeKeywords`/`expenseKeywords` are RU-only — "received salary 1000" logs as an **expense** (the type falls through to the `.expense` default in `parseType`).

The revived test suite (plan 004) pinned this behavior; this plan fixes it and updates that pin.

## Current state

All code verified at `4392be3`:

`Tenra/Services/Voice/VoiceInputParser.swift:523-534` — `parseDate`:

```swift
private func parseDate(from text: String) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    if text.contains("сегодня") {
        return today
    } else if text.contains("вчера") {
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    return today
}
```

`VoiceInputParser.swift:544-566` — `expenseKeywords` / `incomeKeywords` static arrays (RU verb forms only).

`VoiceInputParser.swift:576-584` — matching semantics (load-bearing for keyword choice):

```swift
private func parseTypeOptional(from text: String) -> TransactionType? {
    for keyword in Self.expenseKeywords where text.contains(keyword) {
        return .expense
    }
    for keyword in Self.incomeKeywords where text.contains(keyword) {
        return .income
    }
    return nil
}
```

Facts that constrain the fix:

- **Substring matching, expense checked first.** Therefore "paid" must NOT go into `expenseKeywords` — "got paid 500" would match expense before income ever runs. Income phrases win only by not colliding with expense substrings.
- Input is lowercased by `normalizeText` (line 507) before `parseDate`/`parseType` see it — EN keywords must be lowercase.
- `parseMulti` inherits type from the previous clause via `parseTypeOptional` returning nil — adding keywords doesn't change that mechanism.

Tests (after the Step 0 merge, the live suite `TenraTests/Services/Voice/VoiceInputParserTests.swift` from plan 004 is present in your worktree). One of its tests **pins the old, wrong behavior** and must be updated in this plan:

```swift
/// "yesterday 300" — "yesterday" is not matched by parseDate (only "вчера"
/// is checked) → default = today.
@Test("EN: no date keyword → date defaults to today")
func defaultDateIsToday() { ... parser.parse("yesterday 300 groceries") ... expects today }
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| grep -E "error:" \| head -30` | no output |
| Voice suites | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/VoiceInputParserTests -only-testing:TenraTests/VoiceInputParserAmountTests 2>&1 \| grep -aE "Test case .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | all `passed` |
| Full unit suite | same with `-only-testing:TenraTests` | `** TEST SUCCEEDED **` |

## Scope

**In scope** (the only files you should modify):
- `Tenra/Services/Voice/VoiceInputParser.swift` (the two keyword sites only)
- `TenraTests/Services/Voice/VoiceInputParserTests.swift` (update the stale pin, add EN cases)

**Out of scope** (do NOT touch):
- `categoryMap` / category matching in the parser — EN category keywords are a real gap but a separate, larger change (the map drives category creation; needs product input on EN category names).
- `VoiceInputParserAmountTests.swift` — must keep passing unchanged (amount parsing is language-neutral digits).
- `normalizeText`, `parseAmount`, `parseMulti` internals, and all other production code.

## Git workflow

- Work on the worktree branch you are on. Do **NOT** push.
- One commit for the fix + tests; message style: short descriptive line + `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Steps

### Step 0: Merge the plan-004 test branch into your worktree branch

```bash
git merge --no-edit worktree-agent-a441e10a2c89ecd6f
```

This brings in the revived `VoiceInputParserTests.swift` (plan 004). Expected: clean merge, no conflicts (it touched only `TenraTests/`).

**Verify**: `grep -c "#if false" TenraTests/Services/Voice/VoiceInputParserTests.swift` → 0, and the file contains `@Test` functions (it's the rewritten suite, not the old dark one).

### Step 1: Add English date keywords to `parseDate`

Extend the existing chain symmetrically (EN keywords lowercase — input is pre-lowercased):

```swift
if text.contains("сегодня") || text.contains("today") {
    return today
} else if text.contains("вчера") || text.contains("yesterday") {
    return calendar.date(byAdding: .day, value: -1, to: today) ?? today
}
```

(No substring hazard: "yesterday" does not contain "today".)

**Verify**: build → no errors.

### Step 2: Add English type keywords

Append to the existing static arrays (keep RU entries untouched, add a `// EN` comment group):

- `expenseKeywords` += `"spent"`, `"bought"`, `"purchase"`, `"expense"`
  - deliberately **no** `"paid"` — it is a substring of income phrasing "got paid" and expense is checked first (see Current state). Add a one-line comment in the code saying exactly that, so nobody "completes" the list later.
  - `"purchase"` covers `"purchased"` via substring.
- `incomeKeywords` += `"received"`, `"earned"`, `"income"`, `"salary"`, `"got paid"`

**Verify**: build → no errors.

### Step 3: Update the stale test pin and add EN coverage

In `TenraTests/Services/Voice/VoiceInputParserTests.swift`:

1. **Replace** `defaultDateIsToday` (it asserts "yesterday 300 groceries" → today, which is now wrong). Split it into two tests:
   - `enYesterdayDate`: `"yesterday 300 groceries"` → start-of-yesterday (same `Calendar.current` math as the existing `yesterdayDate` test — no hardcoded dates).
   - `defaultDateIsToday`: a phrase with **no** date keyword in either language, e.g. `"300 groceries"` → today.
2. **Add**:
   - `enTodayDate`: `"today 50 coffee"` → start-of-today.
   - `enIncomeKeyword`: `"received salary 1000"` → `.income`, amount 1000.
   - `enGotPaidIsIncome`: `"got paid 500"` → `.income` (pins the no-"paid"-in-expense decision).
   - `enExpenseKeyword`: `"spent 20 on groceries"` → `.expense` (this phrase now matches via keyword, not default — update the existing `simpleEnExpense` doc comment if you fold it in there instead of adding a new test; either is fine, but the doc comment must stop claiming the type comes from the default).

Derive every expectation from the code you just wrote, in the same comment style the suite already uses.

**Verify**: voice suites command → all tests pass (≥ 12 `Test case ... passed` lines across the two suites), `** TEST SUCCEEDED **`.

### Step 4: Full regression run + commit

**Verify**: full `TenraTests` run → `** TEST SUCCEEDED **`; `git status` clean; `git log` shows the merge commit (Step 0) plus your one fix commit; diff vs the merge base touches only the two in-scope files.

## Test plan

Covered by Step 3 — 5–6 new/updated tests in the revived suite, modeled on its existing style (derivation comments, Calendar-relative dates, retained VM tuple).

## Done criteria

- [ ] `grep -n "yesterday" Tenra/Services/Voice/VoiceInputParser.swift` → match inside `parseDate`
- [ ] `grep -n '"paid"' Tenra/Services/Voice/VoiceInputParser.swift` → **no** match (only `"got paid"` in income)
- [ ] Voice suites: all pass, including `enYesterdayDate`, `enIncomeKeyword`, `enGotPaidIsIncome`
- [ ] `VoiceInputParserAmountTests` unchanged and passing
- [ ] Full `-only-testing:TenraTests` → `** TEST SUCCEEDED **`
- [ ] Only the two in-scope files modified beyond the Step 0 merge

## STOP conditions

Stop and report back (do not improvise) if:

- Step 0's merge conflicts (the 004 branch should be disjoint from everything; a conflict means the base moved).
- The `parseDate`/`parseTypeOptional`/keyword-array excerpts don't match the live code.
- `"got paid 500"` parses as expense **after** your change (means another expense keyword collides — report which, don't keep tweaking lists).
- Any `VoiceInputParserAmountTests` test fails (your change must not affect amount parsing).

## Maintenance notes

- EN **category** keywords remain a gap (`categoryMap` is RU-keyed) — "spent 20 on groceries" still resolves to the fallback "Other" category. Separate plan; needs product decision on EN category names.
- Substring matching means future keyword additions must be checked against both lists for collisions ("paid" is the canonical example, documented in-code).
- This branch contains plan 004's commits — when merging to main, merge THIS branch and skip 004's branch (it's included).
