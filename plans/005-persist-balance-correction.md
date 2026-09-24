# Plan 005: A manual account-balance correction survives relaunch and later recalculations

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/ViewModels/AccountsViewModel.swift Tenra/Services/Balance/BalanceCoordinator.swift Tenra/Services/Repository/AccountRepository.swift`
> On any change, compare with the excerpts below; a mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED (touches balance math; wrong wiring shows a wrong balance)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

When a user edits an account and types its real current balance, Tenra back-calculates a
new `initialBalance` so that `initialBalance + Σ transactions` equals what they typed.
That new `initialBalance` is written to memory only. CoreData keeps the creation-time
value, because `AccountRepository.saveAccountsInternal` deliberately never overwrites
`initialBalance`. The next full recalculation (it runs whenever a future-dated
transaction such as a subscription occurrence matures, on base-currency change and on
FX heal) rebuilds the balance from the stale persisted value, and the user's correction
silently disappears. CLAUDE.md documents the identical failure for deposit conversion
and names the fix: `BalanceCoordinator.persistInitialBalance` (writes CoreData and memory).

## Current state

- `Tenra/ViewModels/AccountsViewModel.swift:80-125` — `updateAccount(_:)`. The balance branch:
  ```swift
  if balanceChanged, let coordinator = balanceCoordinator, let store = transactionStore {
      // account.initialBalance here = desired CURRENT balance (from the edit view text field)
      let desiredBalance = account.initialBalance ?? oldAccount.balance

      // Back-calculate correct initialBalance: initialBalance = desiredBalance - Σ(transactions)
      let engine = BalanceCalculationEngine()
      let correctInitialBalance = engine.calculateInitialBalance(
          currentBalance: desiredBalance,
          accountId: account.id,
          accountCurrency: account.currency,
          transactions: store.transactions
      )

      var corrected = account
      corrected.initialBalance = correctInitialBalance
      corrected.shouldCalculateFromTransactions = false
      store.updateAccount(corrected)

      Task {
          ...
          if currencyChanged {
              await coordinator.registerAccounts(store.accounts)
          }
          await coordinator.setInitialBalance(correctInitialBalance, for: account.id)
          await coordinator.recalculateAccounts(
              [account.id],
              accounts: store.accounts,
              transactions: store.transactions
          )
      }
  }
  ```
- `Tenra/Services/Balance/BalanceCoordinator.swift:214-221`:
  ```swift
  func setInitialBalance(_ balance: Double, for accountId: String) async {
      store.setInitialBalance(balance, for: accountId)
  }

  func persistInitialBalance(_ balance: Double, for accountId: String) async {
      store.setInitialBalance(balance, for: accountId)
      await repository.updateInitialBalancesSync([accountId: balance])
  }
  ```
- `Tenra/Services/Repository/AccountRepository.swift:252` — in `saveAccountsInternal`:
  `// ⚠️ CRITICAL: Don't overwrite initialBalance — it's set once at creation and never changes`.
  `updateInitialBalancesSync` (same file, line ~204) is the one allowed writer, already
  covered by `AccountRepositoryInitialBalanceSyncTests` in `TenraTests/Services/AccountRepositoryTests.swift`.
- Precedent using the persist path: the deposit conversion in the same file (around
  line 283, `await coordinator.persistInitialBalance(snapshotBalance, for: account.id)`).
- Secondary issue in the same branch: `BalanceCalculationEngine.calculateInitialBalance`
  (`Tenra/Services/Balance/BalanceCalculationEngine.swift:277+`) has its own per-type
  `switch` instead of using `contribution(of:to:policy:)`, which CLAUDE.md Red Flag 8
  names as the single rule. It is used ONLY here. Replace its body with the canonical
  rule (Step 2) so the back-calculation cannot drift from the forward calculation.
- Test harness exemplar: `TenraTests/ViewModels/AccountCurrencyEditRecalcTests.swift`
  (`makeGraph()` builds `AccountsViewModel` + `BalanceCoordinator` + `TransactionStore`
  on a `UserDefaultsRepository`; it returns the store because `AccountsViewModel` holds it weakly).
- `UserDefaultsRepository.updateInitialBalancesSync` is a no-op
  (`Tenra/Services/Core/UserDefaultsRepository.swift:115-117`), so a test must use a
  recording repository to observe the persist call (Step 3).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | `** BUILD SUCCEEDED **` |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/AccountBalanceCorrectionPersistTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | `** TEST SUCCEEDED **` |
| All tests | same with `-only-testing:TenraTests`, then `grep -ac "' passed on"` / `grep -ac "' failed on"` on the log | SUCCEEDED, 0 failed |

`-only-testing` takes suite TYPE names; method-level filters silently run 0 tests.

## Scope

**In scope**: `Tenra/ViewModels/AccountsViewModel.swift` (balance branch of `updateAccount` only),
`Tenra/Services/Balance/BalanceCalculationEngine.swift` (`calculateInitialBalance` body only),
`TenraTests/Support/RecordingDataRepository.swift` (create),
`TenraTests/ViewModels/AccountBalanceCorrectionPersistTests.swift` (create).

