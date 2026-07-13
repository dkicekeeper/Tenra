# Entity Detail Unification + Transaction History Consistency

**Date:** 2026-04-23
**Status:** Design — not yet implemented

## Problem

Two related inconsistencies in the app today:

1. **Missing detail screens.** `Account` and `CustomCategory` have no detail view. Tapping a row opens edit directly. Users can't see per-account/per-category transaction history, totals, or trends without leaving for the global `HistoryView` and manually filtering.
2. **Detail-screen divergence.** `SubscriptionDetailView`, `DepositDetailView`, and `LoanDetailView` all exist but were built independently. Hero layout, info-row styling, action placement, and — most visibly — transaction history rendering differ between them. History is inline on subscription detail but lives behind a toolbar button / separate sheet on deposit and loan detail.
3. **Transaction history fragmentation.** Three parallel implementations of "grouped-by-date transaction list":
   - `SubscriptionDetailView.transactionsSection` — manual `Dictionary(grouping:)` + plain `Text` section headers + `visibleTxLimit` pagination
   - `HistoryView` / `HistoryTransactionsList` — FRC-backed sections + `DateSectionHeaderView(.compact)` + `visibleSectionLimit` pagination
   - `LinkPaymentsView` — manual `Dictionary(grouping:)` + `SectionHeaderView(.compact)` + no pagination

   Visual symptoms: different header fonts, different empty states, different spacing, different pagination behavior.

## Goal

- Add `AccountDetailView` and `CategoryDetailView`.
- Unify all five detail screens (Subscription, Account, Category, Deposit, Loan) under one scaffold.
- Extract one `GroupedTransactionList` component used by all detail screens and by `LinkPaymentsView`. `HistoryView` stays on its FRC path but visually aligns (same `DateSectionHeaderView` variant, same `TransactionCard` call site).

## Non-Goals

- Redesigning `HistoryView` itself (filters, search, scope) — untouched.
- Account archiving — the model has no `isArchived` flag; not in scope.
- Category detail charts (donut by subcategory, monthly bar) — explicitly rejected during brainstorming.
- Changing `TransactionCard` — it stays as the row component everywhere.
- Reworking `AccountEditView`, `CategoryEditView`, etc. — they continue to exist, now launched from the detail screen's toolbar menu.

## Architecture

### New reusable components

All under `Views/Components/EntityDetail/` and `Views/Components/History/`.

#### `EntityDetailScaffold` — the outer shell

`Views/Components/EntityDetail/EntityDetailScaffold.swift`

```swift
struct EntityDetailScaffold<Hero: View, CustomSections: View, Menu: View>: View {
    let hero: Hero
    let primaryAction: ActionConfig?
    let secondaryAction: ActionConfig?
    let infoRows: [InfoRowConfig]
    let customSections: CustomSections         // EmptyView() when not needed
    let transactions: [Transaction]            // empty → history section hidden
    let historyContext: HistoryContext         // currency + lookups for rows
    let toolbarMenu: Menu
    let navigationTitle: String                // empty → hidden
}
```

Layout (top-down inside a `ScrollView`):

1. `hero` — caller-provided view (usually `HeroSection`, see below).
2. Actions bar — `HStack` of 0–2 buttons styled with `PrimaryButtonStyle`/`SecondaryButtonStyle`. Hidden when both are nil.
3. Info rows card — `FormSection(.card)` wrapping each `InfoRowConfig` as a `UniversalRow(config: .info)`. Hidden when `infoRows.isEmpty`.
4. `customSections` — caller-provided slot for loan amortization, deposit interest posting breakdown, etc. Scaffold wraps in `.screenPadding()`; caller builds its own cards inside.
5. `GroupedTransactionList` — shown only when `transactions.isNotEmpty`.
6. `.toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { toolbarMenu } label: { Image(systemName: "ellipsis") } } }`.

The scaffold owns `.screenPadding()` on each block and the outer `ScrollView` + `VStack(spacing: AppSpacing.lg)`. Callers pass pure content.

