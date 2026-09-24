# Plan 007: Importing past statement rows does not change an account's real current balance

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Views/Import/ImportTransactionPreviewView.swift Tenra/Services/Balance Tenra/ViewModels/AccountsViewModel.swift`
> Plan 005 is expected to have changed `AccountsViewModel.swift` (persisted balance correction).
> Any other change: compare with the excerpts; a mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (balance math)
- **Depends on**: plans/005-persist-balance-correction.md (same persist path; must land first)
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

An account's balance is `initialBalance + Σ realized transactions`, with no cutoff at the
account's creation date. Onboarding (and "add account") stores the user's REAL current
balance as `initialBalance`. When the user later imports a bank statement for the previous
month, every past row is added on top, so spending that the entered balance already
reflects is subtracted a second time (e.g. real balance 150 000 ₸, shown 70 000 ₸). Net worth,
projected balance and the low-balance signal all inherit the error.

The fix: rows dated BEFORE the account's creation day are, by definition, already baked
into the balance the user typed at creation. When such rows are imported, shift the account's
`initialBalance` by their contribution so the current balance stays the same. Rows on or after
the creation day are genuinely new money movement and keep changing the balance as today.

## Current state

- `Tenra/Services/Balance/BalanceCalculationEngine.swift`:
  - line 45 `struct BalanceCalculationEngine` (plain value type, no shared state);
  - lines 71-86 `calculateBalance(account:transactions:)` = `initialBalance + Σ contribution(... policy: .currentBalance)`;
  - line 121 `func contribution(of tx: Transaction, to account: AccountBalance, policy: LedgerPolicy) -> Double`
    — THE single per-transaction rule (CLAUDE.md Red Flag 8). `.currentBalance` excludes future-dated rows.
- `Tenra/Services/Balance/BalanceStore.swift:46-55` — `AccountBalance.from(_ account: Account)`.
- `Tenra/Services/Balance/BalanceCoordinator.swift:168-174` `recalculateAccounts(_:accounts:transactions:)`,
  `:218-221` `persistInitialBalance(_:for:)` (CoreData + memory), `:223-225` `getInitialBalance(for:) async -> Double?`.
- `Tenra/Models/Transaction.swift:566` `Account.createdDate: Date?` (defaulted to `Date()` at
  init, line 583; persisted as `AccountEntity.createdAt`). Line 567 `shouldCalculateFromTransactions`:
  when true the account's balance is derived purely from transactions (initial 0) and must NOT be compensated.
- `Tenra/Views/Import/ImportTransactionPreviewView.swift` — `addSelectedTransactions()` adds each
  selected row with `transactionStore.add(...)` inside a `Task`, counts `savedCount`, calls
  `RatingPromptService.shared.recordTransactionAdded(count:)` and `dismiss()`. It has
  `accountsViewModel: AccountsViewModel` (`accountsViewModel.balanceCoordinator: BalanceCoordinator?`,
  `accountsViewModel.transactionStore` weak) and `@Environment(TransactionStore.self) transactionStore`.
- Transaction dates are `"yyyy-MM-dd"` strings (string comparison orders them). Convert
  `createdDate` with `DateFormatters.dateFormatter.string(from:)` (the canonical storage formatter).
- Precedent for "keep the current balance while inherited history exists": deposit conversion in
  `Tenra/ViewModels/AccountsViewModel.swift` (~line 262-287) persists a snapshot `initialBalance`
  with `persistInitialBalance`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/ImportBalanceCompensationTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| All tests | `-only-testing:TenraTests`; count `' failed on'` | 0 |

## Scope

**In scope**: `Tenra/Services/Balance/ImportBalanceCompensation.swift` (create),
`Tenra/Views/Import/ImportTransactionPreviewView.swift` (`addSelectedTransactions` only),
`TenraTests/Services/ImportBalanceCompensationTests.swift` (create).

**Out of scope**: the CSV import flow (it creates `shouldCalculateFromTransactions` accounts or
maps into existing ones; same problem for existing accounts, separate follow-up); the receipt
flow (a receipt is new spending); any UI toggle or new strings; setting the balance from the
statement's closing balance (direction item, not this plan).

## Git workflow

Commit directly on `main`; do not push. Message:
`fix(import): past statement rows no longer shift an account's current balance`.

## Steps

### Step 1: Pure compensation rule

