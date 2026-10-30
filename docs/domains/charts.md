# Charts Domain

How Tenra feeds its data into DesignKit's charts. The charts themselves (`LineChart`, `BarChart`,
`ChartSwitcher`, `HeroSparkline`, `Sparkline`, `ChartSelectionBanner`, `ChartZoomControls`,
`OrbChart` / `DonutSlice`, `MiniDonut`, the `Mini*` / `Hero*` visuals, `ProgressRing`,
`LinearProgressBar`) and the Swift Charts rules behind them live in DesignKit:
[docs/charts.md](https://github.com/dkicekeeper/DesignKit/blob/main/docs/charts.md). A change to how a chart
draws is a DesignKit PR.

## `PeriodChartAdapters.swift`

[`Views/Components/Charts/PeriodChartAdapters.swift`](../../Tenra/Views/Components/Charts/PeriodChartAdapters.swift)
maps Tenra's model onto DesignKit's generic `ChartPoint` / `ChartSeries`:

- **`PeriodDataPoint: ChartPoint`**: `chartLabel` = `label` (unique category-axis key),
  `chartAxisLabel` = `PeriodAxisLabel.compact` ("ЯНВ", "W07", "Q1", with a `'25` suffix outside the
  current year), `chartTitle` = `granularity.bannerLabel(for: key)` (banner title), `chartDate` =
  `periodStart` (the first future period gets the "Today" marker), `chartIsPartial` = the period has
  not ended (never for `.allTime`): its bar fades, its line is dashed and the banner says "so far"
  (DesignKit 8.3.0).
- **`PeriodChartSeries`** (`spending`, `income`, `avgDailyExpenses`, `cashFlow`, `wealth`):
  `value(for:)` (what the series plots) and `chart` (the `ChartSeries`: id, the localized name
  VoiceOver reads when several series share a chart, colouring, baseline, line width, which way is
  better (spending and the daily average lower, the rest higher: the banner's change and the record),
  what a long-press stretch sums up to (a total; the last value for wealth and the daily average)).
  A new case needs an arm in each switch; they are exhaustive.
- **`chart(in: points)`** is the series over its dataset (`PeriodChartHistory`), what the call-site
  inits pass: **a year ago** (the period that held this period's start a year earlier, weeks,
  months and quarters only) and, for spending, **the forecast** of the current period: so far plus
  the rest of it at the average of the last three finished periods. The `spending_forecast` insight
  also adds the subscriptions still due this month, so the two can differ by those.
- **Chart options** (`ChartOptionsHost`, `.chartOptionsHost()` on `MainTabView`): DesignKit's
  `ChartDisplayOptions` in `@AppStorage("charts.displayOptions")` (default: all off)
  handed to every chart through `.chartDisplayOptions`. Each `ChartSwitcher` shows them in a menu by
  its zoom: the average line, highs and lows, the forecast, a year ago, a ruler the chart scrolls
  under. A change applies to every chart of the app, standalone `BarChart`s included.
- **Call-site inits** on `LineChart`, `BarChart`, `ChartSwitcher`, `HeroSparkline` and `Sparkline` take
  `PeriodDataPoint`s, `PeriodChartSeries` and the `granularity:` / `currency:` parameters. An empty
  `currency` formats banner and VoiceOver values compactly ("75K"). `MiniSparkline` is a typealias of
  `Sparkline`.

Several series on one chart overlay (line) or group (bar), and the banner lists each one; the income
vs. expense chart is `series: [.income, .spending]`.

Call sites:

- `InsightsSummaryDetailView.chartSection`: `ChartSwitcher(series: focus.chartSeries, initialStyle: .bar)`;
  `focus.chartSeries` is `[.income, .spending]` for the overview, one series for expenses, income and
  net flow.
- `InsightDetailView.chartSection` (`.periodTrend`): `ChartSwitcher` with the series matching the
  insight, default style `.line`.
- `MerchantDetailView.monthlyChart` and `CategoryDetailView.monthlyChart`: the last 24 months as a
  `BarChart` of `ChartValuePoint`s (`PeriodAxisLabel.month`), this month as not over; twice the
  12-month window, so the chart opens with this month in the middle (a series that fits the window
  is shown whole, ending at the screen's edge). Both from `CategoryMonthHistory` (off the main
  actor, 36 months for the year ago): the same month a year ago, this month's forecast for
  expenses; the category's adds a monthly budget as a line the bars past it turn orange at.
- `InsightDetailView` for the period records (`.bestMonth`): `ChartSwitcher(series: .cashFlow,
  initialStyle: .bar)` over every period, highs and lows always on (`.chartShowsRecords()`, the
  person's other options kept), in place of a hero of the whole history, whose axis piled up.
- `AssistantReplyView`'s timeline: this month or week as not over.
- `SpendingByDaySection` ("By day"): `CalendarHeatmap` of the window's days (52 weeks) and a
  `BarChart` of the weekdays with the average line, opening on the busiest (`selection:`), which
  picks the categories listed under it.

Scrollable charts bleed to the screen edges: no horizontal padding on the chart's parent, padding goes on
the neighbouring header and list.

## Breakdown slices

`DonutSlice` and its folding live in DesignKit (`OrbChart.swift`: `foldingSlivers` keeps slices of 5 % and
more, at most 6, merges the rest into "Other" and drops that wedge under 3 %; `opacityStepped` shades
one colour). Tenra's adapters are in [`Utils/DesignKitBridge.swift`](../../Tenra/Utils/DesignKitBridge.swift):
`DonutSlice.from(_: [CategoryBreakdownItem])` (folded category slices) and
`DonutSlice.from(_: [SubcategoryBreakdownItem], baseColor:)` (opacity steps of the category colour).
Category breakdowns render with `OrbChart` in detail screens and `MiniDonut` in feed cards.

## Horizontal paging

Period pagers inside a pushed detail page with `TabView(.page)`, never a custom horizontal
`DragGesture` (it fights the navigation edge swipe-back). `PagedCategoryBreakdownView`
(`InsightDetailView.swift`) and `InsightDeepDiveView` share
[`Views/Insights/PeriodPager.swift`](../../Tenra/Views/Insights/PeriodPager.swift): the index arithmetic
(`PeriodPaging`, pinned by `PeriodPagingTests`), the chevrons centred on the page's chart
(`PeriodPagerChartBand`) and the empty page (`PeriodPagerEmptyState`).

## Insight mini-visuals

Feed cards (`InsightsCardView.miniChart`) draw `Insight.cardVisual` (`InsightCardVisual`, set by the
generators with ready-to-draw values) in a 120×60 pt slot, with DesignKit's Canvas components:

| `cardVisual` | Feed mini | Detail hero |
|---|---|---|
| `.barPair` | `MiniBarPair` | `HeroBarPair` |
| `.halfGauge` | `MiniHalfGauge` | `HeroHalfGauge` |
| `.milestoneGauge` | `MiniMilestoneGauge` | `HeroMilestoneGauge` |
| `.sparkline` | `MiniSparkline` | `HeroSparkline` |
| `.proportionBar` | `MiniProportionBar` | `HeroProportionBar` |
| `.ring` | `ProgressRing` | none |
| `.budgetBars` | up to 3 `LinearProgressBar`s | none |
| `.donut` | `MiniDonut` | none |
| `.weekdayBars` | `MiniBars` (the busiest weekday in colour, initials under the bars) | none: `SpendingByDaySection` |

- Visual grammar: solid fill = fact, translucent or dashed = forecast, grey = comparison base, tick =
  norm or target.
- With no `cardVisual` the card falls back to a chart derived from `detailData` (`legacyMiniChart`).
- `cardVisual` is part of `Insight ==`.
- Feed cards never instantiate Apple Charts (Canvas only), and pass `animatesOnAppear: false` to
  `ProgressRing` / `LinearProgressBar`: the feed is a `LazyVStack`, where `onAppear` re-fires on scroll.
- **`sparklineTail`**: a `.periodTrend` fallback sparkline shows only the last 12 weeks, 12 months or 8
  quarters (years and all-time stay whole). The detail view gets the full series, so the slice stays in
  the card, not in the generators (insights.md contract). `.sparkline` card visuals are shaped by their
  generator and are not sliced; their points must carry real labels (the hero plots them on a category
  axis).

## Hero visuals

`InsightDetailView.heroChartSection` renders the hero for the same `cardVisual` payload (table above).
Every hero gets `entranceDelay: heroEntranceDelay` (0.5 s), so its entrance animation starts after the
zoom navigation transition settles; at 0 the hero jumps when the push completes. `.ring`, `.budgetBars`,
`.donut` and `.weekdayBars` have no hero: their detail screens already render full-size sections.