#### `HeroSection` — the standard hero

`Views/Components/EntityDetail/HeroSection.swift`

```swift
struct HeroSection: View {
    let icon: IconSource
    let title: String
    let primaryAmount: Double
    let primaryCurrency: String
    let subtitle: String?                  // secondary text under amount, e.g. "Next payment in 5 days"
    let progress: ProgressConfig?          // optional linear progress bar under the amount
    let showBaseConversion: Bool           // show ConvertedAmountView if currency != baseCurrency
}

struct ProgressConfig {
    let current: Double
    let total: Double
    let label: String?                     // e.g. "Budget" / "Paid off"
    let color: Color                       // defaults to .accentColor
}
```

Renders `IconView(style: .glassHero())` + title (`AppTypography.h1`) + `FormattedAmountText` (h4 secondary) + optional `ConvertedAmountView` + optional linear progress strip. Matches the existing subscription hero visually; `ProgressConfig` is the only addition.

Used for:

| Entity | `ProgressConfig` |
|---|---|
| Subscription | nil |
| Account | nil |
| Category (expense, has budget) | `{ current: spentThisPeriod, total: monthlyBudget, label: "budget", color: .red/.orange/.green by utilization }` |
| Category (no budget / income) | nil |
| Deposit | nil (kept as custom section — interest timeline is richer than a bar) |
| Loan | `{ current: principalPaid, total: originalAmount, label: "paid off", color: .accent }` |

#### `GroupedTransactionList` — the shared history renderer

`Views/Components/History/GroupedTransactionList.swift`

```swift
struct GroupedTransactionList: View {
    let transactions: [Transaction]        // pre-filtered slice
    let displayCurrency: String?           // card amount currency (nil → tx.currency)
    let accountsById: [String: Account]    // pre-resolved lookup
    let styleHelper: (Transaction) -> CategoryStyleData  // closure; caller decides cache strategy
    let pageSize: Int                       // default 100
    let showCountBadge: Bool                // default true
    let titleKey: LocalizedStringResource   // default "history.section.title"

    @ViewBuilder var rowOverlay: (Transaction) -> AnyView = { _ in AnyView(EmptyView()) }
}
```

Internals:

- Groups by `Transaction.date` (ISO string) via `Dictionary(grouping:)`, sorts descending.
- Section headers use `DateSectionHeaderView(style: .compact)` — the same one used by `HistoryView` and `LinkPaymentsView`.
- Rows render `TransactionCard` with pre-resolved `sourceAccount` / `targetAccount` / `styleData` (fixes the O(N²) account-lookup regression noted in CLAUDE.md).
- Pagination: `@State var visibleLimit` seeded with `pageSize`. Last `LazyVStack` row is a `ProgressView` whose `.onAppear` increments `visibleLimit` by `pageSize` until it reaches `transactions.count`.
- Header row: `HStack { Text(titleKey) · Spacer() · if showCountBadge { Text(count) } }`, font `AppTypography.h4`.
- Empty state: caller decides. Scaffold hides the whole section when `transactions.isEmpty`, so this component never renders empty.
- `rowOverlay` — optional view rendered on top of each `TransactionCard`. Used by `LinkPaymentsView` to layer its selection checkbox without forking the component.

Reactivity: component is pure. Caller re-evaluates `transactions` via `@State + .task(id: trigger)` (same pattern `SubscriptionDetailView` uses today). No new `@Observable` dependencies.

### Not unified (intentional)

- `HistoryView` keeps its FRC pipeline and its own list view. It switches to `DateSectionHeaderView(.compact)` if it isn't already on it, and continues to use `TransactionCard`. No source-of-data change. This keeps the "global history with filters/search/scope" behavior untouched; visual consistency comes from shared row + header components, not a shared list renderer.
- `LinkPaymentsView` keeps its matcher-scan pipeline for candidate generation but swaps its internal `LazyVStack`+manual-grouping block for `GroupedTransactionList` with a `rowOverlay` that draws the selection checkmark. Filters/search/action bar stay as-is.

