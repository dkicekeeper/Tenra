# Insights Reusable Components — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract 9 reusable components from the Insights module — eliminating duplicated code and establishing consistent patterns.

**Architecture:** Each component lives in `Views/Insights/Components/` (Insights-specific) or extends an existing component in `Views/Components/` (app-wide). All components use Design System constants (AppSpacing, AppTypography, AppColors, AppRadius) and existing localization keys. No new architecture — pure view extraction.

**Tech Stack:** SwiftUI iOS 26+, AppTheme Design System, existing FormattedAmountText/IconView/AppEmptyState

---

## Duplication Map (before changes)

| # | Component | Priority | Duplicated In |
|---|-----------|----------|---------------|
| 1 | `BudgetProgressBar` | HIGH | InsightDetailView:144-155, InsightsCardView:151-162 |
| 2 | `PeriodBreakdownRow` | HIGH | InsightDetailView:349-388, InsightsSummaryDetailView:132-174 |
| 3 | `AmountWithPercentage` | HIGH | InsightDetailView:260-271, CategoryDeepDiveView:144-155 |
| 4 | `InsightsTotalsRow` | HIGH | InsightsSummaryHeader:27-48, InsightsSummaryDetailView:63-84 |
| 5 | `InsightTrendBadge` | MEDIUM | InsightsCardView:89-105 (pill), InsightDetailView:57-67 (flat) |
| 6 | `BudgetProgressRow` | MEDIUM | InsightDetailView:127-188 (private func) |
| 7 | Section titles → SectionHeaderView | MEDIUM | 3 files × 9 occurrences |
| 8 | `PeriodComparisonCard` | LOW | CategoryDeepDiveView:165-218 |
| 9 | `HealthScoreBadge` | LOW | InsightsSummaryHeader:72-97 |

**Build verification command** (run after every task):
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

---

## Task 1: BudgetProgressBar

**What:** Extract the identical `ZStack` progress bar from 2 files into one component.

**Exact duplication (current code in both files):**
```swift
// InsightsCardView.swift:151-162 (height: 6)
// InsightDetailView.swift:144-155 (height: 8)
ZStack(alignment: .leading) {
    RoundedRectangle(cornerRadius: AppRadius.xs)
        .fill(AppColors.secondaryBackground)
        .frame(maxWidth: .infinity)
        .frame(height: N)
    RoundedRectangle(cornerRadius: AppRadius.xs)
        .fill(item.isOverBudget ? AppColors.destructive : item.color)
        .frame(maxWidth: .infinity)
        .frame(height: N)
        .scaleEffect(x: min(item.percentage, 100) / 100, anchor: .leading)
}
```

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/BudgetProgressBar.swift`
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsCardView.swift` (lines 150-163)
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift` (lines 143-155)

---

**Step 1: Create BudgetProgressBar.swift**

```swift
//
//  BudgetProgressBar.swift
//  AIFinanceManager
//
//  Reusable horizontal budget progress bar with over-budget state.
//  Extracted from InsightsCardView and InsightDetailView (Phase 26).
//

import SwiftUI

/// Horizontal progress bar for budget utilisation.
/// - Parameter percentage: 0–100+ (clamped at 100 for bar width)
/// - Parameter isOverBudget: true → bar fills with AppColors.destructive
/// - Parameter color: brand color for the category (used when not over budget)
/// - Parameter height: bar height in points (default 8; InsightsCardView uses 6)
struct BudgetProgressBar: View {
    let percentage: Double
    let isOverBudget: Bool
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(AppColors.secondaryBackground)
                .frame(maxWidth: .infinity)
                .frame(height: height)

            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(isOverBudget ? AppColors.destructive : color)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .scaleEffect(x: min(percentage, 100) / 100, anchor: .leading)
        }
    }
}

// MARK: - Previews

