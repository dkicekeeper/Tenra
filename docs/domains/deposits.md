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

### Value date T+1 (start-of-day balance)

Each day's interest is computed on the balance at the **start** of the day (= the
previous day's close), so money earns only from the day **after** it arrives — matching
KZ bank convention (incl. Freedom). In the walk this is `events[i].date < currentDate`
(strictly), NOT `<=`. A top-up dated the 26th first earns on the 27th. Pinned by
`accrual_topUpEarnsFromNextDay`. (A bank may still differ on when it *value-dates* a
specific top-up — the app uses a uniform T+1, so a freshly-added amount the bank hasn't
credited yet will read higher in-app until it matures.)

### Posting day is exclusive of its own interest

Interest posted on the posting day (e.g. the 1st) covers the period that just **ended**,
through the day before. The walk posts the accrued total **before** accruing the posting
day itself — the posting day's interest opens the next period. (Accruing-then-posting
added one extra day to every posting.) Pinned by `reconcile_postsOnTodayWhenTodayIsPostingDay`.

## DepositInterestService.reconcileDepositInterest

- Triggered on view appear (`.task {}`), app launch, and `AccountsManagementView`
- Walks `walkStart … today` **inclusive** (`<= today`) so the posting fires on the
  posting day itself (opening the app on the 1st must post May's interest, not skip it)
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

### ⚠️ Converting an account WITH history → `DepositInfo.conversionTimestamp`

`AccountsViewModel.updateDeposit` detects a conversion (the existing account still has `depositInfo == nil`). The converted account keeps its full transaction history (same `id`), but its current balance is snapshotted into `initialPrincipal`. Every tx that already existed at conversion is therefore baked into that snapshot and must NOT be re-summed by `recalculateAll`.

**The cutoff keys on `conversionTimestamp`, not `startDate`.** On conversion `updateDeposit` stamps `depositInfo.conversionTimestamp = Date().timeIntervalSince1970` (persisted inside `depositInfoData` JSON — survives relaunch) AND `setInitialBalance(snapshot)` so the engine's base matches the snapshot in-session too. [`BalanceCalculationEngine.contribution`](../../Tenra/Services/Balance/BalanceCalculationEngine.swift) then excludes any tx with `createdAt <= conversionTimestamp` from the `.currentBalance` sum, so `recalculateAll` reproduces `initialBalance + Σ(post-conversion)`. Because `createdAt` is a precise timestamp (not a calendar day), same-day pre- vs post-conversion events are separable — the gap that previously forced the `.preserveImported` workaround. `DepositEditView` preserves the marker across deposit edits. Pinned by `BalanceLedgerInvariantTests.convertedDepositRecalcCorrectAfterRelaunchModeLost` + `…SameDayEventsSeparatedByCreatedAt` + `…DoesNotDoubleCountHistory`.

> **Why the change & the `BalanceMode` removal:** the prior fix marked the account `.preserveImported`, a per-account mode living ONLY in the in-memory `BalanceStore.calculationModes` dict, which is never persisted. On the next-day cold launch `recalculateLedgerIfDayChanged` runs `recalculateAll` with an empty mode dict → the converted deposit reverted to the default `.fromInitialBalance`, and the past-dated `startDate` cutoff let inherited history dated after it double-count → the "huge negative balance days later" bug (e.g. a deposit dropping to −3.4M overnight). Since the conversion was the ONLY production user of `.preserveImported`, the entire `BalanceMode` machinery (`markAsImported` / `markAsManual` / `isImported` / `calculationModes` / the engine's mode switch) was removed — every account now computes `initialBalance + Σ contribution`, with the gates inside `contribution` doing all the exclusion.

> Known follow-up: the **interest** walk (`DepositInterestService`) is independent of the balance path and still filters by `startDate` (the open interest period's start). Inherited income/expense/linked-interest dated after it can still pollute the running principal used for interest accrual. Tracked separately — does not affect the displayed balance.

> ⚠️ **Deposits converted BEFORE this fix have `conversionTimestamp == nil`** and fall back to the old `startDate` date-cutoff — they stay corrupted until a one-shot recovery backfills the marker and restores `balance` from `initialPrincipal`. (Recovery is a separate step, not part of the conversion fix.)

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
