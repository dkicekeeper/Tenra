# Backlog: open items, ideas, decisions

What is still open, what could be built next, and what the owner decided not to do. When an
item lands, delete its line here (git and the commit message keep the record); when a decision
changes, edit it. Larger work gets a plan file next to this one while it is in flight, and that
plan moves to `docs/archive/plans/` when it lands.

History: the audit of 2026-09-24 (plans 001-019) and the findings of 2026-09-24 to 2026-10-10,
with the commit of every fix, are in
[archive/plans/2026-09-24-audit/findings-2026-09-24-to-10-10.md](archive/plans/2026-09-24-audit/findings-2026-09-24-to-10-10.md).

## Open

- **Wallet probe code (DEBUG only).** The spike it served (does logging Apple Pay through the
  Shortcuts "Wallet" automation work?) was overtaken by the shipped automation (1.4, merchant
  memory; [domains/intents.md](domains/intents.md) §6). `WalletPaymentProbeIntent`,
  `WalletPaymentProbeLog` and their Experiments section still compile into DEBUG builds:
  remove them, or keep them for measuring trigger coverage. Owner's call.
- **Legacy converted deposits (DP1).** A read-only DEBUG diagnostic lists deposits converted
  before the `conversionTimestamp` fix (Settings → Experiments, `LegacyDepositDiagnostics`).
  Recovery waits for real data.
- **Performance left on the main actor:** `recalculateAll` for balances (one inverted O(N)
  pass); History's CoreData refetch after each debounced (300 ms) search change (the fetched
  results controller is bound to the view context).
- **All-accounts rescans on small edits:** `DepositDetailView`'s edit `onSave` and both
  `LoanDetailView` delete paths call `recalculateAccountBalances()` where
  `recalculateBalances(for:)` with the touched accounts would do.

Found by the docs audit of 2026-10-12, not verified on device yet:
- **Historical FX keys and the calendar.** `CurrencyConverter.dateKey` builds a `DateFormatter`
  without `en_US_POSIX` and the Gregorian calendar: on a device with a Buddhist or Japanese
  calendar region the historical-rate key gets another year.
- **Voice confirmation retry:** after a network FX conversion `VoiceInputConfirmationView`
  rebuilds the draft without `suggestAccount`, so the retry can pick another account.
- **`projected_balance` for `.year`:** averages the last 3 period points' expenses and
  multiplies by the period factor, so a year projects a 3-year average × 12
  (`InsightsService+CashFlow`).
- **Duplicate Siri submissions:** repeating a phrase can log the same transaction twice; the
  confirmation snippet is the only guard. Decide whether intents deduplicate.
- **Health score budget adherence** uses the calendar month, not each budget's own period;
  **`largeTransaction`** counts `.expense` only, so loan payments never qualify. Design calls.
- **`SilenceDetector`** is created in `VoiceInputService` but never fed audio.
- **Dead code and stale comments:** `TransactionStore.getPlannedTransactions(for:horizon:)` and
  `RecurringTransactionCoordinatorProtocol` have no callers or conformers;
  `AccountEntity.isDeposit` is written but never read (drop at the next schema bump); comments
  still name removed things (`principalBalance` in `DepositsViewModel` and `DepositDetailView`,
  aggregate services in `TransactionCacheManager`, the "no Other category" case in
  `LogTransactionIntent`).
- **DesignKit's docs/charts.md** repeats stale lines (`seriesKey`, the `.dual` banner, "~9
  switches", `ChartAxisLabelMapCache`): a DesignKit PR.

## Ideas, not planned yet

- **Savings goals ("Копилка").** `копилка` is already in the ru keyword field. Goal = target +
  optional deadline + linked account, progress = that account's balance (no new transaction
  types). Needs CoreData v13 (`/coredata-schema-bump`); bundle with personal debts.
- **Personal debts ("Долги").** `долг` is in the ru keyword field; `LoanInfo` models bank loans
  only.
- **Quick-add templates, widgets, Control Center, Lock Screen.** Templates first (in-app, cheap,
  the content a widget shows). There is no widget target or App Group today: share a small
  snapshot file through an App Group rather than moving the CoreData store.
- **Statement import:** a one-tap "align the balance to the statement" after the closing-balance
  check (today it only shows the difference).
- **Subscriptions as expected payments**, merged with the real charges when they arrive.
- **Receipt photo straight to the on-device model (iOS 27)** once
  `IntelligenceAvailability.supportsVision` is true on real devices: either an optional image in
  `DocumentSnapshot` or a vision interpreter in front of `ReceiptInterpreter` that falls back to
  the text path.

## Decisions (stand until the owner changes them)

- **Category tiles:** 3 per row, titles on one line (plan 018 reverted 2026-09-25: two-line
  titles made the grid jump).
- **Logo lookups** send brand names to Google favicons and logo.dev: accepted (2026-09-25).
- **No automatic repairs that move balances** (2026-10-06): a transfer out of a deposit lowers
  its interest base by the raw amount (pinned by a characterization test); changing an
  account's currency doesn't reconvert its transactions; transfers saved without a target
  amount before the edit fix stay as saved.
- **No family / shared budget**: it needs sync, and CloudKit sync was removed on 2026-04-22
  after data loss. Drop `семейный` from the ru keyword field in the next ASO pass.
- **No Create ML category model**: history, brand and keyword tiers are cheaper and explainable.
- **iPad deferred**: it matters for featuring, not for traffic
  ([promotion-plan.md](promotion-plan.md)).
- **Minimum iOS stays 26** (2026-08-26): older iOS would add 15-18% installs at the cost of a
  second UI path.
