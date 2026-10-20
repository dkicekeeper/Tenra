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
- Amounts are Doubles, so a debt counts as covered and a goal as reached within half a cent
  (`PersonalDebt.centTolerance`): 1 142.49 + 12 294.80 adds up to 13 437.289999999999. A debt
  its repayments settled opens again once they no longer cover it (a repayment deleted, the
  amount raised); one settled by hand stays settled. Changing the currency of a goal or a debt
  moves its contributions or repayments to the new one at today's rate; without a rate the
  currency stays as it was.
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
- **A receipt repays a debt.** A bank receipt shared to Tenra names who the money went to; when
  exactly one open "I owe" debt has that person (`DebtRecipientMatcher`: the same first name, and
  the same initial when both names have a second word; a person saved by first name alone takes
  only an initial after it, "Асель К."), `ReceiptConfirmationView` shows "It's a debt repayment",
  on when the name came from the receipt's recipient label (`ReceiptDraft.isRecipient`), off when
  it is only the receipt's top line. Saving adds the expense and, once it is saved
  (`TransactionsViewModel.addTransactionAndWait`), a `DebtRepayment` in the debt's currency
  (`convertSync`; without a rate there is no offer) of at most what is left. Pinned by
  `DebtRecipientMatcherTests`.
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
| Finances cards | `Views/Components/Cards/GoalsCardView.swift`, `DebtsCardView.swift` (after Loans): totals in `RedactableAmount` (hidden with the other amounts, a skeleton until the store loads), the open items on the `PackedCircleIcons(style: .shelf)` like every Finances card (debts: green owed to the person, red owed by them, sized by what is left in the base currency) |
| List rows | `GoalCard`, `DebtCard`: adapters over DesignKit's `PayoffProgressCard`, as `LoanCard` (a debt's note on one line); past its deadline or due date a goal or a debt carries a red `Badge`, and an overdue goal's footer says what is left |
| Lists | `Views/Goals/GoalsListView.swift`, `Views/Debts/DebtsListView.swift`: three `PayoffProgressCardSkeleton` until the store loads, then the list or the empty state with `.skeletonReveal` |
| Details | `GoalDetailView`, `DebtDetailView` on `EntityDetailScaffold`: hero with progress ("label · NN%", `.heroAccentGlow` from the item's icon), actions, info rows, history in one card of `HistoryEntryRow` (`Views/Components/Rows/`, an adapter over `AmountRow`; long press deletes an entry, which leaves with `DissolveTransition`). Reaching a goal or settling a debt plays `.celebration(playsHaptic: false)`: the save already gave its haptic |
| Edit | `GoalEditView` (hero with icon, name, target and currency; deadline; account, or none with "already saved"), `DebtEditView` (direction, amount, who, date, due date, note) |
| Money in | `Views/Components/Forms/MoneyEntrySheet.swift`, an adapter over DesignKit's `AmountEntrySheet` (4.14.0): a contribution or a repayment, laid out as `LoanPaymentView` (calculator keypad, note, date buttons); another currency converts to the goal's or debt's on save |

Navigation goes through `FinancesDestination` (`.goals`, `.goalDetail(id)`, `.debts`,
`.debtDetail(id)`).

## Ten

- **Context.** `<app_context>` lists the goals and the open debts by id and name with their
  currency (`savings goals:`, `open debts:` lines, AgentContextBuilder), never amounts.
- **Read tools** (`FinanceToolkit+Plans.swift`): `get_goals` (target, saved, left, percent,
  deadline, months left, monthly, reached, overdue, account; total saved in the base currency)
  and `get_debts` (open debts both ways and the ten latest settled, with repaid, remaining,
  due date, overdue; open totals each way). The numbers are GoalProgress and PersonalDebt.
- **Drafts**, saved on the confirm card through `AgentDraftBook.Writer.savePlan` and undone by
  `undoPlan`: `draft_goal` (with an account it follows the balance; without one it may start
  from `already_saved`), `draft_goal_contribution` (refused for a goal with an account: the
  answer points to a transfer), `draft_debt` (refused without Tenra Pro: the answer points to
  `draft_fact`), `draft_debt_repayment` (no amount is all that is left; more than left is
  refused; settles the debt on Save).
- **Ten writes first** (`AssistantInbox`): a debt due tomorrow (`debt:<id>:<day>`) and a goal
  behind its schedule (`goal:<id>:<month>`: a deadline, not reached, a month or more old, the
  saved share a fifth or more below the share of time gone). Posted after the stores load and
  whenever the app becomes active; the `<notice>` carries `debt_id` / `goal_id`.
- **Ask Ten** in the "…" menu of a goal and a debt (`AssistantTopic.goal`, `.debt`).
- The contract is `server/assistant/src/tools.ts`; the prompt's "Goals and debts" section says
  when to draft what; eval cases `ru-new-goal`, `ru-goal-on-track`, `ru-goal-contribution`,
  `ru-lent-money`, `en-paid-back`, `ru-who-owes-me`.
