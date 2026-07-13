# Financial Health Detail Page — Design

**Date:** 2026-05-04
**Status:** Approved (brainstorming complete, ready for plan writing)
**Scope:** New dedicated detail screen for the Financial Health score in the Insights tab.

---

## Problem

In `InsightsView.swift:118-139`, the `InsightsTotalsCard` (income/expenses/net flow) and `HealthScoreBadge` are wrapped in **a single shared `NavigationLink`** that pushes `InsightsSummaryDetailView`. As a result:

- Tapping the cash-flow totals card and tapping the health-score row both navigate to the **same** cash-flow detail screen.
- The composite Financial Health score (0–100, five weighted components) currently has **no dedicated detail view** that explains how the score is computed, which components are dragging it down, or how to improve it.

The score itself is non-trivial (`InsightsService+HealthScore.swift`) and warrants a dedicated educational + diagnostic screen.

## Out of Scope

The following are intentionally excluded from this design (locked decisions from brainstorming):

- **No score-over-time history.** The detail screen renders the current snapshot only. No line chart, no textual delta vs prior month.
- **No per-component drill-down.** Each of the 5 components is a self-contained inline card; tapping a card does not navigate anywhere.
- **No deeplinks** from a component card to related screens (Categories / Accounts / Subscriptions). May be added in a future iteration; not part of this scope.
- **No formula changes.** `InsightsService+HealthScore.computeHealthScore` keeps its current weights, normalisation, and grading bands. We only add raw values to its return type.
- **`HealthScoreBadge` is unchanged.** It remains the compact entry point on `InsightsView` and any other surface that already uses it.
- **`InsightsSummaryDetailView` is unchanged.** Its content stays as is; only the navigation linkage changes.
- **Audit of duplicate detail screens for other insights** (savings rate, emergency fund, spending forecast, balance runway, year-over-year, subscription growth, duplicate subscriptions) is documented in a separate appendix and is out of scope for this implementation.

## High-Level Approach

Education + diagnostics, components inline, recommendations inline within each component card. Single screen, four sections top-to-bottom:

1. Hero — large 0–100 score with grade.
2. Explainer — what the score is and how the five components are weighted.
3. Components — five inline cards, ordered by weight descending.
4. Unavailable state — when there is not enough data.

## Architecture

### Navigation linkage

`InsightsView.insightsSummaryHeaderSection` currently wraps the entire `InsightsSummaryHeader` (totals card + health badge) in one `NavigationLink`. We split it into two separate links:

- `InsightsTotalsCard` → `InsightsSummaryDetailView` (existing destination).
- `HealthScoreBadge` → new `FinancialHealthDetailView`.

