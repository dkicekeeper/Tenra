# Insights Detail Enrichment & Granularity Correctness

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the headline granularity bug in the totals card (currently sums all-time for `.month/.quarter/.year`) and replace the empty/thin detail screens for 6 MISSING insights with formula-breakdown cards in the design language of `HealthComponentCard`.

**Architecture:**
- Add `currentBucketRange` / `previousBucketRange` / `currentBucketLabel` to `InsightGranularity` so the totals card renders ONLY the current bucket (current month / current quarter / current year / last 7 days for `.week` / all-time).
- Compute current+previous bucket totals in `InsightsViewModel` once per granularity, propagate through `InsightsTotalsCard` (period label + MoM delta) and `InsightsSummaryDetailView`.
- Extend `InsightDetailData` with `case formulaBreakdown(InsightFormulaModel)`. New `InsightFormulaCard` view mirrors `HealthComponentCard` (icon header, big value + label, formula rows, recommendation). Wire it for `savingsRate`, `emergencyFund`, `spendingForecast`, `balanceRunway`, `projectedBalance`, `yearOverYear` — these all currently have `detailData: nil`.

**Tech Stack:** SwiftUI, `@Observable` MainActor, `String(localized:)` for i18n (en + ru `.lproj/Localizable.strings`).

**Out of scope (separate follow-up plans):**
- THIN screens (`monthOverMonthChange`, `averageDailySpending`, `incomeGrowth`, `incomeVsExpenseRatio`, `bestMonth`, `worstMonth`, `wealthGrowth`).
- List-based MISSING screens (`spendingSpike`, `categoryTrend`, `subscriptionGrowth`, `duplicateSubscriptions`).
- Granularity propagation into `sharedInsightIDs` (still hardcoded to last-3-months / 30-day windows).

---

## File Structure

**Create:**
- `Tenra/Models/InsightFormulaModel.swift` — value-type display model for formula breakdown cards.
- `Tenra/Views/Components/Cards/InsightFormulaCard.swift` — reusable detail card mimicking `HealthComponentCard`.
- `TenraTests/Models/InsightGranularityBucketTests.swift` — tests for new granularity helpers.

**Modify:**
- `Tenra/Models/InsightGranularity.swift` — add `currentBucketRange`, `previousBucketRange`, `currentBucketLabel`.
- `Tenra/Models/InsightModels.swift` — extend `InsightDetailData` with `.formulaBreakdown`.
- `Tenra/ViewModels/InsightsViewModel.swift` — add `currentBucketTotals`, `previousBucketTotals`, populate them.
- `Tenra/Views/Components/Cards/InsightsTotalsCard.swift` — add period label + previous-period delta row.
- `Tenra/Views/Insights/InsightsView.swift` — pass new totals into `InsightsTotalsCard` and `InsightsSummaryDetailView`.
- `Tenra/Views/Insights/InsightsSummaryDetailView.swift` — clarify period context.
- `Tenra/Views/Insights/InsightDetailView.swift` — render `.formulaBreakdown` case.
- `Tenra/Services/Insights/InsightsService+Savings.swift` — populate `detailData` for `savingsRate`, `emergencyFund`.
- `Tenra/Services/Insights/InsightsService+Forecasting.swift` — populate `detailData` for `spendingForecast`, `balanceRunway`, `yearOverYear`.
- `Tenra/Services/Insights/InsightsService+CashFlow.swift` — populate `detailData` for `projectedBalance`.
- `Tenra/en.lproj/Localizable.strings` — add new keys.
- `Tenra/ru.lproj/Localizable.strings` — add new keys.

---

## Task 1: Granularity bucket helpers + tests

**Files:**
- Modify: `Tenra/Models/InsightGranularity.swift` (append after existing `dateRange` block, around line 116)
- Test: `TenraTests/Models/InsightGranularityBucketTests.swift` (create)

- [ ] **Step 1.1: Write failing tests for bucket helpers**

Create `TenraTests/Models/InsightGranularityBucketTests.swift`:

```swift
import Testing
import Foundation
@testable import Tenra

@Suite("InsightGranularity — current/previous bucket")
struct InsightGranularityBucketTests {

    private let calendar = Calendar.current
    private let now = Date()

    @Test("month — current bucket is start-of-month → start-of-next-month")
    func monthBucket() {
        let (start, end) = InsightGranularity.month.currentBucketRange()
        let comps = calendar.dateComponents([.year, .month, .day], from: start)
        #expect(comps.day == 1)
        let nowComps = calendar.dateComponents([.year, .month], from: now)
        #expect(comps.year == nowComps.year)
        #expect(comps.month == nowComps.month)

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)!
        #expect(end == nextMonth)
    }

    @Test("month — previous bucket is one month earlier")
    func monthPrevBucket() {
        let (curStart, _) = InsightGranularity.month.currentBucketRange()
        let (prevStart, prevEnd) = InsightGranularity.month.previousBucketRange()
        let expected = calendar.date(byAdding: .month, value: -1, to: curStart)!
        #expect(prevStart == expected)
        #expect(prevEnd == curStart)
    }

    @Test("quarter — current bucket starts on quarter month boundary")
    func quarterBucket() {
        let (start, end) = InsightGranularity.quarter.currentBucketRange()
        let m = calendar.component(.month, from: start)
        #expect([1, 4, 7, 10].contains(m))
        #expect(calendar.component(.day, from: start) == 1)
        #expect(end == calendar.date(byAdding: .month, value: 3, to: start)!)
    }

    @Test("year — current bucket starts on Jan 1")
    func yearBucket() {
        let (start, end) = InsightGranularity.year.currentBucketRange()
        #expect(calendar.component(.month, from: start) == 1)
        #expect(calendar.component(.day, from: start) == 1)
        #expect(end == calendar.date(byAdding: .year, value: 1, to: start)!)
    }

    @Test("week — current bucket is last 7 days")
    func weekBucket() {
        let (start, end) = InsightGranularity.week.currentBucketRange()
        let endOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        #expect(end == endOfDay)
        let expectedStart = calendar.date(byAdding: .day, value: -7, to: endOfDay)!
        #expect(start == expectedStart)
    }

    @Test("allTime — current bucket equals the full data window")
    func allTimeBucket() {
        let (cs, ce) = InsightGranularity.allTime.currentBucketRange()
        let (ds, de) = InsightGranularity.allTime.dateRange(firstTransactionDate: nil)
        #expect(cs == ds)
        #expect(ce == de)
    }

    @Test("currentBucketLabel — month renders 'MMMM yyyy'")
    func monthLabel() {
        let label = InsightGranularity.month.currentBucketLabel(locale: Locale(identifier: "en_US"))
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "MMMM yyyy"
        #expect(label == df.string(from: now))
    }

    @Test("currentBucketLabel — week renders 'Last 7 days' string")
    func weekLabel() {
        let label = InsightGranularity.week.currentBucketLabel(locale: Locale(identifier: "en_US"))
        #expect(!label.isEmpty)
    }
}
```

- [ ] **Step 1.2: Run tests — confirm they fail with "currentBucketRange not found"**

Run:
```
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightGranularityBucketTests 2>&1 | grep -E "error:|FAIL" | head
```

Expected: compile error referencing `currentBucketRange`.

- [ ] **Step 1.3: Implement bucket helpers in `InsightGranularity.swift`**

Append BEFORE the closing `}` of `enum InsightGranularity` (after `previousPeriodKey`, around line 337):

```swift
    // MARK: - Current Bucket Range
    //
    // `dateRange()` returns the FULL data window (used for charts: e.g. `.month`
    // = all months from first transaction). `currentBucketRange()` returns ONLY
    // the current period (this month / this quarter / this year / last 7 days /
    // all-time), used for the totals card and any "current period" metric.

    /// Range covering the current bucket only:
    /// - `.week`     → last 7 days (rolling)
    /// - `.month`    → current calendar month
    /// - `.quarter`  → current calendar quarter
    /// - `.year`     → current calendar year
    /// - `.allTime`  → full data window (same as `dateRange`)
    nonisolated func currentBucketRange(now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)

        switch self {
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: endOfDay)!
            return (start, endOfDay)

        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)

        case .quarter:
            let m = calendar.component(.month, from: now)
            let qMonth = ((m - 1) / 3) * 3 + 1
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = qMonth
            comps.day = 1
            let start = calendar.date(from: comps)!
            let end = calendar.date(byAdding: .month, value: 3, to: start)!
            return (start, end)

        case .year:
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = 1
            comps.day = 1
            let start = calendar.date(from: comps)!
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)

        case .allTime:
            return dateRange(firstTransactionDate: nil)
        }
    }

    /// Range covering the previous bucket — the period right before
    /// `currentBucketRange`. Used for MoM/QoQ/YoY-style comparisons in the
    /// totals card. For `.allTime` this returns a zero-length range
    /// (no comparison possible).
    nonisolated func previousBucketRange(now: Date = Date()) -> (start: Date, end: Date) {
        let (curStart, _) = currentBucketRange(now: now)
        let calendar = Calendar.current

        switch self {
        case .week:
            let prevStart = calendar.date(byAdding: .day, value: -7, to: curStart)!
            return (prevStart, curStart)
        case .month:
            let prevStart = calendar.date(byAdding: .month, value: -1, to: curStart)!
            return (prevStart, curStart)
        case .quarter:
            let prevStart = calendar.date(byAdding: .month, value: -3, to: curStart)!
            return (prevStart, curStart)
        case .year:
            let prevStart = calendar.date(byAdding: .year, value: -1, to: curStart)!
            return (prevStart, curStart)
        case .allTime:
            return (curStart, curStart)
        }
    }

    /// Human-readable label for the current bucket
    /// ("May 2026", "Q2 2026", "2026", localised "Last 7 days", "All time").
    nonisolated func currentBucketLabel(locale: Locale = .current, now: Date = Date()) -> String {
        let calendar = Calendar.current
        switch self {
        case .week:
            return String(localized: "insights.bucket.week.label")
        case .month:
            let df = DateFormatter()
            df.locale = locale
            df.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMMyyyy", options: 0, locale: locale)
            return df.string(from: now)
        case .quarter:
            let m = calendar.component(.month, from: now)
            let q = (m - 1) / 3 + 1
            let y = calendar.component(.year, from: now)
            return "Q\(q) \(y)"
        case .year:
            return "\(calendar.component(.year, from: now))"
        case .allTime:
            return String(localized: "insights.granularity.allTime")
        }
    }
```

