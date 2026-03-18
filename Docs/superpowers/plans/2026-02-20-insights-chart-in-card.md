# InsightsCardView — Embedded Chart Slot Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Embed the section-level `PeriodCashFlowChart` / `WealthChart` inside the first `InsightsCardView` of their respective sections instead of rendering them as standalone views above the cards.

**Architecture:** Add a generic `@ViewBuilder` bottom-chart slot to `InsightsCardView<BottomChart: View>`. Two inits — the existing one (backward-compatible, `BottomChart == EmptyView`) and a new one with an injected chart. When a chart is injected, the mini-chart overlay is hidden and the full-size chart appears at the bottom of the card. `CashFlowInsightsSection` and `WealthInsightsSection` each pass their chart to the first insight card and remove the standalone chart view.

**Tech Stack:** SwiftUI, Swift 6 / `@MainActor` patterns, iOS 26+

---

## Task 1: Make `InsightsCardView` generic with a bottom-chart `@ViewBuilder` slot

**Files:**
- Modify: `AIFinanceManager/Views/Insights/InsightsCardView.swift`

### Step 1: Read the file

Open and read `InsightsCardView.swift` in full before editing.

### Step 2: Replace the struct declaration + add inits

Replace the existing non-generic `struct InsightsCardView: View {` block (through the closing `}` of `body`) with the generic version below. The `trendBadge`, `miniChart`, `budgetProgressBar` private helpers and the `#Preview` blocks at the bottom are **unchanged**.

**New struct declaration + inits:**

```swift
struct InsightsCardView<BottomChart: View>: View {
    let insight: Insight

    private let hasBottomChart: Bool
    @ViewBuilder private let bottomChartContent: () -> BottomChart

    // MARK: - Init (backward compatible — no embedded chart)
    init(insight: Insight) where BottomChart == EmptyView {
        self.insight = insight
        self.hasBottomChart = false
        self.bottomChartContent = { EmptyView() }
    }

    // MARK: - Init (with embedded full-size chart)
    init(insight: Insight, @ViewBuilder bottomChart: @escaping () -> BottomChart) {
        self.insight = insight
        self.hasBottomChart = true
        self.bottomChartContent = bottomChart
    }
```

### Step 3: Replace the `body` property

