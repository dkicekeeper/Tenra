# Audit 2026-09-24 (part 1): features that work "technically" but do not deliver their value

Written by the improve skill (deep, product-defect focus) against commit `a57d5fe4`.
Every finding below was confirmed by reading the cited code. Line numbers are as of
that commit. Plans for the selected findings are `plans/005`–`plans/011`; see
`plans/README.md` for order and status.

## Findings (ordered by leverage)

| # | Finding | Impact | Effort | Confidence | Plan |
|---|---|---|---|---|---|
| F1 | A manual balance correction is kept in memory only and reverts on the next full recalc | every user who ever corrected an account balance | S | HIGH | 005 |
| F2 | Renaming a category never renames its transactions: edits of old transactions fail, the category "empties" after relaunch | every user who renamed a category | M | HIGH | 006 |
| F3 | Importing past transactions into an account created with a real current balance shifts that balance | every statement/CSV importer | M | HIGH | 007 |
| F4 | PDF statement import has no duplicate detection, and imported charges duplicate auto-generated subscription occurrences | Pro import users | M | HIGH | 008 |
| F5 | Weekly digest and insight signals default ON, but notification permission is almost never requested | nearly everyone | S | HIGH | 009 |
| F6 | History category filter applies only one (random) category of a multi-selection; "Uncategorized" never matches | everyone | S | HIGH | 010 |
| F7 | Siri "how much did I spend" excludes loan payments that the home summary counts | Siri + loan users | S | HIGH | 011 |
| F8 | Statement import drops the operation-type column; own-account transfers, top-ups and cash withdrawals count as spending/income | statement importers | M-L | MED | not planned |
| F9 | Subscription reminders are scheduled for the next charge only and rescheduled only on app activation | subscription users who rarely open the app | S | HIGH | not planned |
| F10 | Backups are manual only; the iCloud location is off by default | everyone without device iCloud Backup | M | HIGH | not planned |
| F11 | Dead code: `TransactionsViewModel.updateTransactionCategory` + `CategoryRule` load/save are never applied | none (maintenance) | S | HIGH | not planned |

## Evidence

**F1.** `Tenra/ViewModels/AccountsViewModel.swift:92-122`: when the edit changes the
balance, the corrected `initialBalance` goes to `store.updateAccount(corrected)` and
`coordinator.setInitialBalance(...)` (memory only). `AccountRepository.saveAccountsInternal`
never writes `initialBalance` for existing accounts (`Tenra/Services/Repository/AccountRepository.swift:252`,
"set once at creation"). `BalanceCoordinator.persistInitialBalance` exists for exactly
this (`Tenra/Services/Balance/BalanceCoordinator.swift:218`). A full recalc from the
persisted value runs whenever a future-dated transaction matures
(`TransactionStore.recalculateLedgerIfDayChanged`, `Tenra/ViewModels/TransactionStore.swift:603-641`),
on base-currency change and on FX heal, i.e. at least monthly for anyone with a subscription.
CLAUDE.md documents the same failure mode for deposit conversion.

**F2.** `TransactionStore.updateCategory` (`Tenra/ViewModels/TransactionStore+CategoryCRUD.swift:65-105`)
only calls `renameCategoryIndexKeys` (`TransactionStore+CategoryIndex.swift:181-219`),
which re-keys in-memory indexes. No code rewrites `Transaction.category`, the CoreData
`TransactionEntity.category`, or `RecurringSeries.category`. Consequences:
`TransactionStore.validate` (`TransactionStore.swift:1062-1074`) rejects a non-empty
category that is not in `categories`, so saving an edit of an old transaction fails with
`categoryNotFound`; the cold index rebuild groups by `tx.category`
(`TransactionStore+CategoryIndex.swift:96-99`), so after relaunch the renamed category's
transaction list is empty and the old name shows up in the History filter as a "deleted
category"; recurring series keep generating the old name.

**F3.** `BalanceCalculationEngine.calculateBalance` = `initialBalance + Σ contribution`
over every realized transaction, no account-creation cutoff
(`Tenra/Services/Balance/BalanceCalculationEngine.swift:71-86`). Onboarding creates the
first account with the user's real current balance (`Tenra/ViewModels/OnboardingViewModel.swift:133-139`).
`ImportTransactionPreviewView.addSelectedTransactions` adds historical rows through
`transactionStore.add` with no balance compensation.

