# Assets

What the person owns and what it is worth: a home, a car, land, anything else. An asset has its
own CoreData row (v17), a card in Finances, list, detail and edit screens. It never changes an
account balance or a transaction: a flat bought in 2018 stays an expense, and the asset lives
next to it with its own purchase price and valuations; its rent and upkeep are the transactions
of the categories it is linked to. Adding an asset is Tenra Pro. Net worth (money, assets and
debts) is a free insight. The plan, its ideas for later and the owner's decisions:
[archive/plans/plan-assets.md](../archive/plans/plan-assets.md).

## Model

| Type | File | What it is |
|---|---|---|
| `Asset` | `Models/Asset.swift` | name, `kind`, icon, currency, optional purchase price and day, `valuations`, `depreciationPerYear` (0.15 for 15% a year; nil, the default, keeps the last valuation), `ownershipShare`, optional `linkedLoanAccountId`, `incomeLink` / `expenseLink` (`AssetCategoryLink`: a category id, never a name, and an optional subcategory id), `includeInNetWorth`, `soldAt`, `order`; and, kept for later, `note` |
| `AssetKind` | same | apartment, house, land, commercial (the list's real estate), vehicle (transport), other; the default icon of each |
| `AssetValuation` | same | a day, a value in the asset's currency, a source (`purchase`, `manual`, `assistant`, `sale`) and an optional note ("listings on krisha.kz") |

The purchase is not a stored valuation: `AssetValuationMath.history` puts it first, from the
purchase price and day. The sale is the `.sale` valuation, and `soldAt` its day.

## Storage

- `AssetEntity` (CoreData v17), read and written only by `AssetRepository` (`Services/Assets/`),
  outside the `DataRepositoryProtocol` facade like the goals and debts. Valuations and the category
  links are JSON on the row; the icon is `IconSource` JSON. The purchase price and the depreciation
  are optional numbers (`NSNumber`).
- Backups carry the assets (the store file is copied whole), "delete all data" destroys them with
  the store, and `AssetStore` reloads on `CoreDataStack.storeDidResetNotification`.
- `AssetStore` (`ViewModels/`, `@Observable`) is the single source of truth, owned by
  `AppCoordinator` and loaded with the goals and debts right after `isFullyInitialized`. A nil
  repository keeps it in memory (previews on `UserDefaultsRepository`, tests). `loanBalance`
  (wired by `AppCoordinator`) reads a linked loan account's `remainingPrincipal`.

## Rules

Every figure comes from `AssetValuationMath` (`Services/Assets/AssetValuationMath.swift`), never a
screen's own maths. All amounts are in the asset's currency; totals in the base currency convert
with `CurrencyConverter.convertSync`, the amount itself as the cold-cache fallback.

- **Value**: the latest valuation by day (of two on one day, the later added), else the purchase
  price; once sold, the sale price. The day of that figure is shown next to it ("Valued 16 Oct").
- **Depreciation** (off by default, the person sets it for transport and other things in the form;
  homes and land keep their last valuation): from the latest point (a valuation, else the
  purchase), `value × (1 − rate)^years`. The figure is an estimate, shown "≈ Estimate, valued
  16 Oct"; the asset's chart ends on it today ("30 Oct, estimate"), and so does the list's total
  when an asset depreciates. A new valuation is the new base. A sold asset keeps its sale price.
  `AssetValuationMath.estimate` over a `Timeline` (the dated points without the sale, the rate,
  the sale day, the share, the currency) gives the value on any day: none before the first point
  or from the sale on, an asset without a dated point at its value throughout.
- **Out of date** (`AssetValuationMath.isStale`): a held asset whose value was last set (the
  latest valuation, else the purchase, else when it was added) more than six months ago for real
  estate and transport, twelve for the rest. Its card shows an "Out of date" badge, its screen a
  banner that opens "Update value", and Ten writes once a half-year (below).
- **Gain**: value − purchase price, and as a percent of it; none without a purchase price (an
  inheritance, a gift). For a sold asset it is the result of the sale.
- **Growth a year**: `(value / price)^(1 / years) − 1`, only once a year has passed since the
  purchase (until the sale for a sold one). 24M → 70M over 8 years is about 14.3%.
- **Share**: `value × ownershipShare` is what counts in totals (a house owned with a spouse at
  50%); the gain stays the whole asset's.
- **Loan**: with a linked loan account that still exists, what is left of it (converted to the
  asset's currency) and the person's own money in the asset, owned value − loan left. A sold
  asset shows no loan.
- **Totals** (the Finances card, the list's hero): the held assets with `includeInNetWorth`, each
  at its share; the gain over the ones with a purchase price, as a percent of what they cost.
  `totalHistory` is their worth over time: a point on every day of a purchase or a valuation, each
  asset counted from its first point at its latest value up to that day, the latest 24 points.
- **Rent and upkeep**: the `.income` transactions of the income link and the `.expense` ones of
  the expense link (`AssetStore.transactionsOfLink`, wired by `AppCoordinator` to
  `TransactionStore`'s category index, filtered by the subcategory's transaction links), each in
  the asset's currency. Realized only: up to today, up to the sale for a sold asset. Over the 12
  months before that day, the rent, the upkeep and the yield, (rent − upkeep) ÷ value; since the
  purchase, the full result, gain + every rent − every upkeep (`AssetValuationMath.income`). A
  link whose category is gone reads as empty.
- **No double counting**: two assets' links overlap when they share a category and either takes
  the whole of it or both take the same subcategory (`AssetValuationMath.overlaps`); the form
  refuses one that overlaps another asset's (`InlineStatusText`, Save off).
- **Net worth** (`NetWorthCalculator`, `Services/Assets/`): money (accounts that are not loans,
  in the balance) + assets (held, `includeInNetWorth`, at their share) + what others owe −
  loans (remaining principal of loans in the balance, not paid off) − what the person owes,
  every part converted to the base currency. It is the free `net_worth` insight in the wealth
  section ([insights.md](insights.md) §Metric catalogue): `InsightsViewModel.netWorthHoldings`
  reads the assets and debts on the main actor when a pass starts, and `AssetStore.didChange` /
  `DebtStore.didChange` recompute the insights when they change (or load).
- **Net worth over time** (`NetWorthCalculator.history`, the insight's chart): at the end of each
  period of the granularity, the money's running balance (`cumulativeBalancePoints`, as the
  wealth chart) + each asset's `Timeline` value on that day + what was owed either way then (a
  debt from its day, less its repayments up to then, nothing once settled) − each loan in the
  balance as its schedule (`generateAmortizationSchedule`) left it, never less than is left today
  and nothing before it began. A period not over yet holds today's figure. The holdings carry
  the timelines of every asset counted in net worth, sold ones too, and every debt.
- **Sale**: "Sell" asks the price and the day, adds the `.sale` valuation (a second sale replaces
  it) and sets `soldAt`; the asset leaves the totals for the Sold section. No transaction is made:
  the money comes in as the person records it. "Undo sale", or deleting the sale's valuation,
  takes it back.
- **Editing the value** in the form adds a valuation of today (a sold asset's changes its sale
  price); a value left as it was adds nothing. A new asset bought today at the value typed has the
  purchase as its only point. Changing the currency moves the purchase price and the valuations at
  today's rate; without a rate the currency stays as it was.
- **Pro gate.** Every add path (the list's "+", the empty state's button) opens the paywall
  without Pro and continues into the form once Pro is on (`paywallSheet(onUnlocked:)`). Assets
  already kept stay open to view, value, sell and edit.

## Screens

| Screen | File |
|---|---|
| Finances card | `Views/Components/Cards/AssetsCardView.swift`, right after Deposits: the total in `RedactableAmount` (hidden with the other amounts, a skeleton until the store loads), the count, the held assets on `PackedCircleIcons(style: .shelf)` sized by owned value |
| List rows | `AssetCard`, an adapter over DesignKit's `HoldingCard` (8.2.0): the value rolling up (`isLive`), the gain as a `TrendBadge` pill with "+46 000 000 ₸ since purchase", the purchase and the valuations as the sparkline in the gain's colour, the valuation or sale day under the name ("≈ Estimate, valued …" with depreciation), a "Sold" badge, or an "Out of date" one in the warning colour |
| List | `Views/Assets/AssetsListView.swift`: the hero on `.heroBackground` (green while the assets gained, the accent otherwise) with the total, the gain and `HeroSparkline` of `totalHistory`; the cards rise over its end (`.padding(.top, -AppSpacing.xxl)`, `.heroScrollEdge()`), in sections real estate, transport, other, sold (`CardList(.stack)`, a drag reorders within a section, the sold ones by sale day), each card `.scrollReveal()`; three `HoldingCardSkeleton`s until the store loads, `MascotEmptyState` when there are none |
| Detail | `AssetDetailView` on `EntityDetailScaffold`: `HeroSection` (icon, value, the valuation or sale day, the gain pill, the value in the base currency for a foreign one) with `HeroSparkline` of the history under it (and today's estimate with depreciation), drawing in after the push; "Update value" and "Sell" (or "Undo sale"); info rows (kind, purchase price and day, gain or result, growth a year, depreciation a year, the share, loan left and own money, rent and upkeep over 12 months, yield, full result, sale day); when out of date, a warning `StatusBanner` "The value is from …" that opens "Update value"; with a rent category and no rent yet, a `StatusBanner` that opens the add form in that category (the person makes it monthly there); the valuations newest first in a card of `HistoryEntryRow` (a long press deletes one, which leaves with `DissolveTransition`; the purchase is changed in Edit); the rent and upkeep transactions by day (`GroupedTransactionList`). A valuation above the value plays `.sparkleBurst` over the hero; a sale above the purchase price `.celebration(playsHaptic: false)`. It reads `transactions`, `categoriesMutationVersion` and `subcategoriesMutationVersion` so a transaction or a category change redraws it |
| Edit | `AssetEditView`: hero with icon, name, the value today (the estimate with depreciation) and the currency; kind (an icon the person did not pick follows it); purchase price and day; share (5% steps) and the loan; for transport and other things, depreciation a year (a stepper, 0 is "Off", up to 50%; a real-estate kind saves none); rent and upkeep, each a category and, when it has any, a subcategory (`AssetLinkOptions`) |
| Ten writes | `AssistantNotices.staleAssets` ([assistant.md](assistant.md) §6): once a half-year per out-of-date asset (`asset:<id>:<year>-H<1/2>`), "Valued at 70 000 000 ₸ on 16 Apr…"; its button is "Update value" and opens the valuation sheet on Home (no answer spent); it leaves once the asset is valued, sold or deleted (`Subjects.staleAssets`) |
| Money in | `MoneyEntrySheet` (DesignKit's `AmountEntrySheet`): a valuation or the sale, the current value filled in |

Navigation goes through `FinancesDestination` (`.assets`, `.assetDetail(id)`).

## Ten

Ten reads and drafts assets (phase 4, [assistant.md](assistant.md) §3,
`FinanceToolkit+Assets.swift`): `<app_context>` lists the held assets by id, name and kind
(`assets: none` without any); `get_assets` gives every figure above for each asset, the total
and the gain in the base currency; `get_net_worth` gives net worth's parts and its last 12 months
(the monthly net worth insight's points, when computed). `draft_asset` (Pro) files a new asset,
its value now as a valuation of today; `draft_asset_valuation` a value, or an area times a price
per unit from listings, multiplied on the phone. Both are `source: .assistant`, saved and undone
through `AssetStore` on the confirm card. "Ask Ten" is in an asset's "…" menu ("How much is it
worth now?", "Does it pay off?"). The out-of-date message keeps its button to the valuation
sheet: the quickest way to a new value.