#Preview("Normal") {
    VStack(spacing: AppSpacing.md) {
        BudgetProgressBar(percentage: 65, isOverBudget: false, color: .blue)
        BudgetProgressBar(percentage: 95, isOverBudget: false, color: .green)
        BudgetProgressBar(percentage: 120, isOverBudget: true, color: .orange)
    }
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact (height 6)") {
    BudgetProgressBar(percentage: 72, isOverBudget: false, color: .purple, height: 6)
        .screenPadding()
}
```

**Step 2: Update InsightsCardView.budgetProgressBar (lines 150-163)**

Replace the private `budgetProgressBar(_ item:)` function body with:
```swift
private func budgetProgressBar(_ item: BudgetInsightItem) -> some View {
    BudgetProgressBar(
        percentage: item.percentage,
        isOverBudget: item.isOverBudget,
        color: item.color,
        height: 6
    )
}
```

**Step 3: Update InsightDetailView.budgetChartSection (lines 143-155)**

Replace the inline ZStack with:
```swift
BudgetProgressBar(
    percentage: item.percentage,
    isOverBudget: item.isOverBudget,
    color: item.color
)
```

**Step 4: Build verify**
```bash
xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5
```

**Step 5: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/BudgetProgressBar.swift \
        AIFinanceManager/Views/Insights/Components/InsightsCardView.swift \
        AIFinanceManager/Views/Insights/InsightDetailView.swift
git commit -m "refactor(insights): extract BudgetProgressBar component — Phase 26"
```

---

## Task 2: PeriodBreakdownRow

**What:** Extract the near-identical period row (label + netFlow + income/expenses caption) from 2 files.

**Duplication:**
- `InsightDetailView.periodBreakdownList` — строки ForEach, нет Divider
- `InsightsSummaryDetailView.periodListSection` — строки ForEach + `Divider()` после каждой + `minWidth: 80` у label

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/PeriodBreakdownRow.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift` (func periodBreakdownList)
- Modify: `AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift` (var periodListSection)

---

**Step 1: Create PeriodBreakdownRow.swift**

```swift
//
//  PeriodBreakdownRow.swift
//  AIFinanceManager
//
//  Single period row showing net flow + income/expenses breakdown.
//  Extracted from InsightDetailView and InsightsSummaryDetailView (Phase 26).
//

import SwiftUI

/// One row in a period breakdown list (week / month / quarter / year).
/// Shows label on the left, netFlow + income/expenses on the right.
/// - Parameter showDivider: adds a `Divider` at the bottom (used in InsightsSummaryDetailView)
/// - Parameter labelMinWidth: optional min width for the label column (used in InsightsSummaryDetailView)
struct PeriodBreakdownRow: View {
    let label: String
    let income: Double
    let expenses: Double
    let netFlow: Double
    let currency: String
    var showDivider: Bool = false
    var labelMinWidth: CGFloat? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(minWidth: labelMinWidth, alignment: .leading)

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    FormattedAmountText(
                        amount: netFlow,
                        currency: currency,
                        fontSize: AppTypography.body,
                        fontWeight: .semibold,
                        color: netFlow >= 0 ? AppColors.success : AppColors.destructive
                    )
                    HStack(spacing: AppSpacing.xs) {
                        FormattedAmountText(
                            amount: income,
                            currency: currency,
                            prefix: "+",
                            fontSize: AppTypography.caption,
                            fontWeight: .regular,
                            color: AppColors.success
                        )
                        FormattedAmountText(
                            amount: expenses,
                            currency: currency,
                            prefix: "-",
                            fontSize: AppTypography.caption,
                            fontWeight: .regular,
                            color: AppColors.destructive
                        )
                    }
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .screenPadding()

            if showDivider {
                Divider()
                    .padding(.leading, AppSpacing.lg)
            }
        }
    }
}

// MARK: - Previews

#Preview("Without divider") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Jan 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT")
        PeriodBreakdownRow(label: "Dec 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT")
        PeriodBreakdownRow(label: "Nov 2025", income: 510_000, expenses: 540_000, netFlow: -30_000, currency: "KZT")
    }
}