- [ ] **Step 1.4: Add localization keys for bucket label**

Append to `Tenra/en.lproj/Localizable.strings` (in the existing insights section, around line 800):

```
"insights.bucket.week.label" = "Last 7 days";
```

Append to `Tenra/ru.lproj/Localizable.strings` (matching section):

```
"insights.bucket.week.label" = "Последние 7 дней";
```

- [ ] **Step 1.5: Run tests — confirm they pass**

Run:
```
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightGranularityBucketTests 2>&1 | grep -E "error:|Test Case .* (passed|failed)" | head -20
```

Expected: all 7 tests pass.

- [ ] **Step 1.6: Commit**

```
git add Tenra/Models/InsightGranularity.swift TenraTests/Models/InsightGranularityBucketTests.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "$(cat <<'EOF'
feat(insights): add currentBucketRange/previousBucketRange/currentBucketLabel to InsightGranularity

Foundation for fixing the totals card "all-time" bug — currently for `.month/.quarter/.year`
the dateRange() returns full history, not just the current period. New helpers expose the
*current bucket* (e.g. May 2026) separately from the data window used for charts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Compute current/previous bucket totals in InsightsViewModel

**Files:**
- Modify: `Tenra/ViewModels/InsightsViewModel.swift`

- [ ] **Step 2.1: Add new observable properties**

Find the existing `totalIncome / totalExpenses / netFlow` block in `InsightsViewModel` (search for `var totalIncome:`). Right after them, add:

```swift
    // Current bucket totals (the actual current period — e.g. this month).
    // Distinct from totalIncome/totalExpenses/netFlow which are cumulative across
    // the data window used by charts.
    var currentBucketIncome: Double = 0
    var currentBucketExpenses: Double = 0
    var currentBucketNetFlow: Double = 0

    // Previous bucket totals — same period, one bucket earlier — for MoM delta.
    var previousBucketIncome: Double = 0
    var previousBucketExpenses: Double = 0
    var previousBucketNetFlow: Double = 0

    /// Localised label for the current bucket ("May 2026", "Q2 2026", "Last 7 days").
    var currentBucketLabel: String = ""
```

- [ ] **Step 2.2: Extend `PeriodTotals` and totals computation in background load**

Find `struct PeriodTotals` (defined inside `InsightsViewModel.swift`, search for `struct PeriodTotals`). Replace its definition with:

```swift
    private struct PeriodTotals: Sendable {
        let income: Double
        let expenses: Double
        let netFlow: Double
        // Bucket-only slice (current + previous bucket).
        let currentBucketIncome: Double
        let currentBucketExpenses: Double
        let currentBucketNetFlow: Double
        let previousBucketIncome: Double
        let previousBucketExpenses: Double
        let previousBucketNetFlow: Double
    }
```

In `loadInsightsBackground()` (around lines 319–328 and again around 366–374), the two places where `newTotals[gran] = PeriodTotals(...)` is built — replace each block with:

```swift
            for gran in [priorityGranularity] {
                guard let result = phase1Result.results[gran] else { continue }
                let pts = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in pts { income += p.income; expenses += p.expenses }
                let (curStart, curEnd) = gran.currentBucketRange()
                let (prevStart, prevEnd) = gran.previousBucketRange()
                let curTotals = Self.bucketTotals(in: pts, start: curStart, end: curEnd)
                let prevTotals = Self.bucketTotals(in: pts, start: prevStart, end: prevEnd)
                newInsights[gran] = result.insights
                newPoints[gran]   = pts
                newTotals[gran]   = PeriodTotals(
                    income: income, expenses: expenses, netFlow: income - expenses,
                    currentBucketIncome: curTotals.income,
                    currentBucketExpenses: curTotals.expenses,
                    currentBucketNetFlow: curTotals.income - curTotals.expenses,
                    previousBucketIncome: prevTotals.income,
                    previousBucketExpenses: prevTotals.expenses,
                    previousBucketNetFlow: prevTotals.income - prevTotals.expenses
                )
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(pts.count) pts")
            }
```

Apply the SAME refactor to the second block (the loop over `phase2Result.results`):

```swift
            for (gran, result) in phase2Result.results {
                let pts = result.periodPoints
                var income: Double = 0; var expenses: Double = 0
                for p in pts { income += p.income; expenses += p.expenses }
                let (curStart, curEnd) = gran.currentBucketRange()
                let (prevStart, prevEnd) = gran.previousBucketRange()
                let curTotals = Self.bucketTotals(in: pts, start: curStart, end: curEnd)
                let prevTotals = Self.bucketTotals(in: pts, start: prevStart, end: prevEnd)
                newInsights[gran] = result.insights
                newPoints[gran]   = pts
                newTotals[gran]   = PeriodTotals(
                    income: income, expenses: expenses, netFlow: income - expenses,
                    currentBucketIncome: curTotals.income,
                    currentBucketExpenses: curTotals.expenses,
                    currentBucketNetFlow: curTotals.income - curTotals.expenses,
                    previousBucketIncome: prevTotals.income,
                    previousBucketExpenses: prevTotals.expenses,
                    previousBucketNetFlow: prevTotals.income - prevTotals.expenses
                )
                Self.logger.debug("🔧 [InsightsVM] Gran .\(gran.rawValue, privacy: .public) — \(result.insights.count) insights, \(pts.count) pts")
            }
```

- [ ] **Step 2.3: Add `bucketTotals` static helper**

Add this private static helper to the `InsightsViewModel` class body (just before the closing `}` of the class):

```swift
    /// Sums income/expenses for points whose `[periodStart, periodEnd)` overlaps
    /// the requested range. For `.month/.quarter/.year` granularities, periodPoints
    /// are bucket-aligned, so a contained point fully attributes to that bucket.
    private static func bucketTotals(
        in points: [PeriodDataPoint],
        start: Date,
        end: Date
    ) -> (income: Double, expenses: Double) {
        var inc: Double = 0
        var exp: Double = 0
        for p in points where p.periodStart >= start && p.periodStart < end {
            inc += p.income
            exp += p.expenses
        }
        return (inc, exp)
    }
```

- [ ] **Step 2.4: Update `applyPrecomputed` to project bucket totals + label**

Find `private func applyPrecomputed(for granularity: InsightGranularity)`. Replace its body with:

```swift
    private func applyPrecomputed(for granularity: InsightGranularity) {
        withTransaction(SwiftUI.Transaction(animation: nil)) {
            insights         = precomputedInsights[granularity] ?? []
            periodDataPoints = precomputedPeriodPoints[granularity] ?? []
            let totals       = precomputedTotals[granularity]
            totalIncome      = totals?.income   ?? 0
            totalExpenses    = totals?.expenses ?? 0
            netFlow          = totals?.netFlow  ?? 0
            currentBucketIncome   = totals?.currentBucketIncome   ?? 0
            currentBucketExpenses = totals?.currentBucketExpenses ?? 0
            currentBucketNetFlow  = totals?.currentBucketNetFlow  ?? 0
            previousBucketIncome   = totals?.previousBucketIncome   ?? 0
            previousBucketExpenses = totals?.previousBucketExpenses ?? 0
            previousBucketNetFlow  = totals?.previousBucketNetFlow  ?? 0
            currentBucketLabel = granularity.currentBucketLabel()
            isLoading        = false
        }
    }
```

- [ ] **Step 2.5: Build & verify**

Run:
```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: clean build (no errors).

- [ ] **Step 2.6: Commit**

```
git add Tenra/ViewModels/InsightsViewModel.swift
git commit -m "$(cat <<'EOF'
feat(insights): compute current/previous bucket totals per granularity

Adds currentBucket{Income,Expenses,NetFlow} and previousBucket{...} alongside
existing all-time totals. Same precomputation path — no extra cost. Wires
currentBucketLabel for the totals card. Headline-bug fix lands in next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Period label + MoM delta in InsightsTotalsCard

**Files:**
- Modify: `Tenra/Views/Components/Cards/InsightsTotalsCard.swift`

- [ ] **Step 3.1: Replace InsightsTotalsCard with bucket-aware version**

Replace the entire `struct InsightsTotalsCard: View { ... }` body with:

```swift
struct InsightsTotalsCard: View {
    let income: Double
    let expenses: Double
    let netFlow: Double
    let currency: String
    /// Localised label for the period being shown ("May 2026", "Q2 2026", "Last 7 days", "All time").
    /// When `nil` the period row is hidden.
    var periodLabel: String? = nil
    /// Optional previous-bucket totals for delta indicators. Pass `nil` to hide deltas.
    var previousIncome: Double? = nil
    var previousExpenses: Double? = nil
    var previousNetFlow: Double? = nil
    /// Font for the amount values (default .body matches both callers).
    var amountFont: Font = AppTypography.body

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let label = periodLabel {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .textCase(.uppercase)
            }

