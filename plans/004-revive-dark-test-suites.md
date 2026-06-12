# Plan 004: Revive the voice-parser and onboarding test suites; retire the two obsolete dark suites

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 4392be3..HEAD -- TenraTests/Services/Voice/ TenraTests/Onboarding/ TenraTests/ViewModels/TransactionStoreTests.swift TenraTests/Balance/BalanceCalculationTests.swift Tenra/Services/Voice/VoiceInputParser.swift Tenra/ViewModels/OnboardingViewModel.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (new tests may expose real parser/VM bugs — that's the point; production code is out of scope)
- **Depends on**: none (001 recommended first for CI coverage)
- **Category**: tests
- **Planned at**: commit `4392be3`, 2026-06-11

## Why this matters

Four test suites are wrapped in `#if false` — they compile to nothing while looking like coverage. Two of them guard features that matter right now: **VoiceInputParser** (1,116 lines of EN+RU phrase parsing; voice input is named in `docs/RELEASE_1.1_PLAN.md` as the app's top ASO differentiator) and **OnboardingViewModel** (the first-run flow every new App Store user hits). The other two are dead weight: they test classes deleted in earlier refactors. This plan rewrites the two valuable suites against the current APIs and deletes the two obsolete files so the test target stops carrying zombie code.

## Current state

The four dark files and why each went dark (verbatim from their headers):

- `TenraTests/Services/Voice/VoiceInputParserTests.swift` — "Disabled — VoiceInputParser API changed to ViewModel-based injection (Phase 31+). Tests reference old `init(accounts:categories:subcategories:defaultAccount:)`". **Rewrite** (Step 2).
- `TenraTests/Onboarding/OnboardingViewModelTests.swift` — "Disabled — references removed OnboardingViewModel API (`currentScreen`, `goForward`, `goBack`, …) taken out during the onboarding redesign". **Rewrite** (Step 3).
- `TenraTests/Balance/BalanceCalculationTests.swift` — "Disabled — BalanceCalculationService and BalanceUpdateCoordinator were deleted in Phase 36". The replacement engine already has live coverage: `TenraTests/Services/BalanceCalculationEngineTests.swift` exists, plus `LoanLinkRecalculationTests`. **Delete** (Step 4).
- `TenraTests/ViewModels/TransactionStoreTests.swift` — "Disabled — TransactionStore API changed significantly (Phase 7+, 16+, 28+, 40+)". Drifted across four refactor generations; unrecoverable as written. **Delete** (Step 4) — git history preserves it; a fresh TransactionStore suite is future work, not a salvage job.

The current production APIs (verified by reading the code at `4392be3`):

```swift
// Tenra/Services/Voice/VoiceInputParser.swift:303
init(
    categoriesViewModel: CategoriesViewModel,
    accountsViewModel: AccountsViewModel,
    transactionsViewModel: TransactionsViewModel
)
func parse(_ text: String) -> ParsedOperation          // :313
func parseMulti(_ text: String) -> [ParsedOperation]   // :429
```

```swift
// Tenra/ViewModels/OnboardingViewModel.swift (current public surface)
static func makeForTesting() -> OnboardingViewModel    // :61 — still exists
var path: [OnboardingStep]                              // :37
var draftCurrency: String                               // :40, defaults to AppSettings.defaultCurrency
var draftAccount: AccountDraft                          // :43 (name/iconSource/balance, :22-24)
var draftCategories: [SelectablePreset]                 // :46, seeded from CategoryPreset.defaultExpense
var isFinishing: Bool                                   // :51
var selectedPresetCount: Int                            // :71
var canAdvanceFromAccountStep: Bool                     // :75
var canFinish: Bool                                     // :79
func startDataCollection()                              // :85
func advanceToAccountStep() async                       // :91
func advanceToCategoriesStep() async                    // :98
func skip() async                                       // :112
func finish() async                                     // :124
```

The working exemplar to copy for voice tests — `TenraTests/Services/Voice/VoiceInputParserAmountTests.swift` (live, passing, same target):

```swift
@MainActor
struct VoiceInputParserAmountTests {
    /// VMs are returned and retained by the caller because the parser holds
    /// only weak references to them.
    private static func makeParser() -> (VoiceInputParser, CategoriesViewModel, AccountsViewModel, TransactionsViewModel) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let categoriesVM = CategoriesViewModel(repository: repo)
        let accountsVM = AccountsViewModel(repository: repo)
        let transactionsVM = TransactionsViewModel(repository: repo)
        let parser = VoiceInputParser( ... )   // read the rest of the file for the full body
        ...
```

Repo conventions and documented traps that apply here:

- Suites constructing MainActor-isolated types must be `@MainActor`.
- **The parser holds only weak references to its ViewModels** — every test must keep the returned VM tuple alive for the parser's lifetime (the exemplar's comment says exactly this).
- `AccountsViewModel.transactionStore` is `weak`, and `accounts` reads through it — account-name-matching tests would require building and retaining a `TransactionStore`. That is heavier than this plan needs: scope voice tests to **amount / type / date / category / multi-utterance** parsing, which the exemplar shows works with empty VMs (plus categories seeded through `CategoriesViewModel`).
- swift-testing; suite-level `-only-testing` filtering only; type name, not display name.
- Old and new file may keep the same filename (contents replaced) — filenames must stay unique in the target.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| grep -E "error:" \| head -30` | no output |
| Voice suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/VoiceInputParserTests 2>&1 \| grep -aE "Test case .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | all `passed` |
| Onboarding suite | same with `-only-testing:TenraTests/OnboardingViewModelTests` | all `passed` |
| Full unit suite | same with `-only-testing:TenraTests` | `** TEST SUCCEEDED **` |

## Scope

**In scope** (the only files you should modify/create/delete):
- `TenraTests/Services/Voice/VoiceInputParserTests.swift` (rewrite in place)
- `TenraTests/Onboarding/OnboardingViewModelTests.swift` (rewrite in place)
- `TenraTests/Balance/BalanceCalculationTests.swift` (delete)
- `TenraTests/ViewModels/TransactionStoreTests.swift` (delete)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch):
- ALL production code — especially `Tenra/Services/Voice/VoiceInputParser.swift` and `Tenra/ViewModels/OnboardingViewModel.swift`. If a test exposes a real parsing bug, report it (STOP condition), don't patch the parser to match the test or vice versa without evidence of intended behavior.
- `TenraTests/Services/Voice/VoiceInputParserAmountTests.swift` — live and passing; copy its pattern, don't edit it. Don't duplicate its year-heuristic cases in the new suite.

## Git workflow

- Work directly on `main` (owner's preference). Do **NOT** push.
- One commit per step; message style: short descriptive line + `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Steps

### Step 1: Read the current APIs

Read in full: `TenraTests/Services/Voice/VoiceInputParserAmountTests.swift` (the pattern, including the complete `makeParser` body), `Tenra/Services/Voice/VoiceInputParser.swift` lines 1–450 (`ParsedOperation` shape, `parse`, `parseMulti`, type/date detection), and `Tenra/ViewModels/OnboardingViewModel.swift` in full. Note how `ParsedOperation` exposes amount/category/type/date — the assertions below depend on its real field names.

**Verify**: you can name `ParsedOperation`'s fields and `OnboardingStep`'s cases.

### Step 2: Rewrite `VoiceInputParserTests.swift`

Replace the entire file (drop `#if false`, drop XCTest — use swift-testing). `@MainActor @Suite struct VoiceInputParserTests` with the `makeParser` helper copied from the exemplar, **plus** category seeding: create 2–3 categories through `CategoriesViewModel` (e.g. "Еда", "Такси", "Groceries") so category matching is exercised. Tests, EN + RU per case where the parser is bilingual:

1. Simple expense phrase: `"500 на такси"` → amount 500, expense type, category resolves to "Такси".
2. English equivalent: `"spent 20 on groceries"` → amount 20, expense, category "Groceries".
3. Income phrase: `"доход 5000"` (and/or the EN form the parser supports) → income type, amount 5000.
4. Date extraction: a phrase with `"вчера"`/"yesterday" → parsed date is start-of-yesterday (compare with `Calendar.current` math, not a hardcoded date — tests must not depend on run date).
5. `parseMulti` splits: one utterance containing two operations (read `parseMulti`'s splitting logic first to construct a realistic input) → 2 `ParsedOperation`s with the right amounts.
6. Unmatched category falls back: a phrase naming no known category → whatever the documented fallback is (read the parser; assert the actual designed behavior, e.g. nil category or default).

Before asserting exact expectations, **derive each expected value from reading the parser code**, not from guessing locale behavior. If the parser's behavior for a case is ambiguous in code, drop that case rather than enshrining an accident.

**Verify**: voice suite command → ≥ 6 `passed`, and the output contains `Test case` lines (0-tests-run means the type-name filter is wrong).

### Step 3: Rewrite `OnboardingViewModelTests.swift`

Replace the file. `@MainActor @Suite struct OnboardingViewModelTests`, constructing via `OnboardingViewModel.makeForTesting()`. Tests:

1. `draftCurrency` defaults to `AppSettings.defaultCurrency` (assert against the constant, not a literal).
2. `draftCategories` is non-empty and mirrors `CategoryPreset.defaultExpense` count; `selectedPresetCount` matches the initially-selected subset (read the `SelectablePreset` init to see what starts selected).
3. `canAdvanceFromAccountStep` / `canFinish` gating: read the computed properties (lines 75/79) and assert both the false case (fresh VM, if that's false) and the true case after mutating `draftAccount.name` / selections accordingly.
4. `startDataCollection()` pushes the first step onto `path` (assert `path` contents against `OnboardingStep`'s real cases).
5. `advanceToAccountStep()` / `advanceToCategoriesStep()` append the expected steps in order (`await` them).

Do NOT test `finish()`/`skip()` — they reach through the weak `coordinator` (nil under `makeForTesting`) into app-wide side effects; asserting they "do nothing safely" is acceptable as a bonus test only if it's a plain call + no-crash.

**Verify**: onboarding suite command → ≥ 5 `passed`.

### Step 4: Delete the two obsolete files

`git rm TenraTests/Balance/BalanceCalculationTests.swift TenraTests/ViewModels/TransactionStoreTests.swift`. (File-system-synchronized groups: no pbxproj edit needed.) If `TenraTests/Balance/` becomes empty, remove the directory too.

**Verify**: build → no errors; `grep -rln "#if false" TenraTests/` → **no matches** (all four dark suites are now resolved).

### Step 5: Full regression run + commit

**Verify**: full `TenraTests` run → `** TEST SUCCEEDED **`; `git status` clean apart from in-scope files.

## Test plan

Steps 2–3 are the test plan: ~11 new tests across two revived suites, modeled on `VoiceInputParserAmountTests.swift`. Verification commands above.

## Done criteria

- [ ] `grep -rln "#if false" TenraTests/` → no matches
- [ ] `TenraTests/Balance/BalanceCalculationTests.swift` and `TenraTests/ViewModels/TransactionStoreTests.swift` no longer exist
- [ ] Voice suite: ≥ 6 tests run and pass (visible `Test case ... passed` lines)
- [ ] Onboarding suite: ≥ 5 tests run and pass
- [ ] Full `-only-testing:TenraTests` → `** TEST SUCCEEDED **`
- [ ] Zero production files modified (`git diff --name-only 4392be3..HEAD -- Tenra/` → empty for this plan's commits)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A voice test fails in a way that looks like a **real parser bug** (e.g. "500 на такси" parses amount ≠ 500). Report the phrase, expected, and actual — this is exactly the regression the suite exists to catch; the fix is a separate decision.
- `OnboardingViewModel.makeForTesting()` no longer exists or `OnboardingViewModel`'s surface has drifted from the listing above.
- Seeding categories through `CategoriesViewModel` requires a retained `TransactionStore` after all (API drift) — report rather than constructing half-wired stores.
- The two files marked for deletion contain any test that is NOT covered by a live suite and NOT tied to a deleted class — list such tests instead of deleting.

## Maintenance notes

- A fresh `TransactionStore` suite remains the biggest open coverage gap (highest-churn file in the repo, per `git log`). It needs a deliberate fixture design (retained store + repository mock per CLAUDE.md's three-places rule) — propose it as its own plan; do not bolt it onto this one.
- When voice parsing changes (new phrase forms, new locales), extend `VoiceInputParserTests` in the same derive-expectations-from-code style; keep year-heuristic cases in `VoiceInputParserAmountTests` where they live today.
- Reviewer focus: Step 2's expected values must trace to parser code paths, not to "seems right" — spot-check two assertions against `VoiceInputParser.swift`.
