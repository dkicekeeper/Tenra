# Insights Domain

Operational guide for `InsightsService` (`Services/Insights/`) and the insight notifications
(`Services/Notifications/`). Per-metric formulas, windows and severities: §Metric catalogue.

## Architecture

`InsightsService` is a **`nonisolated final class`**: it opts out of the default MainActor
isolation and runs on a background thread via `Task.detached` in `InsightsViewModel`.

### File layout

`InsightsService.swift` (granularity API, period data points, category deep dive,
`PreAggregatedData`, shared helpers) plus 9 domain extensions: `+Spending`, `+Income`,
`+Budget`, `+Recurring`, `+CashFlow`, `+Wealth`, `+Savings`, `+Forecasting`, `+HealthScore`.
Next to them: `BackgroundInsightsRefresher` (§Signal notifications) and
`HealthRecommendationBuilder`.

## DataSnapshot Pattern

`DataSnapshot` is a `Sendable` struct that bundles MainActor-isolated data: transactions, categories, recurringSeries, accounts, `balanceFor` closure.

- Built on MainActor before `Task.detached`
- Threaded through entire computation chain
- ⚠️ **No `transactionStore` access in extension methods** — all data comes via parameters (snapshot fields). Adding new generators must follow this pattern.

## Summary stat grid (2×2)

Each of the four cards is its **own** `NavigationLink`, so each lands on its own screen and
VoiceOver reads them as separate buttons.

| Card | Destination |
|---|---|
| Available Balance | the `total_wealth` insight (per-account composition) under the card's own title, "Available balance" (`InsightDetailView(insight:currency:title:)`; the feed keeps "Accumulated capital"). Its total is computed from the SAME account filter as `availableBalance` (`!isLoan && includeInBalance`), so the figures agree; falls back to the overview before the first insights pass lands |
| Net Flow / Expenses / Income | `InsightsSummaryDetailView(focus:)` — `SummaryDetailFocus` picks the hero metric, the `PeriodChartSeries` drawn, the `PeriodListMetric` of the period list and the screen title |

Cards also carry a `MiniSparkline` (through `InsightsStatTrend` in
[DesignKitBridge.swift](../../Tenra/Utils/DesignKitBridge.swift)) so the summary answers "is
this normal for me?" without a tap. It plots only the **last 6 periods**
(`InsightsStatTrend.periodLimit`): a 24-month window inside a ~150pt card is unreadable, and
the whole history is one tap away in the detail screen. Callers pass the full series; the
trend view slices it.
The balance card's series is the running-wealth line from
`InsightsService.cumulativeBalancePoints(_:endingBalance:)` — **the** derivation, shared
with the wealth insight's chart so the two never disagree (pinned by
`CumulativeBalancePointsTests`). Don't re-implement that walk locally.

`SummaryDetailFocus` reuses existing section titles (`insights.spendingTrend`,
`insights.incomeGrowth`, `insights.cashFlowTrend`) — no new localization keys.

Under the grid, **For today** (`DailyAllowanceLink`, docs/domains/intents.md §For today): the
only insight not built by `InsightsService`. Its figure is Ten's forecast, which runs on the main
actor, so the view builds an `Insight` of type `.dailyAllowance` with
`.dailyAllowance(DailyAllowanceDetail)` itself and shows it with the feed's `InsightsCardView`
and `InsightDetailView` (formula card, then `InsightAllowancePaymentsList`), never in the feed,
the urgent strip or the signals.

## Money bucket classification (income vs expense)