#Preview("With divider + minWidth") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Jan 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT", showDivider: true, labelMinWidth: 80)
        PeriodBreakdownRow(label: "Dec 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT", showDivider: true, labelMinWidth: 80)
    }
}
```

**Step 2: Refactor InsightDetailView.periodBreakdownList**

Replace the ForEach block (lines 349-388) inner content with:
```swift
private func periodBreakdownList(_ points: [BreakdownPoint]) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
        Text(String(localized: "insights.monthlyBreakdown"))
            .font(AppTypography.h3)
            .foregroundStyle(AppColors.textPrimary)
            .screenPadding()

        ForEach(points.reversed(), id: \.label) { point in
            PeriodBreakdownRow(
                label: point.label,
                income: point.income,
                expenses: point.expenses,
                netFlow: point.netFlow,
                currency: currency
            )
        }
    }
}
```

**Step 3: Refactor InsightsSummaryDetailView.periodListSection**

Replace the ForEach block inner content with:
```swift
private var periodListSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.sm) {
        Text(String(localized: "insights.monthlyBreakdown"))
            .font(AppTypography.h3)
            .foregroundStyle(AppColors.textPrimary)
            .screenPadding()

        ForEach(periodDataPoints.reversed()) { point in
            PeriodBreakdownRow(
                label: point.label,
                income: point.income,
                expenses: point.expenses,
                netFlow: point.netFlow,
                currency: currency,
                showDivider: true,
                labelMinWidth: 80
            )
        }
    }
}
```

**Step 4: Build verify**

**Step 5: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/PeriodBreakdownRow.swift \
        AIFinanceManager/Views/Insights/InsightDetailView.swift \
        AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift
git commit -m "refactor(insights): extract PeriodBreakdownRow component — Phase 26"
```

---

## Task 3: AmountWithPercentage

**What:** Extract the identical `VStack(alignment: .trailing)` with amount + percentage from 2 files.

**Duplication:**
- `InsightDetailView.categoryRow` lines 259-271
- `CategoryDeepDiveView.subcategorySection` lines 143-155

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/AmountWithPercentage.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift`
- Modify: `AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift`

---

**Step 1: Create AmountWithPercentage.swift**

```swift
//
//  AmountWithPercentage.swift
//  AIFinanceManager
//
//  Trailing VStack with formatted amount + percentage caption.
//  Extracted from InsightDetailView and CategoryDeepDiveView (Phase 26).
//

import SwiftUI

/// Right-aligned column showing a monetary amount above a percentage caption.
/// Used in category breakdown rows and subcategory lists.
struct AmountWithPercentage: View {
    let amount: Double
    let currency: String
    let percentage: Double
    var amountFont: Font = AppTypography.body
    var amountWeight: Font.Weight = .semibold
    var amountColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: amountFont,
                fontWeight: amountWeight,
                color: amountColor
            )
            Text(String(format: "%.1f%%", percentage))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: AppSpacing.md) {
        AmountWithPercentage(amount: 85_000, currency: "KZT", percentage: 34.5)
        AmountWithPercentage(amount: 12_400, currency: "USD", percentage: 8.2)
    }
    .screenPadding()
}
```

**Step 2: Update InsightDetailView.categoryRow trailing VStack**

Replace lines 259-271 with:
```swift
HStack(spacing: AppSpacing.xs) {
    AmountWithPercentage(
        amount: item.amount,
        currency: currency,
        percentage: item.percentage
    )
    if onCategoryTap != nil {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColors.textTertiary)
    }
}
```

**Step 3: Update CategoryDeepDiveView.subcategorySection list trailing VStack**

Replace the `VStack(alignment: .trailing)` block (lines 144-155) with:
```swift
AmountWithPercentage(
    amount: item.amount,
    currency: currency,
    percentage: item.percentage
)
```

**Step 4: Build verify**

**Step 5: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/AmountWithPercentage.swift \
        AIFinanceManager/Views/Insights/InsightDetailView.swift \
        AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift
git commit -m "refactor(insights): extract AmountWithPercentage component — Phase 26"
```

---

## Task 4: InsightsTotalsRow

