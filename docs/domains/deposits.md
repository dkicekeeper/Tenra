# Deposits Domain

Interest accrual, capitalization, and account → deposit conversion.

## Model

- `Account.isDeposit` and `AccountBalance.isDeposit` are computed (`depositInfo != nil`).
  `AccountEntity.isDeposit` is written from it and never read.
- `DepositInfo` (`Models/Transaction.swift`) is stored as JSON in `AccountEntity.depositInfoData`. A new
  field goes into the JSON with a decode default, no schema change.
- Fields: `initialPrincipal` (what the deposit starts from, = `Account.initialBalance`), `startDate`,
  `conversionTimestamp` (converted deposits only), `capitalizationEnabled`, `interestRateAnnual` and
  `interestRateHistory`, `interestPostingDay`, `dayCount`, and the interest state
  `interestAccruedForCurrentPeriod`, `lastInterestCalculationDate`, `lastInterestPostingMonth`.
- **There is no stored principal.** `principalBalance` and `interestAccruedNotCapitalized` are
  decode-only keys: a payload that has only `principalBalance` decodes it as `initialPrincipal`.

## Balance

A deposit's balance is `initialBalance + Σ BalanceCalculationEngine.contribution`, like every account.
For the current balance, `contribution` first drops what `initialPrincipal` already contains:

- converted deposit (`conversionTimestamp` set): every transaction with `createdAt <= conversionTimestamp`;
- fresh deposit: every transaction dated on or before `startDate`.

The rest counts as on any account: income, top-ups and `.depositInterestAccrual` add, expenses and
withdrawals subtract, transfers move by their leg. Posted interest always adds to the balance, with or
without capitalization.

## Interest walk (`DepositInterestService`)

`reconcileDepositInterest(account:allTransactions:onTransactionCreated:)` recomputes the open period from
its start on every call, so a transaction backdated into it is always counted:

