# Assets

What the person owns and what it is worth: a home, a car, land, anything else. An asset has its
own CoreData row (v17; v18 its payments by hand; v19 its characteristics), a card in Finances, list, detail and edit
screens. It never changes an account balance or a transaction: a flat bought in 2018 stays an expense, and the asset lives
next to it with its own purchase price and valuations; its rent and upkeep are the transactions
of the categories it is linked to. Adding an asset is Tenra Pro. Net worth (money, assets and
debts) is a free insight. The first plan and the owner's decisions:
[archive/plans/plan-assets.md](../archive/plans/plan-assets.md); what comes next:
[plan-assets-roadmap.md](../plan-assets-roadmap.md).

## Model

| Type | File | What it is |
|---|---|---|
| `Asset` | `Models/Asset.swift` | name, `kind`, icon, currency, optional purchase price and day, `valuations`, `depreciationPerYear` (0.15 for 15% a year; nil, the default, keeps the last valuation), `ownershipShare`, optional `linkedLoanAccountId`, `incomeLink` and `expenseLinks` (`AssetCategoryLink`: a category id, never a name, and any of its subcategory ids; upkeep from several categories, `expenseLink` the first), `includeInNetWorth`, `soldAt`, `order`, `excludedTransactionIds` / `includedTransactionIds` (the payments removed and linked by hand), `attributes` (`AssetAttributes`), `yieldOnShare` (the yield and the full result of the person's share; off by default), `note` |
| `AssetKind` | same | apartment, house, land, commercial (the list's real estate), vehicle (transport), other; the default icon of each |
| `AssetValuation` | same | a day, a value in the asset's currency, a source (`purchase`, `manual`, `assistant`, `sale`; one a later version adds reads as `manual`), an optional note ("listings on krisha.kz") and, for an estimate by listings, `listings` (`Listings`: the quartiles in the asset's currency, the count, the sites) |
| `AssetEstimate`, `AssetEstimateRequest` | `Services/Assets/AssetEstimate.swift` | an estimate by listings: the request (the kind, the country given, saved or the phone's, and `AssetAttributes.request(for:)`, what the user said in the chat over the saved ones) and the server's answer read back (the median and quartiles in the market's currency, the count, the accuracy, the listings with their sites and links, only `http`/`https` ones kept, the estimates left this month) |
| `AssetAttributes` | `Models/AssetAttributes.swift` | the characteristics for an estimate by listings, by the valuation request's field names (`server/assistant/src/valuation.ts`): the country, city, district, a flat's area, rooms, year, building, floor and condition, a house's land and utilities, a car's make, model, generation, year, mileage, engine, fuel, gearbox, drive, steering wheel and customs; values are texts, numbers, yes or no and lists. `Field` holds each field's rule (the server's types and ranges, no text with seven digits in a row), the fields of each kind and the required ones; `request(for:)` is what the request may send (another kind's field and a value outside the rules left out: the server refuses the whole request for one), `missing(for:)` what it still needs. A key this version does not know is kept |

The purchase is not a stored valuation: `AssetValuationMath.history` puts it first, from the
purchase price and day. The sale is the `.sale` valuation, and `soldAt` its day.

## Storage

- `AssetEntity` (CoreData v17), read and written only by `AssetRepository` (`Services/Assets/`),
  outside the `DataRepositoryProtocol` facade like the goals and debts. Valuations and the category
  links are JSON on the row (the upkeep links an array in `expenseLinkData`; one object, as v18
  and before wrote it, reads as one link), and so are the payments by hand (`transactionLinksData`, v18,
  `AssetTransactionLinks`, nil while both lists are empty) and the characteristics
  (`attributesData`, v19, `AssetAttributes`, nil while empty), `yieldOnShare` (v19, NO); the icon is `IconSource` JSON. The
  purchase price and the depreciation are optional numbers (`NSNumber`). The valuations are read
  one by one: one that does not decode (a later version's) is skipped, not the list.
- Writes go one after another in the order asked for (`SerialTaskQueue` in `AssetStore`, as in
  `GoalStore` and `DebtStore`), each on a fresh background context: two quick edits never land in
  the other order.
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

- **Value**: the latest point of `AssetValuationMath.history` by day, the purchase and the
  valuations merged (the purchase first in its day, valuations of one day in the order added, so
  a valuation dated before the purchase does not outlive it), else the purchase price; once sold,
  the sale price. The day of that figure is shown next to it ("Valued 16 Oct").
- **Depreciation** (off by default, the person sets it for transport and other things in the form;
  homes and land keep their last valuation): from the latest point (a valuation, else the
  purchase), `value × (1 − rate)^years`, rounded to whole units of the asset's currency (an
  estimate has no cents). The figure is an estimate, shown "≈ Estimate, valued
  16 Oct"; the asset's chart ends on it today ("30 Oct, estimate"), and so does the list's total
  when an asset depreciates. A new valuation is the new base. A sold asset keeps its sale price.
  `AssetValuationMath.estimate` over a `Timeline` (the dated points without the sale, the rate,
  the sale day, the share, the currency) gives the value on any day: none before the first point
  or from the sale on, an asset without a dated point at its value throughout.
  The wear ahead (`AssetValuationMath.forecast`, `forecastYears` = 3): the same rule three years
  from today, drawn as the hero chart's dashed tail (`HeroSparkline(projectedValue:)`) and the
  "In 3 years ≈ …" row under the depreciation, and given to Ten as `value_in_3_years` in
  `get_assets`; none without a rate, once sold, or without a dated point.
- **Out of date** (`AssetValuationMath.isStale`): a held asset whose value was last set (the
  latest point, else the purchase, else when it was added) more than six months ago for real
  estate and transport, twelve for the rest. Its card shows an "Out of date" badge (the list moves
  its day at midnight), its screen a banner that opens "Update value" (or the estimate from
  listings, once available), and Ten writes once a half-year (below).
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
  Their worth over time is `totalChartHistory`, each asset counted from its first point at its
  value on that day. **Charts run evenly in time** (the owner's decision D3): DesignKit's sparklines
  space points evenly, so `AssetValuationMath.chartDays` gives a day a month apart (a few months
  over a long span, at most 48) from the first point to today; an asset's own chart
  (`chartHistory`) ends on the sale price on the sale day once sold. `totalHistory` (a point on
  every day of a purchase or a valuation) is no longer drawn; its tests pin the value on a day.
- **Rent and upkeep**: the `.income` transactions of the income link and the `.expense` ones of
  every expense link, a payment two links both count once (`AssetStore.transactionsOfLink`, wired by `AppCoordinator` to
  `TransactionStore`'s category index, filtered by the transaction links of its subcategories:
  any of `AssetCategoryLink.subcategoryIds`, none for the whole category; a link saved with one
  `subcategoryId` before 2026-10-30 reads as a list of one, and a link is written with both), each in
  the asset's currency. **Only the days the asset is held** count (`AssetValuationMath.HeldPeriod`:
  from the purchase day, any day without one, to the sale day, `AssetStore.linkedTransactions`):
  the owner's car bought in June 2021 counted the repairs of the car before it (2026-11-02).
  **Payments by hand** (the detail screen's menu, `LinkPaymentsView` with `Options.asset`):
  "Link payments" adds any expense or income it does not count yet, whatever its category or day
  (`includedTransactionIds`: an expense is upkeep, an income rent; an asset with no link counts
  them too); "Remove payments" unlinks one linked by hand and excludes one its links count
  (`excludedTransactionIds`), and "Removed payments" gives those back (`AssetStore.include`,
  `exclude`, `restore`; `transactionsWithIds` reads them from `TransactionStore.transactionById`,
  a deleted one drops out). Realized only: up to today, up to the sale for a sold asset. Over the 12
  months before that day, the rent, the upkeep and the yield, (rent − upkeep) ÷ value; since the
  purchase, the full result, gain + every rent − every upkeep (`AssetValuationMath.income`). Of the
  whole asset by default; with `yieldOnShare` (the owner's decision D2, a co-owner who records
  their own rent) the yield is over their share of the value and the full result takes their share
  of the gain (`onShare:`; Ten's `get_assets` says so in `yield_of_share`). A
  link whose category is gone reads as empty.
- **No double counting**: two assets' links overlap when they share a category and either takes
  the whole of it or they take a subcategory in common (`AssetValuationMath.overlaps`), and the
  days they are held overlap (`overlaps(_:held:_:held:)`: a car sold before, or on the day, the
  next was bought may keep the same "Transport"); the form refuses one that overlaps another
  asset's (`InlineStatusText`, Save off; `AssetLinkOptions.Taken` carries each link's days).
  Payments linked by hand are not checked: the person picks each one.
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
- **The sale's money** (`AssetSale`): the proceeds are the sale price at the person's share, to
  the cent. Until an income of the sale exists, the sold asset's screen shows "Record the money
  from the sale": it asks the income category (a dialog of the income categories, or "Already
  recorded", which hides the banner on this device: `@AppStorage("asset.saleIncome.dismissed")`,
  cleared by "Undo sale") and opens the add form with the proceeds, the sale day and "Sale: <name>"
  filled in, in the asset's currency (`TransactionAddModal.Prefill`: an account in another currency
  converts it rather than taking its own). An income of the sale is one dated from 30 days before
  the sale day to 90 after (`AssetSale.window`, the incomes from `AssetStore.incomesOnDays`) at the
  proceeds in the asset's currency, or whose description names the asset. A sold asset whose
  linked loan still has principal left shows a warning banner that opens the loan.
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
| List rows | `AssetCard`, an adapter over DesignKit's `HoldingCard` (8.2.0): the value rolling up (`isLive`), the gain as a `TrendBadge` pill with "+46 000 000 ₸ since purchase", its value over time as the sparkline in the gain's colour (`AssetValuationMath.chartHistory`, evenly in time, ending today or on the sale, as on its screen), the valuation or sale day under the name ("≈ Estimate, valued …" with depreciation), a "Sold" badge, or an "Out of date" one in the warning colour |
| List | `Views/Assets/AssetsListView.swift`: the hero on `.heroBackground` (green while the assets gained, the accent otherwise) with the total, the gain and `HeroSparkline` of `totalChartHistory` (evenly in time, to today); the cards rise over its end (`.padding(.top, -AppSpacing.xxl)`, `.heroScrollEdge()`), in sections real estate, transport, other, sold (`CardList(.stack)`, a drag reorders within a section, the sold ones by sale day), each card `.scrollReveal()`; three `HoldingCardSkeleton`s until the store loads, `MascotEmptyState` when there are none |
| Detail | `AssetDetailView` on `EntityDetailScaffold`: `HeroSection` (icon, value, the valuation or sale day, the gain pill, the value in the base currency for a foreign one) with `HeroSparkline` of `chartHistory` under it (evenly in time; today's estimate with depreciation, and with a rate a dashed tail to the value in three years), drawing in after the push; "Update value" and "Sell" (or "Undo sale", which asks first: it drops the sale's price, day and note); info rows (kind, purchase price and day, gain or result, growth a year, depreciation a year and "In 3 years ≈ …", the share, loan left and own money, rent and upkeep over 12 months, yield, full result, sale day, "Count in net worth: No" when it is off, the note); when out of date, a warning `StatusBanner` "The value is from …" that opens "Update value"; with a rent category and no rent yet, a `StatusBanner` that opens the add form in that category with the link's subcategories picked (the person makes it monthly there); once sold, the "Record the money from the sale" banner and, with the linked loan still owed, the "not paid off" one (Rules, the sale's money); the valuations newest first in a card of `HistoryEntryRow` (a tap or the menu's "Edit" opens `AssetValuationEditView`: the value, the day and the note, or the sale's price and day, which is also the asset's sale day, `AssetStore.updateValuation`; a changed value drops an estimate's range; a long press deletes one, which leaves with `DissolveTransition`; a tap on the purchase opens Edit); the rent and upkeep transactions by day (`GroupedTransactionList`); the menu's "Link payments", "Remove payments" (with any counted) and "Removed payments" (with any removed) open `LinkPaymentsView` (search, category, subcategory and account filters, select all). A valuation above the value plays `.sparkleBurst` over the hero; a sale above the purchase price `.celebration(playsHaptic: false)`. It reads `transactions`, `categoriesMutationVersion` and `subcategoriesMutationVersion` so a transaction or a category change redraws it; once Ten's server values assets (`AppCoordinator.checkAssetEstimates`, `GET /v1/health` once a launch), "Estimate from listings" in the menu (Tenra Pro: without it the paywall, `.assetEstimate`, then the estimate), and for a Pro user the out-of-date banner opens it instead of "Update value"; the rent and upkeep transactions and their summary are a snapshot by `.task(id:)` (the transactions' `mutationVersion`, the categories, the subcategory links, the rates, the asset and the day), the "no rent yet" banner waiting for the first |
| Estimate | Tenra Pro, 10 a month (the owner's decision, 2026-11-03). `AssetEstimateSheet` with `AssetEstimateViewModel`: the characteristics (`AssetAttributesSection`, "Fill in: …" while the kind's required fields are empty), "Find listings" saves them into the asset and asks `POST /v1/valuation` through `AppCoordinator.assetEstimateTransport` (the chat's `AgentServerClient`, one App Attest key); while it searches (up to a minute) the sheet cannot be swiped away. The result: the median in the asset's currency in `HeroSection` with the count and the accuracy, the low and high ends and the value in the app as amount rows, "asking prices" under them, the listings (a tap opens one in Safari), the estimates left this month, "Save valuation" (today's `.assistant` valuation with `listings` and the note "Listings: 14 (krisha.kz, olx.kz)"; above the value it bursts sparkles). Too few listings: "Add details" back to the characteristics, or "Enter by hand" (the money sheet, after this one closes). Refusals: the month's estimates used up (a free user gets "More with Tenra Pro", the paywall), not available, or busy with "Retry" |
| Edit | `AssetEditView`: hero with icon, name, the value today (the estimate with depreciation) and the currency; kind (an icon the person did not pick follows it); purchase price and day; share (5% steps), below 100% "Yield on my share" (`yieldOnShare`), the loan and "Count in net worth" (`includeInNetWorth`; off, the asset stays in its list but out of the totals and net worth); for transport and other things, depreciation a year (a stepper, 0 is "Off", up to 50%; a real-estate kind saves none); rent, a category and, when it has any, its subcategories as chips, several at once (`ChipPicker`, "Whole category" while none is picked; `AssetLinkOptions`); upkeep, the same rows, one category each, "Add another category" while every row has one (a category picked twice merges its subcategories; a row left without a category is dropped; each is checked against the links other assets hold); last, `AssetAttributesSection`: "Location" (country, a list with search, the phone's by default; city; district for real estate) and "Characteristics" by kind (a flat: area, rooms, year built, building, floor, floors, condition; a house: area, land, year, building, floors, utilities as chips, condition; commercial: type, area, floor, condition; land: ares, use, utilities; a car: make, model, generation, year, mileage, engine, fuel, gearbox, drive, and in Kazakhstan the steering wheel and customs; other: what it is, year, condition), each optional, "Not set" by default; then the note. `AssetAttributesDraft` keeps them as typed: a number that does not read is left out, the kind's fields the form does not show (region, complex) stay, another kind's go, and the country is saved only with something else; what a typed value does (a valuation of today, the sale price once sold, nothing for a new asset bought today at that price) and a new currency moving the amounts are `AssetEditing`, shared with Ten's `draft_asset` |
| Ten writes | `AssistantNotices.staleAssets` ([assistant.md](assistant.md) §6): once a half-year per out-of-date asset (`asset:<id>:<year>-H<1/2>`), "Valued at 70 000 000 ₸ on 16 Apr…"; its button is "Update value" and opens the valuation sheet on Home (no answer spent); it leaves once the asset is valued, sold or deleted (`Subjects.staleAssets`); a long loan without an asset gets one message ever (`AssistantNotices.loansWithoutAsset`, [assistant.md](assistant.md) §6) whose button opens a new asset with the loan |
| Loan | `LoanDetailView`, above its cards: the asset the loan bought ("Asset", a row that opens it), or, while the loan is owed, "Add asset", which opens `AssetEditView` with the loan picked and its currency (`initialLoanAccountId`; the paywall first without Pro, `PaywallSource.assetAdd`) |
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
through `AssetStore` on the confirm card. `estimate_asset_value` (the same `AssetEstimateRequest` as the screen's sheet) values a held asset by comparable
listings found by a web search on Ten's server (`POST /v1/valuation`, [assistant.md](assistant.md)
§8; off until the version that ships it): it sends the characteristics saved in the form with
what the user said in the chat over them, and `get_assets` lists them (`characteristics`) with
what an estimate still needs (`missing_for_estimate`), so Ten asks only for that (a flat's city
and area, a car's make, model and year) or estimates right away; it shows the median and range
in the asset's currency against its value in the app, and offers `draft_asset_valuation` with it.
What the user tells Ten in the chat is not saved into the form.
"Ask Ten" is in an asset's "…" menu ("How much is it worth now?", "Does it pay off?"). The out-of-date message keeps its button to the valuation
sheet: the quickest way to a new value.