**What:** Extract the 3-column income/expenses/netFlow HStack that appears in both `InsightsSummaryHeader` and `InsightsSummaryDetailView` as private helper functions with different names (`summaryItem` vs `totalItem`) but identical content.

**Duplication:**
- `InsightsSummaryHeader.summaryItem` × 3 uses (lines 27-48) — calls with label + amount + color
- `InsightsSummaryDetailView.totalItem` × 3 uses (lines 63-84) — identical pattern

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/InsightsTotalsRow.swift`
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift`

---

**Step 1: Create InsightsTotalsRow.swift**

```swift
//
//  InsightsTotalsRow.swift
//  AIFinanceManager
//
//  Three-column income / expenses / net-flow summary row.
//  Extracted from InsightsSummaryHeader (summaryItem) and
//  InsightsSummaryDetailView (totalItem) — Phase 26.
//

import SwiftUI

/// Horizontal row with three labeled financial totals: income, expenses, net flow.
/// Used inside glass cards in the Insights summary header and summary detail view.
struct InsightsTotalsRow: View {
    let income: Double
    let expenses: Double
    let netFlow: Double
    let currency: String
    /// Font for the amount labels (default .bodySmall — matches both callers).
    var amountFont: Font = AppTypography.bodySmall

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            totalItem(
                title: String(localized: "insights.income"),
                amount: income,
                color: AppColors.success
            )
            Spacer()
            totalItem(
                title: String(localized: "insights.expenses"),
                amount: expenses,
                color: AppColors.destructive
            )
            Spacer()
            totalItem(
                title: String(localized: "insights.netFlow"),
                amount: netFlow,
                color: netFlow >= 0 ? AppColors.success : AppColors.destructive
            )
        }
    }

    private func totalItem(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            FormattedAmountText(
                amount: amount,
                currency: currency,
                fontSize: amountFont,
                fontWeight: .semibold,
                color: color
            )
        }
    }
}

// MARK: - Previews

#Preview("Positive") {
    InsightsTotalsRow(income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT")
        .glassCardStyle(radius: AppRadius.pill)
        .screenPadding()
        .padding(.vertical)
}

#Preview("Negative net flow") {
    InsightsTotalsRow(income: 280_000, expenses: 340_000, netFlow: -60_000, currency: "KZT")
        .glassCardStyle(radius: AppRadius.pill)
        .screenPadding()
        .padding(.vertical)
}
```

**Step 2: Simplify InsightsSummaryHeader body**

Remove `summaryItem` private func. Replace the HStack with:
```swift
InsightsTotalsRow(
    income: totalIncome,
    expenses: totalExpenses,
    netFlow: netFlow,
    currency: currency
)
```

**Step 3: Simplify InsightsSummaryDetailView.periodTotalsSection**

Remove `totalItem` private func. Replace the HStack in `periodTotalsSection` with:
```swift
private var periodTotalsSection: some View {
    InsightsTotalsRow(
        income: totalIncome,
        expenses: totalExpenses,
        netFlow: netFlow,
        currency: currency
    )
    .glassCardStyle(radius: AppRadius.pill)
    .screenPadding()
}
```

**Step 4: Build verify**

**Step 5: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/InsightsTotalsRow.swift \
        AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift \
        AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift
git commit -m "refactor(insights): extract InsightsTotalsRow component — Phase 26"
```

---

## Task 5: InsightTrendBadge

**What:** The trend pill badge is private in `InsightsCardView` and used as a plain inline HStack in `InsightDetailView.headerSection`. Extract to one public component with two style variants.

**Style `.pill`** (InsightsCardView:89-105):
- icon + `%+.1f%%` — colored foreground, colored `.opacity(0.12)` background, Capsule clip

**Style `.inline`** (InsightDetailView:57-67):
- icon + `%+.1f%%` — colored foreground, no background, semibold weight

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/InsightTrendBadge.swift`
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsCardView.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift`

---

**Step 1: Create InsightTrendBadge.swift**

```swift
//
//  InsightTrendBadge.swift
//  AIFinanceManager
//
//  Trend indicator badge for Insights cards and detail headers.
//  Extracted from InsightsCardView (pill) and InsightDetailView (inline) — Phase 26.
//

