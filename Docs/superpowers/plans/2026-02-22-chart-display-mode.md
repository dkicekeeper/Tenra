# Chart Display Mode Unification — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `compact: Bool` with a `ChartDisplayMode` enum across all 7 Insights chart components for consistent, self-documenting API.

**Architecture:** New `ChartDisplayMode` enum in `Utils/`, mechanical rename of `compact: Bool → mode: ChartDisplayMode` in each chart struct, then search-replace of all call sites. Each struct gets a private `isCompact` computed property so the `body` diff is minimal.

**Tech Stack:** SwiftUI, Charts framework, iOS 26+

**Design doc:** `docs/plans/2026-02-22-chart-display-mode-design.md`

---

## Task 1: Create `ChartDisplayMode` enum

**Files:**
- Create: `AIFinanceManager/Utils/ChartDisplayMode.swift`

**Step 1: Create the file**

```swift
//
//  ChartDisplayMode.swift
//  AIFinanceManager
//
//  Phase 25: Replaces `compact: Bool` across all Insights chart components.
//

/// Controls the visual fidelity of Insights chart components.
///
/// - `.compact`: 60pt sparkline — hidden axes/labels/legend. Used in `InsightsCardView`.
/// - `.full`: Full-height chart with axes, gridlines, and legend. Used in detail/section views.
enum ChartDisplayMode {
    case compact
    case full

    /// Whether axes and gridlines should be rendered.
    var showAxes: Bool   { self == .full }
    /// Whether a legend should be rendered (where applicable).
    var showLegend: Bool { self == .full }
}
```

**Step 2: Verify the project still builds**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add AIFinanceManager/AIFinanceManager.xcodeproj/project.pbxproj \
        AIFinanceManager/Utils/ChartDisplayMode.swift
git commit -m "feat(charts): add ChartDisplayMode enum — Phase 25"
```

> ⚠️ If `ChartDisplayMode.swift` doesn't appear in the Xcode project automatically (since we're
> using CLI), you may need to add it to the Xcode target. If the build fails with "Cannot find type
> 'ChartDisplayMode'", add the file to the target in Xcode or via `project.pbxproj` manually.
> Alternative: temporarily put the enum in `Utils/AppTheme.swift` to unblock — move later.

---

## Task 2: Migrate `CashFlowChart.swift` (3 structs)

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Components/CashFlowChart.swift`

**Step 1: Update `CashFlowChart` struct**

Find (line ~22):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Then rename every remaining `compact` reference inside `CashFlowChart.body` to `isCompact`.

**Step 2: Update `PeriodCashFlowChart` struct**

Find (line ~129):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Then rename every `compact` reference inside `PeriodCashFlowChart.body` to `isCompact`.

**Step 3: Update `WealthChart` struct**

Find (line ~242):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Then rename every `compact` reference inside `WealthChart.body` to `isCompact`.

**Step 4: Build**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

Expected: `** BUILD FAILED **` — call sites still pass `compact:` label. That's expected; fix in Task 6.
Actually: since `compact` was a `var` with a default, removing it will only break explicit call sites.
The build may succeed if no file currently passes `compact:` to these three structs. Check actual error output.

> If the build fails only because of call site label mismatches, proceed directly to Task 6.
> If the build fails because `isCompact` is inaccessible from `#Preview`, change `private` to `fileprivate` in preview blocks.

**Step 5: Commit**

```bash
git add AIFinanceManager/Views/Insights/Components/CashFlowChart.swift
git commit -m "refactor(charts): migrate CashFlowChart/PeriodCashFlowChart/WealthChart to ChartDisplayMode"
```

---

## Task 3: Migrate `IncomeExpenseChart.swift` (2 structs)

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Components/IncomeExpenseChart.swift`

**Step 1: Update `IncomeExpenseChart` struct**

Find (line ~22):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Rename every `compact` reference in body to `isCompact`.

**Step 2: Update `PeriodIncomeExpenseChart` struct**

Find (line ~153):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Rename every `compact` reference in body to `isCompact`.

**Step 3: Build (expect call site errors for these two structs)**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

**Step 4: Commit**

```bash
git add AIFinanceManager/Views/Insights/Components/IncomeExpenseChart.swift
git commit -m "refactor(charts): migrate IncomeExpenseChart/PeriodIncomeExpenseChart to ChartDisplayMode"
```

---

## Task 4: Migrate `SpendingTrendChart.swift`

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Components/SpendingTrendChart.swift`

**Step 1: Update `SpendingTrendChart` struct**

Find (line ~16):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Rename every `compact` reference in body to `isCompact`.

**Step 2: Build**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Insights/Components/SpendingTrendChart.swift
git commit -m "refactor(charts): migrate SpendingTrendChart to ChartDisplayMode"
```

---

## Task 5: Migrate `CategoryBreakdownChart.swift`

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Components/CategoryBreakdownChart.swift`

**Step 1: Update `CategoryBreakdownChart` struct**

Find (line ~14):
```swift
var compact: Bool = false
```
Replace with:
```swift
var mode: ChartDisplayMode = .full
private var isCompact: Bool { mode == .compact }
```
Rename every `compact` reference in body to `isCompact`.