Replace the existing `var body: some View { ... }` with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header: icon + title + conditional mini-chart overlay
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: insight.category.icon)
                    .font(.system(size: AppIconSize.md))
                    .foregroundStyle(insight.severity.color)

                Text(insight.title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()
                    // Mini chart rendered OUTSIDE clip region to avoid being clipped.
                    // Hidden when a full-size bottom chart is injected.
                    .overlay(alignment: .topTrailing) {
                        if !hasBottomChart {
                            miniChart
                                .frame(width: 120, height: 100)
                        }
                    }
            }

            Text(insight.subtitle)
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            HStack(spacing: AppSpacing.sm) {
                // Large metric
                Text(insight.metric.formattedValue)
                    .font(AppTypography.h2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.textPrimary)

                // Trend indicator
                if let trend = insight.trend {
                    trendBadge(trend)
                }
                if let unit = insight.metric.unit {
                    Text(unit)
                        .font(AppTypography.bodyLarge)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Full-size chart — shown only when injected via init(insight:bottomChart:)
            if hasBottomChart {
                bottomChartContent()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(radius: AppRadius.pill)
    }
```

### Step 4: Build to verify no compilation errors

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED` (all existing callsites use the `init(insight:) where BottomChart == EmptyView` overload — no changes required there).

### Step 5: Commit

```bash
git add AIFinanceManager/AIFinanceManager/Views/Insights/InsightsCardView.swift
git commit -m "feat(insights): add generic @ViewBuilder bottom-chart slot to InsightsCardView

Adds InsightsCardView<BottomChart: View> with two inits:
- init(insight:) — backward-compatible, BottomChart == EmptyView
- init(insight:bottomChart:) — embeds a full-size chart below the metric row

When a bottom chart is injected the mini-chart overlay is hidden.
Existing callsites compile without changes.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Update `CashFlowInsightsSection` — embed `PeriodCashFlowChart` in first card

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Sections/CashFlowInsightsSection.swift`

### Step 1: Read the file

Read `CashFlowInsightsSection.swift` in full.

### Step 2: Replace `body`

Replace the entire `var body: some View` with:

```swift
    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                if periodDataPoints.count >= 2, let firstInsight = insights.first {
                    // First card — PeriodCashFlowChart embedded inside InsightsCardView
                    NavigationLink(destination: InsightDetailView(insight: firstInsight, currency: currency)) {
                        InsightsCardView(insight: firstInsight) {
                            PeriodCashFlowChart(
                                dataPoints: periodDataPoints,
                                currency: currency,
                                granularity: granularity,
                                compact: false
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    // Remaining cards — standard (mini chart overlay preserved)
                    ForEach(insights.dropFirst()) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // No period data available — all cards rendered without bottom chart
                    ForEach(insights) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
```

> **Note:** The standalone `PeriodCashFlowChart` block and its `.screenPadding()` call are removed — the chart now lives inside the first `InsightsCardView`.

### Step 3: Build to verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

### Step 4: Commit

```bash
git add AIFinanceManager/AIFinanceManager/Views/Insights/Sections/CashFlowInsightsSection.swift
git commit -m "feat(insights): embed PeriodCashFlowChart inside first InsightsCardView in CashFlowInsightsSection

Removes standalone chart above cards. PeriodCashFlowChart is now rendered
as the bottom slot of the first insight card. Remaining cards retain
their existing mini-chart overlay.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Update `WealthInsightsSection` — embed `WealthChart` in first card

**Files:**
- Modify: `AIFinanceManager/Views/Insights/Sections/WealthInsightsSection.swift`

### Step 1: Read the file

Read `WealthInsightsSection.swift` in full.

### Step 2: Replace `body`

Replace the entire `var body: some View` with:

```swift
    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader

                if periodDataPoints.count >= 2, let firstInsight = insights.first {
                    // First card — WealthChart embedded inside InsightsCardView
                    NavigationLink(destination: InsightDetailView(insight: firstInsight, currency: currency)) {
                        InsightsCardView(insight: firstInsight) {
                            WealthChart(
                                dataPoints: periodDataPoints,
                                currency: currency,
                                granularity: granularity,
                                compact: false
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    // Remaining cards — standard
                    ForEach(insights.dropFirst()) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // No period data — all cards rendered without bottom chart
                    ForEach(insights) { insight in
                        NavigationLink(destination: InsightDetailView(insight: insight, currency: currency)) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
```

> **Note:** The standalone `WealthChart` block with its double `.padding(.horizontal, AppSpacing.lg).screenPadding()` is removed. The chart is now embedded inside the first `InsightsCardView`.

### Step 3: Final build

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`

### Step 4: Commit

```bash
git add AIFinanceManager/AIFinanceManager/Views/Insights/Sections/WealthInsightsSection.swift
git commit -m "feat(insights): embed WealthChart inside first InsightsCardView in WealthInsightsSection

Removes standalone WealthChart above cards. Chart is now the bottom slot
of the first insight card. Removes double-padding noise on the old
standalone chart (.padding(.horizontal) + .screenPadding()).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Verification Checklist

After all tasks:

- [ ] `BUILD SUCCEEDED` after each task
- [ ] All existing `InsightsCardView(insight: ...)` callsites compile unchanged (backward-compatible init)
- [ ] `CashFlowInsightsSection` no longer renders a standalone `PeriodCashFlowChart`
- [ ] `WealthInsightsSection` no longer renders a standalone `WealthChart`
- [ ] First insight card in each section shows the chart at the bottom of the card
- [ ] Remaining insight cards retain their mini-chart overlays
- [ ] When `periodDataPoints.count < 2`, sections fall back to standard cards (no bottom chart)