import SwiftUI

/// Compact trend indicator displaying direction icon + percentage change.
///
/// Two styles:
/// - `.pill` — with colored semi-transparent background capsule (cards)
/// - `.inline` — flat, no background (detail header)
struct InsightTrendBadge: View {
    let trend: InsightTrend

    enum Style {
        /// Colored capsule background. Used in `InsightsCardView`.
        case pill
        /// Flat, no background. Used in `InsightDetailView` header.
        case inline
    }

    var style: Style = .pill

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: trend.trendIcon)
                .font(style == .pill
                      ? AppTypography.caption2.weight(.bold)
                      : AppTypography.bodySmall)

            if let percent = trend.changePercent {
                Text(String(format: "%+.1f%%", percent))
                    .font(style == .pill ? AppTypography.caption2 : AppTypography.bodySmall)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(trend.trendColor)
        .if(style == .pill) { view in
            view
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(trend.trendColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

// MARK: - View+if helper (add only if not already in codebase)
// If `View.if` already exists, remove this extension.
private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Previews

#Preview {
    let upTrend = InsightTrend(direction: .up, changePercent: 12.4, changeAbsolute: nil, comparisonPeriod: "vs prev month")
    let downTrend = InsightTrend(direction: .down, changePercent: -5.1, changeAbsolute: nil, comparisonPeriod: "vs prev month")

    return VStack(spacing: AppSpacing.lg) {
        HStack(spacing: AppSpacing.md) {
            InsightTrendBadge(trend: upTrend, style: .pill)
            InsightTrendBadge(trend: downTrend, style: .pill)
        }
        HStack(spacing: AppSpacing.md) {
            InsightTrendBadge(trend: upTrend, style: .inline)
            InsightTrendBadge(trend: downTrend, style: .inline)
        }
    }
    .screenPadding()
}
```

> **Note:** Check if `View.if` already exists in `Extensions/`. If yes, remove the private extension from this file.

**Step 2: Update InsightsCardView**

Replace private `trendBadge(_ trend:)` func usage with:
```swift
// In body where trendBadge is called:
if let trend = insight.trend {
    InsightTrendBadge(trend: trend, style: .pill)
}
```
Remove the private `trendBadge` function entirely.

**Step 3: Update InsightDetailView.headerSection**

Replace the inline trend HStack (lines 57-67):
```swift
if let trend = insight.trend {
    InsightTrendBadge(trend: trend, style: .inline)
}
```

**Step 4: Check for View.if extension**
```bash
grep -r "func \`if\`" AIFinanceManager/Extensions/
```
If found: remove the private extension from InsightTrendBadge.swift.

**Step 5: Build verify**

**Step 6: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/InsightTrendBadge.swift \
        AIFinanceManager/Views/Insights/Components/InsightsCardView.swift \
        AIFinanceManager/Views/Insights/InsightDetailView.swift
git commit -m "refactor(insights): extract InsightTrendBadge component — Phase 26"
```

---

## Task 6: BudgetProgressRow

**What:** Extract the complete budget detail row (icon + name + `BudgetProgressBar` + spent/budget/daysLeft amounts) from its private `budgetChartSection` in `InsightDetailView`. This row is self-contained enough to be a standalone component and benefits from the `BudgetProgressBar` already extracted in Task 1.

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/BudgetProgressRow.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift`

---

**Step 1: Create BudgetProgressRow.swift**

```swift
//
//  BudgetProgressRow.swift
//  AIFinanceManager
//
//  Full budget progress row: icon + name + BudgetProgressBar + spent/budget amounts.
//  Extracted from InsightDetailView.budgetChartSection — Phase 26.
//

import SwiftUI

/// One row in the budget breakdown list. Shows category name, progress bar,
/// spent vs budget amounts, and remaining days.
struct BudgetProgressRow: View {
    let item: BudgetInsightItem
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Icon + name + percentage
            HStack {
                if let iconSource = item.iconSource {
                    IconView(source: iconSource, size: AppIconSize.lg)
                }
                Text(item.categoryName)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", item.percentage))
                    .font(AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.isOverBudget ? AppColors.destructive : AppColors.textPrimary)
            }

            // Progress bar (Task 1 component)
            BudgetProgressBar(
                percentage: item.percentage,
                isOverBudget: item.isOverBudget,
                color: item.color
            )

            // Spent / Budget / Days left
            HStack {
                FormattedAmountText(
                    amount: item.spent,
                    currency: currency,
                    fontSize: AppTypography.caption,
                    fontWeight: .regular,
                    color: AppColors.textSecondary
                )
                Text("/")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                FormattedAmountText(
                    amount: item.budgetAmount,
                    currency: currency,
                    fontSize: AppTypography.caption,
                    fontWeight: .regular,
                    color: AppColors.textSecondary
                )
                Spacer()
                if item.daysRemaining > 0 {
                    Text(String(format: String(localized: "insights.daysLeft"), item.daysRemaining))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}
```

**Step 2: Simplify InsightDetailView.budgetChartSection**

Replace the `VStack(alignment: .leading, spacing:)` inside `LazyVStack` with:
```swift
private func budgetChartSection(_ items: [BudgetInsightItem]) -> some View {
    LazyVStack(spacing: AppSpacing.md) {
        ForEach(items) { item in
            BudgetProgressRow(item: item, currency: currency)
        }
    }
}
```

**Step 3: Build verify**

**Step 4: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/BudgetProgressRow.swift \
        AIFinanceManager/Views/Insights/InsightDetailView.swift
git commit -m "refactor(insights): extract BudgetProgressRow component — Phase 26"
```

---

## Task 7: Section Titles → SectionHeaderView

**What:** Replace 9 inline `Text(localized:).font(.h3).foregroundStyle(.textPrimary)` section headers with `SectionHeaderView`. The existing `SectionHeaderView(.default)` uses `.bodyLarge` — Insights uses `.h3` which is larger. Add a new `.insights` style variant to `SectionHeaderView`.

**Files with inline titles (9 occurrences):**
- `InsightDetailView.swift`: `categoryDetailList`, `recurringDetailList`, `periodBreakdownList`, `accountDetailList`
- `InsightsSummaryDetailView.swift`: `chartSection`, `periodListSection`
- `CategoryDeepDiveView.swift`: `trendSection`, `subcategorySection`, `comparisonSection`

**Files:**
- Modify: `AIFinanceManager/Views/Components/SectionHeaderView.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightDetailView.swift`
- Modify: `AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift`
- Modify: `AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift`

---

**Step 1: Add `.insights` style to SectionHeaderView**

In `SectionHeaderView.swift`, add to the `Style` enum:
```swift
/// Insights section title — h3 weight, primary color. Used in all Insights detail views.
case insights
```

Add case to `body` switch:
```swift
case .insights:
    insightsStyle
```

Add computed property:
```swift
private var insightsStyle: some View {
    Text(title)
        .font(AppTypography.h3)
        .foregroundStyle(AppColors.textPrimary)
}
```

**Step 2: Replace inline titles in InsightDetailView**

In each of the 4 functions, replace:
```swift
Text(String(localized: "insights.breakdown"))
    .font(AppTypography.h3)
    .foregroundStyle(AppColors.textPrimary)
    .screenPadding()
```
With:
```swift
SectionHeaderView(String(localized: "insights.breakdown"), style: .insights)
    .screenPadding()
```

Apply same pattern to `insights.monthlyBreakdown` and `insights.wealth.accounts` keys.

**Step 3: Replace inline titles in InsightsSummaryDetailView**

In `chartSection` and `periodListSection`, replace the inline Text with `SectionHeaderView(..., style: .insights)`.

> Note: `chartSection` uses `.padding([.horizontal, .top], AppSpacing.lg)` — replace with `.padding([.horizontal, .top], AppSpacing.lg)` on `SectionHeaderView`.

**Step 4: Replace inline titles in CategoryDeepDiveView**

In `trendSection`, `subcategorySection`, `comparisonSection` — replace inline Text with:
```swift
SectionHeaderView(String(localized: "insights.spendingTrend"), style: .insights)
    .padding([.horizontal, .top], AppSpacing.lg)
// or .screenPadding() where appropriate
```

**Step 5: Build verify**

**Step 6: Commit**
```bash
git add AIFinanceManager/Views/Components/SectionHeaderView.swift \
        AIFinanceManager/Views/Insights/InsightDetailView.swift \
        AIFinanceManager/Views/Insights/InsightsSummaryDetailView.swift \
        AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift
git commit -m "refactor(insights): replace inline section titles with SectionHeaderView(.insights) — Phase 26"
```

---

## Task 8: PeriodComparisonCard

**What:** Extract `CategoryDeepDiveView.comparisonSection` into a standalone component. Single location now, but the MoM comparison pattern is core to Insights and will likely appear in Phase 27+ analytics.

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/PeriodComparisonCard.swift`
- Modify: `AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift`

---

**Step 1: Create PeriodComparisonCard.swift**

```swift
//
//  PeriodComparisonCard.swift
//  AIFinanceManager
//
//  Period-over-period comparison card (current vs previous).
//  Extracted from CategoryDeepDiveView.comparisonSection — Phase 26.
//

import SwiftUI

/// Glass card comparing two adjacent time periods.
/// Shows current amount | direction arrow + change% | previous amount.
///
/// - Parameter isExpenseContext: if true, an increase is shown in red (bad).
///   If false (income), an increase is shown in green (good).
struct PeriodComparisonCard: View {
    let currentLabel: String
    let currentAmount: Double
    let previousLabel: String
    let previousAmount: Double
    let currency: String
    var isExpenseContext: Bool = true

    private var change: Double {
        guard previousAmount > 0 else { return 0 }
        return ((currentAmount - previousAmount) / previousAmount) * 100
    }

    private var direction: TrendDirection {
        change > 2 ? .up : (change < -2 ? .down : .flat)
    }

    private var changeColor: Color {
        switch direction {
        case .up: return isExpenseContext ? AppColors.destructive : AppColors.success
        case .down: return isExpenseContext ? AppColors.success : AppColors.destructive
        case .flat: return AppColors.textSecondary
        }
    }

    private var arrowIcon: String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    var body: some View {
        HStack {
            // Current period
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(currentLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                FormattedAmountText(
                    amount: currentAmount,
                    currency: currency,
                    fontSize: AppTypography.h3,
                    fontWeight: .bold,
                    color: AppColors.textPrimary
                )
            }

            Spacer()

            // Change indicator
            VStack(spacing: AppSpacing.xxs) {
                Image(systemName: arrowIcon)
                    .foregroundStyle(changeColor)
                Text(String(format: "%+.1f%%", change))
                    .font(AppTypography.captionEmphasis)
                    .foregroundStyle(changeColor)
            }

            Spacer()

            // Previous period
            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(previousLabel)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                FormattedAmountText(
                    amount: previousAmount,
                    currency: currency,
                    fontSize: AppTypography.h3,
                    fontWeight: .semibold,
                    color: AppColors.textSecondary
                )
            }
        }
        .glassCardStyle(radius: AppRadius.pill)
    }
}

// MARK: - Previews

#Preview("Expense increase (bad)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 120_000,
        previousLabel: "Jan 2026", previousAmount: 95_000,
        currency: "KZT", isExpenseContext: true
    )
    .screenPadding()
    .padding(.vertical)
}

#Preview("Expense decrease (good)") {
    PeriodComparisonCard(
        currentLabel: "Feb 2026", currentAmount: 75_000,
        previousLabel: "Jan 2026", previousAmount: 95_000,
        currency: "KZT", isExpenseContext: true
    )
    .screenPadding()
    .padding(.vertical)
}
```

**Step 2: Simplify CategoryDeepDiveView.comparisonSection**

Replace the `HStack` content in `comparisonSection` with:
```swift
private var comparisonSection: some View {
    VStack(alignment: .leading, spacing: AppSpacing.md) {
        SectionHeaderView(String(localized: "insights.periodComparison"), style: .insights)

        if let current = monthlyTrend.last, monthlyTrend.count >= 2 {
            let previous = monthlyTrend[monthlyTrend.count - 2]
            PeriodComparisonCard(
                currentLabel: current.label,
                currentAmount: current.expenses,
                previousLabel: previous.label,
                previousAmount: previous.expenses,
                currency: currency,
                isExpenseContext: true
            )
        }
    }
    .screenPadding()
}
```

**Step 3: Build verify**

**Step 4: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/PeriodComparisonCard.swift \
        AIFinanceManager/Views/Insights/CategoryDeepDiveView.swift
git commit -m "refactor(insights): extract PeriodComparisonCard component — Phase 26"
```