⚠️ **Never write a bare `tx.type == .expense` / `== .income` in an Insights aggregation.**
Use `InsightsService.moneyBucket(_:)`, which delegates to the canonical
`TransactionType.summaryContribution(isFuture:)` (CLAUDE.md ⚠️ #11) — the same rule the
Home and History summary cards use:

- `.loanPayment` / `.loanEarlyRepayment` → **expense**
- `.depositInterestAccrual` → **income**
- `.internalTransfer`, `.depositTopUp`, `.depositWithdrawal` → neither

`filterService.filterByType(_:type:)` matches the raw type and must NOT be used for the
expense/income slice.

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
`InsightsService.syntheticCategoryStyle(for:)` supplies one (`creditcard.fill` /
`TransactionDisplayHelper.loanPaymentColor`, `percent` / income tint), mirroring
`CategoryStyleCache.systemTypeStyle` so a loan payment looks the same in Insights as in the
transaction list (both read the one loan colour; pinned by `CategoryStyleCacheTests`). Every
`CategoryBreakdownItem` builder falls back to it: `cat?.iconSource ?? synthetic?.icon`.

**Deep dive** — `InsightsService.DeepDiveGrouping.forCategory(_:)` decides what a drill-down
breaks a category into: user categories → subcategories, `"Loan Payment"` → the loan account of
each payment (`targetAccountId`), `"Deposit Interest"` → the deposit that paid it (`accountId`).
Account groupings key on the account **id** (one row per id: a renamed account keeps one row,
under its latest name), so `SubcategoryBreakdownItem.id` is an account id
there and `InsightsViewModel.categoryDeepDivePages` fills `iconSource` from
`transactionStore.accountById` (the nonisolated builder can't read account icons).
`InsightDeepDiveView` then renders the account logo instead of a colour dot and recolors its orb
slices with each logo's dominant colour via `DominantColorExtractor` — the same async resolve
`heroAccentGlow` and `WealthOrbSection` use. `InsightsService.categoryDeepDivePeriods` filters on the
money bucket of the breakdown it opens from (`.expense` for spending, `.income` for income sources —
an income and an expense category may share a name), so income categories drill down too;
`InsightsView` therefore enables the drill-down closure for `.income` insights as well and passes
`isExpenseContext: false`, which selects the income bucket and colors a rise green in the comparison card.

Pinned by `InsightsMoneyBucketTests` and `CategoryDeepDivePeriodsTests`.

## PreAggregatedData

One O(N) pass (`PreAggregatedData.build`) builds: monthly totals, category-month expenses,
`categoryTotals` (all-time per category), `txDateMap`, `firstDate` / `lastDate`,
`accountTransactionCounts`, `lastAccountDates`, `seriesMonthlyEquivalents`, and `fxStale`
(a cross-currency tx was skipped on a cold FX cache; the view model recomputes when rates land).

All generators use O(M) dictionary lookups against this struct.

⚠️ **Piggyback rule**: Add fields to `PreAggregatedData.build()` O(N) loop — never add separate O(N) loops when one already exists.

### `seriesMonthlyEquivalents` map

Pre-computed `[seriesId: monthlyEquivalent]` map built once in `PreAggregatedData.build(…, recurringSeries:)`. Generators (HealthScore, Recurring growth, Forecasting) pass it via `seriesMonthlyEquivalent(_:baseCurrency:cache:)` to skip per-series `CurrencyConverter.convertSync` calls.

⚠️ **When adding a new generator that calls `seriesMonthlyEquivalent`, always pass `cache: preAggregated?.seriesMonthlyEquivalents`**.

### `filterByTimeRange(_:start:end:txDateMap:)` overload

Legacy MoM paths (Spending/Income) and `computeMonthlyPeriodDataPoints` accept an optional `txDateMap` to skip date parsing. Always thread `preAggregated?.txDateMap` through new generators that filter by date range.

`filterService.filterByTimeRange` without txDateMap is expensive (~16μs/tx due to DateFormatter) — use `txDateMap` inline filter when available.

## Static Helpers

Three top-level computation entry points:
- `computeMonthlyTotals`
- `computeLastMonthlyTotals`
- `computeCategoryMonthTotals`

All return lightweight value-type structs (`InMemoryMonthlyTotal`, `InMemoryCategoryMonthTotal`).

## Feed order and the urgent strip

- `InsightsViewModel.sortedBySeverity()` sorts insights within each section:
  `critical > warning > neutral > positive`.
- **"Needs attention" strip** — `InsightsViewModel.urgentInsights` (top 5 of
  `allUrgentInsights`, the critical/warning insights of ALL categories). Promoted insights are
  EXCLUDED from their category sections (unique `matchedTransitionSource` ids). The strip leads
  with the **health score card** (`HealthScoreCardView`, insight-card style with a mini absolute
  half-gauge).
- The filter carousel has an **"Important" chip** (`InsightFilter.urgent`, key
  `insights.filter.urgent`) right after "All": the health card + the UNCAPPED
  `allUrgentInsights` list. Feed filtering runs on `InsightsViewModel.selectedFilter:
  InsightFilter` (`.all` / `.urgent` / `.category(_)`).

## Signal notifications

- `InsightSignalService` (`Services/Notifications/`) — diff engine: fires local pushes for NEW critical/warning signals only (7-day per-id dedup + 5/week global cap + 2-per-recompute cap; delivery inside a 09:00-21:00 window with randomized spacing (`deliveryDates`; night signals move to next morning 09:00-10:30); pending signals that stop qualifying are cancelled on the next recompute (history kept — no flapping re-push); history in UserDefaults). Pure core `selectSignals` is unit-tested (`InsightSignalServiceTests`). Wired at the END of `loadInsightsBackground` phase 2 (`.month` insights).
  - **State vs event signals:** the 7-day per-id dedup suits STATES (a budget that stays overspent may remind weekly). An insight with `Insight.signalKey` is an EVENT: it pushes **once per key** (`FiredRecord(id: signalKey, isEvent: true)`, kept `eventDedupWindow` = 365 days by `retainedHistory`, persisted in the same `insightSignals.history`, so relaunches and BG refreshes respect it). Only `subscriptionPriceIncrease` sets a key (series + new amount, §Metric catalogue). Older records keyed by the plain insight id are re-keyed by `migratingLegacyEventRecords` (same date, no double count in the weekly cap). Event records still count toward the 5/week cap.
- `WeeklyDigestScheduler` — Monday-09:00 digest from `.week` periodPoints, rescheduled on every recompute; body names the week it covers (stale-content guard). Toggle + per-kind toggles: `InsightSignalSettings` → `InsightSignalSettingsView` (Settings).
- **Ten writes first** (`AssistantInbox`, `Services/Agent/`): at the same call site the fresh `.month` signals (any critical/warning of a push kind, at most 2 new a day, each key once) and last week's summary (`AssistantNotices.digest`, once per week key) also become messages from Ten, independent of push permission; tomorrow's subscription charges post from `AppCoordinator.refreshAssistantInbox` (app to the front). They show on Home, never in the chat: `AssistantNoticesSection` under the accounts carries the newest unread one and how many wait; "Go through it" opens the assistant's tab with its question ([assistant.md](assistant.md) §6).
- **From Ten:** a signal and the digest carry Ten's still picture (`TenNotificationArt`, DesignKit's `ParticleCreature.image`, drawn when scheduled in the phone's appearance): surprised at a spike or a large expense (`InsightSignalKind.isSurprise`), worried at the rest, glad on the digest. Its message on Home takes the same mood (`AssistantNotice.Mood.surprised`).
- Notification ids use prefix `insightSignal_` — AppDelegate routes taps to the Analytics tab via `.insightSignalNotificationTapped`.
- Permission: both senders skip unless authorized or `.provisional`. After the full load, `ContentView` calls `NotificationPermissionManager.requestProvisionalIfUndetermined()` (quiet delivery, no system prompt) while the user is undecided and signals or the digest are on.
- `BackgroundInsightsRefresher` (`Services/Insights/`) — BGAppRefreshTask (`dakacom.Tenra.insightsRefresh`, earliest +4h, registered in AppDelegate, submitted on scenePhase → .background): headless recompute straight from `CoreDataRepository` (no TransactionStore/AppCoordinator), feeds `processInsights(.month)` + digest `reschedule(.week)`. It also rolls subscription next-charge reminders forward first (`rescheduleSubscriptionReminders`, independent of the insight toggles), so reminders keep coming when the app is not opened for a billing cycle. Does NOT run recurring/deposit catch-up — sees data as of the last foreground session. Simulator does not run BGTasks; verify on device via LLDB `_simulateLaunchForTaskWithIdentifier:`.

## Adding a New Generator — Checklist

1. Place in appropriate `+<Domain>` extension file
2. Accept all data via `DataSnapshot` parameters — no `transactionStore`
3. If filtering by date range — accept optional `txDateMap` and use it
4. If iterating series — accept `seriesMonthlyEquivalents` cache and pass to `seriesMonthlyEquivalent`
5. If adding new aggregations — piggyback on `PreAggregatedData.build()` O(N) pass
6. Return value-type Sendable struct — no class instances threaded through
7. If insight is severity-sortable, ensure `severity` field is set
8. Consider setting `cardVisual` (purpose-built feed mini-visual — see charts.md §Insight mini-visuals); pick by message type: pairwise comparison → `.barPair`, value-vs-norm → `.halfGauge`, % of limit → `.ring`, composition → `.donut` (accounts) / `.proportionBar` (flat bar), per-category budget list → `.budgetBars` (top-3), progress to a discrete milestone → `.milestoneGauge`, trend with projection/extremes/custom points → `.sparkline`; a plain trend stays on the detailData sparkline fallback
9. If the result is the same for every granularity, add its id to `sharedInsightIDs` (or a prefix to `sharedInsightIDPrefixes`), and add a row to §Metric catalogue

## Granularity switching — gotchas

- **`Insight` equality MUST stay value-based** (`Models/InsightModels.swift`). Insight ids are stable across granularities (e.g. `top_spending_<category>` when the same category tops every period). With id-only `==`, SwiftUI diffing treats a new granularity's card as unchanged and skips re-render → cards show the previous period's numbers. `==` compares rendered fields; `hash` stays id-only.
- **Granularity switches must NOT cancel the in-flight recompute** (two phases, §Refresh). `currentGranularity.didSet` applies from cache if present, else sets `isLoading` and waits — starting a competing load cancels phase 2 and leaves the cache incomplete → cards lag / show the wrong granularity.
- **`healthScore` is published with the PHASE-1 write.** It needs only `.month` period data, derivable from `preAggregated` (`computePeriodDataPointsFromPreAggregated(.month)` — internal for exactly this call), so the health card appears with the rest of the feed.
- **`applyPrecomputed` never applies a missing granularity** — it keeps `isLoading=true` instead of flashing empty/stale cards.
- **Budget insights are shared, computed once per refresh.** A budget's spent covers its own period, never the granularity window, so `generateBudgetInsights` runs over ALL transactions on the first granularity and the others take the cards from `sharedInsights` (`InsightsService.budgetInsightIDs`, part of `sharedInsightIDs`). They are put back in their own feed slot, not appended with the other shared insights, so the urgent strip keeps its order. Pinned by `InsightsBudgetOnceTests`.
- **The summary card shows the CURRENT bucket.** For `.week` the current week is often empty (totals = 0) while the 52-week window total is non-zero — correct, not a bug.
- **Deep-dive subcategory breakdown reads the LINKED subcategory** (`TransactionSubcategoryLink` via store indexes), passed to `categoryDeepDivePeriods` as the `subcategoryName` lookup. The add flow leaves `tx.subcategory` nil, so grouping by `tx.subcategory` dumps everything into "no subcategory".

## Detail view & paging

- **Adding an `InsightDetailData` case → update 3 exhaustive switches**: `InsightDetailView.chartSection`, `InsightDetailView.detailSection`, and `InsightsCardView.miniChart`. Miss one → build error (or silent `EmptyView`).
- **Hero charts**: every `cardVisual` renders a DEDICATED interactive hero (`HeroSparkline`, `HeroProportionBar`, `HeroHalfGauge`, `HeroBarPair`, `HeroMilestoneGauge` — see charts.md §Hero visuals), all with `entranceDelay = 0.5` (`heroEntranceDelay`) so entrance animations start after the zoom nav transition. Period records (`bestMonth`) keep `chartSection == EmptyView` — their chart IS the `HeroSparkline` (full history, extreme markers, tap selection) above the ranked lists.
- **Per-`insight.type` detail variants are done by special-casing `insight.type` inside the existing `chartSection`/`detailSection` switch arms — NOT by adding an `InsightDetailData` case** (which costs the 3 exhaustive-switch updates above). E.g. `bestMonth` reuses `.periodTrend` but renders the ranked Top-10 lists; wealthGrowth reuses `.periodTrend` but lists cumulative balance. `PeriodListMetric` selects the single row value (`.cumulativeBalance`, `.expenses`, …).
- **The tone's colour (`.heroBackground`) goes behind the header only with a hero visual (`cardVisual` other than `.ring` / `.budgetBars` / `.donut` / nil) and never on a screen with an `OrbChart`** (`.categoryBreakdown`, `.wealthBreakdown`): the owner's rules of 2026-10, `InsightDetailView.showsHeroColour`. A header alone on the colour ended right under it, with the full chart half on the fade.
- **Detail structure contract, top to bottom: `HeroSection` header → chart (hero visual / full chart) → cards (formula) → detail lists.** EVERY detail shows the header, including formula breakdowns — `InsightFormulaCard` is rendered with `showsHero: false` there so the metric isn't duplicated (the card keeps its icon+title row, formula rows, explainer, recommendation). The header is always **iconless** (`showsIcon: false`).
- **Detail lists live in [InsightDetailLists.swift](../../Tenra/Views/Insights/InsightDetailLists.swift)** (`InsightCategoryBreakdownList` / `InsightRecurringBreakdownList` / `InsightPeriodBreakdownList` / `InsightRankedPeriodList` / `InsightAccountBreakdownList` / `InsightDormantAccountList` / `InsightBudgetBreakdownList`), sharing one private `InsightDetailListCard` shell: `SectionHeader(.large)` ABOVE the card, rows inside `.cardStyle()` with `AppSpacing.lg` inner padding, `.screenPadding()` owned by the shell — call sites must NOT add their own screenPadding. ⚠️ Exception: `InsightBudgetBreakdownList` does NOT use the shell — `BudgetProgressRow` (adapter over DesignKit's `LimitProgressCard`) is already a standalone card, wrapping it would nest cards. The category list is generic over the drill-down destination and is reused by the paged breakdown's pages (`periodKey:`).
- **Detail header (`InsightDetailView.headerSection`) is DesignKit's `HeroSection`.** Mapping: `title ← insight.subtitle` (insight.title is the nav title), amount slot ← metric (`FormattedAmountText` for currency metrics, `primaryText:` for percent/count + unit), centered `accessory` ← `InsightTrendBadge(.pill)`, `HeroSection.subtitle ← trend.comparisonPeriod`. Two duplication traps: (a) generators that set `trend.comparisonPeriod == subtitle` (monthOverMonth, wealthGrowth) would render the same line twice — `comparisonSubtitle` suppresses it; (b) **count-style metrics** (`"2"` + unit "categories") duplicate the count already in the subtitle — prefer an **amount** metric (total overshoot / total idle balance) and leave the count in the subtitle (budgetOverspend / projectedOverspend / accountDormancy).
- **`wealthBreakdown` chartSection renders the wealth orb from the generator's `cardVisual` `.donut` slices** (top accounts + "Other" already aggregated) via `WealthOrbSection` (private in InsightDetailView.swift): perimeter labels show ACCOUNT NAMES (`OrbChart(labelStyle: .name)`), and slice colours resolve asynchronously to the dominant logo colour (`DominantColorExtractor`) for brand-icon accounts — hash palette stays the fallback. The generator can't resolve logo colours itself (nonisolated, no image access).
- **MoM spending detail renders NO full trend chart** — `chartSection` skips `.periodTrend` for `.monthOverMonthChange` (and `.bestMonth`): the HeroBarPair already carries the was/now message; the period breakdown list stays.
- **`InsightFormulaCard` headerRow title is the static `insights.formula.howCalculated`** ("How it's calculated"), not `model.titleKey`, which would repeat the navigation title.
- **`InsightFormulaRow.labelText` overrides `labelKey`** — use it to put a data-driven label (date, category name) in the row heading instead of cramming `.rawText("amount — label")` into the value cell (yearOverYear rows).
- **`.categoryBreakdownPaged` renders full-screen in `InsightDetailView.body`** via `TabView(.page)`, NOT inside `detailSection` (the detailSection case is a dead `EmptyView`). A TabView must own the vertical space — nesting it in the body's `ScrollView` collapses it. The TabView is the OUTER container and **each page is its own `ScrollView { HeroSection → OrbChart (arrows overlaid) → category rows }`**, so hero and orb scroll with the list.
- **Top-spending is emitted for every finite granularity even when the current period is empty** (empty hero "no expenses", still tappable). Only `.allTime` (or a pass without period points) gets the single `.categoryBreakdown`. Paged breakdowns cover all `periodPoints` (current → first tx); `.week` is bounded by its rolling 52-week window.
- **The category drill-down (`InsightDeepDiveView`) pages the same periods**: the TabView swipe + the chevrons on its orb, through `PeriodPagerChartBand` (over DesignKit's `PagerArrows`) / `PeriodPagerEmptyState` / `PeriodPaging` ([PeriodPager.swift](../../Tenra/Views/Insights/PeriodPager.swift)), which `PagedCategoryBreakdownView` uses too — change the pager there, not per screen. Pages = `InsightsViewModel.periodDataPoints` keys at the current granularity, so it opens on the page tapped from (`periodKey`; current period for non-paged breakdowns) and steps exactly where the breakdown does. Every page (hero total + period subtitle, orb, rows, comparison) comes from ONE off-main pass, `InsightsService.categoryDeepDivePeriods` (realized only, like the breakdown, so the total equals the tapped row; previous total read even outside the window). It reloads on `InsightsViewModel.categoryDeepDiveKey` (mutationVersion + touched `transactions`, base currency, FX version, granularity + period keys, subcategory/account versions, the day) and keeps the selected period across reloads. `.allTime`: one page, no arrows, no comparison card. Stepping pinned by `PeriodPagingTests`.
- **`incomeSourceBreakdown` pages the same way** — `generateIncomeSourceBreakdown` mirrors the spending paged path off `pt.income`. It needs the **windowed** transactions, not the current bucket (`generateForecastingInsights(filteredTransactions:)` receives `windowedTransactions`); pre-narrowing to the current bucket would empty every page but the current one. `PeriodCategoryBreakdown.total` is flavor-neutral (expenses OR income), and `PagedCategoryBreakdownView` takes an `emptyTitle`, so an income page does not say "no expenses".
- **Per-generator ad-hoc tx filters MUST apply `LedgerPolicyRule.isRealized`.** `computePeriodDataPoints` and `PreAggregatedData.build` already exclude future-dated tx; a breakdown list that re-filters `expenses` by date range must too, or its rows include future tx while its % total is realized only.
- **Period-trend detail charts/lists choose metric by `insight.type`** (avg-daily → avg daily expenses, monthOverMonth → expenses, incomeGrowth → income; else cash-flow). Pass the FULL `periodPoints` (not `[prev, current]`) so the chart/list span all time. See `periodListMetric` / `periodChartSeries` in `InsightDetailView`.

## Date labels — headings vs axis

- **Hidden amounts in a subtitle.** A generator whose subtitle carries money (the savings rate's saved amount) also sets `Insight.hiddenSubtitle`, the same line with `Formatting.hiddenAmount` in place of the amount; the card and the detail header show `insight.subtitle(amountsHidden:)` with `\.amountsHidden`. The metric itself hides through `FormattedAmountText`. A new generator that puts an amount in its subtitle sets both.
- **`InsightGranularity.headingLabel(for:)`** — use for ANY date acting as a heading / row-title: breakdown-list rows, `PeriodComparisonCard`, paged pager header, wealth/spending service subtitles. Capitalized, full month names, full week range (no abbreviations). Built on `String.capitalizedFirstLetter`.
- **`InsightGranularity.periodLabel(for:)`** — axis / chart only: abbreviates `.week` ("3 янв"); month is full but locale-cased (ru → lowercase "май 2026"). Do NOT use it for headings — renders lowercase in ru locale. `PeriodDataPoint.label` is built from it (axis-oriented); heading call sites recompute via `headingLabel(for: point.key)`.

## Metric catalogue

26 generated insight types. Windows come from `InsightGranularity.dateRange(firstTransactionDate:)`:
`.week` = the last 52 weeks (rolling), `.month` / `.quarter` / `.year` / `.allTime` = first
transaction → today. "Bucket" = one period of the granularity (`currentPeriodKey`,
`previousPeriodKey`); `.allTime` has a single bucket. All money is realized, in base currency,
classified by `moneyBucket` unless a row says otherwise. **Shared** insights are computed on the
first granularity of a refresh and reused for the others (`sharedInsightIDs`,
`budgetInsightIDs`, prefixes `price_increase_` / `large_tx_` in `InsightsService.swift`); the
others are recomputed per granularity.

| Insight id · type | File | Formula and conditions | Window | Severity | Shared |
|---|---|---|---|---|---|
| `top_spending` · `.topSpendingCategory` | +Spending | Largest expense category of the current bucket; metric = its amount, trend = its share of the bucket. Detail `.categoryBreakdownPaged`, one page per bucket | finite: page per bucket, opens on the current one; `.allTime`: id `top_spending_<category>`, one `.categoryBreakdown` over all history | warning if share > 50%; an empty current bucket keeps the card, neutral | no |
| `top_merchant` · `.topMerchant` | +Spending | Merchant with the most spent in the current bucket: realized `.expense` transactions grouped by `normalizedMerchant` (store numbers merge; a description that only repeats its category's name is skipped); metric = its amount, trend = its share of the bucket's realized expenses (loan payments included). Needs ≥ 3 merchants. Detail `.categoryBreakdown` of the top 10, each in its most used category's colour and icon, read-only (`InsightsView` gives it no category drill-down) | bucket (`.allTime`: whole history) | neutral | no |
| `mom_spending` · `.monthOverMonthChange` | +Spending | Expenses of the current bucket vs the previous one; needs previous > 0 | finite: buckets; `.allTime`: this calendar month vs the previous one | warning > +20%, positive < −10% | no |
| `avg_daily` · `.averageDailySpending` | +Spending | Current bucket expenses ÷ its days; trend vs the previous bucket's daily average | bucket (`.allTime`: whole history) | neutral | no |
| `spending_spike` · `.spendingSpike` | +Spending | Category whose spend this calendar month is > 1.5× its average over its months with spending in the 3 previous months; categories whose average is ≤ 1% of the window total are skipped; highest multiplier wins | this month + 3 previous | critical > 2×, else warning | yes |
| `category_trend_<category>` · `.categoryTrend` | +Spending | Category with ≥ 3 consecutive monthly rises up to its latest month (needs ≥ 3 months of its own, ≥ 4 category-months overall); longest streak wins | months: `.week` 3, `.month` 6, `.quarter` 12, `.year` 24, `.allTime` 12 | warning | no |
| `check_growth` · `.averageCheckGrowth` | +Spending | The merchant whose average check grew most in money ((now − before) × visits now): realized one-off `.expense` transactions grouped by `normalizedMerchant`, the last 90 days against the 90 before, ≥ 3 visits in each, up ≥ 15 %. Subscriptions (`recurringSeriesId`) are `subscriptionPriceIncrease`'s. Card `.barPair` (before, now), detail `.formulaBreakdown` | 90 + 90 days | neutral | yes |
| `large_tx_<txId>` · `.largeTransaction` | +Spending | Largest non-recurring (`recurringSeriesId == nil`) `.expense` of the last 30 days, ≥ 4× the average `.expense` of the last 90 days; needs ≥ 20 expenses in those 90 days | 30 / 90 days | warning ≥ 8×, else neutral | yes |
| `income_growth` · `.incomeGrowth` | +Income | Income of the current bucket vs the previous one; needs previous > 0 | as `mom_spending` | positive > +10%, warning < −10% | no |
| `income_source_breakdown` · `.incomeSourceBreakdown` | +Forecasting | Income by category (deposit interest is its own source) as % of each page's `pt.income`; needs ≥ 2 income categories, or 1 plus deposit interest | page per bucket; `.allTime`: one breakdown | neutral | no |
| `budget_over` · `.budgetOverspend` | +Budget | Expense categories over budget; metric = total overshoot | each budget's own period (week, month from `budgetResetDay`, year) via `CategoryBudgetService.budgetProgress(for:transactions:baseCurrency:rates:)` over all transactions | critical | yes |
| `budget_projected_over` · `.projectedOverspend` | +Budget | Not over yet, but spent ÷ days elapsed × days in period > budget; extrapolates only after `max(7, periodDays / 4)` days (before that, projection = spent) | as above | warning | yes |
| `budget_under` · `.budgetUnderutilized` (title "budget headroom") | +Budget | The remaining budgets under 80% spent (0% included); metric = Σ(budget − spent) | as above | positive | yes |
| `total_recurring` · `.totalRecurringCost` | +Recurring | Σ monthly equivalents of active series (daily ×30, weekly ×4.33, quarterly ÷3, yearly ÷12), scaled to the bucket | current state × `.week` 7/30, `.quarter` 3, `.year` 12, else 1 | neutral (positive when 0) | no |
| `price_increase_<seriesId>` · `.subscriptionPriceIncrease` | +Recurring | See below; up to 3 cards, largest increase first | 30 days from the first charge at the new price | warning | yes |
| `subscription_growth` · `.subscriptionGrowth` | +Recurring | Monthly total of all active series vs the total of those started before the lookback; needs ≥ 2 active series, shown when the change is > 5% either way | lookback months: `.week` 1, `.month` 3, `.quarter` 6, `.year` 12, `.allTime` 12 | warning > +10%, positive < −10% | no |
| `net_cashflow` · `.netCashFlow` | +CashFlow | Income − expenses of the current bucket; trend vs the average of all buckets | buckets (none for `.allTime`, see below) | positive > 0, critical < 0 | no |
| `period_records` · `.bestMonth` | +CashFlow | Bucket with the highest net flow; the detail ranks the best 10 and the worst 10 (deficit buckets only) | all buckets (none for `.allTime`) | neutral | no |
| `projected_balance` · `.projectedBalance` | +CashFlow | Balance of non-loan accounts included in balance + monthly recurring net of active series × period factor − average expenses of the last 3 buckets (a bucket is one period, so not scaled again); metric = the projected change | factor `.week` 7/30, `.quarter` 3, `.year` 12, `.month` 1 (none for `.allTime`) | positive if the projected balance ≥ 0, else critical | no |
| `total_wealth` · `.totalWealth` | +Wealth | Σ balances of non-loan accounts included in balance; detail per account, card donut = top 6 + other | current state; trend arrow = sign of the current bucket's net flow | positive ≥ 0, critical < 0 | no |
| `wealth_growth` · `.wealthGrowth` | +Wealth | Metric = current bucket net flow, change % vs the previous bucket's net flow, shown when \|change\| > 1%; detail = cumulative balance (`cumulativeBalancePoints`) | buckets | positive if net flow > 0, else warning | no |
| `accountDormancy` · `.accountDormancy` | +Wealth | Accounts included in balance, not deposits, balance > 0, last transaction > 30 days ago (`lastAccountDates`); metric = total idle balance; copy frames it as idle money / missed deposit yield | 30 days | neutral | yes |
| `savings_rate` · `.savingsRate` | +Savings | (income − expenses) ÷ income of the last completed calendar month (salary often lands at month end, so a partial month would read as a deficit); needs income > 0 | last completed month, same value for every granularity | positive > 20%, warning ≥ 10%, critical < 10% | no |
| `emergency_fund` · `.emergencyFund` | +Savings | Months covered = balance (non-loan, included) ÷ average monthly expenses of the last 3 calendar months (current one included). When the average net flow is negative the detail adds runway = balance ÷ \|net flow\| | 3 months | months covered: positive ≥ 3, warning ≥ 1, critical < 1; with a runway, the worse of the two | yes |
| `spending_forecast` · `.spendingForecast` | +Forecasting | Spent this calendar month + (expenses of the last 30 days ÷ 30) × days left + monthly equivalent of active expense series ÷ days in month × days left | this month + 30 days | warning if forecast > this month's income, positive if not, neutral with no income | yes |
| `year_over_year` · `.yearOverYear` | +Forecasting | This calendar month's expenses vs the same month a year ago; shown when \|Δ\| > 3% | 2 calendar months | positive ≤ −10%, warning ≥ +15% | yes |

The three cash-flow insights need ≥ 2 buckets, so `.allTime` (one bucket) has none of them;
`wealth_growth` never shows there either (the bucket is compared with itself). `InsightType`
still declares `subcategoryBreakdown` and `accountActivity`; no generator emits them.

### `subscriptionPriceIncrease`

Active series whose category is not income. Only realized linked charges in the latest
charge's currency are compared. From the latest charge, the generator walks back while
neighbouring charges differ by ≤ 5% (same price level); the oldest of those is the **first
charge at the new price**. It is compared with the last charge at the old price, or with
`series.amount` when only one charge is linked. Conditions: increase > 5% and ≤ 300%, and the
gap between the two charges is 0.5–1.6× the period of `series.frequency` (otherwise the plan's
billing period changed, e.g. monthly → yearly, and nothing is shown). The card is visible for
`InsightsService.priceIncreaseVisibleDays` (30) days from the first new-price charge; later
charges at the same price do not extend it. Detail: `formulaBreakdown` (old price, new price,
%, yearly impact, in the charge currency); card `.barPair`. `signalKey =
price_increase_<seriesId>@<currency>:<new amount>`, so each increase pushes once.

### Health score

`computeHealthScore` (+HealthScore), 0–100, over the `.month` buckets of the whole history:
income and expenses summed, `avgMonthlyIncome` = income ÷ number of months. Unavailable when
income is 0.

| Component | Weight | Weight, no budgets | Score |
|---|:---:|:---:|---|
| Savings rate | 30% | 40% | (income − expenses) ÷ income ÷ 20% × 100, capped at 100 |
| Budget adherence | 25% | excluded | share of budgeted categories whose spend this calendar month ≤ `budgetAmount` |
| Recurring load | 20% | 26.7% | (1 − monthly recurring expenses ÷ avg monthly income) × 100, floor 0 |
| Emergency fund | 15% | 20% | months covered (as `emergency_fund`) ÷ 3 × 100, capped at 100 |
| Cash flow | 10% | 13.3% | latest month's net flow ÷ avg monthly income: +20% or more = 100, 0 = 50, −20% or less = 0 |

### Refresh

`InsightsViewModel.loadInsightsBackground()` runs one `Task.detached`:

1. Builds `PreAggregatedData` once for all granularities.
2. **Phase 1**: `computeGranularities([currentGranularity])` plus the health score (from `.month`
   points of `preAggregated`); the shared insights come out of this pass. One MainActor write
   publishes both.
3. **Phase 2**: the other four granularities, reusing the shared insights; a second MainActor
   write. Then `InsightSignalService.processInsights` (`.month` insights) and
   `WeeklyDigestScheduler.reschedule` (`.week` points).

Both writes are generation-guarded (`computeGeneration`) and MERGE into the precomputed caches;
the final apply uses the live `currentGranularity`, so a switch during the load shows the
right tab.
