# Plan 019: The core add/edit transaction flows and subscription reminder dates are covered by tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Views/Transactions/TransactionAddCoordinator.swift Tenra/Views/Transactions/TransactionEditCoordinator.swift Tenra/Services/Notifications/SubscriptionNotificationScheduler.swift`
> Plans 003, 006 and 016 may have changed these files: write tests against the CURRENT behavior and note in your report which plan's behavior each test pins.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (tests only; no production code changes except testability seams listed below)
- **Depends on**: none (best run after 006 and 016 so the pinned behavior is the fixed one)
- **Category**: tests
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

The two screens every user uses daily have zero tests: `TransactionAddCoordinator` (0 references in
`TenraTests`) and `TransactionEditCoordinator` (0). The rating-counter bug fixed on 2026-09-24 lived in
the add coordinator unnoticed ("the main add form never incremented the counter"). The category-rename
failure (plan 006) and series-detach rules also run through the edit coordinator. Reminder date math in
`SubscriptionNotificationScheduler.calculateNextChargeDate` has no tests either. These characterization
tests pin current behavior so the upcoming fixes (005-018) cannot silently regress these flows.

## Current state

- `Tenra/Views/Transactions/TransactionAddCoordinator.swift` — `@Observable final class` (MainActor by project default).
  `init(category:type:currency:transactionsViewModel:categoriesViewModel:accountsViewModel:transactionStore:)`;
  `var formData: TransactionFormData`; `func save() async -> ValidationResult` (line ~114): validates, handles
  recurring (`formData.recurring`), converts currency, creates the transaction through the store, links subcategories,
  calls `RatingPromptService.shared.recordTransactionAdded()`.
- `Tenra/Views/Transactions/TransactionEditCoordinator.swift` — `@Observable @MainActor final class`;
  `init(transaction:transactionsViewModel:categoriesViewModel:accountsViewModel:transactionStore:)`;
  `var formData: EditTransactionFormData`; `var errorMessage: String?`; `var canSave: Bool`;
  `func save(onSuccess:)` (spawns a Task; to await it in tests, poll the store or add an internal
  `func saveAndWait() async -> Bool` seam that the existing `save` calls).
- Store harness exemplar: `TenraTests/ViewModels/TransactionSeriesDetachTests.swift` (`makeStore()` on
  `UserDefaultsRepository`) and `TenraTests/ViewModels/AccountCurrencyEditRecalcTests.swift` (`makeGraph()` with
  `AccountsViewModel`, `BalanceCoordinator`; keep the store alive, `AccountsViewModel.transactionStore` is weak).
  Build `TransactionsViewModel(repository:)` and `CategoriesViewModel(repository:)` the same way as
  `TenraTests/Services/Voice/VoiceInputParserTests.makeParser()` does, and wire them to the store if their
  initializers/properties require it (read `TransactionsViewModel` / `CategoriesViewModel` first).
- `RatingPromptService.shared` keeps counters in `UserDefaults.standard` under keys in its `Key` enum. Read the counter
  before/after rather than asserting absolute values, and mark suites that touch it with `.sharedProcessState`
  (`TenraTests/SharedProcessStateTrait.swift`) because it is process-global.
- `SubscriptionNotificationScheduler.calculateNextChargeDate(for:)` reads `Date()` directly. Add an internal overload
  `calculateNextChargeDate(for:today:)` used by the public one, to make it testable (only seam allowed in production code).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| New suites | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/TransactionAddCoordinatorTests -only-testing:TenraTests/TransactionEditCoordinatorTests -only-testing:TenraTests/SubscriptionNextChargeDateTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| All tests | `-only-testing:TenraTests`; count `' failed on'` | 0 |

## Scope

**In scope**: three new files under `TenraTests/` (`ViewModels/TransactionAddCoordinatorTests.swift`,
`ViewModels/TransactionEditCoordinatorTests.swift`, `Services/SubscriptionNextChargeDateTests.swift`);
minimal testability seams: `TransactionEditCoordinator.saveAndWait()` (internal) and
`SubscriptionNotificationScheduler.calculateNextChargeDate(for:today:)` (internal).
**Out of scope**: any behavior change. If a test reveals a bug, keep the test pinning the CORRECT behavior,
mark it with `.disabled("bug: <one line>")` and list it in your report.

## Git workflow

Commit directly on `main`; do not push. Message: `test: characterize add/edit transaction flows and reminder dates`.

## Steps

### Step 1: Add flow tests (`TransactionAddCoordinatorTests`, `@MainActor`, `.sharedProcessState`)

1. Valid expense (amount "1500", existing category, regular account) → `.valid`; store has 1 new transaction with that
   amount/category/account; rating tx counter +1.
2. Empty amount → not valid; store unchanged.
3. Missing account id → `.accountNotFound`.
4. Recurring monthly enabled → a series is created and the first occurrence exists; counter +1 exactly once.
5. Foreign-currency amount on a KZT account: the saved transaction keeps its own `currency`, and `convertedAmount`
   is set when a rate is available (seed `CurrencyRateStore.shared` as other currency tests do, and call
   `CurrencyRateStore.shared.clearAll()` in the suite init per CLAUDE.md).

### Step 2: Edit flow tests (`TransactionEditCoordinatorTests`, `@MainActor`)

1. Change amount only → store updated; `errorMessage == nil`.
2. Empty category on an expense → `canSave == false`.
3. Editing a transaction linked to a live series with recurring "never" chosen detaches it (mirrors
   `TransactionSeriesDetachTests`), while a hidden recurring control (deposit interest) keeps the link.
4. (If plan 006 has landed) rename the category, then edit the old transaction's amount → succeeds.
5. (If plan 003 has landed) changing the category of one of three same-merchant uncategorized transactions produces a
   `bulkCategoryProposal` with the other two ids.

### Step 3: Reminder date tests (`SubscriptionNextChargeDateTests`)

Seam first (see Current state). Cases with a fixed `today`:
1. Monthly from 2026-01-15, today 2026-09-10 → 2026-09-15.
2. Monthly from 2026-01-15, today 2026-09-15 → current behavior (next is 2026-10-15); pin it and comment why.
3. Monthly from 2025-01-31, today 2026-03-01 → 2026-03-31.
4. Weekly, yearly and a future start date → the start date itself.
5. Paused subscription → nil.

**Verify**: New suites → SUCCEEDED; All tests → 0 failed.

## Done criteria

- [ ] 3 new suites, at least 15 tests, all passing (or explicitly `.disabled` with a bug note)
- [ ] Only the two listed seams changed in production code (`git diff --stat -- Tenra/` shows only those two files)
- [ ] `plans/README.md` row 019 updated

## STOP conditions

- The coordinators cannot be constructed in tests without a running `AppCoordinator` (report what is missing; do not build one).
- A seam would require changing a public signature used by views.

## Maintenance notes

- Add a test here whenever a new side effect is added to `save()` (counters, learning stores, notifications).