---

## Task 9: HealthScoreBadge

**What:** Extract `InsightsSummaryHeader.healthScoreBadge(_:)` private function to a standalone component. Currently single location, but `FinancialHealthScore` may surface in Settings / AccountDetail in future phases.

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/HealthScoreBadge.swift`
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift`

---

**Step 1: Create HealthScoreBadge.swift**

```swift
//
//  HealthScoreBadge.swift
//  AIFinanceManager
//
//  Financial health score row: heart icon + score + grade capsule.
//  Extracted from InsightsSummaryHeader — Phase 26.
//

import SwiftUI

/// Compact row displaying the composite financial health score with grade badge.
/// Intended for use inside glass cards in Insights and Settings.
struct HealthScoreBadge: View {
    let score: FinancialHealthScore

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(score.gradeColor)
                .font(AppTypography.body)

            Text(String(localized: "insights.healthScore"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text("\(score.score)")
                .font(AppTypography.body.bold())
                .foregroundStyle(score.gradeColor)

            Text(score.grade)
                .font(AppTypography.caption)
                .foregroundStyle(score.gradeColor)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 2)
                .background(score.gradeColor.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}
```

**Step 2: Update InsightsSummaryHeader**

Replace `if let hs = healthScore { healthScoreBadge(hs) }` with:
```swift
if let hs = healthScore {
    HealthScoreBadge(score: hs)
}
```

