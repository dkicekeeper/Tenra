# Deposit Action Parity with Accounts — Design

**Date:** 2026-04-29
**Status:** Approved

## Problem

`DepositDetailView`'s "Add transaction" sheet currently exposes a `Top-up / Withdrawal` segmented picker — both options create `.internalTransfer` events between the deposit and another account, just with swapped source/target. The flow has no way to record income directly into a deposit (e.g. salary deposited into savings, third-party payout) tagged with an income category, the way regular accounts can via their `Transfer / Top-up` picker.

The user wants the deposit action sheet to mirror the regular-account UX exactly: `Перевод (Transfer) / Пополнение (Top-up)`, where `Top-up` produces an income transaction tagged with an income category.

## Decisions

### D1. Component reuse

`AccountActionView` and `AccountActionViewModel` are already shared between regular accounts and deposits via the `transferDirection: DepositTransferDirection?` parameter. The parameter and the enum are **removed**. After this change, neither file has any `if account.isDeposit` branch — deposits behave exactly like regular accounts in the action sheet.

### D2. Direction in `Transfer` mode (Variant A)

When `Transfer` is selected on a deposit, the deposit is **always the source**. The user picks the target account. To put money into a deposit, the user navigates to the source account's detail and transfers from there (existing flow). The deposit's action sheet does not offer "transfer in" as a direction.

### D3. `Top-up` mode on a deposit

Selecting `Top-up` shows the income-category picker (same as regular accounts). On save, the form creates a `.income`-typed `Transaction` with `accountId = deposit.id` and `category = chosen income category`. The transaction goes through `transactionStore.add(_:)` — no special-case path.

### D4. Deposit balance reconcile must count `.income` (and `.expense`)

Deposit balance is derived from `DepositInfo.principalBalance`, which is mutated only by `DepositInterestService.reconcileDepositInterest` walking deposit-event transactions. To make `.income` on a deposit grow the principal:

- Introduce `TransactionType.affectsDepositPrincipal: Bool` returning `true` for `.depositTopUp | .depositWithdrawal | .depositInterestAccrual | .income | .expense`.
- Replace the inline filter `(tx.type == .depositTopUp || tx.type == .depositWithdrawal || tx.type == .depositInterestAccrual)` in both `reconcileDepositInterest` and `calculateInterestToToday(depositInfo:accountId:allTransactions:)` with `tx.type.affectsDepositPrincipal`.
- Extend `principalDelta(for:capitalizationEnabled:)` with:
  - `case .income: return Decimal(tx.amount)`
  - `case .expense: return -Decimal(tx.amount)`

`.expense` is added for symmetry — even though the new UI does not expose an "expense from deposit" mode, an `.expense` transaction may already exist on deposit accounts via legacy data, voice input, CSV import, or future flows. Counting it consistently prevents principal divergence.

### D5. Currency conversion on deposit `.income`

`AccountActionViewModel.saveIncomeTransaction` already converts the input amount to the account's currency when they differ and writes `convertedAmount`. Reconcile reads `tx.amount` (source currency). To keep the principal consistent with the deposit's display currency:

- `principalDelta(for:capitalizationEnabled:)` must use `convertedAmount` when present (the value already in deposit currency), falling back to `amount`.

### D6. Incremental balance updates must skip deposits

`BalanceCalculationEngine.applyTransaction` and `calculateDelta` currently apply `.income` / `.expense` deltas to any account, including deposits. Once `.income` lands on a deposit, the incremental path would add `tx.amount` to the live balance while reconcile separately mutates `principalBalance` — double-counting.

Fix: in both `applyTransaction` and `calculateDelta`, gate `.income` / `.expense` deltas on `!account.isDeposit`. For deposits the live balance is sourced from `calculateDepositBalance(depositInfo:)` after reconcile runs; the incremental path becomes a no-op for these types (matching the existing `.depositTopUp/.depositWithdrawal/.depositInterestAccrual` no-op behavior).

### D7. Reconcile trigger on add/edit/delete

`DepositDetailView` runs `depositsViewModel.reconcileDepositInterest(for:allTransactions:onTransactionCreated:)` once per appearance via `.task {}` (no id). After saving a `Top-up` from the action sheet, the sheet dismisses and the deposit detail re-renders, but `.task {}` without id does not re-fire on re-render — only on view recreation.

Fix: change the reconcile task to `.task(id: refreshTrigger)` so it re-runs whenever the count of relevant transactions changes (the existing `refreshTrigger` already counts deposit-related transactions and increments on add/edit/delete).

### D7a. Same-day principal recomputation

`DepositInterestService.reconcileDepositInterest` early-exits when `lastInterestCalculationDate >= today` and never rewrites `principalBalance` in that branch. Today's `.income` top-up therefore would not affect the deposit balance until the next calendar day's reconcile. This breaks the "balance grows immediately after Top-up" UX.