## Per-Entity Specs

### AccountDetailView (new)

`Views/Accounts/AccountDetailView.swift`

- **Applies only to regular accounts.** Deposits and loans keep their own detail views (below). Caller should route based on `account.isDeposit` / `account.isLoan`.
- Hero: icon + name + `account.balance` in `account.currency`, base-currency conversion shown when different.
- Info rows:
  - Type (`account.type.displayName`)
  - Currency (`account.currency`)
  - Bank (shown only if `account.bankName != nil`)
  - Total transactions (count of `tx.accountId == account.id || tx.targetAccountId == account.id`)
  - Total income, all time (sum of `.income` into this account + `.internalTransfer` where target == this, in account currency; with base conversion)
  - Total expense, all time (sum of `.expense` from this account + outgoing transfers)
- Actions:
  - **Add Transaction** (primary) — opens `QuickAddView` with `accountId` pre-filled.
  - **Transfer** (secondary) — opens `AccountActionView` (existing) in transfer mode with this account as source.
- Toolbar menu: Edit · Delete.
- History: `tx.accountId == id || tx.targetAccountId == id`, sorted desc by date.

### CategoryDetailView (new)

`Views/Categories/CategoryDetailView.swift`

- Hero:
  - Icon (category color + `IconView`), name.
  - Primary amount = **total for selected period** (drives off `TimeFilterManager` like Insights). Currency = `appSettings.baseCurrency`.
  - Subtitle = period label ("This month" / custom range).
  - `ProgressConfig` only for expense categories with a monthly budget: `current = spent this month, total = budget, label = "budget"`, color stepped by utilization (≤75% green, ≤100% orange, >100% red).
- Info rows:
  - Type (expense / income) — `category.kind`
  - Budget (expense only, shown only when budget set) — "150 000 ₸ / 200 000 ₸ (75%)"
  - Average monthly spend (last 6 full calendar months, in base currency)
  - Total transactions, all time
  - Total amount, all time (in base currency; with original-currency breakdown if mixed)
  - Subcategories — count with trailing "→" chevron; taps into `SubcategoriesManagementView` scoped to this category.
- Actions:
  - **Add Transaction** (primary) — opens `QuickAddView` with `category` pre-filled. No secondary.
- Toolbar menu: Edit · Manage Subcategories · Delete (destructive with confirmation alert; warning text if transactions exist).
- History: `tx.category == category.name`, sorted desc.

### SubscriptionDetailView (refactor)

- Migrate to `EntityDetailScaffold`. Current hero becomes `HeroSection` (nil progress).
- Info rows stay the same: category, frequency, next charge, account, status, spent-all-time.
- Actions bar: 0 buttons (subscription has none today; keep that way).
- Custom sections: none.
- Toolbar menu: unchanged (Link Payments · Edit · Pause/Resume · Unlink all · Delete).
- History: `tx.recurringSeriesId == subscription.id`. Uses `GroupedTransactionList`.

### DepositDetailView (refactor)

- Migrate to `EntityDetailScaffold`. History becomes inline (removes the toolbar history icon and the separate `HistoryView` sheet).
- Hero: icon + bank name/title + balance + (optional) base-currency conversion. `progress` = nil.
- Info rows: rate, capitalization, posting day.
- Actions: Top Up (primary) · Transfer to Account (secondary). Unchanged.
- Custom sections: interest section ("Interest to today" / "Next posting", as today).
- Toolbar menu: Edit · Change Rate · Link Interest · Recalculate · Delete. **Remove** the separate history toolbar icon.
- History: `tx.accountId == account.id || tx.targetAccountId == account.id`.

### LoanDetailView (refactor)

