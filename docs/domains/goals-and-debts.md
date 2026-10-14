# Goals and debts

Savings goals and personal debts: two small domains with their own CoreData rows (v15), cards
in Finances, list, detail and edit screens. They read accounts but never write them: a goal or
a debt never changes an account balance or a transaction. Goals are free; debts are Tenra Pro.
Ten (the assistant) reads and drafts them in phase 4b of
[plan-ai-assistant.md](../plan-ai-assistant.md).

## Model

| Type | File | What it is |
|---|---|---|
| `SavingsGoal` | `Models/SavingsGoal.swift` | name, icon, target, currency, optional deadline, optional `linkedAccountId`, `contributions`, `reachedAt`, `order` |
| `GoalContribution` | same | money put towards a goal by hand, in the goal's currency |
| `PersonalDebt` | `Models/PersonalDebt.swift` | `direction` (`owedToMe` / `iOwe`), person, amount, currency, `date`, optional `dueDate`, note, `repayments`, `settledAt` |
| `DebtRepayment` | same | money that came back, in the debt's currency |

Bank loans are accounts with `LoanInfo` ([loans.md](loans.md)); a `PersonalDebt` is between
people and has no account.

## Storage

- `GoalEntity` and `DebtEntity` (CoreData v15), read and written only by `GoalRepository`
  (`Services/Goals/`) and `DebtRepository` (`Services/Debts/`), outside the
  `DataRepositoryProtocol` facade like the assistant's threads and facts. A goal's
  contributions and a debt's repayments are JSON on their row; the icon is `IconSource` JSON as
  on `AccountEntity`.
- Backups carry them (the store file is copied whole), "delete all data" destroys them with the
  store, and both stores reload on `CoreDataStack.storeDidResetNotification`.
- `GoalStore` and `DebtStore` (`ViewModels/`, `@Observable`) are the single source of truth,
  owned by `AppCoordinator` and loaded right after `isFullyInitialized`. A nil repository keeps
  them in memory (previews on `UserDefaultsRepository`, tests).

## Rules

- **Saved amount.** A goal with a linked account that still exists follows its live balance
  (`GoalStore.accountBalance`, wired by `AppCoordinator` to `BalanceCoordinator.balances`),
  converted to the goal's currency, never below zero. Without an account, or once the account
  is gone, it is the sum of the contributions. `GoalStore.totalSaved(in:)` counts an account
  that several goals follow once.
- **Progress** is `GoalProgress.status` (`Services/Goals/GoalProgress.swift`): fraction, what is
  left, reached, and with a deadline the months left (the current one counted, at least 1:
  14 Oct → 14 Apr is 6, → 20 Apr is 7) and what to put aside each month. A deadline behind
  today on a goal not reached is overdue. Every screen (and Ten) uses this, never its own maths.
- **Reached** is noted once: `GoalStore.refreshReached` sets `reachedAt` when the saved amount
  first reaches the target (the detail screen bursts confetti on `true`) and clears it if the
  goal falls back below.
- **Settling.** A repayment that covers what is left settles the debt on its date; deleting that
  repayment opens it again. "Settle" by hand (returned outside the app, or the rest forgiven)
  and "Reopen" are the person's own; lowering the amount to what already came back settles it.
- **Overdue**: open and its due date is before today (`PersonalDebt.isOverdue`), a red badge in
  the list.
- **Sorting.** Goals in list order (creation); reached goals in their own section. Open debts per
  direction by due date (soonest first, undated after, then oldest), settled ones latest first.
- **Pro gate (debts).** Every add path (the list's "+", the empty state's button) opens the
  paywall without Pro and continues into the form once Pro is on (`paywallSheet(onUnlocked:)`).
  Debts already kept stay open to view, repay, settle and edit. Goals have no gate.
- **Base-currency totals** on the Finances cards convert with `CurrencyConverter.convertSync`
  (the amount itself as the cold-cache fallback); the cards take
  `TransactionStore.currencyRatesVersion` so they redraw when rates refresh.

## Screens

| Screen | File |
|---|---|
| Finances cards | `Views/Components/Cards/GoalsCardView.swift`, `DebtsCardView.swift` (after Loans) |
| List rows | `GoalCard`, `DebtCard`: adapters over DesignKit's `PayoffProgressCard`, as `LoanCard` |
| Lists | `Views/Goals/GoalsListView.swift`, `Views/Debts/DebtsListView.swift` |
| Details | `GoalDetailView`, `DebtDetailView` on `EntityDetailScaffold`: hero with progress, actions, info rows, history (long press deletes an entry) |
| Edit | `GoalEditView` (hero with icon, name, target and currency; deadline; account, or none with "already saved"), `DebtEditView` (direction, amount, who, date, due date, note) |
| Money in | `Views/Components/Forms/MoneyEntrySheet.swift`: a contribution or a repayment, laid out as `LoanPaymentView` (calculator keypad, note, date buttons); another currency converts to the goal's or debt's on save |

Navigation goes through `FinancesDestination` (`.goals`, `.goalDetail(id)`, `.debts`,
`.debtDetail(id)`).