**Step 2: Build**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Insights/Components/CategoryBreakdownChart.swift
git commit -m "refactor(charts): migrate CategoryBreakdownChart to ChartDisplayMode"
```

---

## Task 6: Fix all call sites

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsCardView.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightsView.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift`
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift`
- Modify: `AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift`

**Step 1: InsightsCardView.swift — 4 call sites (compact: true → mode: .compact)**

Find and replace each:
```swift
// Before:
CategoryBreakdownChart(items: items, compact: true)
CashFlowChart(dataPoints: points, currency: insight.metric.currency ?? "KZT", compact: true)
SpendingTrendChart(..., compact: true)
PeriodCashFlowChart(..., compact: true)

// After:
CategoryBreakdownChart(items: items, mode: .compact)
CashFlowChart(dataPoints: points, currency: insight.metric.currency ?? "KZT", mode: .compact)
SpendingTrendChart(..., mode: .compact)
PeriodCashFlowChart(..., mode: .compact)
```

**Step 2: InsightsSummaryHeader.swift — 1 call site (compact: true → mode: .compact)**

```swift
// Before:
PeriodIncomeExpenseChart(
    dataPoints: periodDataPoints,
    currency: currency,
    granularity: periodDataPoints.first?.granularity ?? .month,
    compact: true
)

// After:
PeriodIncomeExpenseChart(
    dataPoints: periodDataPoints,
    currency: currency,
    granularity: periodDataPoints.first?.granularity ?? .month,
    mode: .compact
)
```

**Step 3: InsightsView.swift — 2 call sites (compact: false → mode: .full)**

```swift
// Before:
PeriodCashFlowChart(..., compact: false)
WealthChart(..., compact: false)

// After:
PeriodCashFlowChart(..., mode: .full)
WealthChart(..., mode: .full)
```

**Step 4: InsightDetailView.swift — 4 call sites (add explicit mode: .full)**

```swift
// Before (omitted — defaults to false):
CategoryBreakdownChart(items: items)
CashFlowChart(dataPoints: points, currency: currency)
PeriodCashFlowChart(dataPoints: points, currency: currency, granularity: ...)
SpendingTrendChart(dataPoints: points.map { ... }, currency: currency)

// After (explicit):
CategoryBreakdownChart(items: items, mode: .full)
CashFlowChart(dataPoints: points, currency: currency, mode: .full)
PeriodCashFlowChart(dataPoints: points, currency: currency, granularity: ..., mode: .full)
SpendingTrendChart(dataPoints: points.map { ... }, currency: currency, mode: .full)
```

**Step 5: InsightsSummaryDetailView.swift — 1 call site (compact: false → mode: .full)**

```swift
// Before:
PeriodIncomeExpenseChart(dataPoints: periodDataPoints, currency: currency, granularity: granularity, compact: false)

// After:
PeriodIncomeExpenseChart(dataPoints: periodDataPoints, currency: currency, granularity: granularity, mode: .full)
```

**Step 6: CategoryDeepDiveView.swift — 1 preview site (add mode: .full)**

Find `SpendingTrendChart(dataPoints: monthlyTrend, currency: "KZT")` in preview:
```swift
// After:
SpendingTrendChart(dataPoints: monthlyTrend, currency: "KZT", mode: .full)
```

**Step 7: Build — expect SUCCESS**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:)"
```

Expected: `** BUILD SUCCEEDED **`

If there are remaining `compact:` label errors, grep for them:
```bash
grep -rn "compact:" AIFinanceManager/Views/Insights/ --include="*.swift"
```
Expected: no output (all replaced).

**Step 8: Commit**

```bash
git add \
  AIFinanceManager/Views/Insights/Components/InsightsCardView.swift \
  AIFinanceManager/Views/Insights/InsightsView.swift \
  AIFinanceManager/Views/Insights/InsightDetailView.swift \
  AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift \
  AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift \
  AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift
git commit -m "refactor(charts): update all call sites to ChartDisplayMode — Phase 25 complete"
```

---

## Task 7: Final verification

**Step 1: Clean build**

```bash
xcodebuild clean build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "(BUILD|error:|warning: )" | head -20
```

Expected: `** BUILD SUCCEEDED **`, zero errors, minimal warnings (pre-existing only).

**Step 2: Confirm no old `compact:` label survives in Insights views**

```bash
grep -rn "compact:" \
  AIFinanceManager/Views/Insights/ \
  AIFinanceManager/Utils/ \
  --include="*.swift"
```

Expected: **no output**.

**Step 3: Confirm every chart call site has explicit `mode:`**

```bash
grep -rn "ChartDisplayMode\|mode: \.\(compact\|full\)" \
  AIFinanceManager/Views/Insights/ \
  --include="*.swift"
```

Expected: matches in InsightsCardView (`.compact`), InsightDetailView (`.full`), InsightsView (`.full`), InsightsSummaryDetailView (`.full`), InsightsSummaryHeader (`.compact`), CategoryDeepDiveView (`.full`).

**Step 4: Update CLAUDE.md**

Add to Recent Refactoring Phases section:

```
**Phase 25** (2026-02-22): ChartDisplayMode — Consistent Chart API
- Replaced `compact: Bool` with `ChartDisplayMode` enum across all 7 chart components
- New `Utils/ChartDisplayMode.swift` with `.compact` / `.full` cases
- Each struct uses private `isCompact` computed property — minimal body diff
- All call sites updated: InsightsCardView (.compact), detail/section views (.full)
- Design doc: `docs/plans/2026-02-22-chart-display-mode-design.md`
```