- Migrate to `EntityDetailScaffold`. Same "history inline" change.
- Hero: icon + name + remaining principal + `ProgressConfig { current: principalPaid, total: original, label: "paid off" }`. Subtitle = "Next payment {date}".
- Info rows: rate, term, payments made/remaining, end date, total interest (projected), early repayments count.
- Actions: Make Payment (primary) · Early Repayment (secondary). Unchanged.
- Custom sections: payment breakdown card + amortization schedule card. Both keep their current internal layout; they just move from being top-level children to the scaffold's `customSections` slot.
- Toolbar menu: unchanged minus the history icon.
- History: `tx.accountId == account.id || tx.targetAccountId == account.id`.

### LinkPaymentsView (refactor)

- Replace its internal `LazyVStack` + manual date grouping (`LinkPaymentsView.swift:319–387`) with `GroupedTransactionList`.
- Selection checkmark renders via `rowOverlay`.
- Filters, matcher scan, action bar at top, search — all unchanged.

### HistoryView (alignment only)

- Confirm `DateSectionHeaderView(.compact)` is the header in use (if a different style is in use elsewhere, standardize on `.compact`).
- No other changes.

## Navigation

Current entry points open edit. New behavior:

| From | To |
|---|---|
| Account row in `AccountsManagementView` | `AccountDetailView` (regular) / `DepositDetailView` / `LoanDetailView` — branch on `isDeposit` / `isLoan` |
| Account card in home carousel | `AccountDetailView` / `DepositDetailView` / `LoanDetailView` |
| Category row in `CategoriesManagementView` | `CategoryDetailView` |
| Subscription row | `SubscriptionDetailView` (already the case) |

Edit is moved to each detail screen's toolbar menu. Long-press / alternative entry points: not added.

Entry points use `NavigationLink(destination:)` — same pattern as `SubscriptionDetailView`.

## Data & Performance

- History in detail screens filters `transactionStore.transactions` in memory. At ~19k transactions, a single O(N) pass + `Dictionary(grouping:)` runs in a few ms; acceptable.
- Caching follows the existing subscription pattern: `@State var cachedTransactions: [Transaction]` rebuilt inside `.task(id: triggerKey)` where `triggerKey` is a small `Equatable` struct (`count`, `lastUpdatedAt`, plus the entity id). `GroupedTransactionList` is fed the cached slice; per-row `styleData` / account lookup pre-resolved at the call site.
- Account/category aggregates (total income, total spent, avg monthly) computed once inside the same `.task` as part of a `DetailAggregates` struct — not recomputed per view body.
- No new CoreData fetch requests. All data reads go through `TransactionStore` + `AccountsViewModel` + `CategoriesViewModel`.

## Localization

New keys (add to both `Tenra/en.lproj/Localizable.strings` and `Tenra/ru.lproj/Localizable.strings`):

```
"account.detail.totalIncome" = "Total income";
"account.detail.totalExpense" = "Total expense";
"account.detail.transactionCount" = "Transactions";
"account.detail.actions.addTransaction" = "Add transaction";
"account.detail.actions.transfer" = "Transfer";
"account.detail.delete.confirmTitle" = "Delete account?";
"account.detail.delete.confirmMessage" = "This will permanently delete this account. Linked transactions behavior matches the existing `AccountsManagementView` delete flow (cascade rules to be confirmed against current behavior during implementation).";

"category.detail.totalSpent" = "Total spent";
"category.detail.totalEarned" = "Total earned";
"category.detail.avgMonthly" = "Avg. per month";
"category.detail.budget" = "Budget";
"category.detail.subcategories" = "Subcategories";
"category.detail.transactionCount" = "Transactions";
"category.detail.actions.addTransaction" = "Add transaction";
"category.detail.manageSubcategories" = "Manage subcategories";
"category.detail.delete.confirmTitle" = "Delete category?";
"category.detail.delete.confirmMessage" = "This will delete the category. %d transactions will keep this category name as their label.";

"history.section.title" = "History";
"history.empty" = "No transactions yet";
```

Russian equivalents go in `ru.lproj/Localizable.strings` with the same keys.

## Design System Compliance

