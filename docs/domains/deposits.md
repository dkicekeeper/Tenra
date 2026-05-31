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

### ⚠️ Converting an account WITH history → mark `.preserveImported`

`AccountsViewModel.updateDeposit` detects a conversion (the existing account still has `depositInfo == nil`) and calls `balanceCoordinator.markAsImported(account.id)`. The converted account keeps its full transaction history (same `id`), but its current balance is snapshotted into `initialPrincipal`. Under the default `.fromInitialBalance` mode the cold-launch `recalculateAll` would re-sum that inherited history **on top of** the snapshot — the "converted deposit shows a huge negative balance days later" bug (incremental balance looked fine in-session; full recalc on next launch diverged). `.preserveImported` makes recalc keep the live, incrementally-maintained balance instead. This is robust even when the first post-conversion transfer is the same day as the conversion (a date-only `startDate` cutoff can't separate same-day pre- vs post-conversion events). Pinned by `BalanceLedgerInvariantTests.convertedDepositRecalcDoesNotDoubleCountHistory`.

> Known follow-up: the **interest** walk (`DepositInterestService`) is independent of balance mode and still filters by `startDate`, which for a conversion sits at the open interest period's start (a past date). Inherited income/expense/linked-interest dated after it can still pollute the running principal used for interest accrual. Tracked separately — does not affect the displayed balance.

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

`DepositInterestService.principalDelta` defines how a tx moves the deposit's **running principal** (interest-accrual input). It is a SEPARATE definition from `BalanceCalculationEngine.contribution` (which moves the account **balance** = principal + interest). These model different quantities and must NOT be merged. Behavior is pinned by `DepositPrincipalDeltaCharacterizationTests` (+ `DepositCrossCurrencyTransferTests`).

**The essential, by-design divergence — keep it:**
- **`.depositInterestAccrual` capitalization gate.** `principalDelta` grows the running principal ONLY when `capitalizationEnabled` (interest compounds); `contribution` always adds the accrual to the balance. Merging would make non-capitalizing deposits compound incorrectly.

**Resolved (M-1):**
- The cross-currency `.internalTransfer` **inflow** leg now credits `targetAmount` (in the deposit's currency), matching `contribution`'s `getTargetAmount` — previously it used the source-side `convertedAmount`, adding a wrong-currency amount to the principal for cross-currency top-ups.
- The `.internalTransfer` **outflow** leg uses `-amount`, which is correct because the deposit is the source so `amount` is already in the deposit's currency (not an asymmetry to "fix").

Do NOT collapse `principalDelta` into `contribution` — the capitalization gate above is the reason they exist separately.
