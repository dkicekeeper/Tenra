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

## Recent Metric Changes (2026-04 audit)

### Deleted (low signal / duplicated)
- `incomeSeasonality`
- `spendingVelocity`
- `savingsMomentum`

### Threshold tweaks
- **`spendingSpike`** — uses relative threshold (1.5x category average) not absolute amount
- **`accountDormancy`** — excludes deposit accounts (they accrue interest without transactions)

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

## Granularity switching — gotchas (hard-won)

- **`Insight` equality MUST stay value-based** (`Models/InsightModels.swift`). Insight ids are stable across granularities (e.g. `top_spending_<category>` when the same category tops every period). With id-only `==`, SwiftUI diffing treats a new granularity's card as unchanged and skips re-render → cards show the previous period's numbers. `==` compares rendered fields; `hash` stays id-only. Do NOT revert to id-only `==`.
- **Granularity switches must NOT cancel the in-flight recompute.** `loadInsightsBackground` is two-phase (priority gran first, then the rest); MainActor writes are generation-guarded and MERGE into the cache (never replace). `currentGranularity.didSet` applies from cache if present, else sets `isLoading` and waits — starting a competing load cancels phase 2 and leaves the cache incomplete → cards lag / show the wrong granularity.
- **`applyPrecomputed` never applies a missing granularity** — it keeps `isLoading=true` instead of flashing empty/stale cards.
- **The summary card shows the CURRENT bucket.** For `.week` the current week is often empty (totals = 0) while the 52-week window total is non-zero — correct, not a bug.
- **Deep-dive subcategory breakdown reads the LINKED subcategory** (`TransactionSubcategoryLink` via store indexes), passed as `subcategoryNameByTxId`. The add flow leaves `tx.subcategory` nil, so grouping by `tx.subcategory` dumps everything into "no subcategory".

## Detail view & paging

- **Adding an `InsightDetailData` case → update 3 exhaustive switches**: `InsightDetailView.chartSection`, `InsightDetailView.detailSection`, and `InsightsCardView.miniChart`. Miss one → build error (or silent `EmptyView`).
- **`.categoryBreakdownPaged` renders full-screen in `InsightDetailView.body`** via `TabView(.page)`, NOT inside `detailSection` (the detailSection case is a dead `EmptyView`). A TabView must own the vertical space — nesting it in the body's `ScrollView` collapses it.
- **Top-spending is emitted for every finite granularity even when the current period is empty** (empty hero "Нет расходов", still tappable). It only falls back to the legacy single `.categoryBreakdown` for `.allTime`. Paged breakdowns cover all `periodPoints` (current → first tx); `.week` is bounded by its rolling 52-week window.
- **Per-generator ad-hoc tx filters MUST apply `LedgerPolicyRule.isRealized`.** `computePeriodDataPoints` and `PreAggregatedData.build` already exclude future-dated tx, but breakdown lists that re-filter `expenses` by date range (e.g. top-spending) did not — caused future tx in the breakdown vs. a realized % total. Keep them consistent.
- **Period-trend detail charts/lists choose metric by `insight.type`** (avg-daily → avg daily expenses, monthOverMonth → expenses, incomeGrowth → income; else cash-flow). Pass the FULL `periodPoints` (not `[prev, current]`) so the chart/list span all time. See `periodListMetric` / `periodChartSeries` in `InsightDetailView`.

## Date labels — headings vs axis

- **`InsightGranularity.headingLabel(for:)`** — use for ANY date acting as a heading / row-title: breakdown-list rows, `PeriodComparisonCard`, paged pager header, wealth/spending service subtitles. Capitalized, full month names, full week range (no abbreviations). Built on `String.capitalizedFirstLetter`.
- **`InsightGranularity.periodLabel(for:)`** — axis / chart only: abbreviates `.week` ("3 янв"); month is full but locale-cased (ru → lowercase "май 2026"). Do NOT use it for headings — renders lowercase in ru locale. `PeriodDataPoint.label` is built from it (axis-oriented); heading call sites recompute via `headingLabel(for: point.key)`.
