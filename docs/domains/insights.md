# Insights Domain

Operational guide for `InsightsService`. For per-metric formulas/granularity see [INSIGHTS_METRICS_REFERENCE.md](../INSIGHTS_METRICS_REFERENCE.md).

## Architecture

`InsightsService` is a **`nonisolated final class`** — explicitly opts out of implicit MainActor, runs on background thread via `Task.detached` in `InsightsViewModel`.

### File layout

Split into 10 files: main service (~1095 LOC) + 9 domain extensions:
- `+Spending`
- `+Income`
- `+Budget`
- `+Recurring`
- `+CashFlow`
- `+Wealth`
- `+Savings`
- `+Forecasting`
- `+HealthScore`

## DataSnapshot Pattern

`DataSnapshot` is a `Sendable` struct that bundles MainActor-isolated data: transactions, categories, recurringSeries, accounts, `balanceFor` closure.

- Built on MainActor before `Task.detached`
- Threaded through entire computation chain
- ⚠️ **No `transactionStore` access in extension methods** — all data comes via parameters (snapshot fields). Adding new generators must follow this pattern.

## Summary stat grid (2×2)

Each of the four cards is its **own** `NavigationLink` — the grid used to be one link
around everything, so every card landed on the same generic overview and VoiceOver
announced the whole grid as a single button.

| Card | Destination |
|---|---|
| Доступный баланс | the `total_wealth` insight (per-account composition). Its total is computed from the SAME account filter as `availableBalance` (`!isLoan && includeInBalance`), so the figures agree; falls back to the overview before the first insights pass lands |
| Чистый поток / Расходы / Доходы | `InsightsSummaryDetailView(focus:)` — `SummaryDetailFocus` picks the hero metric, the `PeriodChartSeries` drawn, the `PeriodListMetric` of the period list and the screen title |

Cards also carry a `MiniSparkline` so the summary answers "is this normal for me?" without
a tap. It plots only the **last `InsightsStatCard.trendPeriodLimit` (6) periods** — a full
24-month window inside a ~150pt card is unreadable noise, and the whole history is one tap
away in the detail screen. Callers pass the full series; the card slices it.
The balance card's series is the running-wealth line from
`InsightsService.cumulativeBalancePoints(_:endingBalance:)` — **the** derivation, shared
with the wealth insight's chart so the two never disagree (pinned by
`CumulativeBalancePointsTests`). Don't re-implement that walk locally.

`SummaryDetailFocus` reuses existing section titles (`insights.spendingTrend`,
`insights.incomeGrowth`, `insights.cashFlowTrend`) — no new localization keys.

## Money bucket classification (income vs expense)

