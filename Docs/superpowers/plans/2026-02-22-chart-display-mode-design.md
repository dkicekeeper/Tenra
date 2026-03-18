# Chart Display Mode Unification — Design Document

**Date:** 2026-02-22
**Phase:** 25 (Chart API Consistency)

---

## Problem

All 7 chart components in `Views/Insights/Components/` share a `compact: Bool = false` parameter to
switch between a 60pt sparkline (for `InsightsCardView`) and a full-size chart (for detail/section
views). The parameter exists in every chart, but:

- `compact: Bool` is a boolean code smell — callers pass magic `true`/`false` with no semantic meaning
- `InsightDetailView.swift` omits the parameter entirely (relies on default `false`) — no explicit intent
- `CategoryDeepDiveView.swift` preview omits the parameter — same issue
- `InsightsSummaryHeader` previously had `compact: false` even though it renders a mini chart
  (fixed during Phase 24, but only incidentally)
- No shared documentation of what "compact" means visually for any given chart

---

## Solution

Replace `compact: Bool` with a new `ChartDisplayMode` enum across all 7 chart components.

### New type: `ChartDisplayMode`

```swift
/// Controls the visual fidelity of Insights chart components.
/// .compact — 60pt sparkline, no axes, no legend. Used in InsightsCardView.
/// .full    — full-height chart with axes, gridlines, and legend. Used in detail/section views.
enum ChartDisplayMode {
    case compact
    case full

    /// Whether axes and gridlines should be rendered.
    var showAxes: Bool     { self == .full }
    /// Whether legends should be rendered.
    var showLegend: Bool   { self == .full }
}
```

Chart-specific dimensions remain inside each chart (each full chart has its own height: 200, 220, or
240pt), so `ChartDisplayMode` does **not** expose `chartHeight` — that stays per-struct.

### Per-struct migration pattern

Each chart struct gets:

```swift
// replace:
var compact: Bool = false

// with:
var mode: ChartDisplayMode = .full

// add private helper to keep body diff minimal:
private var isCompact: Bool { mode == .compact }
```

Then every `compact` reference in `body` is renamed to `isCompact` with no semantic change.

---

## Affected Files

### New file
| File | Purpose |
|------|---------|
| `Utils/ChartDisplayMode.swift` | New enum + helper properties |

### Modified chart files
| File | Structs inside |
|------|---------------|
| `Views/Insights/Components/CashFlowChart.swift` | `CashFlowChart`, `PeriodCashFlowChart`, `WealthChart` |
| `Views/Insights/Components/IncomeExpenseChart.swift` | `IncomeExpenseChart`, `PeriodIncomeExpenseChart` |
| `Views/Insights/Components/SpendingTrendChart.swift` | `SpendingTrendChart` |
| `Views/Insights/Components/CategoryBreakdownChart.swift` | `CategoryBreakdownChart` |

### Call site audit
| File | Current | After |
|------|---------|-------|
| `InsightsCardView.swift` (4 sites) | `compact: true` | `mode: .compact` |
| `InsightsView.swift` (2 sites) | `compact: false` | `mode: .full` |
| `InsightDetailView.swift` (4 sites) | omitted (default false) | `mode: .full` (explicit) |
| `InsightsSummaryDetailView.swift` (1 site) | `compact: false` | `mode: .full` |
| `InsightsSummaryHeader.swift` (1 site) | `compact: true` (Phase 24) | `mode: .compact` |
| `CategoryDeepDiveView.swift` (1 preview site) | omitted (default false) | `mode: .full` |

---

## Standard: What Each Mode Means

| Property | `.compact` | `.full` |
|----------|-----------|--------|
| Height | 60pt | 200–240pt (per chart) |
| X-axis labels | hidden | visible |
| Y-axis labels | hidden | visible |
| Gridlines | hidden | visible |
| Legend | hidden | visible (where applicable) |
| Interaction | none | touch/hover selection |
| Context | InsightsCardView mini-chart | Detail views, section inlines |

---

## Non-Goals

- No visual design changes — only API renaming
- No performance changes
- `scrollable: Bool` parameter is **not** affected (some charts have it, keep as-is)
- No new chart modes (`.summary`, `.thumbnail`) — YAGNI

---

## Build Verification

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

Expected: `** BUILD SUCCEEDED **`
