# Deposits Domain

Interest accrual, capitalization, and account ↔ deposit conversion.

## Account vs Deposit Distinction

`Account.isDeposit` is a **computed property** (`depositInfo != nil`), not a stored flag.

`DepositInfo` is persisted via `depositInfoData: Data?` (JSON-encoded Binary) on `AccountEntity` (CoreData v6).

## Interest Formula

Simple daily interest, compound monthly at posting:

```
dailyInterest = principalBalance × (rate/100) / 365
```

## DepositInterestService.reconcileDepositInterest

- Triggered on view appear (`.task {}`)
- Walks days since `lastInterestCalculationDate`
- Creates `.depositInterestAccrual` transaction on posting day

### Capitalization behavior

| Setting | Effect |
|---------|--------|
| Capitalization enabled | `principalBalance += postedAmount` |
| Capitalization disabled | `interestAccruedNotCapitalized += postedAmount` |

### `calculateInterestToToday()`

Read-only calculation for UI display (no side effects).

## Account → Deposit Conversion

`DepositEditView` handles 3 modes (new, edit, convert) via `isConverting` computed property.

### ⚠️ Initial date computation

New/converted deposits MUST use `DepositEditView.computeInitialDates(postingDay:)` to set `lastInterestCalculationDate` to the most recent posting date — otherwise interest shows 0 (default is today → `calculateInterestToToday()` loop never executes).

### ⚠️ Don't decompose Account for `addDeposit`

Use `AccountsViewModel.addDepositAccount(_ account:)` to preserve computed `DepositInfo` dates. Decomposing into fields loses `lastInterestCalculationDate` / `lastInterestPostingMonth`.

## Deposit Balance Model

```
balance = initialPrincipal + sum(events with date > startDate)
```

Where `events` =
- `.depositTopUp` (+)
- `.depositWithdrawal` (−)
- `.depositInterestAccrual` (+ iff `capitalizationEnabled`)

⚠️ **`principalBalance` is a cached result** of `DepositInterestService.reconcileDepositInterest` — never mutate it outside that service.

The link-interest flow reclassifies tx type only; it must NOT touch `principalBalance` / `interestAccruedNotCapitalized`.

## startDate Semantics

`startDate` on `DepositInfo` marks when the deposit "exists for calculation".

Events dated on/before `startDate` are assumed baked into `initialPrincipal` and filtered out of the reconcile walk — prevents double-counting when converting a regular account with past income into a deposit.

## Auto-Posted Interest Tx ID Prefix `di_`

Deterministic djb2 hash of `(depositId, month, amount, currency)`. Survives process restarts → use for idempotency and bulk cleanup.

`DepositsViewModel.recalculateInterest` deletes only `.depositInterestAccrual` with `di_` prefix so user-linked interest stays.

## Linking Existing Transactions as Interest

`DepositsViewModel.linkTransactionsAsInterest(depositId:transactions:transactionStore:)`:
- Converts `.income` on the deposit's account into `.depositInterestAccrual`
- Pure reclassification — no balance/deposit-info mutation
- UI wrapper: `DepositLinkInterestView` (uses shared `LinkPaymentsView` with `Options.deposit`)

## Reconciliation Callback Pattern

⚠️ **Never spawn `Task {}` inside synchronous `onTransactionCreated` callbacks** — collect into array, batch-persist after reconciliation completes. Same rule applies to loans (see [loans.md](loans.md)).

## Where Reconciliation Runs

`AccountsManagementView` is the centralized reconciliation point for both deposits AND loans on `.task {}` appear.

## ⚠️ principalDelta vs BalanceCalculationEngine.contribution (M-1 — intentionally NOT unified)

`DepositInterestService.principalDelta` defines how a tx moves the deposit's **running principal** (interest-accrual input). It is a SEPARATE definition from `BalanceCalculationEngine.contribution` (which moves the account **balance**), and the data-integrity refactor deliberately left them apart — they have genuinely different semantics and unifying risks corrupting accrued interest. The exact divergences are pinned by `DepositPrincipalDeltaCharacterizationTests` and listed in the `principalDelta` doc-comment:

1. **Eligible types / amount source.** `principalDelta` counts `.income`/`.expense` on the deposit and uses `convertedAmount ?? amount`; `contribution` prefers `targetAmount` for cross-currency — so cross-currency inflows can differ.
2. **`.depositInterestAccrual` capitalization gate.** `principalDelta` adds interest to the running principal ONLY when `capitalizationEnabled`; `contribution` always adds the accrual to the balance.
3. **`.internalTransfer` source leg asymmetry.** `principalDelta` uses `-amount` (raw deposit-currency) on the source side while using `+convertedAmount ?? amount` on the target side; `contribution` uses `-(convertedAmount ?? amount)` on the source.

If you ever unify these, do it as a deliberate, separately-reviewed change and update the characterization tests in lock-step. Do NOT "fix" `principalDelta` to look like `contribution` as a drive-by.