⚠️ **Never write a bare `tx.type == .expense` / `== .income` in an Insights aggregation.**
Use `InsightsService.moneyBucket(_:)`, which delegates to the canonical
`TransactionType.summaryContribution(isFuture:)` (CLAUDE.md ⚠️ #11) — the same rule the
Home and History summary cards use:

- `.loanPayment` / `.loanEarlyRepayment` → **expense**
- `.depositInterestAccrual` → **income**
- `.internalTransfer`, `.depositTopUp`, `.depositWithdrawal` → neither

Until 2026-08 Insights ran its own `switch tx.type` matching only `.income`/`.expense`, so
loan payments and deposit interest were silently missing from every total, chart and derived
metric (savings rate, health score, forecast, cash flow). `filterService.filterByType(_:type:)`
matches the raw type and must NOT be used for the expense/income slice.

Realized-vs-future is **not** decided by `moneyBucket` — every call site keeps its own
`LedgerPolicyRule.isRealized` gate.

### Synthetic categories: `InsightsService.categoryKey(for:)`

Two transaction types have no usable `category` string, so they get locale-independent
synthetic keys (both rendered through `CategoryDisplay.displayName`):

| Type | Key | Why |
|---|---|---|
| `.loanPayment` / `.loanEarlyRepayment` | `TransactionType.loanPaymentCategoryName` | `category` is empty (UI infers the label from the type) |
| `.depositInterestAccrual` | `TransactionType.depositInterestCategoryName` | `category` stores a *localized* string, so a locale change would split the income source in two |

Without the keys, loan payments would land in the expense total but vanish from the category
breakdown (per-category sum ≠ total). A loan payment tagged with a real user category **still**
maps to the synthetic key: `TransactionStore`'s category aggregates count `expenseAmount` for
`type == .expense` only (rule C-6), so folding it into a user category would desync Insights
budget figures from the Categories screen.

`CategoryBreakdownItem.categoryName` and `InsightDeepDiveView.categoryName` carry the **raw**
key (it drives the deep-dive lookup) — localize at render time with `CategoryDisplay`, or with
`InsightsService.categoryLabel(for:)` when the service builds a card subtitle.

**Icon/tint** — synthetic categories have no `CustomCategory`, so
`InsightsService.syntheticCategoryStyle(for:)` supplies one (`creditcard.fill` / expense tint,
`percent` / income tint), mirroring `CategoryStyleCache.systemTypeStyle` so a loan payment looks
the same in Insights as in the transaction list. Every `CategoryBreakdownItem` builder falls back
to it: `cat?.iconSource ?? synthetic?.icon`.

**Deep dive** — `InsightsService.DeepDiveGrouping.forCategory(_:)` decides what a drill-down
breaks a category into: user categories → subcategories, `"Loan Payment"` → the loan account of
each payment (`targetAccountId`), `"Deposit Interest"` → the deposit that paid it (`accountId`).
Account groupings key on the account **id**, so `SubcategoryBreakdownItem.id` is an account id
there and `InsightsViewModel.categoryDeepDive` fills `iconSource` from
`transactionStore.accountById` (the nonisolated generator can't read account icons).
`InsightDeepDiveView` then renders the account logo instead of a colour dot and recolors its orb
slices with each logo's dominant colour via `DominantColorExtractor` — the same async resolve
`heroAccentGlow` and `WealthOrbSection` use. `generateCategoryDeepDive` filters on `moneyBucket != .none` (not expense-only),
so income categories drill down too; `InsightsView` therefore enables the drill-down closure for
`.income` insights as well and passes `isExpenseContext: false` so the comparison card colors a
rise green.

Pinned by `InsightsMoneyBucketTests`.

## PreAggregatedData

Single O(N) pass builds:
- monthly totals
- category-month expenses
- `txDateMap`
- per-account counts
- `seriesMonthlyEquivalents`

All generators use O(M) dictionary lookups against this struct.

⚠️ **Piggyback rule**: Add fields to `PreAggregatedData.build()` O(N) loop — never add separate O(N) loops when one already exists.

### `seriesMonthlyEquivalents` map

Pre-computed `[seriesId: monthlyEquivalent]` map built once in `PreAggregatedData.build(…, recurringSeries:)`. Generators (HealthScore, Recurring growth/duplicates, Forecasting) pass it via `seriesMonthlyEquivalent(_:baseCurrency:cache:)` to skip per-series `CurrencyConverter.convertSync` calls.

⚠️ **When adding a new generator that calls `seriesMonthlyEquivalent`, always pass `cache: preAggregated?.seriesMonthlyEquivalents`**.

### `filterByTimeRange(_:start:end:txDateMap:)` overload

Legacy MoM paths (Spending/Income) and `computeMonthlyPeriodDataPoints` accept an optional `txDateMap` to skip `DateFormatter.date(from:)` (~16μs/tx). Always thread `preAggregated?.txDateMap` through new generators that filter by date range.

`filterService.filterByTimeRange` without txDateMap is expensive (~16μs/tx due to DateFormatter) — use `txDateMap` inline filter when available.

## Static Helpers

Three top-level computation entry points:
- `computeMonthlyTotals`
- `computeLastMonthlyTotals`
- `computeCategoryMonthTotals`

All return lightweight value-type structs (`InMemoryMonthlyTotal`, `InMemoryCategoryMonthTotal`).

## Severity Sorting

`InsightsViewModel` sorts insights by severity within each section via `sortedBySeverity()`:

```
critical > warning > neutral > positive
```

## Recent Metric Changes (2026-07 product audit)

Full rationale + benchmarks (archived): [archive/INSIGHTS_PRODUCT_AUDIT_2026_07_13.md](../archive/INSIGHTS_PRODUCT_AUDIT_2026_07_13.md).

### Deleted / merged (audit 2026-07)
- `incomeVsExpenseRatio` — deleted (unintuitive `1.2x` multiplier; duplicated `savingsRate` + `netCashFlow`)
- `bestMonth` + `worstMonth` — merged into one neutral "period records" card (id `period_records`, type stays `.bestMonth`); detail renders both Top-10 rankings (worst list filters to deficit periods only)
- `balanceRunway` — merged into `emergencyFund`: runway rows reuse the `insights.formula.balanceRunway.row.*` keys, severity = worse of (monthsCovered, runway); the standalone generator is gone
- ⚠️ `duplicateSubscriptions` enum case exists but has NO generator — dead code, don't "fix" callers into existence without a product decision

### Added (audit 2026-07)
- `subscriptionPriceIncrease` (`+Recurring`) — latest linked charge vs previous (or series amount), >5% и ≤300% в той же валюте; up to 3 cards, ids `price_increase_<seriesId>`; **shared** (prefix-matched in `extractSharedInsights`). Billing-period guard (2026-07): интервал между сравниваемыми списаниями должен быть в 0.5–1.6× периода `series.frequency`, иначе это смена тарифа (месячный→годовой) — не сигналить
- `largeTransaction` (`+Spending`) — largest non-recurring realized expense of last 30d, ≥4× the 90d average tx (needs ≥20 baseline tx); id `large_tx_<txId>`; **shared** (prefix-matched)
- "Важное сейчас" strip — `InsightsViewModel.urgentInsights` (top-5 critical/warning across ALL categories); promoted insights are EXCLUDED from their category sections (unique `matchedTransitionSource` ids). 2026-07 UX pass: the strip also leads with the **health score card** (`HealthScoreCardView` — insight-card-style with a mini absolute half-gauge; replaced the old `HealthScoreBadge` row in the summary header), and the filter carousel has a matching **«Важное» chip** (`InsightFilter.urgent`, key `insights.filter.urgent`) right after «Все» — it shows the health card + the UNCAPPED `allUrgentInsights` list (the strip stays top-5). Feed filtering runs on `InsightsViewModel.selectedFilter: InsightFilter` (`.all` / `.urgent` / `.category(_)`) — the old `selectedCategory` property is gone.
- `accountDormancy` — reframed as "money sitting idle / missed deposit yield" (copy only)

### Signal notifications (Phase C/D)
- `InsightSignalService` (`Services/Notifications/`) — diff engine: fires local pushes for NEW critical/warning signals only (7-day per-id dedup + 5/week global cap, history in UserDefaults). Pure core `selectSignals` is unit-tested (`InsightSignalServiceTests`). Wired at the END of `loadInsightsBackground` phase 2 (`.month` insights).
- `WeeklyDigestScheduler` — Monday-09:00 digest from `.week` periodPoints, rescheduled on every recompute; body names the week it covers (stale-content guard). Toggle + per-kind toggles: `InsightSignalSettings` → `InsightSignalSettingsView` (Settings).
- Notification ids use prefix `insightSignal_` — AppDelegate routes taps to the Analytics tab via `.insightSignalNotificationTapped`.
- ⚠️ Known limitation: signals/digest only (re)compute when InsightsViewModel recomputes (Analytics tab usage). BGAppRefresh follow-up in the audit doc.

## Recent Metric Changes (2026-04 audit)

### Deleted (low signal / duplicated)
- `incomeSeasonality`
- `spendingVelocity`
- `savingsMomentum`

### Threshold tweaks
- **`spendingSpike`** — uses relative threshold (1.5x category average) not absolute amount
- **`accountDormancy`** — excludes deposit accounts (they accrue interest without transactions)
- **`savingsRate`** uses the **last completed calendar month** (`preAggregated.lastMonthlyTotals(1, anchor: now − 1mo)`), NOT the current partial bucket — salary commonly lands month-end, so mid-month the current bucket always reads as a deficit. Now granularity-independent (same value across week/month/quarter/year).
- **`projectedOverspend`** only extrapolates once ≥ `max(7, totalDays/4)` days of the budget period have elapsed — early-period run-rates falsely flagged categories at ~7 % spent.

### Health Score components
- **Cash Flow score** uses gradient 0-100 (not binary)
- **Emergency Fund baseline** is 3 months (not 6)
- **Budget Adherence** excluded and weight redistributed when no budgets exist

## Adding a New Generator — Checklist

1. Place in appropriate `+<Domain>` extension file
2. Accept all data via `DataSnapshot` parameters — no `transactionStore`
3. If filtering by date range — accept optional `txDateMap` and use it
4. If iterating series — accept `seriesMonthlyEquivalents` cache and pass to `seriesMonthlyEquivalent`
5. If adding new aggregations — piggyback on `PreAggregatedData.build()` O(N) pass
6. Return value-type Sendable struct — no class instances threaded through
7. If insight is severity-sortable, ensure `severity` field is set
8. Consider setting `cardVisual` (purpose-built feed mini-visual — see charts.md §Insight mini-visuals); pick by message type: pairwise comparison → `.barPair`, value-vs-norm → `.halfGauge`, % of limit → `.ring`, composition → `.donut` (accounts) / `.proportionBar` (flat bar), per-category budget list → `.budgetBars` (top-3), progress to a discrete milestone → `.milestoneGauge`, trend with projection/extremes/custom points → `.sparkline`; a plain trend stays on the detailData sparkline fallback

## Granularity switching — gotchas (hard-won)

- **`Insight` equality MUST stay value-based** (`Models/InsightModels.swift`). Insight ids are stable across granularities (e.g. `top_spending_<category>` when the same category tops every period). With id-only `==`, SwiftUI diffing treats a new granularity's card as unchanged and skips re-render → cards show the previous period's numbers. `==` compares rendered fields; `hash` stays id-only. Do NOT revert to id-only `==`.
- **Granularity switches must NOT cancel the in-flight recompute.** `loadInsightsBackground` is two-phase (priority gran first, then the rest); MainActor writes are generation-guarded and MERGE into the cache (never replace). `currentGranularity.didSet` applies from cache if present, else sets `isLoading` and waits — starting a competing load cancels phase 2 and leaves the cache incomplete → cards lag / show the wrong granularity.
- **`healthScore` is published with the PHASE-1 write, not after phase 2.** It needs only `.month` period data, derivable from `preAggregated` (`computePeriodDataPointsFromPreAggregated(.month)` — internal for exactly this call). Publishing it in the final write made the health badge pop in seconds after the rest of the feed. Don't move it back.
- **`applyPrecomputed` never applies a missing granularity** — it keeps `isLoading=true` instead of flashing empty/stale cards.
- **The summary card shows the CURRENT bucket.** For `.week` the current week is often empty (totals = 0) while the 52-week window total is non-zero — correct, not a bug.
- **Deep-dive subcategory breakdown reads the LINKED subcategory** (`TransactionSubcategoryLink` via store indexes), passed as `subcategoryNameByTxId`. The add flow leaves `tx.subcategory` nil, so grouping by `tx.subcategory` dumps everything into "no subcategory".

## Detail view & paging

- **Adding an `InsightDetailData` case → update 3 exhaustive switches**: `InsightDetailView.chartSection`, `InsightDetailView.detailSection`, and `InsightsCardView.miniChart`. Miss one → build error (or silent `EmptyView`).
- **Hero charts (2026-07 UX pass)**: every `cardVisual` renders a DEDICATED interactive hero (`HeroSparkline`, `HeroProportionBar`, `HeroHalfGauge`, `HeroBarPair`, `HeroMilestoneGauge` — see charts.md §Hero visuals), all with `entranceDelay = 0.5` so entrance animations start after the zoom nav transition (was: hero jumped at transition end). Period records (`bestMonth`) keep `chartSection == EmptyView` — their chart IS the `HeroSparkline` (full history, extreme markers, tap selection) above the ranked lists.
- **Per-`insight.type` detail variants are done by special-casing `insight.type` inside the existing `chartSection`/`detailSection` switch arms — NOT by adding an `InsightDetailData` case** (which costs the 3 exhaustive-switch updates above). E.g. bestMonth/worstMonth reuse `.periodTrend` but render a ranked Top-10 list with no chart; wealthGrowth reuses `.periodTrend` but lists cumulative balance. `PeriodListMetric` selects the single row value (`.cumulativeBalance`, `.expenses`, …).
- **Detail structure contract (2026-07 UX pass), top to bottom: `HeroSection` header → chart (hero visual / full chart) → cards (formula) → detail lists.** EVERY detail shows the header, including formula breakdowns — `InsightFormulaCard` is rendered with `showsHero: false` there so the metric isn't duplicated (the card keeps its icon+title row, formula rows, explainer, recommendation). The header is always **iconless** (`showsIcon: false` — the severity glyph carried no information over the trend badge + hero chart).
- **Detail lists live in [InsightDetailLists.swift](../../Tenra/Views/Insights/InsightDetailLists.swift)** (`InsightCategoryBreakdownList` / `InsightRecurringBreakdownList` / `InsightPeriodBreakdownList` / `InsightRankedPeriodList` / `InsightAccountBreakdownList` / `InsightDormantAccountList` / `InsightBudgetBreakdownList`), sharing one private `InsightDetailListCard` shell: `SectionHeaderView(.large)` ABOVE the card, rows inside `.cardStyle()` with `AppSpacing.lg` inner padding, `.screenPadding()` owned by the shell — call sites must NOT add their own screenPadding. ⚠️ Exception: `InsightBudgetBreakdownList` does NOT use the shell — `BudgetProgressRow` is already a standalone `.cardStyle()` card, wrapping it would nest cards. The category list is generic over the drill-down destination and is reused by the paged breakdown's pages (`periodKey:`).
- **Detail header (`InsightDetailView.headerSection`) is the shared `HeroSection`** (replaced a bespoke three-line header). Mapping: `title ← insight.subtitle` (insight.title is the nav title), amount slot ← metric (`FormattedAmountText` for currency metrics, `primaryText` for percent/count + unit), centered `accessory` ← `InsightTrendBadge(.pill)`, `HeroSection.subtitle ← trend.comparisonPeriod`. Two duplication traps remain: (a) generators that set `trend.comparisonPeriod == subtitle` (monthOverMonth, wealthGrowth) would render the same line twice — `comparisonSubtitle` suppresses it; (b) **count-style metrics** (`"2"` + unit "категорий") duplicate the count already in the subtitle ("2 категорий под угрозой") — prefer an **amount** metric (currency: total overshoot / total idle balance) and leave the count in the subtitle (budgetOverspend / projectedOverspend / accountDormancy). `HeroSection` itself gained backward-compatible `primaryText:` + a generic `accessory` ViewBuilder slot (default `EmptyView` via convenience init).
- **`wealthBreakdown` chartSection renders the wealth orb from the generator's `cardVisual` `.donut` slices** (top accounts + "Other" already aggregated) via `WealthOrbSection` (private in InsightDetailView.swift): perimeter labels show ACCOUNT NAMES (`OrbChart(labelStyle: .name)`), and slice colours resolve asynchronously to the dominant logo colour (`DominantColorExtractor`) for brand-icon accounts — hash palette stays the fallback. The generator can't resolve logo colours itself (nonisolated, no image access).
- **MoM spending detail renders NO full trend chart** — `chartSection` skips `.periodTrend` for `.monthOverMonthChange` (and `.bestMonth`): the HeroBarPair already carries the was/now message; the period breakdown list stays.
- **`InsightFormulaCard` headerRow title is the static "insights.formula.howCalculated"** ("Как считается") — `model.titleKey` duplicated the detail screen's navigation title.
- **`InsightFormulaRow.labelText` overrides `labelKey`** — use it to put a data-driven label (date, category name) in the row heading instead of cramming `.rawText("amount — label")` into the value cell (yearOverYear rows).
- **`.categoryBreakdownPaged` renders full-screen in `InsightDetailView.body`** via `TabView(.page)`, NOT inside `detailSection` (the detailSection case is a dead `EmptyView`). A TabView must own the vertical space — nesting it in the body's `ScrollView` collapses it. 2026-07 UX pass: the TabView is the OUTER container and **each page is its own `ScrollView { HeroSection → OrbChart (arrows overlaid) → category rows }`** — hero and orb scroll together with the list (they used to be pinned above a list-only pager).
- **Top-spending is emitted for every finite granularity even when the current period is empty** (empty hero "Нет расходов", still tappable). It only falls back to the legacy single `.categoryBreakdown` for `.allTime`. Paged breakdowns cover all `periodPoints` (current → first tx); `.week` is bounded by its rolling 52-week window.
- **`incomeSourceBreakdown` pages the same way** (2026-07) — `generateIncomeSourceBreakdown` mirrors the spending paged path off `pt.income`. Two consequences for callers: it needs the **windowed** transactions, not the current bucket (`generateForecastingInsights(filteredTransactions:)` now receives `windowedTransactions`, and the old `currentBucketForForecasting` pre-narrowing is gone — it would have collapsed every page but the current one to empty); and `PeriodCategoryBreakdown.total` is flavor-neutral (expenses OR income), which is why it isn't named `totalExpenses`. `PagedCategoryBreakdownView` takes an `emptyTitle` for the same reason — an income page must not say "Нет расходов".
- **Per-generator ad-hoc tx filters MUST apply `LedgerPolicyRule.isRealized`.** `computePeriodDataPoints` and `PreAggregatedData.build` already exclude future-dated tx, but breakdown lists that re-filter `expenses` by date range (e.g. top-spending) did not — caused future tx in the breakdown vs. a realized % total. Keep them consistent.
- **Period-trend detail charts/lists choose metric by `insight.type`** (avg-daily → avg daily expenses, monthOverMonth → expenses, incomeGrowth → income; else cash-flow). Pass the FULL `periodPoints` (not `[prev, current]`) so the chart/list span all time. See `periodListMetric` / `periodChartSeries` in `InsightDetailView`.

## Date labels — headings vs axis

- **`InsightGranularity.headingLabel(for:)`** — use for ANY date acting as a heading / row-title: breakdown-list rows, `PeriodComparisonCard`, paged pager header, wealth/spending service subtitles. Capitalized, full month names, full week range (no abbreviations). Built on `String.capitalizedFirstLetter`.
- **`InsightGranularity.periodLabel(for:)`** — axis / chart only: abbreviates `.week` ("3 янв"); month is full but locale-cased (ru → lowercase "май 2026"). Do NOT use it for headings — renders lowercase in ru locale. `PeriodDataPoint.label` is built from it (axis-oriented); heading call sites recompute via `headingLabel(for: point.key)`.