To do this cleanly, we **remove `InsightsSummaryHeader` entirely** and assemble the two child views (`InsightsTotalsCard` + `HealthScoreBadge`) with their own `NavigationLink`s directly inside `InsightsView`. `InsightsSummaryHeader` is a thin wrapper used only by `InsightsView` — its only logic is a debug `onAppear` log line and a `VStack`. Removing it eliminates the navigation-coupling problem at the source rather than papering over it with callbacks. This is verified safe: a project-wide grep finds zero non-self consumers of `InsightsSummaryHeader` (its #Previews are self-contained and removed alongside the file).

The zoom transition pattern already used for insight cards (`matchedTransitionSource(id:in:)` + `navigationTransition(.zoom(...))`) is preserved for the health-score link as well, with a stable id (e.g. `"health-score"`).

### Model extension

The detail view needs **raw input values** as well as the per-component 0–100 scores (for educational text, target labels, and recommendation copy). All of them are already computed inside `computeHealthScore`; we extend `FinancialHealthScore` to carry them out.

New fields on `FinancialHealthScore`:

```swift
let savingsRatePercent: Double          // raw %, e.g. 12.4
let budgetsOnTrack: Int                 // 7
let budgetsTotal: Int                   // 10  (0 = budget component excluded)
let recurringMonthlyTotal: Double       // baseCurrency, used in recommendation text
let recurringPercentOfIncome: Double    // raw %, e.g. 38.5
let monthsCovered: Double               // raw, e.g. 1.8
let avgMonthlyExpenses: Double          // for emergency-fund recommendation maths
let avgMonthlyNetFlow: Double           // for "N months until target" projection
let totalBalance: Double                // for emergency-fund recommendation maths
let netFlowPercent: Double              // raw %, e.g. -7.2
let totalIncomeWindow: Double           // for savings-rate recommendation maths
let totalExpensesWindow: Double         // for savings-rate recommendation maths
let baseCurrency: String                // for currency formatting on detail view
let isBudgetComponentActive: Bool       // mirrors budgetsTotal > 0; explicit for readability
```

These are filled in `InsightsService+HealthScore.swift` from values that are already computed in the function — no extra passes over transactions.

`FinancialHealthScore.unavailable()` keeps returning a placeholder; new fields default to zero / empty currency / `false`.

### New files

| File | Purpose |
|---|---|
| `Tenra/Views/Insights/FinancialHealthDetailView.swift` | Root screen, composes the four sections. |
| `Tenra/Views/Components/Cards/HealthScoreHeroCard.swift` | Large progress ring + score + grade capsule + subtitle. |
| `Tenra/Views/Components/Cards/HealthScoreWeightingCard.swift` | Stacked weight bar + 5-row legend (4 rows when budgets are absent). |
| `Tenra/Views/Components/Cards/HealthComponentCard.swift` | Single component card: header, score contribution, current value, target, progress bar, explainer, recommendation. |
| `Tenra/Services/Insights/HealthRecommendationBuilder.swift` | `nonisolated enum` of pure functions that build localized recommendation strings from `FinancialHealthScore` raw fields. |

### Modified files

| File | Change |
|---|---|
| `Tenra/Models/InsightModels.swift` | Add raw fields to `FinancialHealthScore` (above). Update `unavailable()` initialiser. |
| `Tenra/Services/Insights/InsightsService+HealthScore.swift` | Populate new raw fields in the returned `FinancialHealthScore`. No formula changes. |
| `Tenra/Views/Insights/InsightsView.swift` | Split the shared `NavigationLink` into two; add destination for `FinancialHealthDetailView`. |
| `Tenra/Views/Components/Headers/InsightsSummaryHeader.swift` | **Deleted.** Its visual composition is inlined into `InsightsView.insightsSummaryHeaderSection`. |
| Localization catalog (`.xcstrings` / `Localizable.strings`) | Add new keys (see Localization section). |

## Screen Composition

`FinancialHealthDetailView` body:

```
NavigationStack
└── ScrollView
    └── VStack(spacing: AppSpacing.xl)
        ├── HeroSection         — `HealthScoreHeroCard`
        ├── ExplainerSection    — `HealthScoreWeightingCard`
        ├── ComponentsSection   — five `HealthComponentCard`s, OR EmptyState if unavailable
        └── (optional padding bottom)
```

Standard visual conventions: `screenPadding()`, `cardStyle()`, tokens from `AppSpacing` / `AppTypography` / `AppColors`. Navigation: `navigationTitle = String(localized: "insights.healthScore")`, `.inline` mode.

### Section 1 — HeroSection (`HealthScoreHeroCard`)

A single `cardStyle` card containing:

- **Progress ring**, ~140 pt diameter. `Circle().trim(from: 0, to: score/100).rotation(-90°)` styled with `gradeColor`. Background ring at low opacity. Center: score number in `AppTypography.h1` bold, plus the grade capsule (existing pattern from `HealthScoreBadge`) directly below.
- **Subtitle** in `AppTypography.bodyEmphasis`, `textSecondary`. One of four localized strings depending on grade band (excellent / good / fair / needsAttention). Conveys what this score *band* implies, not numeric details.
- **Reduce Motion:** ring fill is non-animated when `AppAnimation.isReduceMotionEnabled`.

### Section 2 — ExplainerSection (`HealthScoreWeightingCard`)

A single `cardStyle` card containing:

- **`SectionHeaderView` "How it's computed"** (localized).
- **Short paragraph** (`AppTypography.body`, `textSecondary`, ~2 lines): "A 0–100 weighted score across five aspects of financial health. Higher means more financial resilience."
- **Stacked weight bar** ~14 pt high, divided into segments proportional to weights. Five segments by default (30/25/20/15/10). Four segments when `isBudgetComponentActive == false` with redistributed weights (40/26.7/20/13.3). Each segment uses the colour of its component category.
- **Legend** below the bar — 5 (or 4) rows, each with the component icon, name, and weight percent. When budget is excluded, an additional small note states that 25% has been redistributed.

### Section 3 — ComponentsSection

Five `HealthComponentCard`s in a `LazyVStack(spacing: AppSpacing.lg)`, ordered by weight descending: Savings Rate, Budget Adherence, Recurring Ratio, Emergency Fund, Cash Flow.

#### `HealthComponentCard` layout

Inside one `cardStyle()` card:

```
┌───────────────────────────────────────────────────┐
│ [icon]  Savings Rate                  [30% weight]│ ← header
│                                                    │
│   62 / 100        ● Fair                           │ ← score contribution + status capsule
│                                                    │
│   Current value         Target                     │ ← labels (caption, secondary)
│   12.4%                 ≥ 20%                      │ ← jumbo current + target (h2 / body)
│                                                    │
│   ▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░               │ ← progress bar normalised to target
│                                                    │
│   What it is: How much of your income you keep.   │ ← explainer (bodySmall, secondary)
│   A higher savings rate means more resilience.    │
│                                                    │
│   💡 To raise this from 12.4% to 20%, cut          │ ← inline recommendation in tinted box
│       expenses by ≈ 85 000 ₸/mo or grow income     │
│       by ≈ 110 000 ₸/mo.                           │
└───────────────────────────────────────────────────┘
```

Approximate height: ~210 pt; recommendation may take 2–3 lines.

**Progress-bar normalisation** — bars are normalised to each component's target zone, not to an absolute 0–100 scale, so the bar visually represents "distance to a healthy target":

| Component | Bar normalisation |
|---|---|
| Savings Rate | `min(rate / 20.0, 1)` |
| Budget Adherence | `onTrack / total` (0…1); empty bar with muted style when `total == 0` |
| Recurring Ratio | `1 − min(recurring/income, 1)` (lower recurring share → fuller bar) |
| Emergency Fund | `min(monthsCovered / 3, 1)` |
| Cash Flow | `clamp((netFlowPercent + 20) / 40, 0, 1)` (matches the formula's 0–100 mapping) |

**Bar colour** by progress: `destructive` < 0.33, `warning` 0.33–0.66, `success` ≥ 0.66. Uses existing `AppColors`.

**Score contribution row** displays the per-component score (0–100) and a small severity capsule (mirroring `HealthScoreBadge` styling) coloured by score band.

**Component palette** (icons mirror existing `InsightCategory.icon` choices where possible):

- Savings Rate — `banknote.fill` (matches `InsightCategory.savings`)
- Budget Adherence — `gauge.with.dots.needle.33percent` (matches `.budget`)
- Recurring Ratio — `repeat.circle` (matches `.recurring`)
- Emergency Fund — `shield.lefthalf.filled`
- Cash Flow — `chart.line.uptrend.xyaxis` (matches `.cashFlow`)

#### Recommendation builder

`HealthRecommendationBuilder` is a `nonisolated enum` that takes a `FinancialHealthScore` and returns a localized `String` per component. Each component has 2–3 branches (problem / borderline / healthy):

| Component | Branches |
|---|---|
| Savings Rate | `< 20%` → "raise to 20% by cutting `<X>` or earning `<Y>` more"; `≥ 20%` → healthy confirmation. |
| Budget Adherence | `total == 0` → "budgets not configured, this component is excluded"; `onTrack < total` → "K categories over budget — review them"; `onTrack == total` → healthy confirmation. |
| Recurring Ratio | `> 50%` → "recurring is X% of income; review subscriptions"; `≤ 50%` → healthy confirmation. |
| Emergency Fund | `< 3 months` → "need ≈ Z more to reach 3 months" plus optional projection "at current saving pace, ~N months" only if `avgMonthlyNetFlow > 0`; `≥ 3 months` → healthy confirmation. |
| Cash Flow | `netFlowPercent < 0` → "spending exceeds income by X%"; `≥ 0` → healthy confirmation. |

Numeric placeholders are formatted with `Formatting.formatCurrencySmart` (currency amounts) and `String(format:)` (percentages, integers). Strings live entirely in the localization catalog with parameterised placeholders — no inline string concatenation in the builder.

### Section 4 — Unavailable state

Triggered when `score == 0` AND `totalIncomeWindow == 0` (i.e. the value returned by `FinancialHealthScore.unavailable()`):

- Hero shows "—" instead of the number, neutral colour, subtitle "Not enough data".
- Explainer section renders normally (the educational content is still useful).
- Components section is replaced by a single `EmptyStateView` (icon `chart.bar.doc.horizontal`, message "Add income and expense transactions — we'll evaluate your financial health once enough data is available").

## Edge cases

All of the below are part of the implementation scope:

1. `totalIncome == 0` → unavailable hero + components replaced by empty state.
2. `budgetsTotal == 0` → Budget Adherence card rendered in muted style (textTertiary text, empty bar, neutral severity), value shown as "—", recommendation explains the redistribution. Weighting bar shows 4 segments instead of 5 with a redistribution note.
3. `recurringMonthlyTotal == 0` → Recurring Ratio shows 0% with a positive recommendation ("no recurring obligations — this component is at full strength").
4. `avgMonthlyExpenses == 0` → Emergency Fund "months covered" computed value can be unbounded; cap display at "12+" months, severity positive.
5. `avgMonthlyNetFlow ≤ 0` for the emergency-fund recommendation → omit the "N months until target" projection sentence; keep the "need ≈ Z more" sentence.
6. All five components at 100 → no special case; healthy-branch recommendations render naturally; hero shows "Excellent".
7. Extreme negative cash flow (e.g. `netFlowPercent < −20%`) → progress bar at 0 (clamped), severity critical, recommendation copy avoids quoting an unintuitive percentage when it is dramatically out of bounds.
8. Very large currency values → `Formatting.formatCurrencySmart` already renders short forms ("1.2 млрд").
9. Reduce Motion enabled → ring fill and progress bars use `AppAnimation.adaptiveSpring` so animation collapses to no-op.
10. Dark mode → all colours route through `AppColors` and `gradeColor`. Verify contrast on the grade capsule's 0.12-opacity background; adjust opacity if needed.

## Localization

All copy is added to the existing localization catalog. New keys, grouped by purpose:

**Hero / general**

- `insights.health.subtitle.excellent`
- `insights.health.subtitle.good`
- `insights.health.subtitle.fair`
- `insights.health.subtitle.needsAttention`
- `insights.health.unavailable.title`
- `insights.health.unavailable.message`

**Explainer**

- `insights.health.howItWorks` — section header.
- `insights.health.explainer` — paragraph copy.
- `insights.health.weightLabel` — capsule format, e.g. `"%d%%"`.
- `insights.health.weights.redistributed` — note shown when budget component is excluded.

**Component titles & explainers** (5× each):

- `insights.health.component.<name>.title`
- `insights.health.component.<name>.short` (icon-row label, used in legend)
- `insights.health.component.<name>.explainer`

…where `<name>` ∈ `{savingsRate, budgetAdherence, recurringRatio, emergencyFund, cashFlow}`.

**Value & target labels**

- `insights.health.currentValue`
- `insights.health.target`
- `insights.health.scoreContribution` — e.g. `"%d / 100"`.
- `insights.health.target.<name>` (5×) — copy such as `"≥ 20%"`, `"100% in budget"`, `"< 50% of income"`, `"≥ 3 months"`, `"≥ 0"`.

**Recommendations** (per branch):

- `insights.health.rec.savingsRate.below`, `.healthy`
- `insights.health.rec.budgetAdherence.empty`, `.partial`, `.full`
- `insights.health.rec.recurringRatio.high`, `.healthy`
- `insights.health.rec.emergencyFund.below`, `.belowWithProjection`, `.healthy`
- `insights.health.rec.cashFlow.negative`, `.positive`

All recommendation strings carry placeholder positions (`%@`, `%d`, `%.1f`) compatible with both Russian and English grammar.

## Testing

Unit tests added under `TenraTests/Insights/`:

- `HealthRecommendationBuilderTests` — table-driven: each component × each branch → assert the expected localization key is selected and that the substituted numeric arguments are correct.
- `FinancialHealthScoreTests` (extend or add) — assert that on a small fixture of transactions and accounts, every newly added raw field on `FinancialHealthScore` matches the per-component score's underlying value, and that `unavailable()` initialises every new field to a sensible zero/empty default.

No SwiftUI snapshot tests are added; visual fidelity is verified manually in `#Preview`s.

## Risk Notes

- **`InsightsSummaryHeader` deletion.** Verified at design time: the only production consumer is `InsightsView.insightsSummaryHeaderSection`. The file's #Previews are self-contained and removed with it. The implementation plan still includes a re-verification step before deletion.
- **`HealthScoreBadge` reuse.** It is also used in `Settings` (per the comment header in `HealthScoreBadge.swift`). Verify that the badge's tap target is unaffected by this change. If `Settings` does not navigate from the badge, no further action; if it does, consider unifying with the new detail view.
- **`unavailable()` initialiser.** Adding many new fields to `FinancialHealthScore` requires updating every existing call site. Compiler will catch them; nonetheless, the implementation plan must explicitly list each.

---

## Appendix — Audit of insights with duplicating detail screens (out of scope, deferred)

This appendix is reference material for a follow-up project. Not part of this design's implementation.

`InsightDetailView` renders a header, a chart section, and a detail section based on `Insight.detailData`. When `detailData == nil`, the detail screen is essentially the card's contents repeated — the user gains no new information by tapping. Audit results follow.

### Insights with `detailData == nil` (full duplication)

| Category | Type | Source location | What's missing on detail |
|---|---|---|---|
| Savings | `savingsRate` | `InsightsService+Savings.swift` | Income vs expenses split, monthly trend, target zone visualization. |
| Savings | `emergencyFund` | `InsightsService+Savings.swift` | Which accounts are counted, the avg-monthly-expenses figure used in the calculation, distance to a 3-month target. |
| Forecasting | `spendingForecast` | `InsightsService+Forecasting.swift` | Breakdown of `spentSoFar` + `avgDailySpend × daysRemaining` + recurring; daily-burn chart. |
| Forecasting | `balanceRunway` | `InsightsService+Forecasting.swift` | The `avgMonthlyNetFlow` figure used; balance projection line; "what-if" alternative scenarios. |
| Forecasting | `yearOverYear` | `InsightsService+Forecasting.swift` | This-year vs last-year monthly bar chart; top categories driving the change. |
| Recurring | `subscriptionGrowth` | `InsightsService+Recurring.swift` | List of new or price-increased subscriptions over the comparison window. |
| Recurring | `duplicateSubscriptions` | `InsightsService+Recurring.swift` | The actual duplicate series within each affected category. |

### Insights with `detailData == nil` that may be acceptable

`InsightsService+CashFlow.swift:131` — `projectedBalance` (line 130) carries `detailData: nil` but its `trend.comparisonPeriod` already includes the current balance. Acceptable in the short term; revisit when overhauling cash-flow drill-downs.

### Suggested expansion patterns (for the future project)

- **Computational components.** `savingsRate`, `emergencyFund`, `spendingForecast`, `balanceRunway`: detail should expose the inputs to the formula (income/expenses windows, accounts counted, days remaining, avg net flow) so the user can see *why* the number is what it is. Pattern: a small "inputs" card under the header followed by the existing chart-or-empty body.
- **List-driven insights.** `subscriptionGrowth`, `duplicateSubscriptions`: extend `InsightDetailData` with new cases that carry the actual offending series (`recurringDeltaList`, `duplicateGroupList`) and render them as rows in the detail body.
- **Comparison insights.** `yearOverYear`: extend `InsightDetailData` with a `yearComparison(thisYear: [PeriodDataPoint], lastYear: [PeriodDataPoint], topMovers: [CategoryBreakdownItem])` case and render an overlaid bar chart plus the top movers list.

These follow the same architecture (extend `InsightDetailData`, render in `InsightDetailView.detailSection`); no new screens are needed, only new detail-data cases and rendering branches. Each insight type's expansion is independent and can be sequenced separately.