            HStack(alignment: .top, spacing: AppSpacing.xs) {
                totalItem(
                    title: String(localized: "insights.income"),
                    amount: income,
                    previous: previousIncome,
                    color: AppColors.success,
                    upIsGood: true
                )
                Spacer()
                totalItem(
                    title: String(localized: "insights.expenses"),
                    amount: expenses,
                    previous: previousExpenses,
                    color: AppColors.destructive,
                    upIsGood: false
                )
                Spacer()
                totalItem(
                    title: String(localized: "insights.netFlow"),
                    amount: netFlow,
                    previous: previousNetFlow,
                    color: netFlow >= 0 ? AppColors.textPrimary : AppColors.destructive,
                    upIsGood: true
                )
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func totalItem(
        title: String,
        amount: Double,
        previous: Double?,
        color: Color,
        upIsGood: Bool
    ) -> some View {
        VStack(alignment: .center, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)

            if abs(amount) >= 1_000_000 {
                let symbol = Formatting.currencySymbol(for: currency)
                Text(Self.compactAmount(amount) + " " + symbol)
                    .font(amountFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .animation(AppAnimation.gentleSpring, value: amount)
            } else {
                FormattedAmountText(
                    amount: amount,
                    currency: currency,
                    fontSize: amountFont,
                    fontWeight: .semibold,
                    color: color
                )
            }

            if let prev = previous, let badge = Self.deltaBadge(current: amount, previous: prev, upIsGood: upIsGood) {
                badge
            }
        }
    }

    /// Builds a tiny delta badge ("+12%" / "−4%") coloured by direction.
    /// Returns nil when previous is zero (delta undefined) or values are equal.
    @ViewBuilder
    private static func deltaBadge(current: Double, previous: Double, upIsGood: Bool) -> some View {
        if abs(previous) > 0.01 {
            let delta = ((current - previous) / abs(previous)) * 100
            if abs(delta) >= 0.5 {
                let isUp = delta > 0
                let color: Color = (isUp == upIsGood) ? AppColors.success : AppColors.destructive
                HStack(spacing: 2) {
                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.0f%%", abs(delta)))
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(color)
            }
        }
    }

    /// Compact formatting for millions: 1M, 2.34M, -12.5M
    private static func compactAmount(_ value: Double) -> String {
        let absValue = abs(value)
        let millions = absValue / 1_000_000
        let sign = value < 0 ? "-" : ""

        if millions == millions.rounded(.down) {
            return "\(sign)\(Int(millions))M"
        } else {
            let formatted = String(format: "%.2f", millions)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
            return "\(sign)\(formatted)M"
        }
    }
}
```

- [ ] **Step 3.2: Update existing previews to exercise new params**

Replace the three existing `#Preview` blocks at the bottom of the file with:

```swift
#Preview("Positive — with deltas") {
    InsightsTotalsCard(
        income: 530_000, expenses: 320_000, netFlow: 210_000,
        currency: "KZT",
        periodLabel: "May 2026",
        previousIncome: 480_000, previousExpenses: 350_000, previousNetFlow: 130_000
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("All-time — no deltas") {
    InsightsTotalsCard(
        income: 12_400_000, expenses: 8_900_000, netFlow: 3_500_000,
        currency: "KZT",
        periodLabel: "All time"
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Negative net flow") {
    InsightsTotalsCard(
        income: 280_000, expenses: 340_000, netFlow: -60_000,
        currency: "KZT",
        periodLabel: "Q2 2026",
        previousIncome: 290_000, previousExpenses: 300_000, previousNetFlow: -10_000
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
```

- [ ] **Step 3.3: Build & verify previews compile**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: clean.

- [ ] **Step 3.4: Commit**

```
git add Tenra/Views/Components/Cards/InsightsTotalsCard.swift
git commit -m "feat(insights): period label + MoM delta badge in InsightsTotalsCard

New optional params periodLabel + previousIncome/Expenses/NetFlow; backward-compatible
defaults (nil) preserve original three-column layout.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire bucket totals into InsightsView

**Files:**
- Modify: `Tenra/Views/Insights/InsightsView.swift`

- [ ] **Step 4.1: Update `insightsSummaryHeaderSection` to pass bucket data**

Replace the `insightsSummaryHeaderSection` computed var (around lines 117–147) with:

```swift
    private var insightsSummaryHeaderSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            NavigationLink(destination: InsightsSummaryDetailView(
                totalIncome: insightsViewModel.totalIncome,
                totalExpenses: insightsViewModel.totalExpenses,
                netFlow: insightsViewModel.netFlow,
                currentBucketIncome: insightsViewModel.currentBucketIncome,
                currentBucketExpenses: insightsViewModel.currentBucketExpenses,
                currentBucketNetFlow: insightsViewModel.currentBucketNetFlow,
                previousBucketIncome: insightsViewModel.previousBucketIncome,
                previousBucketExpenses: insightsViewModel.previousBucketExpenses,
                previousBucketNetFlow: insightsViewModel.previousBucketNetFlow,
                bucketLabel: insightsViewModel.currentBucketLabel,
                currency: insightsViewModel.baseCurrency,
                periodDataPoints: insightsViewModel.periodDataPoints,
                granularity: insightsViewModel.currentGranularity
            )) {
                InsightsTotalsCard(
                    income: insightsViewModel.currentBucketIncome,
                    expenses: insightsViewModel.currentBucketExpenses,
                    netFlow: insightsViewModel.currentBucketNetFlow,
                    currency: insightsViewModel.baseCurrency,
                    periodLabel: insightsViewModel.currentBucketLabel,
                    previousIncome: insightsViewModel.previousBucketIncome,
                    previousExpenses: insightsViewModel.previousBucketExpenses,
                    previousNetFlow: insightsViewModel.previousBucketNetFlow
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let hs = insightsViewModel.healthScore {
                NavigationLink(destination: FinancialHealthDetailView(score: hs)) {
                    HealthScoreBadge(score: hs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .screenPadding()
        .contentReveal(isReady: !insightsViewModel.isLoading)
    }
```

- [ ] **Step 4.2: Build (will fail — InsightsSummaryDetailView signature mismatch)**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: errors about `InsightsSummaryDetailView` init signature — that's the next task.

---

## Task 5: Update InsightsSummaryDetailView to show period context

**Files:**
- Modify: `Tenra/Views/Insights/InsightsSummaryDetailView.swift`

- [ ] **Step 5.1: Read current file & update signature**

Read the file to understand current structure first:

```
Read: Tenra/Views/Insights/InsightsSummaryDetailView.swift
```

- [ ] **Step 5.2: Extend struct with bucket params + render two-tier hero**

In the struct properties at the top of `InsightsSummaryDetailView`, add the new params alongside the existing ones. Current totals (`totalIncome`/`totalExpenses`/`netFlow`) stay — they back the chart breakdown. New params:

```swift
    let currentBucketIncome: Double
    let currentBucketExpenses: Double
    let currentBucketNetFlow: Double
    let previousBucketIncome: Double
    let previousBucketExpenses: Double
    let previousBucketNetFlow: Double
    let bucketLabel: String
```

In the view body, replace the existing top totals card (the one that shows `totalIncome`/`totalExpenses`/`netFlow`) with two stacked cards:

```swift
            // Current period (bucket) — primary card
            InsightsTotalsCard(
                income: currentBucketIncome,
                expenses: currentBucketExpenses,
                netFlow: currentBucketNetFlow,
                currency: currency,
                periodLabel: bucketLabel,
                previousIncome: previousBucketIncome,
                previousExpenses: previousBucketExpenses,
                previousNetFlow: previousBucketNetFlow
            )

            // All-time (chart window) — secondary, smaller
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: "insights.summary.windowTotalsLabel"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
                InsightsTotalsCard(
                    income: totalIncome,
                    expenses: totalExpenses,
                    netFlow: netFlow,
                    currency: currency
                )
            }
```

- [ ] **Step 5.3: Add localization key**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.summary.windowTotalsLabel" = "Across the whole chart window";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.summary.windowTotalsLabel" = "За весь период графика";
```

- [ ] **Step 5.4: Update previews in InsightsSummaryDetailView**

Replace `#Preview` blocks at the bottom of `InsightsSummaryDetailView.swift` to provide the new params:

```swift
#Preview("Summary Detail — Month") {
    NavigationStack {
        InsightsSummaryDetailView(
            totalIncome: 12_400_000, totalExpenses: 8_900_000, netFlow: 3_500_000,
            currentBucketIncome: 530_000, currentBucketExpenses: 320_000, currentBucketNetFlow: 210_000,
            previousBucketIncome: 480_000, previousBucketExpenses: 350_000, previousBucketNetFlow: 130_000,
            bucketLabel: "May 2026",
            currency: "KZT",
            periodDataPoints: [],
            granularity: .month
        )
    }
}
```

- [ ] **Step 5.5: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: clean.

- [ ] **Step 5.6: Commit**

```
git add Tenra/Views/Insights/InsightsView.swift Tenra/Views/Insights/InsightsSummaryDetailView.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "$(cat <<'EOF'
fix(insights): totals card shows current bucket, not all-time cumulative

Headline bug: at granularity .month/.quarter/.year, the totals card was summing
ALL months/quarters/years from the first transaction. Now it shows only the
current bucket (e.g. May 2026) with a MoM delta badge vs. the previous bucket.
The summary detail view shows both the current bucket card AND the chart-window
totals (the latter labeled clearly so users know what the chart sums to).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: InsightFormulaModel + .formulaBreakdown case

**Files:**
- Create: `Tenra/Models/InsightFormulaModel.swift`
- Modify: `Tenra/Models/InsightModels.swift`

- [ ] **Step 6.1: Create `InsightFormulaModel.swift`**

```swift
//
//  InsightFormulaModel.swift
//  Tenra
//
//  Display model for formula-breakdown detail cards (savingsRate,
//  emergencyFund, spendingForecast, balanceRunway, projectedBalance,
//  yearOverYear). Mirrors the shape of HealthComponentDisplayModel.
//

import SwiftUI

/// One row of the formula breakdown — e.g. "Income: 530 000 ₸".
/// `kind` controls the value formatting (currency / months / percentage / count).
struct InsightFormulaRow: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case currency        // formatted via Formatting.formatCurrencySmart
        case months          // "1.8 months" — value is months count
        case percent         // "12.4%"
        case days            // "12 days"
        case rawText(String) // pre-formatted, render text as-is
    }

    let id: String
    let labelKey: String        // "insights.formula.<insight>.row.<name>"
    let value: Double
    let kind: Kind
    /// Optional emphasis (e.g. true for the "= result" row).
    let isEmphasised: Bool

    init(id: String, labelKey: String, value: Double, kind: Kind, isEmphasised: Bool = false) {
        self.id = id
        self.labelKey = labelKey
        self.value = value
        self.kind = kind
        self.isEmphasised = isEmphasised
    }
}

/// Display model for a formula-breakdown detail card — value-type, Sendable.
/// Carries everything needed to render: header, hero value, formula rows, and
/// localized recommendation copy.
struct InsightFormulaModel: Hashable, Sendable {
    let id: String                  // stable id, e.g. "savingsRate"
    let titleKey: String            // "insights.formula.<insight>.title"
    let icon: String                // SF Symbol name
    let color: Color                // tint
    let heroValueText: String       // pre-formatted hero, e.g. "12.4%" / "1.8 mo"
    let heroLabelKey: String        // "insights.formula.<insight>.heroLabel"
    let formulaHeaderKey: String    // "insights.formula.<insight>.formulaHeader"
    let formulaRows: [InsightFormulaRow]
    let explainerKey: String        // "insights.formula.<insight>.explainer"
    let recommendation: String      // ready-to-render localized copy
    let baseCurrency: String        // for currency-kind rows

    // Color is not Hashable; hash and compare by id only.
    static func == (lhs: InsightFormulaModel, rhs: InsightFormulaModel) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

- [ ] **Step 6.2: Add `.formulaBreakdown` case to `InsightDetailData`**

In `Tenra/Models/InsightModels.swift`, find `enum InsightDetailData` (around line 179) and add the new case:

```swift
enum InsightDetailData: Hashable {
    case categoryBreakdown([CategoryBreakdownItem])
    case periodTrend([PeriodDataPoint])
    case budgetProgressList([BudgetInsightItem])
    case recurringList([RecurringInsightItem])
    case accountComparison([AccountInsightItem])
    case wealthBreakdown([AccountInsightItem])
    case formulaBreakdown(InsightFormulaModel)   // ← NEW
}
```

- [ ] **Step 6.3: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean (no consumers exist yet — `switch` in `InsightDetailView` already has `default:` so adding the case won't break exhaustiveness… actually it does on `chartSection` — verify next task).

- [ ] **Step 6.4: Commit**

```
git add Tenra/Models/InsightFormulaModel.swift Tenra/Models/InsightModels.swift
git commit -m "feat(insights): InsightFormulaModel + InsightDetailData.formulaBreakdown case

Foundation for replacing 'detailData: nil' empty detail screens with a rich
formula-breakdown card mirroring the HealthComponentCard pattern.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: InsightFormulaCard view component

**Files:**
- Create: `Tenra/Views/Components/Cards/InsightFormulaCard.swift`

- [ ] **Step 7.1: Create the view**

```swift
//
//  InsightFormulaCard.swift
//  Tenra
//
//  Reusable detail card for insights with formula-style breakdown.
//  Mirrors HealthComponentCard's visual language: header → hero value →
//  formula rows → explainer → recommendation.
//

import SwiftUI

struct InsightFormulaCard: View {
    let model: InsightFormulaModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerRow
            heroRow
            formulaSection
            explainer
            recommendationBox
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: model.icon)
                .font(.system(size: AppIconSize.md))
                .foregroundStyle(model.color)
                .frame(width: 28)

            Text(String(localized: String.LocalizationValue(model.titleKey)))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()
        }
    }

    // MARK: - Hero value

    private var heroRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(String(localized: String.LocalizationValue(model.heroLabelKey)))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(model.heroValueText)
                .font(AppTypography.h1.bold())
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    // MARK: - Formula breakdown

    private var formulaSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(String(localized: String.LocalizationValue(model.formulaHeaderKey)))
                .font(AppTypography.bodySmall)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: AppSpacing.xs) {
                ForEach(model.formulaRows) { row in
                    formulaRow(row)
                    if row.id != model.formulaRows.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formulaRow(_ row: InsightFormulaRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: String.LocalizationValue(row.labelKey)))
                .font(row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body)
                .foregroundStyle(row.isEmphasised ? AppColors.textPrimary : AppColors.textSecondary)
            Spacer()
            Text(formattedValue(row))
                .font(row.isEmphasised ? AppTypography.bodyEmphasis : AppTypography.body)
                .fontWeight(row.isEmphasised ? .bold : .semibold)
                .foregroundStyle(row.isEmphasised ? model.color : AppColors.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func formattedValue(_ row: InsightFormulaRow) -> String {
        switch row.kind {
        case .currency:
            return Formatting.formatCurrencySmart(row.value, currency: model.baseCurrency)
        case .months:
            return String(format: String(localized: "insights.formula.value.months"), row.value)
        case .percent:
            return String(format: "%.1f%%", row.value)
        case .days:
            return String(format: String(localized: "insights.formula.value.days"), Int(row.value.rounded()))
        case .rawText(let s):
            return s
        }
    }

    // MARK: - Explainer

    private var explainer: some View {
        Text(String(localized: String.LocalizationValue(model.explainerKey)))
            .font(AppTypography.bodySmall)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Recommendation

    private var recommendationBox: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(model.color)

            Text(model.recommendation)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .background(model.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

// MARK: - Previews

#Preview("Savings rate") {
    InsightFormulaCard(model: InsightFormulaModel(
        id: "savingsRate",
        titleKey: "insights.formula.savingsRate.title",
        icon: "banknote.fill",
        color: AppColors.success,
        heroValueText: "12.4%",
        heroLabelKey: "insights.formula.savingsRate.heroLabel",
        formulaHeaderKey: "insights.formula.savingsRate.formulaHeader",
        formulaRows: [
            InsightFormulaRow(id: "income", labelKey: "insights.formula.savingsRate.row.income", value: 530_000, kind: .currency),
            InsightFormulaRow(id: "expenses", labelKey: "insights.formula.savingsRate.row.expenses", value: 464_000, kind: .currency),
            InsightFormulaRow(id: "saved", labelKey: "insights.formula.savingsRate.row.saved", value: 66_000, kind: .currency),
            InsightFormulaRow(id: "rate", labelKey: "insights.formula.savingsRate.row.rate", value: 12.4, kind: .percent, isEmphasised: true)
        ],
        explainerKey: "insights.formula.savingsRate.explainer",
        recommendation: "Aim for 20%. Trim recurring subscriptions or one-off splurges to widen the gap.",
        baseCurrency: "KZT"
    ))
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
```

- [ ] **Step 7.2: Build & verify the preview compiles**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 7.3: Commit**

```
git add Tenra/Views/Components/Cards/InsightFormulaCard.swift
git commit -m "feat(insights): InsightFormulaCard reusable detail component

Mirrors the HealthComponentCard pattern: header / hero / formula rows / explainer
/ recommendation. Used by the next series of commits to enrich savingsRate,
emergencyFund, spendingForecast, balanceRunway, projectedBalance, yearOverYear
detail screens.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Render .formulaBreakdown in InsightDetailView

**Files:**
- Modify: `Tenra/Views/Insights/InsightDetailView.swift`

- [ ] **Step 8.1: Add a case to the chartSection switch**

In the `chartSection` `@ViewBuilder` (around lines 89–124), add a new case BEFORE `case nil:`:

```swift
        case .formulaBreakdown(let model):
            InsightFormulaCard(model: model)
                .screenPadding()
```

- [ ] **Step 8.2: Add a case to the detailSection switch**

In the `detailSection` `@ViewBuilder` (around lines 137–155), the `default:` already handles unknown cases — no extra wiring needed (the formula card lives entirely in chartSection, so `detailSection` correctly renders nothing for `.formulaBreakdown`).

But to make exhaustiveness clean, replace `default: EmptyView()` with explicit cases:

```swift
    @ViewBuilder
    private var detailSection: some View {
        switch insight.detailData {
        case .categoryBreakdown(let items):
            categoryDetailList(items)
        case .recurringList(let items):
            recurringDetailList(items)
        case .budgetProgressList:
            EmptyView()
        case .periodTrend(let points):
            periodBreakdownList(points.map { BreakdownPoint(label: $0.label, income: $0.income, expenses: $0.expenses, netFlow: $0.netFlow) })
        case .wealthBreakdown(let accounts):
            accountDetailList(accounts)
        case .accountComparison(let accounts):
            dormantAccountDetailList(accounts)
        case .formulaBreakdown:
            EmptyView()
        case nil:
            EmptyView()
        }
    }
```

- [ ] **Step 8.3: Hide redundant header for formula-breakdown insights**

When `detailData == .formulaBreakdown`, the formula card already shows hero + label + everything — the existing `headerSection` (subtitle + big metric + comparison) becomes redundant. Add a guard:

Find `var body: some View` (around line 34). Replace with:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if !isFormulaBreakdown {
                    headerSection
                }

                chartSection
                detailSection
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(insight.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            logger.debug("📋 [InsightDetail] OPEN — type=\(String(describing: insight.type), privacy: .public), category=\(String(describing: insight.category), privacy: .public), metric=\(insight.metric.formattedValue, privacy: .public), drillDown=\(_onCategoryTap != nil)")
        }
    }

    private var isFormulaBreakdown: Bool {
        if case .formulaBreakdown = insight.detailData { return true }
        return false
    }
```

- [ ] **Step 8.4: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 8.5: Commit**

```
git add Tenra/Views/Insights/InsightDetailView.swift
git commit -m "feat(insights): render .formulaBreakdown via InsightFormulaCard

Skips the generic headerSection when detailData is .formulaBreakdown — the
formula card already carries the hero, so duplicating would feel redundant.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Localization keys for formula card chrome

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 9.1: Add the formatting keys (used by all formula cards)**

Append to `Tenra/en.lproj/Localizable.strings` (in the insights section, near `insights.months`):

```
"insights.formula.value.months" = "%.1f mo";
"insights.formula.value.days" = "%d days";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.value.months" = "%.1f мес";
"insights.formula.value.days" = "%d дн";
```

- [ ] **Step 9.2: Commit**

```
git add Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "i18n(insights): formula-card formatting keys (months / days)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Wire savingsRate detail

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Savings.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 10.1: Build the formula model in `generateSavingsRate`**

Replace the `generateSavingsRate` function (lines 42–64) entirely with:

```swift
    private nonisolated func generateSavingsRate(allIncome: Double, allExpenses: Double, baseCurrency: String) -> Insight? {
        guard allIncome > 0 else { return nil }
        let rate = ((allIncome - allExpenses) / allIncome) * 100
        let savedAmount = allIncome - allExpenses
        let severity: InsightSeverity = rate > 20 ? .positive : (rate >= 10 ? .warning : .critical)

        let recommendation: String
        if rate >= 20 {
            recommendation = String(localized: "insights.formula.savingsRate.rec.good")
        } else if rate >= 10 {
            let target = allIncome * 0.20
            let gap = target - savedAmount
            recommendation = String(
                format: String(localized: "insights.formula.savingsRate.rec.fair"),
                Formatting.formatCurrencySmart(max(0, gap), currency: baseCurrency)
            )
        } else {
            let target = allIncome * 0.10
            let gap = target - savedAmount
            recommendation = String(
                format: String(localized: "insights.formula.savingsRate.rec.low"),
                Formatting.formatCurrencySmart(max(0, gap), currency: baseCurrency)
            )
        }

        let model = InsightFormulaModel(
            id: "savingsRate",
            titleKey: "insights.formula.savingsRate.title",
            icon: "banknote.fill",
            color: severity.color,
            heroValueText: String(format: "%.1f%%", rate),
            heroLabelKey: "insights.formula.savingsRate.heroLabel",
            formulaHeaderKey: "insights.formula.savingsRate.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "income", labelKey: "insights.formula.savingsRate.row.income", value: allIncome, kind: .currency),
                InsightFormulaRow(id: "expenses", labelKey: "insights.formula.savingsRate.row.expenses", value: allExpenses, kind: .currency),
                InsightFormulaRow(id: "saved", labelKey: "insights.formula.savingsRate.row.saved", value: max(0, savedAmount), kind: .currency),
                InsightFormulaRow(id: "rate", labelKey: "insights.formula.savingsRate.row.rate", value: rate, kind: .percent, isEmphasised: true)
            ],
            explainerKey: "insights.formula.savingsRate.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("💰 [Insights] SavingsRate — \(String(format: "%.1f%%", rate), privacy: .public), severity=\(String(describing: severity), privacy: .public)")
        return Insight(
            id: "savings_rate",
            type: .savingsRate,
            title: String(localized: "insights.savingsRate"),
            subtitle: Formatting.formatCurrencySmart(max(0, savedAmount), currency: baseCurrency),
            metric: InsightMetric(
                value: rate,
                formattedValue: String(format: "%.1f%%", rate),
                currency: nil,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: .formulaBreakdown(model)
        )
    }
```

- [ ] **Step 10.2: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.formula.savingsRate.title" = "Savings Rate";
"insights.formula.savingsRate.heroLabel" = "Of every dollar you earn, you keep";
"insights.formula.savingsRate.formulaHeader" = "How it's computed";
"insights.formula.savingsRate.row.income" = "Income";
"insights.formula.savingsRate.row.expenses" = "Expenses";
"insights.formula.savingsRate.row.saved" = "Saved (income − expenses)";
"insights.formula.savingsRate.row.rate" = "Savings rate";
"insights.formula.savingsRate.explainer" = "What share of your income survives the month. A higher rate buys you more freedom — flexibility in slow months, faster goal funding, and a real emergency cushion.";
"insights.formula.savingsRate.rec.good" = "You're saving more than 20% — keep the routine and consider directing the surplus toward a long-term goal.";
"insights.formula.savingsRate.rec.fair" = "Decent, but pushing to 20%% means an extra %@ saved each month. Trim recurring or one-off categories that crept up.";
"insights.formula.savingsRate.rec.low" = "Below 10%% leaves no buffer. Aim for at least %@ more each month — start with the largest discretionary category.";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.savingsRate.title" = "Норма сбережений";
"insights.formula.savingsRate.heroLabel" = "С каждого заработанного остаётся";
"insights.formula.savingsRate.formulaHeader" = "Как считается";
"insights.formula.savingsRate.row.income" = "Доход";
"insights.formula.savingsRate.row.expenses" = "Расходы";
"insights.formula.savingsRate.row.saved" = "Сбережено (доход − расход)";
"insights.formula.savingsRate.row.rate" = "Норма сбережений";
"insights.formula.savingsRate.explainer" = "Какая доля дохода уцелела до конца периода. Чем выше — тем больше свободы: подушка на просадки, ускорение целей и настоящий резерв.";
"insights.formula.savingsRate.rec.good" = "Сберегаете больше 20% — держите ритм и направьте излишек на долгосрочную цель.";
"insights.formula.savingsRate.rec.fair" = "Неплохо, но до 20%% не хватает %@ в месяц. Подрежьте регулярные или разовые категории, которые подросли.";
"insights.formula.savingsRate.rec.low" = "Ниже 10%% — буфера почти нет. Минимум +%@ в месяц: начните с самой крупной дискреционной категории.";
```

- [ ] **Step 10.3: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 10.4: Commit**

```
git add Tenra/Services/Insights/InsightsService+Savings.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(insights): formula breakdown for savingsRate detail

Replaces empty detail screen with income / expenses / saved / rate breakdown
plus a target-aware recommendation (20% goal).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Wire emergencyFund detail

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Savings.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 11.1: Build the formula model in `generateEmergencyFund`**

Replace the `generateEmergencyFund` function entirely with:

```swift
    private nonisolated func generateEmergencyFund(accounts: [Account], transactions: [Transaction], baseCurrency: String, balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let totalBalance = accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard totalBalance > 0 else { return nil }

        let aggregates: [InMemoryMonthlyTotal]
        if let preAggregated {
            aggregates = preAggregated.lastMonthlyTotals(3)
        } else {
            aggregates = Self.computeLastMonthlyTotals(3, from: transactions, baseCurrency: baseCurrency)
        }
        guard !aggregates.isEmpty else { return nil }

        let avgMonthlyExpenses = aggregates.reduce(0.0) { $0 + $1.totalExpenses } / Double(aggregates.count)
        guard avgMonthlyExpenses > 0 else { return nil }

        let monthsCovered = totalBalance / avgMonthlyExpenses
        let severity: InsightSeverity = monthsCovered >= 3 ? .positive : (monthsCovered >= 1 ? .warning : .critical)
        let monthsInt = Int(monthsCovered.rounded(.down))

        let recommendation: String
        if monthsCovered >= 3 {
            recommendation = String(localized: "insights.formula.emergencyFund.rec.good")
        } else {
            let targetMonths: Double = 3
            let targetBalance = avgMonthlyExpenses * targetMonths
            let gap = targetBalance - totalBalance
            recommendation = String(
                format: String(localized: "insights.formula.emergencyFund.rec.gap"),
                Formatting.formatCurrencySmart(max(0, gap), currency: baseCurrency)
            )
        }

        let model = InsightFormulaModel(
            id: "emergencyFund",
            titleKey: "insights.formula.emergencyFund.title",
            icon: "shield.lefthalf.filled",
            color: severity.color,
            heroValueText: String(format: String(localized: "insights.formula.value.months"), monthsCovered),
            heroLabelKey: "insights.formula.emergencyFund.heroLabel",
            formulaHeaderKey: "insights.formula.emergencyFund.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "balance", labelKey: "insights.formula.emergencyFund.row.balance", value: totalBalance, kind: .currency),
                InsightFormulaRow(id: "avgExpenses", labelKey: "insights.formula.emergencyFund.row.avgExpenses", value: avgMonthlyExpenses, kind: .currency),
                InsightFormulaRow(id: "monthsCovered", labelKey: "insights.formula.emergencyFund.row.monthsCovered", value: monthsCovered, kind: .months, isEmphasised: true)
            ],
            explainerKey: "insights.formula.emergencyFund.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("🛡 [Insights] EmergencyFund — \(String(format: "%.1f", monthsCovered), privacy: .public) months, severity=\(String(describing: severity), privacy: .public)")
        return Insight(
            id: "emergency_fund",
            type: .emergencyFund,
            title: String(localized: "insights.emergencyFund"),
            subtitle: String(format: String(localized: "insights.monthsCovered"), monthsInt),
            metric: InsightMetric(
                value: monthsCovered,
                formattedValue: String(format: "%.1f", monthsCovered),
                currency: nil,
                unit: String(localized: "insights.months")
            ),
            trend: nil,
            severity: severity,
            category: .savings,
            detailData: .formulaBreakdown(model)
        )
    }
```

- [ ] **Step 11.2: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.formula.emergencyFund.title" = "Emergency Fund";
"insights.formula.emergencyFund.heroLabel" = "Months of expenses your balance covers";
"insights.formula.emergencyFund.formulaHeader" = "How it's computed";
"insights.formula.emergencyFund.row.balance" = "Total balance";
"insights.formula.emergencyFund.row.avgExpenses" = "Avg monthly expenses (last 3 mo)";
"insights.formula.emergencyFund.row.monthsCovered" = "Months covered";
"insights.formula.emergencyFund.explainer" = "How long your accounts cover regular spending if income paused tomorrow. 3+ months is the floor most planners recommend; 6 months is a comfortable cushion.";
"insights.formula.emergencyFund.rec.good" = "You're past the 3-month threshold. Consider parking the surplus in a higher-yield account or directing it toward longer-term goals.";
"insights.formula.emergencyFund.rec.gap" = "To reach 3 months of cover, top up by %@. Even small monthly contributions compound — start with whatever fits your savings rate.";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.emergencyFund.title" = "Резервный фонд";
"insights.formula.emergencyFund.heroLabel" = "Сколько месяцев расходов покроет баланс";
"insights.formula.emergencyFund.formulaHeader" = "Как считается";
"insights.formula.emergencyFund.row.balance" = "Общий баланс";
"insights.formula.emergencyFund.row.avgExpenses" = "Средние расходы (3 мес)";
"insights.formula.emergencyFund.row.monthsCovered" = "Месяцев покрытия";
"insights.formula.emergencyFund.explainer" = "Сколько продержитесь, если доход остановится завтра. Минимум — 3 месяца; 6 месяцев — комфортная подушка.";
"insights.formula.emergencyFund.rec.good" = "Покрытие выше 3 месяцев. Излишек можно перевести на доходный счёт или направить на долгосрочные цели.";
"insights.formula.emergencyFund.rec.gap" = "До 3 месяцев покрытия не хватает %@. Даже небольшие пополнения накапливаются — начните с любой суммы, которая укладывается в норму сбережений.";
```

- [ ] **Step 11.3: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 11.4: Commit**

```
git add Tenra/Services/Insights/InsightsService+Savings.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(insights): formula breakdown for emergencyFund detail

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Wire spendingForecast detail

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Forecasting.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 12.1: Build the formula model in `generateSpendingForecast`**

Replace the entire `generateSpendingForecast` function with:

```swift
    private nonisolated func generateSpendingForecast(transactions: [Transaction], recurringSeries: [RecurringSeries], categories: [CustomCategory], baseCurrency: String, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        let df = DateFormatters.dateFormatter

        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }

        let last30Spent = transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { total, tx in
                guard let txDate = df.date(from: tx.date),
                      txDate >= thirtyDaysAgo, txDate < now else { return total }
                return total + resolveAmount(tx, baseCurrency: baseCurrency)
            }
        let avgDailySpend = last30Spent / 30

        let totalDaysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: now)
        let daysRemaining = totalDaysInMonth - dayOfMonth

        let monthlyRecurringExpenses = recurringSeries
            .filter { $0.isActive }
            .filter { series in
                let isExpense = categories.first { c in c.name == series.category }?.type != .income
                return isExpense
            }
            .reduce(0.0) { total, series in
                guard let startDate = df.date(from: series.startDate) else { return total }
                if startDate > now { return total }
                return total + seriesMonthlyEquivalent(series, baseCurrency: baseCurrency, cache: preAggregated?.seriesMonthlyEquivalents)
            }

        let currentMonthData: InMemoryMonthlyTotal?
        if let preAggregated {
            currentMonthData = preAggregated.lastMonthlyTotals(1).first
        } else {
            currentMonthData = Self.computeLastMonthlyTotals(1, from: transactions, baseCurrency: baseCurrency).first
        }
        let spentSoFar = currentMonthData?.totalExpenses ?? 0
        let monthlyIncome = currentMonthData?.totalIncome ?? 0

        let pendingRecurring = max(0, (monthlyRecurringExpenses / Double(totalDaysInMonth)) * Double(daysRemaining))
        let projectedRemaining = avgDailySpend * Double(daysRemaining)
        let forecast = spentSoFar + projectedRemaining + pendingRecurring

        let severity: InsightSeverity = monthlyIncome > 0 ? (forecast > monthlyIncome ? .warning : .positive) : .neutral

        let recommendation: String
        if monthlyIncome > 0 && forecast > monthlyIncome {
            let overrun = forecast - monthlyIncome
            recommendation = String(
                format: String(localized: "insights.formula.spendingForecast.rec.overrun"),
                Formatting.formatCurrencySmart(overrun, currency: baseCurrency)
            )
        } else if monthlyIncome > 0 {
            let cushion = monthlyIncome - forecast
            recommendation = String(
                format: String(localized: "insights.formula.spendingForecast.rec.onTrack"),
                Formatting.formatCurrencySmart(cushion, currency: baseCurrency)
            )
        } else {
            recommendation = String(localized: "insights.formula.spendingForecast.rec.noIncome")
        }

        let model = InsightFormulaModel(
            id: "spendingForecast",
            titleKey: "insights.formula.spendingForecast.title",
            icon: "calendar.badge.exclamationmark",
            color: severity.color,
            heroValueText: Formatting.formatCurrencySmart(forecast, currency: baseCurrency),
            heroLabelKey: "insights.formula.spendingForecast.heroLabel",
            formulaHeaderKey: "insights.formula.spendingForecast.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "spentSoFar", labelKey: "insights.formula.spendingForecast.row.spentSoFar", value: spentSoFar, kind: .currency),
                InsightFormulaRow(id: "avgDaily", labelKey: "insights.formula.spendingForecast.row.avgDaily", value: avgDailySpend, kind: .currency),
                InsightFormulaRow(id: "daysLeft", labelKey: "insights.formula.spendingForecast.row.daysLeft", value: Double(daysRemaining), kind: .days),
                InsightFormulaRow(id: "projectedRest", labelKey: "insights.formula.spendingForecast.row.projectedRest", value: projectedRemaining + pendingRecurring, kind: .currency),
                InsightFormulaRow(id: "total", labelKey: "insights.formula.spendingForecast.row.total", value: forecast, kind: .currency, isEmphasised: true)
            ],
            explainerKey: "insights.formula.spendingForecast.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("🔮 [Insights] SpendingForecast — spentSoFar=\(String(format: "%.0f", spentSoFar), privacy: .public), avgDaily=\(String(format: "%.0f", avgDailySpend), privacy: .public), daysLeft=\(daysRemaining), forecast=\(String(format: "%.0f", forecast), privacy: .public) \(baseCurrency, privacy: .public)")
        return Insight(
            id: "spending_forecast",
            type: .spendingForecast,
            title: String(localized: "insights.spendingForecast"),
            subtitle: String(format: "%d " + String(localized: "insights.days") + " " + String(localized: "insights.remaining"), daysRemaining),
            metric: InsightMetric(
                value: forecast,
                formattedValue: Formatting.formatCurrencySmart(forecast, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .forecasting,
            detailData: .formulaBreakdown(model)
        )
    }
```

- [ ] **Step 12.2: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.formula.spendingForecast.title" = "Month-end Spending Forecast";
"insights.formula.spendingForecast.heroLabel" = "Projected total spend this month";
"insights.formula.spendingForecast.formulaHeader" = "How it's computed";
"insights.formula.spendingForecast.row.spentSoFar" = "Spent so far this month";
"insights.formula.spendingForecast.row.avgDaily" = "Avg daily spend (last 30 days)";
"insights.formula.spendingForecast.row.daysLeft" = "Days remaining";
"insights.formula.spendingForecast.row.projectedRest" = "Projected for the rest of month";
"insights.formula.spendingForecast.row.total" = "Forecast total";
"insights.formula.spendingForecast.explainer" = "Spent so far + (avg daily × days remaining) + pending recurring. Recurring is prorated by days remaining so a subscription on the 28th doesn't double-count if today's the 25th.";
"insights.formula.spendingForecast.rec.overrun" = "On track to overshoot income by %@. Pull discretionary spend forward into review or postpone optional purchases until next month.";
"insights.formula.spendingForecast.rec.onTrack" = "Forecast leaves a cushion of %@. Lock it in by avoiding unscheduled purchases, or move it to savings now.";
"insights.formula.spendingForecast.rec.noIncome" = "No income recorded yet this month — forecast is informational only.";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.spendingForecast.title" = "Прогноз расходов до конца месяца";
"insights.formula.spendingForecast.heroLabel" = "Прогнозируемый расход этого месяца";
"insights.formula.spendingForecast.formulaHeader" = "Как считается";
"insights.formula.spendingForecast.row.spentSoFar" = "Потрачено в этом месяце";
"insights.formula.spendingForecast.row.avgDaily" = "Средний расход в день (30 дн)";
"insights.formula.spendingForecast.row.daysLeft" = "Осталось дней";
"insights.formula.spendingForecast.row.projectedRest" = "Прогноз на остаток месяца";
"insights.formula.spendingForecast.row.total" = "Итоговый прогноз";
"insights.formula.spendingForecast.explainer" = "Уже потрачено + (среднее в день × оставшиеся дни) + ожидаемые подписки. Подписки делятся пропорционально дням, чтобы подписка 28-го не учитывалась дважды, если сегодня 25-е.";
"insights.formula.spendingForecast.rec.overrun" = "Превышение дохода на %@. Перепроверьте дискреционные траты или перенесите необязательные покупки на следующий месяц.";
"insights.formula.spendingForecast.rec.onTrack" = "Запас по доходу — %@. Чтобы зафиксировать, избегайте незапланированных покупок или сразу перенесите сумму в сбережения.";
"insights.formula.spendingForecast.rec.noIncome" = "В этом месяце ещё не зафиксирован доход — прогноз только информационный.";
```

- [ ] **Step 12.3: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 12.4: Commit**

```
git add Tenra/Services/Insights/InsightsService+Forecasting.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(insights): formula breakdown for spendingForecast detail

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: Wire balanceRunway detail

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Forecasting.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 13.1: Build the formula model in `generateBalanceRunway`**

Replace the entire `generateBalanceRunway` function with:

```swift
    private nonisolated func generateBalanceRunway(accounts: [Account], transactions: [Transaction], baseCurrency: String, balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let currentBalance = accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        guard currentBalance > 0 else { return nil }

        let aggregates: [InMemoryMonthlyTotal]
        if let preAggregated {
            aggregates = preAggregated.lastMonthlyTotals(3)
        } else {
            aggregates = Self.computeLastMonthlyTotals(3, from: transactions, baseCurrency: baseCurrency)
        }
        guard !aggregates.isEmpty else { return nil }

        let avgIncome = aggregates.reduce(0.0) { $0 + $1.totalIncome } / Double(aggregates.count)
        let avgExpenses = aggregates.reduce(0.0) { $0 + $1.totalExpenses } / Double(aggregates.count)
        let avgMonthlyNetFlow = avgIncome - avgExpenses

        // Positive net flow → growing balance: not strictly a runway, but show the breakdown.
        if avgMonthlyNetFlow > 0 {
            let model = InsightFormulaModel(
                id: "balanceRunway",
                titleKey: "insights.formula.balanceRunway.title",
                icon: "fuelpump.fill",
                color: AppColors.success,
                heroValueText: "+" + Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency) + " / " + String(localized: "insights.perMonth"),
                heroLabelKey: "insights.formula.balanceRunway.heroLabel.growing",
                formulaHeaderKey: "insights.formula.balanceRunway.formulaHeader",
                formulaRows: [
                    InsightFormulaRow(id: "balance", labelKey: "insights.formula.balanceRunway.row.balance", value: currentBalance, kind: .currency),
                    InsightFormulaRow(id: "avgIncome", labelKey: "insights.formula.balanceRunway.row.avgIncome", value: avgIncome, kind: .currency),
                    InsightFormulaRow(id: "avgExpenses", labelKey: "insights.formula.balanceRunway.row.avgExpenses", value: avgExpenses, kind: .currency),
                    InsightFormulaRow(id: "netFlow", labelKey: "insights.formula.balanceRunway.row.netFlow", value: avgMonthlyNetFlow, kind: .currency, isEmphasised: true)
                ],
                explainerKey: "insights.formula.balanceRunway.explainer.growing",
                recommendation: String(localized: "insights.formula.balanceRunway.rec.growing"),
                baseCurrency: baseCurrency
            )
            return Insight(
                id: "balance_runway",
                type: .balanceRunway,
                title: String(localized: "insights.balanceRunway"),
                subtitle: Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency) + " " + String(localized: "insights.perMonth"),
                metric: InsightMetric(
                    value: avgMonthlyNetFlow,
                    formattedValue: "+" + Formatting.formatCurrencySmart(avgMonthlyNetFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: String(localized: "insights.perMonth")
                ),
                trend: nil,
                severity: .positive,
                category: .forecasting,
                detailData: .formulaBreakdown(model)
            )
        }

        let burn = abs(avgMonthlyNetFlow)
        let runway = currentBalance / burn
        let severity: InsightSeverity = runway >= 3 ? .positive : (runway >= 1 ? .warning : .critical)

        let recommendation: String
        if runway >= 3 {
            recommendation = String(localized: "insights.formula.balanceRunway.rec.long")
        } else if runway >= 1 {
            let neededReduction = burn - (currentBalance / 3)
            recommendation = String(
                format: String(localized: "insights.formula.balanceRunway.rec.short"),
                Formatting.formatCurrencySmart(max(0, neededReduction), currency: baseCurrency)
            )
        } else {
            recommendation = String(localized: "insights.formula.balanceRunway.rec.critical")
        }

        let model = InsightFormulaModel(
            id: "balanceRunway",
            titleKey: "insights.formula.balanceRunway.title",
            icon: "fuelpump.fill",
            color: severity.color,
            heroValueText: String(format: String(localized: "insights.formula.value.months"), runway),
            heroLabelKey: "insights.formula.balanceRunway.heroLabel",
            formulaHeaderKey: "insights.formula.balanceRunway.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "balance", labelKey: "insights.formula.balanceRunway.row.balance", value: currentBalance, kind: .currency),
                InsightFormulaRow(id: "avgIncome", labelKey: "insights.formula.balanceRunway.row.avgIncome", value: avgIncome, kind: .currency),
                InsightFormulaRow(id: "avgExpenses", labelKey: "insights.formula.balanceRunway.row.avgExpenses", value: avgExpenses, kind: .currency),
                InsightFormulaRow(id: "burn", labelKey: "insights.formula.balanceRunway.row.burn", value: burn, kind: .currency),
                InsightFormulaRow(id: "runway", labelKey: "insights.formula.balanceRunway.row.runway", value: runway, kind: .months, isEmphasised: true)
            ],
            explainerKey: "insights.formula.balanceRunway.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("🛤 [Insights] BalanceRunway — balance=\(String(format: "%.0f", currentBalance), privacy: .public), burn=\(String(format: "%.0f", burn), privacy: .public)/mo, runway=\(String(format: "%.1f", runway), privacy: .public) months")
        return Insight(
            id: "balance_runway",
            type: .balanceRunway,
            title: String(localized: "insights.balanceRunway"),
            subtitle: String(format: "%.1f " + String(localized: "insights.balanceRunway.months"), runway),
            metric: InsightMetric(
                value: runway,
                formattedValue: String(format: "%.1f", runway),
                currency: nil,
                unit: String(localized: "insights.months")
            ),
            trend: nil,
            severity: severity,
            category: .forecasting,
            detailData: .formulaBreakdown(model)
        )
    }
```

- [ ] **Step 13.2: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.formula.balanceRunway.title" = "Balance Runway";
"insights.formula.balanceRunway.heroLabel" = "Months until balance runs out at current burn";
"insights.formula.balanceRunway.heroLabel.growing" = "Average monthly surplus";
"insights.formula.balanceRunway.formulaHeader" = "How it's computed";
"insights.formula.balanceRunway.row.balance" = "Current balance";
"insights.formula.balanceRunway.row.avgIncome" = "Avg monthly income (3 mo)";
"insights.formula.balanceRunway.row.avgExpenses" = "Avg monthly expenses (3 mo)";
"insights.formula.balanceRunway.row.burn" = "Monthly burn (expenses − income)";
"insights.formula.balanceRunway.row.netFlow" = "Average net flow";
"insights.formula.balanceRunway.row.runway" = "Runway";
"insights.formula.balanceRunway.explainer" = "Balance ÷ monthly burn. The 3-month threshold matches a healthy emergency cushion; below 1 month means a single bad pay cycle drains the buffer.";
"insights.formula.balanceRunway.explainer.growing" = "Income exceeds expenses, so balance is growing. The hero value is your average monthly surplus — your balance has indefinite runway at this rate.";
"insights.formula.balanceRunway.rec.growing" = "You're net-positive — direct the surplus toward goals, debt, or higher-yield savings rather than letting it idle.";
"insights.formula.balanceRunway.rec.long" = "More than 3 months of runway — you're well-buffered. Consider deploying excess cash to longer-term instruments.";
"insights.formula.balanceRunway.rec.short" = "Below 3 months. Cut burn by ~%@/mo to reach a 3-month buffer; start with the largest discretionary category.";
"insights.formula.balanceRunway.rec.critical" = "Less than a month of runway — close the gap urgently. Even pausing one major recurring payment buys days.";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.balanceRunway.title" = "Запас прочности";
"insights.formula.balanceRunway.heroLabel" = "Месяцев до исчерпания баланса";
"insights.formula.balanceRunway.heroLabel.growing" = "Среднее ежемесячное превышение";
"insights.formula.balanceRunway.formulaHeader" = "Как считается";
"insights.formula.balanceRunway.row.balance" = "Текущий баланс";
"insights.formula.balanceRunway.row.avgIncome" = "Средний доход (3 мес)";
"insights.formula.balanceRunway.row.avgExpenses" = "Средние расходы (3 мес)";
"insights.formula.balanceRunway.row.burn" = "Ежемесячный расход (расход − доход)";
"insights.formula.balanceRunway.row.netFlow" = "Средний чистый поток";
"insights.formula.balanceRunway.row.runway" = "Запас прочности";
"insights.formula.balanceRunway.explainer" = "Баланс ÷ ежемесячный расход. Порог 3 месяца — здоровая подушка; ниже 1 месяца значит, что одна неудачная зарплата «съедает» весь буфер.";
"insights.formula.balanceRunway.explainer.growing" = "Доход превышает расход — баланс растёт. Вверху — среднее ежемесячное превышение. При таком темпе запас прочности неограничен.";
"insights.formula.balanceRunway.rec.growing" = "Вы в плюсе — направьте излишек на цели, долги или доходные сбережения, а не оставляйте просто на счёте.";
"insights.formula.balanceRunway.rec.long" = "Запас более 3 месяцев — вы хорошо забуферены. Часть денег можно перевести в более долгосрочные инструменты.";
"insights.formula.balanceRunway.rec.short" = "Ниже 3 месяцев. Сократите расходы на ~%@/мес для подушки на 3 месяца — начните с самой крупной дискреционной категории.";
"insights.formula.balanceRunway.rec.critical" = "Меньше месяца — закрывайте разрыв срочно. Даже пауза одной крупной подписки даст несколько дней.";
```

- [ ] **Step 13.3: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 13.4: Commit**

```
git add Tenra/Services/Insights/InsightsService+Forecasting.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(insights): formula breakdown for balanceRunway detail

Two variants — net-positive (growing balance) and net-negative (true runway).
Both show full income/expense decomposition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Wire yearOverYear detail

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Forecasting.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 14.1: Build the formula model in `generateYearOverYear`**

Replace the entire `generateYearOverYear` function with:

```swift
    private nonisolated func generateYearOverYear(transactions: [Transaction], baseCurrency: String, preAggregated: PreAggregatedData? = nil) -> Insight? {
        let calendar = Calendar.current
        let now = Date()
        guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }

        let thisMonth: InMemoryMonthlyTotal?
        let lastYear: InMemoryMonthlyTotal?
        if let preAggregated {
            thisMonth = preAggregated.lastMonthlyTotals(1).first
            lastYear = preAggregated.lastMonthlyTotals(1, anchor: oneYearAgo).first
        } else {
            thisMonth = Self.computeLastMonthlyTotals(1, from: transactions, baseCurrency: baseCurrency).first
            lastYear = Self.computeLastMonthlyTotals(1, from: transactions, anchor: oneYearAgo, baseCurrency: baseCurrency).first
        }

        guard let thisExpenses = thisMonth?.totalExpenses,
              let lastYearExpenses = lastYear?.totalExpenses,
              lastYearExpenses > 0 else { return nil }

        let delta = ((thisExpenses - lastYearExpenses) / lastYearExpenses) * 100
        guard abs(delta) > 3 else { return nil }

        let direction: TrendDirection = delta > 0 ? .up : .down
        let severity: InsightSeverity = delta <= -10 ? .positive : (delta >= 15 ? .warning : .neutral)
        let thisLabel = thisMonth?.label ?? ""
        let lastLabel = lastYear?.label ?? ""

        let recommendation: String
        if delta <= -10 {
            recommendation = String(localized: "insights.formula.yearOverYear.rec.down")
        } else if delta >= 15 {
            recommendation = String(
                format: String(localized: "insights.formula.yearOverYear.rec.up"),
                String(format: "%.1f%%", delta)
            )
        } else {
            recommendation = String(localized: "insights.formula.yearOverYear.rec.flat")
        }

        let absDelta = thisExpenses - lastYearExpenses

        let model = InsightFormulaModel(
            id: "yearOverYear",
            titleKey: "insights.formula.yearOverYear.title",
            icon: "calendar.circle.fill",
            color: severity.color,
            heroValueText: String(format: "%+.1f%%", delta),
            heroLabelKey: "insights.formula.yearOverYear.heroLabel",
            formulaHeaderKey: "insights.formula.yearOverYear.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "thisMonth", labelKey: "insights.formula.yearOverYear.row.thisMonth", value: thisExpenses, kind: .rawText("\(Formatting.formatCurrencySmart(thisExpenses, currency: baseCurrency)) — \(thisLabel)")),
                InsightFormulaRow(id: "lastYear", labelKey: "insights.formula.yearOverYear.row.lastYear", value: lastYearExpenses, kind: .rawText("\(Formatting.formatCurrencySmart(lastYearExpenses, currency: baseCurrency)) — \(lastLabel)")),
                InsightFormulaRow(id: "absDelta", labelKey: "insights.formula.yearOverYear.row.absDelta", value: absDelta, kind: .currency),
                InsightFormulaRow(id: "delta", labelKey: "insights.formula.yearOverYear.row.delta", value: delta, kind: .percent, isEmphasised: true)
            ],
            explainerKey: "insights.formula.yearOverYear.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("📅 [Insights] YoY — this=\(String(format: "%.0f", thisExpenses), privacy: .public), lastYear=\(String(format: "%.0f", lastYearExpenses), privacy: .public), delta=\(String(format: "%+.1f%%", delta), privacy: .public)")
        return Insight(
            id: "year_over_year",
            type: .yearOverYear,
            title: String(localized: "insights.yearOverYear"),
            subtitle: thisLabel,
            metric: InsightMetric(
                value: thisExpenses,
                formattedValue: Formatting.formatCurrencySmart(thisExpenses, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: delta,
                changeAbsolute: absDelta,
                comparisonPeriod: String(localized: "insights.yearOverYear")
            ),
            severity: severity,
            category: .forecasting,
            detailData: .formulaBreakdown(model)
        )
    }
```

- [ ] **Step 14.2: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.formula.yearOverYear.title" = "Year-Over-Year Spending";
"insights.formula.yearOverYear.heroLabel" = "Change vs same month last year";
"insights.formula.yearOverYear.formulaHeader" = "How it's computed";
"insights.formula.yearOverYear.row.thisMonth" = "This month";
"insights.formula.yearOverYear.row.lastYear" = "Same month last year";
"insights.formula.yearOverYear.row.absDelta" = "Absolute change";
"insights.formula.yearOverYear.row.delta" = "Percentage change";
"insights.formula.yearOverYear.explainer" = "Compares total expenses for the current month vs. the same month one year ago. Useful for spotting genuine drift versus seasonal swings — December always spends more, but is *this* December heavier than last?";
"insights.formula.yearOverYear.rec.down" = "Spending is meaningfully down year-over-year. If unintentional, audit which categories cooled — sometimes a missed recurring is hiding here.";
"insights.formula.yearOverYear.rec.up" = "Spending is up %@. Compare top categories for both months — single new subscriptions, an extra rent cycle, or one big purchase often explain the jump.";
"insights.formula.yearOverYear.rec.flat" = "Modest change vs. last year — your spending pattern is stable. Track the same metric next month to spot any drift.";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.yearOverYear.title" = "Год к году";
"insights.formula.yearOverYear.heroLabel" = "Изменение к тому же месяцу год назад";
"insights.formula.yearOverYear.formulaHeader" = "Как считается";
"insights.formula.yearOverYear.row.thisMonth" = "В этом месяце";
"insights.formula.yearOverYear.row.lastYear" = "Тот же месяц год назад";
"insights.formula.yearOverYear.row.absDelta" = "Абсолютное изменение";
"insights.formula.yearOverYear.row.delta" = "Изменение в %%";
"insights.formula.yearOverYear.explainer" = "Сравнение общих расходов за текущий месяц и тот же месяц год назад. Помогает отличить реальный сдвиг от сезонности — декабрь всегда «дороже», но именно этот декабрь тяжелее прошлого?";
"insights.formula.yearOverYear.rec.down" = "Расходы заметно ниже год к году. Если это случайно — проверьте, не пропущена ли регулярная транзакция; иногда она «прячется» именно так.";
"insights.formula.yearOverYear.rec.up" = "Рост на %@. Сравните топ-категории обоих месяцев — обычно скачок объясняется одной новой подпиской, дополнительным циклом аренды или крупной покупкой.";
"insights.formula.yearOverYear.rec.flat" = "Изменение умеренное — ваш паттерн расходов стабилен. Проверьте тот же показатель в следующем месяце для отслеживания дрейфа.";
```

- [ ] **Step 14.3: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```

Expected: clean.

- [ ] **Step 14.4: Commit**

```
git add Tenra/Services/Insights/InsightsService+Forecasting.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(insights): formula breakdown for yearOverYear detail

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Wire projectedBalance detail

**Files:**
- Read first: `Tenra/Services/Insights/InsightsService+CashFlow.swift`
- Modify: `Tenra/Services/Insights/InsightsService+CashFlow.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 15.1: Read the existing `generateProjectedBalance` function**

```
Read: Tenra/Services/Insights/InsightsService+CashFlow.swift
```

Find `generateProjectedBalance` (around line 230–294 based on audit). Note its inputs (`accounts`, `monthlyEquivalents`, `granularity`, `balanceFor` etc.).

- [ ] **Step 15.2: Build the formula model**

Replace the body of `generateProjectedBalance` so it constructs the formula model. The function currently computes a `currentBalance`, an `avgMonthlyExpenses` (or net flow) figure, a `projectedPeriodMultiplier` (week/month/quarter/year scale), and a `projectedBalance = currentBalance + projectedNetFlow * multiplier`. Right before the existing `return Insight(...)` at the end of the function, build:

```swift
        let recommendation: String
        if projectedBalance >= currentBalance {
            recommendation = String(localized: "insights.formula.projectedBalance.rec.growing")
        } else {
            let drop = currentBalance - projectedBalance
            recommendation = String(
                format: String(localized: "insights.formula.projectedBalance.rec.dropping"),
                Formatting.formatCurrencySmart(drop, currency: baseCurrency)
            )
        }

        let model = InsightFormulaModel(
            id: "projectedBalance",
            titleKey: "insights.formula.projectedBalance.title",
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            color: severity.color,
            heroValueText: Formatting.formatCurrencySmart(projectedBalance, currency: baseCurrency),
            heroLabelKey: "insights.formula.projectedBalance.heroLabel",
            formulaHeaderKey: "insights.formula.projectedBalance.formulaHeader",
            formulaRows: [
                InsightFormulaRow(id: "currentBalance", labelKey: "insights.formula.projectedBalance.row.currentBalance", value: currentBalance, kind: .currency),
                InsightFormulaRow(id: "avgNetFlow", labelKey: "insights.formula.projectedBalance.row.avgNetFlow", value: avgMonthlyNetFlow, kind: .currency),
                InsightFormulaRow(id: "horizon", labelKey: "insights.formula.projectedBalance.row.horizon", value: Double(projectedPeriodMultiplier), kind: .rawText(granularity.displayName)),
                InsightFormulaRow(id: "projected", labelKey: "insights.formula.projectedBalance.row.projected", value: projectedBalance, kind: .currency, isEmphasised: true)
            ],
            explainerKey: "insights.formula.projectedBalance.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )
```

Then change the existing return statement so `detailData: nil` becomes `detailData: .formulaBreakdown(model)`.

> **Note for the implementer:** the exact local variable names in the existing function may differ (`avgMonthlyExpenses`, `avgMonthlyNetFlow`, `projectedPeriodMultiplier`, `currentBalance`, `projectedBalance`). Adjust the formula-row values to match the variable names actually present, but preserve the row order: current balance, avg net flow, horizon (granularity display name), projected balance.

- [ ] **Step 15.3: Add localization keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
"insights.formula.projectedBalance.title" = "Projected Balance";
"insights.formula.projectedBalance.heroLabel" = "Estimated balance at the end of period";
"insights.formula.projectedBalance.formulaHeader" = "How it's computed";
"insights.formula.projectedBalance.row.currentBalance" = "Current balance";
"insights.formula.projectedBalance.row.avgNetFlow" = "Avg monthly net flow (3 mo)";
"insights.formula.projectedBalance.row.horizon" = "Horizon";
"insights.formula.projectedBalance.row.projected" = "Projected balance";
"insights.formula.projectedBalance.explainer" = "Current balance + (recent net flow × period multiplier). Naïve linear projection — assumes the last 3 months represent the next period. Use it for early warning, not as a forecast.";
"insights.formula.projectedBalance.rec.growing" = "Projection trends upward — your current pattern adds to balance over the period.";
"insights.formula.projectedBalance.rec.dropping" = "Projection drops by %@ over the period. Identify which categories drove the recent net-negative months — those are where intervention compounds.";
```

Append to `Tenra/ru.lproj/Localizable.strings`:

```
"insights.formula.projectedBalance.title" = "Прогноз баланса";
"insights.formula.projectedBalance.heroLabel" = "Ожидаемый баланс к концу периода";
"insights.formula.projectedBalance.formulaHeader" = "Как считается";
"insights.formula.projectedBalance.row.currentBalance" = "Текущий баланс";
"insights.formula.projectedBalance.row.avgNetFlow" = "Средний чистый поток (3 мес)";
"insights.formula.projectedBalance.row.horizon" = "Горизонт";
"insights.formula.projectedBalance.row.projected" = "Прогнозный баланс";
"insights.formula.projectedBalance.explainer" = "Текущий баланс + (недавний чистый поток × множитель периода). Простая линейная проекция — предполагает, что последние 3 месяца повторятся. Используйте для раннего сигнала, не как точный прогноз.";
"insights.formula.projectedBalance.rec.growing" = "Тренд вверх — текущий паттерн прибавляет к балансу за период.";
"insights.formula.projectedBalance.rec.dropping" = "Просадка на %@ за период. Найдите категории, которые формировали отрицательные месяцы — именно там вмешательство даёт максимальный эффект.";
```

- [ ] **Step 15.4: Build & verify**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: clean. If errors mention undefined variables, double-check Step 15.2 note — adjust local names to match the existing function.

- [ ] **Step 15.5: Commit**

```
git add Tenra/Services/Insights/InsightsService+CashFlow.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(insights): formula breakdown for projectedBalance detail

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: Manual verification + final build

- [ ] **Step 16.1: Full build**

```
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

Expected: clean.

- [ ] **Step 16.2: Run all tests**

```
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -E "error:|FAIL|Test Suite .* (passed|failed)" | head -30
```

Expected: green.

- [ ] **Step 16.3: Manual verification on simulator**

Boot the app and verify:

1. Open Insights tab. The top totals card shows a period label (e.g. "May 2026") above the three columns and small +/− delta badges below each amount.
2. Switch granularity Week → Month → Quarter → Year → All time. Verify totals values change and the period label updates each time.
3. Tap into the totals card → summary detail shows two cards stacked: current bucket on top, "Across the whole chart window" totals below.
4. Open these insights and verify rich formula breakdown:
   - Savings / Savings Rate
   - Savings / Emergency Fund
   - Forecasting / Spending Forecast
   - Forecasting / Balance Runway
   - Forecasting / Year-Over-Year
   - Cash Flow / Projected Balance
5. Switch app language to Russian (Settings → General → Language → Русский) and re-open one of the cards. Verify all strings localised.

- [ ] **Step 16.4: Final commit / push**

If verification surfaces issues, fix them in a follow-up commit. Once green:

```
# No code change — just a marker that the plan is complete.
git log --oneline -16  # confirm 13 feature commits + 1 i18n + 1 manual verify
```

---

## Self-Review

**Spec coverage:**
- ✅ Headline granularity bug — Tasks 1–5.
- ✅ MISSING detail screens (6 of 10): savingsRate, emergencyFund, spendingForecast, balanceRunway, yearOverYear, projectedBalance — Tasks 10–15.
- ❌ Out of scope (separate plans): subscriptionGrowth, duplicateSubscriptions, spendingSpike, categoryTrend (need list-based UI), THIN screens (7), shared-insight granularity propagation. These are documented in the plan header.

**Placeholder scan:** No "TBD" / "implement later" / "similar to" found. Each task has full code.

**Type consistency:**
- `currentBucketRange()` / `previousBucketRange()` / `currentBucketLabel()` — names consistent across Tasks 1, 2, 4, 5.
- `InsightFormulaModel` / `InsightFormulaRow` / `.formulaBreakdown` — consistent in Tasks 6, 7, 8, 10–15.
- `bucketTotals` helper — defined Task 2.3, used 2.2.
- `currentBucketIncome/Expenses/NetFlow`, `previousBucket*` properties — consistent Tasks 2, 4, 5.

**One known fragility:** Task 15 (projectedBalance) requires reading the existing CashFlow generator first because variable names there were not pre-confirmed. Step 15.2 documents this and gives the implementer the row-order contract to follow.