**F4.** `TransactionFingerprint` is used only by the CSV path
(`Tenra/Services/CSV/CSVImportCoordinator.swift:58,206`); the PDF/receipt review
(`Tenra/Views/Import/ImportTransactionPreviewView.swift`) adds every selected row.
The recurring generator dedupes only its own occurrences by `seriesId:date`
(`Tenra/Services/Recurring/RecurringTransactionGenerator.swift:117-135`), so a
subscription occurrence and the imported bank charge for it both count. Loans removed
auto-generation for the same reason (`docs/domains/loans.md` "No Auto-Reconciliation").
Side effect: the "subscription price increase" signal
(`Tenra/Services/Insights/InsightsService+Recurring.swift:143-163`) reads only
series-linked transactions, which carry the series' own amount, so it effectively
fires only on the user's own series edits.

**F5.** `InsightSignalSettings` defaults the master switch and the weekly digest to ON
(`Tenra/Services/Notifications/InsightSignalSettings.swift:66-67`). Both senders bail out
without authorization (`WeeklyDigestScheduler.swift:74-75`, `InsightSignalService.swift:260-263`).
`requestAuthorization` is called only from the Settings toggle
(`Tenra/Views/Settings/InsightSignalSettingsView.swift:60`, which a default-ON user never
touches) and when saving a subscription with reminders (`SubscriptionEditView.swift:209`).
Both senders already accept `.provisional`.

**F6.** `CategoryFilterView` returns a `Set<String>` (`Tenra/Views/Components/Input/CategoryFilterView.swift:205`);
History passes only `selectedCategories?.first` (`Tenra/Views/History/HistoryView.swift:346`)
into `category == %@` (`Tenra/ViewModels/TransactionPaginationController.swift:285-288`).
The filter lists empty categories under the localized label "Uncategorized"
(`Tenra/Services/Transactions/TransactionQueryService.swift:237-239`), which never equals
the stored empty string.

**F7.** `SpendingQueryService.total` fetches `type == expense` only
(`Tenra/Services/Intents/SpendingQueryService.swift:44-48`). The summary rule counts
`.expense`, `.loanPayment` and `.loanEarlyRepayment` as spending
(`Tenra/Models/SummaryContribution.swift:47`). CLAUDE.md Red Flag 11 forbids divergent summary paths.

**F8.** `StatementInterpreter.description(from:roles:)` uses only the description column
when one exists (`Tenra/Services/Import/StatementInterpreter.swift:182-198`); `ColumnRole`
has no operation-type role (`ColumnRoleResolver.swift:16-23`); no path emits
`TransactionDirection.transfer`, so `ParsedTransactionMapper`'s `.transfer` branch is
unreachable. Needs a real Kaspi PDF to design the mapping (Покупка / Перевод / Пополнение / Снятие).

**F9.** `SubscriptionNotificationScheduler.scheduleNotifications(for:nextChargeDate:)`
schedules one charge (`SubscriptionNotificationScheduler.swift:34-77`); rescheduling runs on
`applicationDidBecomeActive` (`TransactionStore.swift:396-398`); `BackgroundInsightsRefresher`
reschedules only the weekly digest (`BackgroundInsightsRefresher.swift:193-201`).

**F10.** `CloudBackupService.isICloudEnabled` defaults to false
(`Tenra/Services/Utilities/CloudBackupService.swift:48-50`); `createBackup` is called only
from the Backups screen button (`Tenra/Views/Settings/CloudBackupsView.swift:73`).
Mitigation today: the CoreData store is part of the device iCloud Backup when the user has it on.

**F11.** `updateTransactionCategory` (`Tenra/ViewModels/TransactionsViewModel.swift:264`)
has no callers; `CategoriesViewModel` loads/saves `CategoryRule`s that nothing applies.
Superseded by `CategorySuggestionService` (history tier) and the "apply to similar" prompt.

## Direction options (not bugs)

- **Balance from the statement.** Kaspi statements print the closing balance; import could
  offer to set the account balance from it instead of only preserving the current one (F3).
- **Subscriptions as expected, not assumed, payments.** Keep a generated occurrence "expected"
  until a real charge arrives and merge them. Closes F4 at the root, makes price-increase
  detection real, and stops cancelled-but-not-paused subscriptions from "charging" forever.
  Larger than plan 008; plan 008 only prevents the double count at import time.