- **Period start** (`currentPeriodStart`): the posting date of `lastInterestPostingMonth` (clamped to the
  month's length), never before `startDate`, and for a converted deposit never before the conversion day.
- **Events**: transactions on the deposit whose `type.affectsDepositPrincipal` (everything but loan
  payments) and that come after the anchor (`eventIsAfterAnchor`: `createdAt > conversionTimestamp` for a
  converted deposit, else `date > startDate`).
- **Running principal**: `initialPrincipal` plus the `principalDelta` of each event before the walk
  starts; it exists only inside the walk.
- **Days**: from the day after the period start through today inclusive (`<= today`), so opening the
  app on the posting day posts the period that just ended. Each day earns
  `runningPrincipal × rate / 100 × dayCount.dailyFraction(on: day)`, with the rate from
  `interestRateHistory`.
- **Value date T+1**: a day earns on the balance at its start, so an event dated D counts from D+1
  (`events[i].date < currentDate`, strictly). Pinned by `accrual_topUpEarnsFromNextDay`.
- **Posting**: on the posting day the accrued total is posted **before** that day accrues (the posting day
  opens the next period). Pinned by `reconcile_postsOnTodayWhenTodayIsPostingDay`. Posting creates a
  `.depositInterestAccrual` transaction, hands it to `onTransactionCreated` (the caller saves it) and sets
  `lastInterestPostingMonth`; it is skipped, with only the month marker moving, when the deposit already
  has an interest accrual dated in that month or later. With `capitalizationEnabled` the posted amount
  joins the running principal, so later days compound.
- **End**: writes `interestAccruedForCurrentPeriod` and `lastInterestCalculationDate = today`.

`calculateInterestToToday(depositInfo:accountId:allTransactions:)` runs the same walk read-only, for
display.

The interest state is written by the reconciler, set first by `DepositEditView` for a new or converted
deposit (below), and reset by `DepositsViewModel.recalculateInterest`.

### `principalDelta` vs `contribution`

`DepositInterestService.principalDelta` moves the walk's running principal; `contribution` moves the
balance. They stay separate: `.depositInterestAccrual` grows the principal only when
`capitalizationEnabled`, but always adds to the balance. Income, top-ups, expenses and withdrawals use
`convertedAmount ?? amount`; a transfer into the deposit credits `targetAmount` (the deposit's currency),
and a transfer out uses `-amount` (the deposit is the source, so `amount` is in its currency). Pinned by
`DepositPrincipalDeltaCharacterizationTests` and `DepositCrossCurrencyTransferTests`.

### Day-count convention (`DepositDayCount`)

Each deposit stores how its bank counts days (`DepositInfo.dayCount`). Kazakh banks mostly use 30/360
(Kaspi, Alatau City Bank; the National Bank's own deposits use actual/360), Russian banks actual/365 or 366.

| Case | Daily fraction | Note |
|------|----------------|------|
| `.thirty360` | weight / 360 | the 31st weighs 0, the last day of February 3 (2 in a leap year), others 1: every full month earns rate / 12; a period from the 15th earns 16 days |
| `.actual365` | 1 / 365 | `.legacy` |
| `.actualActual` | 1 / 365 or 1 / 366 | days of that calendar year |
| `.actual360` | 1 / 360 | |

New and converted deposits default to `.thirty360` (`defaultForNewDeposits`: the `DepositEditView`
picker, `AccountsViewModel.addDeposit`). A payload without the field decodes as `.legacy`, and
`DepositInfo.init` defaults to it. Changing the method affects the open period onward: the walk
recomputes from the period start, posted interest transactions stay. Pinned by `DepositDayCountTests`.

## Where reconciliation runs

- App launch: `AppCoordinator.reconcileDepositsOnLaunch`, after the FX prewarm wait and before the ledger
  recalculation; the posted interest goes in one `addBatch`.
- `DepositsListView`: on `.task` and after adding a deposit (all deposits).
- `DepositDetailView`: `.task(id: refreshTrigger)` (that deposit).
- After an account → deposit conversion: the convert sheet's `onSave` in `AccountsManagementView` and
  `AccountDetailView`.

Rules:

- ⚠️ Never spawn a `Task {}` inside the synchronous `onTransactionCreated` callback: collect the
  transactions and persist them after the reconcile returns.
- One accounts save per pass: `reconcileAllDeposits` applies every reconciled deposit with one
  `TransactionStore.updateAccounts`; `recalculateInterest` saves once. Pinned by `DepositReconcileSaveTests`.

## Recalculating interest

`DepositsViewModel.recalculateInterest(for:transactionStore:)` deletes the auto-posted interest
(`.depositInterestAccrual` whose id starts with `di_`), resets `lastInterestCalculationDate` to
`startDate`, `lastInterestPostingMonth` to the month before `startDate` and
`interestAccruedForCurrentPeriod` to 0, reruns the reconciler and adds the reposted interest in one batch.
User-linked interest keeps its own ids and stays.

Auto-posted interest ids are `di_` + a deterministic hash of deposit id, month, amount and currency
(`generateDepositInterestTransactionID`), stable across launches.

## Creating and converting

- `DepositEditView` handles new, edit and convert (`isConverting`).
- ⚠️ A new or converted deposit gets `lastInterestCalculationDate` / `lastInterestPostingMonth` from
  `DepositEditView.computeInitialDates(postingDay:)`: the latest posting date on or before today, so the
  first period starts there. An edit keeps the stored values.
- ⚠️ Add a deposit built by the edit screen with `AccountsViewModel.addDepositAccount(_:)`, which keeps
  those dates. `addDeposit(name:balance:…)` builds `DepositInfo` from fields with the init's default
  dates.

### Converting an account with history

`AccountsViewModel.updateDeposit` detects a conversion (the stored account has no `depositInfo` yet). It
keeps the account's id and history, stamps `depositInfo.conversionTimestamp` (now) and persists the
snapshot balance with `BalanceCoordinator.persistInitialBalance` (CoreData and memory;
`AccountRepository.saveAccountsInternal` never overwrites `initialBalance`). Every transaction that
existed at conversion then stays out of the balance (`contribution`'s `createdAt` gate) and out of the
interest walk (`eventIsAfterAnchor`). `createdAt` is a timestamp, so same-day events before and after the
conversion separate. `DepositEditView` carries `conversionTimestamp` over on edits.

Pinned by `BalanceLedgerInvariantTests` (`convertedDepositRecalcDoesNotDoubleCountHistory`,
`convertedDepositRecalcCorrectAfterRelaunchModeLost`, `convertedDepositSameDayEventsSeparatedByCreatedAt`,
`inSessionConversionAppliesCutoff`) and `DepositInterestServiceTests`
(`convertedDeposit_excludesPreConversionEvents_noNegativeInterest`,
`convertedDeposit_postConversionTopUpStillAccrues`).

⚠️ A converted deposit without `conversionTimestamp` falls back to the `startDate` cutoff, so inherited
income and expenses dated after `startDate` count twice; such deposits stay corrupted until a one-shot
recovery, which does not exist yet. The DEBUG-only `LegacyDepositDiagnostics` (Settings → Experiments)
lists the suspicious ones and changes nothing.

## Linking existing transactions as interest

`DepositsViewModel.linkTransactionsAsInterest(depositId:transactions:transactionStore:)` rewrites each
picked transaction as a `.depositInterestAccrual` on the deposit (type, the "Interest" category,
`accountId` / `accountName`) through `TransactionStore.update`, and leaves `DepositInfo` alone. UI:
`DepositLinkInterestView` over the shared `LinkPaymentsView` with `Options.deposit`
([loans.md](loans.md) §Link-Payments UI).
