# Assets

What the person owns and what it is worth: a home, a car, land, anything else. An asset has its
own CoreData row (v17), a card in Finances, list, detail and edit screens. It never changes an
account balance or a transaction: a flat bought in 2018 stays an expense, and the asset lives
next to it with its own purchase price and valuations. Adding an asset is Tenra Pro. The plan,
its later phases (rent and upkeep, net worth, stale valuations, Ten) and the owner's decisions:
[plan-assets.md](../plan-assets.md).

## Model

| Type | File | What it is |
|---|---|---|
| `Asset` | `Models/Asset.swift` | name, `kind`, icon, currency, optional purchase price and day, `valuations`, `ownershipShare`, optional `linkedLoanAccountId`, `soldAt`, `order`; and, kept for later phases, `depreciationPerYear`, `incomeLink` / `expenseLink` (`AssetCategoryLink`: a category id and an optional subcategory id), `includeInNetWorth`, `note` |
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
| List rows | `AssetCard`, an adapter over DesignKit's `HoldingCard` (8.2.0): the value rolling up (`isLive`), the gain as a `TrendBadge` pill with "+46 000 000 ₸ since purchase", the purchase and the valuations as the sparkline in the gain's colour, the valuation or sale day under the name, a "Sold" badge |
| List | `Views/Assets/AssetsListView.swift`: the hero on `.heroBackground` (green while the assets gained, the accent otherwise) with the total, the gain and `HeroSparkline` of `totalHistory`; the cards rise over its end (`.padding(.top, -AppSpacing.xxl)`, `.heroScrollEdge()`), in sections real estate, transport, other, sold (`CardList(.stack)`, a drag reorders within a section, the sold ones by sale day), each card `.scrollReveal()`; three `HoldingCardSkeleton`s until the store loads, `MascotEmptyState` when there are none |
| Detail | `AssetDetailView` on `EntityDetailScaffold`: `HeroSection` (icon, value, the valuation or sale day, the gain pill, the value in the base currency for a foreign one) with `HeroSparkline` of the history under it, drawing in after the push; "Update value" and "Sell" (or "Undo sale"); info rows (kind, purchase price and day, gain or result, growth a year, the share, loan left and own money, sale day); the valuations newest first in a card of `HistoryEntryRow` (a long press deletes one, which leaves with `DissolveTransition`; the purchase is changed in Edit). A valuation above the value plays `.sparkleBurst` over the hero; a sale above the purchase price `.celebration(playsHaptic: false)` |
| Edit | `AssetEditView`: hero with icon, name, the value today and the currency; kind (an icon the person did not pick follows it); purchase price and day; share (5% steps) and the loan |
| Money in | `MoneyEntrySheet` (DesignKit's `AmountEntrySheet`): a valuation or the sale, the current value filled in |

Navigation goes through `FinancesDestination` (`.assets`, `.assetDetail(id)`).

## Not yet

Rent and upkeep links, yield and net worth (phase 2), stale valuations, depreciation and the
net worth chart (phase 3), Ten's tools and drafts (phase 4): [plan-assets.md](../plan-assets.md)
§9. Ten does not see assets yet, so their screens have no "Ask Ten".