Delete the private `healthScoreBadge(_:)` function.

**Step 3: Build verify**

**Step 4: Commit**
```bash
git add AIFinanceManager/Views/Insights/Components/HealthScoreBadge.swift \
        AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift
git commit -m "refactor(insights): extract HealthScoreBadge component — Phase 26"
```

---

## Final Verification

**Build:**
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|warning:|SUCCEEDED|FAILED"
```

**Expected:** 0 errors, `BUILD SUCCEEDED`

**New files created (9):**
```
AIFinanceManager/Views/Insights/Components/
├── BudgetProgressBar.swift       ← Task 1
├── PeriodBreakdownRow.swift      ← Task 2
├── AmountWithPercentage.swift    ← Task 3
├── InsightsTotalsRow.swift       ← Task 4
├── InsightTrendBadge.swift       ← Task 5
├── BudgetProgressRow.swift       ← Task 6
├── PeriodComparisonCard.swift    ← Task 8
└── HealthScoreBadge.swift        ← Task 9
AIFinanceManager/Views/Components/
└── SectionHeaderView.swift       ← Task 7 (modified, not new)
```

**Modified files (8):**
- `InsightsCardView.swift` — Tasks 1, 5
- `InsightDetailView.swift` — Tasks 1, 2, 3, 5, 6, 7
- `InsightsSummaryHeader.swift` — Tasks 4, 9
- `InsightsSummaryDetailView.swift` — Tasks 2, 4, 7
- `CategoryDeepDiveView.swift` — Tasks 3, 7, 8
- `SectionHeaderView.swift` — Task 7

**Estimated LOC reduction:** ~250 lines eliminated across 5 modified files.