- All spacing via `AppSpacing.*`, all colors via `AppColors.*` / `CategoryColors`, all typography via `AppTypography.*`.
- All buttons use `PrimaryButtonStyle` / `SecondaryButtonStyle`.
- All cards use `.cardStyle()` with explicit `.padding(AppSpacing.lg)` (the "rows own padding" contract from CLAUDE.md applies — scaffold doesn't inject padding around custom-section cards).
- Info rows go through `UniversalRow(config: .info)` inside `FormSection(.card)`.
- All animations use `AppAnimation` tokens (e.g., hero amount transitions use `AppAnimation.gentleSpring`).
- Section headers use `DateSectionHeaderView(style: .compact)` — the single source of truth for date headers across the app after this change.

## File Layout

```
Tenra/
├── Views/
│   ├── Accounts/
│   │   └── AccountDetailView.swift             NEW
│   ├── Categories/
│   │   └── CategoryDetailView.swift            NEW
│   ├── Subscriptions/
│   │   └── SubscriptionDetailView.swift        refactor → uses scaffold
│   ├── Deposits/
│   │   └── DepositDetailView.swift             refactor → uses scaffold, history inline
│   ├── Loans/
│   │   └── LoanDetailView.swift                refactor → uses scaffold, history inline
│   └── Components/
│       ├── EntityDetail/                       NEW directory
│       │   ├── EntityDetailScaffold.swift      NEW
│       │   ├── HeroSection.swift               NEW
│       │   ├── ActionConfig.swift              NEW (ActionConfig + InfoRowConfig + ProgressConfig)
│       │   └── DetailAggregates.swift          NEW (computed aggregate helpers for account/category)
│       └── History/                            NEW directory
│           └── GroupedTransactionList.swift    NEW
```

## Phasing (suggested build order)

1. **Foundation** — `EntityDetailScaffold`, `HeroSection`, `GroupedTransactionList`, `ActionConfig` + `InfoRowConfig` + `ProgressConfig`. Build in isolation with previews only.
2. **Subscription migration** — port `SubscriptionDetailView` to the scaffold. Smallest delta; proves the scaffold.
3. **Account detail** — build `AccountDetailView`, rewire `AccountsManagementView` and home carousel tap targets.
4. **Category detail** — build `CategoryDetailView`, rewire `CategoriesManagementView` tap targets.
5. **Deposit migration** — port `DepositDetailView`, move interest section into `customSections`, remove toolbar history icon.
6. **Loan migration** — port `LoanDetailView`, move breakdown/stats/amortization into `customSections`, remove toolbar history icon.
7. **LinkPaymentsView integration** — swap internal list for `GroupedTransactionList` with `rowOverlay` selection.
8. **HistoryView alignment** — ensure `DateSectionHeaderView(.compact)`, nothing else changes.
9. **Localization** — add all keys to both `.strings` files.

Each phase lands as its own commit and is verifiable independently: screens work before and after, no intermediate broken state.

## Risks / Open Questions

- **Category total currency conversion.** Transactions on a category can span currencies; "total spent all time" is shown in base currency. Uses `CurrencyConverter.convertSync` with historical-rate fallback to stored `convertedAmount`. Same approach the subscription detail already uses for `spentAllTime`; no new risk.
- **Loan `customSections` brittleness.** Loan detail has three custom cards today (breakdown, stats, amortization). They're preserved verbatim in the `customSections` slot — no internal refactor as part of this change. If the loan migration turns out painful, it can ship as a later phase without blocking the others.
- **`rowOverlay` + `TransactionCard` tap.** `TransactionCard` has its own `.onTapGesture` / sheet. In `LinkPaymentsView`, the selection tap currently wraps the card in a `Button`. The `rowOverlay` approach needs to suppress the inner gesture (or the card needs a `disableDefaultTap` flag). Verified risk — resolve in phase 7 by adding `tapAction: (() -> Void)?` to `TransactionCard` so `LinkPaymentsView` can override.
- **Home carousel navigation.** If the home carousel currently opens `AccountActionView` on tap (not edit), that flow changes to navigate to detail. Confirm the intended default at phase 3 — may be worth a short in-phase check with the user.
