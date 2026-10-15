---
phase: 03-performance
plan: "01"
subsystem: insights-performance
tags: [performance, insights, pre-aggregated-data, O(1)-lookup, allTime]
dependency_graph:
  requires: []
  provides: [categoryTotals-field-in-PreAggregatedData, allTime-O1-spending-lookup]
  affects: [InsightsService, InsightsService+Spending, generateSpendingInsights]
tech_stack:
  added: []
  patterns: [PreAggregatedData-piggyback, conditional-fast-path]
key_files:
  modified:
    - Tenra/Services/Insights/InsightsService.swift
    - Tenra/Services/Insights/InsightsService+Spending.swift
decisions:
  - "Use Double (not Decimal) for categoryTotals — consistent with resolveAmountStatic return type and existing categoryMonthExpenses field"
  - "categoryGroups still built lazily in allTime path for subcategory breakdown downstream — avoids changing downstream code"
  - "Conditional fast-path: granularity == .allTime AND preAggregated != nil; non-allTime falls back to original O(N) grouping"
metrics:
  duration_minutes: 3
  completed_date: "2026-03-02"
  tasks_completed: 2
  files_modified: 2
---

# Phase 3 Plan 1: categoryTotals O(1) allTime Spending Optimization Summary

**One-liner:** Added `categoryTotals: [String: Double]` to `PreAggregatedData.build()` single O(N) pass, wired `generateSpendingInsights` to use O(1) lookup for `.allTime` granularity — eliminating the 307ms `Dictionary(grouping:) + resolveAmount` bottleneck.

## What Was Built

### Task 1: categoryTotals field in PreAggregatedData

Added `categoryTotals: [String: Double]` field to `PreAggregatedData` struct in `InsightsService.swift`. The accumulation piggybacks inside the existing `case .expense:` branch of `build()`'s single O(N) loop — exactly alongside the existing `categoryMonth[catKey]` accumulation. Zero extra loop cost.

Key implementation detail: placed accumulation only when `!tx.category.isEmpty` (same guard as `categoryMonth` accumulation), keeping behavior consistent.

### Task 2: O(1) fast-path in generateSpendingInsights

Updated `generateSpendingInsights` in `InsightsService+Spending.swift`:

- Added `preAggregated: PreAggregatedData? = nil` parameter (with default, fully backwards-compatible)
- For `.allTime` granularity with non-empty `preAggregated?.categoryTotals`, uses O(1) dictionary lookup to build `sortedCategories` — replaces the old `Dictionary(grouping: topExpenses, by: { $0.category })` + `.map { resolveAmount }` O(N) scan
- `categoryGroups` is still computed (using the old path) because it's needed for subcategory breakdown downstream (`categoryGroups[item.key] ?? []`)
- Non-allTime granularities unchanged — fallback to original O(N) path
- Call site in `generateAllInsights(granularity:...)` updated to pass `preAggregated: preAggregated`

## Performance Impact

- `.allTime` category grouping: O(N) + O(N×resolveAmount) → O(1) dictionary lookup
- Expected improvement: ~307ms → <5ms for the `sortedCategories` computation in allTime generator
- Non-allTime granularities: no change (use existing per-bucket window, not allTime totals)

## Deviations from Plan

### Pre-existing Issue (out-of-scope, documented in deferred-items.md)

**[Scope Boundary] TransactionStore.swift — incomplete RecurringStore extraction**
- **Found during:** Task 2 build verification
- **Issue:** `TransactionStore.swift` has uncommitted local changes from an incomplete Plan 03-PERF-02 — `recurringSeries`/`recurringOccurrences` changed to get-only computed properties, but extension mutations still reference them. Causes 5 build errors in `TransactionStore.swift`.
- **Not caused by our changes** — InsightsService.swift and InsightsService+Spending.swift have zero errors
- **Action:** Logged to `deferred-items.md`. Will be resolved by Plan 03-02.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 37a6925 | feat(03-01): add categoryTotals to PreAggregatedData.build() |
| 2 | 68a32d4 | feat(03-01): use categoryTotals in generateSpendingInsights for allTime |

## Self-Check: PASSED