**Out of scope**: `AccountRepository.saveAccountsInternal` (its "never overwrite" rule is
correct and protects other paths); deposit/loan branches of `AccountsViewModel`;
`BalanceCoordinator` public API.

## Git workflow

Commit directly on `main` (maintainer preference); do not push. Message:
`fix(accounts): persist a manual balance correction so recalculation cannot revert it`.

## Steps

### Step 1: Persist the corrected initial balance

In the balance branch of `AccountsViewModel.updateAccount`, replace
`await coordinator.setInitialBalance(correctInitialBalance, for: account.id)` with
`await coordinator.persistInitialBalance(correctInitialBalance, for: account.id)`.
Keep the order: `registerAccounts` (if currency changed) → persist → `recalculateAccounts`.
Add a one-line comment: saveAccounts never writes initialBalance, so the correction must
go through the persist path or the next full recalc reverts it.

**Verify**: Build → `** BUILD SUCCEEDED **`;
`grep -n "setInitialBalance(correctInitialBalance" Tenra/ViewModels/AccountsViewModel.swift` → no output.

### Step 2: Make the back-calculation use the canonical contribution rule

Change `BalanceCalculationEngine.calculateInitialBalance(currentBalance:accountId:accountCurrency:transactions:)`
to compute `currentBalance - Σ contribution(of: tx, to: account, policy: .currentBalance)`,
where `account` is an `AccountBalance` built for `accountId` / `accountCurrency`. Read the
`contribution` signature and `AccountBalance` initializer in the same file and in
`Tenra/Services/Balance/BalanceStore.swift` before writing it. If `contribution` needs
account fields you do not have in this function (e.g. deposit info), add an overload that
takes the `AccountBalance` directly and call it from `AccountsViewModel` with
`store.accounts.first { $0.id == account.id }` mapped to `AccountBalance`. If that
mapping is not obvious from existing code, STOP (see STOP conditions) and do only Step 1.

**Verify**: Build → SUCCEEDED; the existing balance suites still pass:
`-only-testing:TenraTests/AccountCurrencyEditRecalcTests -only-testing:TenraTests/BalanceCalculationEngineTests` → `** TEST SUCCEEDED **`.

### Step 3: Recording repository for tests

Create `TenraTests/Support/RecordingDataRepository.swift`:
`final class RecordingDataRepository: DataRepositoryProtocol, @unchecked Sendable` that
holds an inner `UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)`
and forwards EVERY requirement of `DataRepositoryProtocol`
(`Tenra/Services/Core/DataRepositoryProtocol.swift`, 32 requirements) to it, except
`updateInitialBalancesSync`, which appends its argument to
`private(set) var persistedInitialBalances: [[String: Double]]` and then forwards.
(Create the `TenraTests/Support/` folder; the project picks up new files automatically.)

**Verify**: `xcodebuild build-for-testing -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' 2>&1 | grep -E "error:|TEST BUILD (SUCCEEDED|FAILED)"` → `** TEST BUILD SUCCEEDED **`.

### Step 4: Tests

Create `TenraTests/ViewModels/AccountBalanceCorrectionPersistTests.swift`, `@MainActor`,
harness copied from `AccountCurrencyEditRecalcTests.makeGraph()` but built on
`RecordingDataRepository`. Cases in the Test plan.

**Verify**: Suite command → `** TEST SUCCEEDED **`; then All tests → 0 failed.

## Test plan

1. Editing the balance of an account with one realized expense persists exactly one
   `[accountId: expectedInitial]` via `updateInitialBalancesSync`, where
   `expectedInitial = desired + expense` (e.g. desired 1 000, one 200 expense → 1 200).
2. After the edit, `BalanceCoordinator.balances[accountId] == desired` (in-session).
3. After the edit, a full `coordinator.recalculateAll(accounts:transactions:)` still yields `desired`
   (proves the in-memory base is the corrected one; the persisted base is covered by case 1).
4. An edit that does NOT change the balance (rename only) records no persist call.
5. `calculateInitialBalance` agrees with `calculateBalance` for a mix of income, expense,
   an internal transfer out and in, and a future-dated expense (the future one must not count):
   `calculateBalance(initial: calculateInitialBalance(current: X)) == X`.

## Done criteria

- [ ] Build SUCCEEDED; new suite passes (5+ tests); full TenraTests 0 failed
- [ ] `grep -n "setInitialBalance(correctInitialBalance" Tenra/ViewModels/AccountsViewModel.swift` → none
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 005 updated

## STOP conditions

- The balance branch no longer matches the excerpt.
- `persistInitialBalance` no longer writes through `updateInitialBalancesSync`.
- Step 2 requires deposit/loan-specific state you cannot obtain without touching out-of-scope code (then ship Step 1 + tests 1-4 and report).
- Any existing balance/deposit/loan test fails after your change.

## Maintenance notes

- Human device check: correct an account balance, then add a future-dated expense for
  tomorrow (or wait for a subscription occurrence), relaunch the next day: the corrected
  balance must still be shown (minus the matured expense).
- Users who corrected balances before this fix already lost the correction on disk; they
  will see the old balance until they correct it again. No migration is possible (the
  intended value was never stored).
- Plan 007 (import keeps current balance) depends on this persist path.