Fix: in `reconcileDepositInterest`, replace the early-exit with an unconditional principal recomputation. Walk all events with `tx.date > startDate && tx.date <= today` (filtered by `affectsDepositPrincipal`), set `depositInfo.principalBalance = runningPrincipal`, then short-circuit the day-by-day interest-accrual loop if there are no new days to walk. `syncDepositBalance` (already called by the view-model wrapper) propagates the refreshed `principalBalance` to `BalanceCoordinator`. Reconcile remains idempotent — re-running on the same data yields the same `principalBalance`.

### D8. `DepositDetailView` button layout

- Remove `DepositTransferDirection` enum.
- Replace `@State activeTransferDirection: DepositTransferDirection?` with `@State showingAction: Bool`.
- Primary `Add transaction` button → `showingAction = true`.
- **Remove the secondary `Transfer` button.** A single primary action matches the regular-account detail screen; the segmented picker inside the sheet covers both modes. This is a UX simplification and brings deposits to parity.
- The sheet uses `.sheet(isPresented:)` instead of `.sheet(item:)`.

### D9. Default mode in the sheet

`AccountActionViewModel.selectedAction` defaults to `.transfer`. For deposits opened from `Add transaction`, default to `.income` (Top-up) — matches the expected primary action ("recording income into the savings deposit"). Pass an optional `defaultAction: ActionType?` to the view model init; when `account.isDeposit` and the caller does not specify, default to `.income`. Regular accounts continue to default to `.transfer`.

## Files Changed

**Modified:**
- `Tenra/ViewModels/AccountActionViewModel.swift` — drop `transferDirection`, drop deposit branches in `navigationTitleText` / `headerForAccountSelection` / `saveTransfer`, add `defaultAction: ActionType?` init parameter, default to `.income` for deposits.
- `Tenra/Views/Accounts/AccountActionView.swift` — drop `transferDirection` init parameter, drop `if account.isDeposit` branch in `safeAreaBar`, single `Transfer / Top-up` picker.
- `Tenra/Views/Deposits/DepositDetailView.swift` — drop `DepositTransferDirection` enum, drop `activeTransferDirection`, drop secondary action, switch sheet to `isPresented`, change reconcile `.task` to `.task(id: refreshTrigger)`.
- `Tenra/Models/Transaction.swift` — add `TransactionType.affectsDepositPrincipal: Bool`.
- `Tenra/Services/Deposits/DepositInterestService.swift` — replace inline filters with `affectsDepositPrincipal`, extend `principalDelta` for `.income/.expense` (using `convertedAmount` when present).
- `Tenra/Services/Balance/BalanceCalculationEngine.swift` — gate `.income/.expense` deltas on `!account.isDeposit` in `applyTransaction` and `calculateDelta` (and `revertTransaction` for symmetry).

**New tests:**
- `TenraTests/Services/Deposits/DepositInterestServiceTests.swift` — coverage for the new `.income/.expense` cases (or extend existing test file if present).
- `TenraTests/ViewModels/AccountActionViewModelTests.swift` — saving `.income` on a deposit; default action selection.

## Edge Cases

- **Existing `.income` transactions on deposits.** A regular account may have been converted to a deposit via `DepositEditView`, leaving prior `.income` transactions on the account. `DepositInfo.startDate` already gates reconcile to events strictly after `startDate` — pre-conversion income remains baked into `initialPrincipal`. Behavior is unchanged for legacy data.
- **Capitalization off + `.income`.** `interestAccruedNotCapitalized` is only written by interest postings; `.income` from the new flow updates `principalBalance` directly via the running-principal walk. No special handling needed.
- **CSV round-trip.** `.income` on a deposit is exported as a regular `income` row (not `deposit_topup`) — CSV mapping is type-driven and remains consistent. No changes required.
- **Recurring `.income` series targeting a deposit.** Already supported by `transactionStore.createSeries` — generated `.income` transactions land on the deposit account and reconcile counts them. No changes required.
- **`DepositLinkInterestView`.** Reclassifies `.income` on a deposit into `.depositInterestAccrual`. Behavior is unchanged: both the source `.income` and the resulting `.depositInterestAccrual` are now in `affectsDepositPrincipal`, so the principal walk is consistent before and after reclassification (delta is `+amount` in both states, but `.depositInterestAccrual` is gated on `capitalizationEnabled`). When capitalization is **off**, the principal contribution drops on reclassification — this matches existing semantics (interest accrued not capitalized lives in `interestAccruedNotCapitalized`, not in `principalBalance`). Acceptable.

## Out of Scope

- The existing Transfer flow on deposits creates `.internalTransfer` (not `.depositTopUp/.depositWithdrawal`). Whether that path correctly updates deposit principal is a pre-existing question outside this change; this design preserves current behavior.
- `BalanceCalculationEngine.applyTransactionToDeposit` is dead code (no callers). Not deleted here.