Create `Tenra/Services/Balance/ImportBalanceCompensation.swift`:
```swift
/// Rows dated before an account's creation day are already reflected in the balance the
/// user entered when creating it. Importing them must not move the current balance, so
/// the account's initialBalance shifts by exactly their contribution.
enum ImportBalanceCompensation {
    /// Σ contribution(.currentBalance) of `imported` rows that touch `account` and are
    /// dated strictly before the account's creation day. 0 when the account derives its
    /// balance from transactions, has no initialBalance, or has no createdDate.
    nonisolated static func preCreationContribution(
        of imported: [Transaction],
        to account: Account,
        engine: BalanceCalculationEngine = BalanceCalculationEngine()
    ) -> Double
}
```
New `initialBalance` = old `initialBalance` − `preCreationContribution`. Rows ON the creation
day are treated as new (not compensated): document that in the doc comment.
If `BalanceCalculationEngine.contribution` is not callable from a `nonisolated` context,
drop `nonisolated` and mark the enum `@MainActor` instead.

**Verify**: Build → SUCCEEDED.

### Step 2: Apply it after import

In `addSelectedTransactions()`, collect the SAVED transactions (the values returned by
`transactionStore.add`) in an array. After the loop and before `dismiss()`:
1. `guard let coordinator = accountsViewModel.balanceCoordinator` (otherwise skip).
2. For each distinct `accountId` among saved rows, find the `Account` in `transactionStore.accounts`.
3. `let shift = ImportBalanceCompensation.preCreationContribution(of: saved, to: account)`;
   skip when `abs(shift) < 0.005`.
4. `guard let oldInitial = await coordinator.getInitialBalance(for: account.id)`; then
   `await coordinator.persistInitialBalance(oldInitial - shift, for: account.id)`.
5. Also update the in-memory `Account` model so a later `registerAccounts` cannot restore the
   old base: copy the account, set `initialBalance = oldInitial - shift`,
   `transactionStore.updateAccount(copy)`.
6. After the per-account loop, one `await coordinator.recalculateAccounts(Set(changedIds), accounts: transactionStore.accounts, transactions: transactionStore.transactions)`.

**Verify**: Build → SUCCEEDED.

### Step 3: Tests

`TenraTests/Services/ImportBalanceCompensationTests.swift`. Pure cases use `Account(...)` with an
explicit `createdDate` built from `DateFormatters.dateFormatter.date(from: "2026-09-10")`.
The integration case builds the store graph like `TenraTests/ViewModels/AccountCurrencyEditRecalcTests.swift`
(`makeGraph()`), adds an account, sets its `createdDate`/`initialBalance`, adds rows with
`store.add`, applies the same steps as Step 2 through a small internal helper you extract from
the view (e.g. `ImportBalanceCompensation.apply(saved:store:coordinator:) async`) so the view and
the test share one code path. Move the Step 2 logic into that helper if you have not already.

**Verify**: Suite → SUCCEEDED; All tests → 0 failed.

## Test plan

1. Pre-creation expense 50 000 → contribution −50 000 → initial shifts +50 000.
2. Post-creation expense → not counted (0).
3. Row ON the creation day → not counted.
4. Future-dated row → 0 (excluded by `.currentBalance`).
5. `shouldCalculateFromTransactions == true` account → 0.
6. Row for another account → 0.
7. Integration: initial 150 000 created 2026-09-10; import expense 50 000 on 2026-08-15 and
   expense 10 000 on 2026-09-15 → final balance 140 000 (only the post-creation row moves it),
   and the same after `coordinator.recalculateAll(...)`.

## Done criteria

- [ ] Build SUCCEEDED; suite (7 tests) passes; full TenraTests 0 failed
- [ ] `grep -n "persistInitialBalance" Tenra/Services/Balance/ImportBalanceCompensation.swift Tenra/Views/Import/ImportTransactionPreviewView.swift` → at least 1 match
- [ ] `git status --short` lists only in-scope files (plus `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 007 updated

## STOP conditions

- Plan 005 has not landed (the balance branch still uses `setInitialBalance(correctInitialBalance`).
- `getInitialBalance` returns nil for normal accounts in tests (the base lives elsewhere): report instead of guessing.
- Existing balance/deposit tests fail.

## Maintenance notes

- Device check: new account with balance 100 000 today, import last month's PDF → balance still
  100 000; a row from today in the same PDF moves it.
- Known edge: after a manual balance correction (plan 005) the entered balance is "as of the
  correction day", but the rule uses the creation day, so rows between creation and correction
  still move the balance. Fixing that needs a stored "balance anchor date" (future work).
- When CSV import into existing accounts is fixed, reuse `ImportBalanceCompensation`.
