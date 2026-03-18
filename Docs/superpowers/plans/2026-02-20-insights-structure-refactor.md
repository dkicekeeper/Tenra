# Insights: Folder Structure + Component Extraction Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align `Views/Insights/` with the project's `Components/` convention and eliminate duplicated section code by extracting `InsightsSectionHeader` and a unified `InsightsSectionView<FirstChart>`.

**Architecture:**
Two phases. Phase A restructures the folder tree to match every other feature (`Sections/` + `Charts/` → `Components/`); `CategoryDeepDiveView` moves from `Sections/` to the root because it is a screen, not a component. Phase B extracts two new components: `InsightsSectionHeader` (removes 6 identical `private var sectionHeader` definitions) and `InsightsSectionView` (replaces all 6 `*InsightsSection.swift` files with a single generic type). `InsightsView` is updated to call `InsightsSectionView` directly; the six individual section files are deleted.

**Tech Stack:** SwiftUI, Swift 6, iOS 26+, Xcode project (.xcodeproj / project.pbxproj)

---

## Context

### Current structure (non-standard)
```
Views/Insights/
├── InsightsView.swift
├── InsightsSummaryHeader.swift    ← component but in root
├── InsightsGranularityPicker.swift ← component but in root
├── InsightsCardView.swift          ← component but in root
├── InsightDetailView.swift
├── InsightsSummaryDetailView.swift
├── InsightPreviewData.swift
├── Sections/                       ← NON-STANDARD
│   ├── SpendingInsightsSection.swift
│   ├── IncomeInsightsSection.swift   ← 41 lines, identical to Budget/Recurring
│   ├── BudgetInsightsSection.swift   ← 41 lines, identical
│   ├── RecurringInsightsSection.swift ← 41 lines, identical
│   ├── CashFlowInsightsSection.swift
│   ├── WealthInsightsSection.swift
│   └── CategoryDeepDiveView.swift   ← SCREEN inside components folder (wrong)
└── Charts/                          ← NON-STANDARD
    ├── CashFlowChart.swift
    ├── CategoryBreakdownChart.swift
    ├── IncomeExpenseChart.swift
    └── SpendingTrendChart.swift
```

### Target structure (project convention)
```
Views/Insights/
├── InsightsView.swift              ← screen
├── InsightDetailView.swift         ← screen
├── InsightsSummaryDetailView.swift ← screen
├── CategoryDeepDiveView.swift      ← screen (moved from Sections/)
├── InsightPreviewData.swift        ← mock data
└── Components/
    ├── InsightsSummaryHeader.swift
    ├── InsightsCardView.swift
    ├── InsightsGranularityPicker.swift
    ├── InsightsSectionHeader.swift  ← NEW
    ├── InsightsSectionView.swift    ← NEW (replaces all 6 section files)
    ├── SpendingInsightsSection.swift ← DELETED after InsightsSectionView absorbs it
    ├── CashFlowChart.swift
    ├── CategoryBreakdownChart.swift
    ├── IncomeExpenseChart.swift
    └── SpendingTrendChart.swift
```

---

## Phase A — Folder Restructure

### Task 1: Move files to `Components/` via git + update Xcode project

**Files:**
- Create dir: `AIFinanceManager/Views/Insights/Components/`
- Move: 3 root-level components + 6 section files + 4 chart files
- Move: `CategoryDeepDiveView.swift` from `Sections/` to root

**Step 1: Move files in the filesystem**

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager/AIFinanceManager/Views/Insights
mkdir -p Components

# Move root-level components
git mv InsightsSummaryHeader.swift     Components/InsightsSummaryHeader.swift
git mv InsightsGranularityPicker.swift Components/InsightsGranularityPicker.swift
git mv InsightsCardView.swift          Components/InsightsCardView.swift

# Move section files
git mv Sections/SpendingInsightsSection.swift    Components/SpendingInsightsSection.swift
git mv Sections/IncomeInsightsSection.swift      Components/IncomeInsightsSection.swift
git mv Sections/BudgetInsightsSection.swift      Components/BudgetInsightsSection.swift
git mv Sections/RecurringInsightsSection.swift   Components/RecurringInsightsSection.swift
git mv Sections/CashFlowInsightsSection.swift    Components/CashFlowInsightsSection.swift
git mv Sections/WealthInsightsSection.swift      Components/WealthInsightsSection.swift

# Move CategoryDeepDiveView to root (it's a screen, not a component)
git mv Sections/CategoryDeepDiveView.swift CategoryDeepDiveView.swift

# Move chart files
git mv Charts/CashFlowChart.swift          Components/CashFlowChart.swift
git mv Charts/CategoryBreakdownChart.swift Components/CategoryBreakdownChart.swift
git mv Charts/IncomeExpenseChart.swift     Components/IncomeExpenseChart.swift
git mv Charts/SpendingTrendChart.swift     Components/SpendingTrendChart.swift

# Remove now-empty subdirectories
rmdir Sections Charts
```

**Step 2: Update Xcode project references**

File paths in `project.pbxproj` must be updated. Run this Python script:

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager
python3 - <<'EOF'
import re, pathlib

pbxproj = pathlib.Path("AIFinanceManager.xcodeproj/project.pbxproj")
text = pbxproj.read_text()

moves = {
    # Root → Components
    "path = InsightsSummaryHeader.swift":     "path = Components/InsightsSummaryHeader.swift",
    "path = InsightsGranularityPicker.swift": "path = Components/InsightsGranularityPicker.swift",
    "path = InsightsCardView.swift":          "path = Components/InsightsCardView.swift",
    # Sections → Components
    "path = Sections/SpendingInsightsSection.swift":  "path = Components/SpendingInsightsSection.swift",
    "path = Sections/IncomeInsightsSection.swift":    "path = Components/IncomeInsightsSection.swift",
    "path = Sections/BudgetInsightsSection.swift":    "path = Components/BudgetInsightsSection.swift",
    "path = Sections/RecurringInsightsSection.swift": "path = Components/RecurringInsightsSection.swift",
    "path = Sections/CashFlowInsightsSection.swift":  "path = Components/CashFlowInsightsSection.swift",
    "path = Sections/WealthInsightsSection.swift":    "path = Components/WealthInsightsSection.swift",
    # Sections → root
    "path = Sections/CategoryDeepDiveView.swift": "path = CategoryDeepDiveView.swift",
    # Charts → Components
    "path = Charts/CashFlowChart.swift":          "path = Components/CashFlowChart.swift",
    "path = Charts/CategoryBreakdownChart.swift": "path = Components/CategoryBreakdownChart.swift",
    "path = Charts/IncomeExpenseChart.swift":     "path = Components/IncomeExpenseChart.swift",
    "path = Charts/SpendingTrendChart.swift":     "path = Components/SpendingTrendChart.swift",
}

for old, new in moves.items():
    text = text.replace(old, new)

pbxproj.write_text(text)
print(f"Updated {sum(1 for o,n in moves.items() if o in pbxproj.read_text() == False)} paths")
print("Done. Verify with: xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5")
EOF
```

> **Alternative (preferred):** Open Xcode → Project Navigator → select the files → drag them into a new "Components" group. Xcode updates `project.pbxproj` automatically.

**Step 3: Build to verify no missing file errors**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -20
```

Expected: `BUILD SUCCEEDED`

If you see `error: no such file`, re-run the Python script or fix paths manually in Xcode.

**Step 4: Commit**

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager
git add -A
git commit -m "$(cat <<'EOF'
refactor(insights): restructure folders — Sections/ + Charts/ → Components/

Aligns Views/Insights/ with project convention (every other feature uses
Components/ subfolder for reusable components, not Sections/ + Charts/).
CategoryDeepDiveView moved to root — it is a screen, not a component.

No code changes; only file paths updated.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase B — Component Extraction

### Task 2: Extract `InsightsSectionHeader` component

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/InsightsSectionHeader.swift`
- Modify (after this task): every `*InsightsSection.swift` that still has `private var sectionHeader`

**Step 1: Create the component file**

Write to `AIFinanceManager/Views/Insights/Components/InsightsSectionHeader.swift`:

```swift
//
//  InsightsSectionHeader.swift
//  AIFinanceManager
//
//  Reusable section header for all Insights sections.
//  Displays InsightCategory icon (accent) and localised display name.
//

import SwiftUI

/// Standard section header for Insights sections.
/// Replaces the identical `private var sectionHeader` found in every section view.
struct InsightsSectionHeader: View {
    let category: InsightCategory

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: category.icon)
                .foregroundStyle(AppColors.accent)
            Text(category.displayName)
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .screenPadding()
    }
}

// MARK: - Previews

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        InsightsSectionHeader(category: .spending)
        InsightsSectionHeader(category: .income)
        InsightsSectionHeader(category: .cashFlow)
        InsightsSectionHeader(category: .wealth)
    }
}
```

**Step 2: Add the new file to the Xcode project**

In Xcode: File → Add Files to "AIFinanceManager" → select `InsightsSectionHeader.swift` → ensure target checkbox is checked.

OR: update `project.pbxproj` with the UUID-based entry (prefer Xcode GUI for new files).

**Step 3: Build to confirm the new type compiles**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager
git add AIFinanceManager/Views/Insights/Components/InsightsSectionHeader.swift
git commit -m "$(cat <<'EOF'
feat(insights): add InsightsSectionHeader component

Extracts the identical 8-line sectionHeader found in all 6 section views
into a reusable parametric component. Next step will replace all callsites.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Create `InsightsSectionView` generic unified section component

**Files:**
- Create: `AIFinanceManager/Views/Insights/Components/InsightsSectionView.swift`

**Step 1: Create the component**

Write to `AIFinanceManager/Views/Insights/Components/InsightsSectionView.swift`:

```swift
//
//  InsightsSectionView.swift
//  AIFinanceManager
//
//  Universal parameterised section view for Insights.
//  Replaces: IncomeInsightsSection, BudgetInsightsSection, RecurringInsightsSection,
//            SpendingInsightsSection, CashFlowInsightsSection, WealthInsightsSection.
//
//  Usage — simple section (Income, Budget, Recurring):
//      InsightsSectionView(category: .income, insights: insights, currency: currency)
//
//  Usage — section with drill-down (Spending):
//      InsightsSectionView(category: .spending, insights: insights, currency: currency,
//                          onCategoryTap: { item in AnyView(CategoryDeepDiveView(...)) })
//
//  Usage — section with embedded chart (CashFlow, Wealth):
//      InsightsSectionView(
//          category: .cashFlow, insights: insights, currency: currency,
//          periodDataPoints: points, granularity: .month
//      ) {
//          PeriodCashFlowChart(dataPoints: points, currency: currency,
//                              granularity: .month, compact: false)
//      }
//

import SwiftUI

struct InsightsSectionView<FirstChart: View>: View {

    // MARK: - Properties

    let category: InsightCategory
    let insights: [Insight]
    let currency: String
    let periodDataPoints: [PeriodDataPoint]
    let granularity: InsightGranularity
    var onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil
    @ViewBuilder private let firstCardChart: () -> FirstChart

    // MARK: - Init (simple — no embedded chart)
    //
    // Covers: .income, .budget, .recurring, .spending (via onCategoryTap)

    init(
        category: InsightCategory,
        insights: [Insight],
        currency: String,
        onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil
    ) where FirstChart == EmptyView {
        self.category = category
        self.insights = insights
        self.currency = currency
        self.periodDataPoints = []
        self.granularity = .month
        self.onCategoryTap = onCategoryTap
        self.firstCardChart = { EmptyView() }
    }

    // MARK: - Init (with embedded chart in the first card)
    //
    // Covers: .cashFlow (PeriodCashFlowChart), .wealth (WealthChart)

    init(
        category: InsightCategory,
        insights: [Insight],
        currency: String,
        periodDataPoints: [PeriodDataPoint],
        granularity: InsightGranularity,
        @ViewBuilder firstCardChart: @escaping () -> FirstChart
    ) {
        self.category = category
        self.insights = insights
        self.currency = currency
        self.periodDataPoints = periodDataPoints
        self.granularity = granularity
        self.onCategoryTap = nil
        self.firstCardChart = firstCardChart
    }

    // MARK: - Computed

    /// `true` when `FirstChart` is not `EmptyView` — a chart was injected via init.
    private var hasChart: Bool {
        FirstChart.self != EmptyView.self
    }

    // MARK: - Body

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                InsightsSectionHeader(category: category)

                if hasChart, let firstInsight = insights.first, periodDataPoints.count >= 2 {
                    // First card — injected chart embedded inside InsightsCardView
                    NavigationLink(
                        destination: InsightDetailView(
                            insight: firstInsight,
                            currency: currency
                        )
                    ) {
                        InsightsCardView(insight: firstInsight) {
                            firstCardChart()
                        }
                    }
                    .buttonStyle(.plain)

                    // Remaining cards — standard (mini-chart overlay preserved)
                    ForEach(insights.dropFirst()) { insight in
                        NavigationLink(
                            destination: InsightDetailView(
                                insight: insight,
                                currency: currency,
                                onCategoryTap: onCategoryTap
                            )
                        ) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // No period data or no chart injected — all cards standard
                    ForEach(insights) { insight in
                        NavigationLink(
                            destination: InsightDetailView(
                                insight: insight,
                                currency: currency,
                                onCategoryTap: onCategoryTap
                            )
                        ) {
                            InsightsCardView(insight: insight)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
```

**Step 2: Add `InsightsSectionView.swift` to the Xcode project**

Same as Task 2, Step 2 — add via Xcode File menu or project navigator.

**Step 3: Build**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager
git add AIFinanceManager/Views/Insights/Components/InsightsSectionView.swift
git commit -m "$(cat <<'EOF'
feat(insights): add InsightsSectionView — unified generic section component

Generic InsightsSectionView<FirstChart: View> with two inits:
- Simple init (Income, Budget, Recurring, Spending with optional onCategoryTap)
- Chart init (CashFlow, Wealth — embeds FirstChart in first insight card)

Mirrors InsightsCardView<BottomChart> pattern already in the codebase.
Next step: update InsightsView to use this and delete all 6 section files.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Update `InsightsView.insightSections` to use `InsightsSectionView`

**Files:**
- Modify: `AIFinanceManager/Views/Insights/InsightsView.swift`

**Step 1: Read the file**

Read `InsightsView.swift` completely before editing.

**Step 2: Replace `insightSections` computed property**

Find and replace the entire `private var insightSections: some View` property (currently ~50 lines) with:

```swift
    // MARK: - Insight Sections

    @ViewBuilder
    private var insightSections: some View {
        let filtered = insightsViewModel.filteredInsights

        if filtered.isEmpty {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: AppIconSize.xxxl))
                    .foregroundStyle(AppColors.textTertiary)
                Text(String(localized: "insights.noInsightsForFilter"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, AppSpacing.xxxl)

        } else if insightsViewModel.selectedCategory == nil {
            // Spending — with drill-down to CategoryDeepDiveView
            InsightsSectionView(
                category: .spending,
                insights: insightsViewModel.spendingInsights,
                currency: insightsViewModel.baseCurrency,
                onCategoryTap: { [insightsViewModel] item in
                    AnyView(
                        CategoryDeepDiveView(
                            categoryName: item.categoryName,
                            color: item.color,
                            iconSource: item.iconSource,
                            currency: insightsViewModel.baseCurrency,
                            viewModel: insightsViewModel
                        )
                    )
                }
            )

            InsightsSectionView(
                category: .income,
                insights: insightsViewModel.incomeInsights,
                currency: insightsViewModel.baseCurrency
            )

            InsightsSectionView(
                category: .budget,
                insights: insightsViewModel.budgetInsights,
                currency: insightsViewModel.baseCurrency
            )

            InsightsSectionView(
                category: .recurring,
                insights: insightsViewModel.recurringInsights,
                currency: insightsViewModel.baseCurrency
            )

            InsightsSectionView(
                category: .cashFlow,
                insights: insightsViewModel.cashFlowInsights,
                currency: insightsViewModel.baseCurrency,
                periodDataPoints: insightsViewModel.periodDataPoints,
                granularity: insightsViewModel.currentGranularity
            ) {
                PeriodCashFlowChart(
                    dataPoints: insightsViewModel.periodDataPoints,
                    currency: insightsViewModel.baseCurrency,
                    granularity: insightsViewModel.currentGranularity,
                    compact: false
                )
            }

            InsightsSectionView(
                category: .wealth,
                insights: insightsViewModel.wealthInsights,
                currency: insightsViewModel.baseCurrency,
                periodDataPoints: insightsViewModel.periodDataPoints,
                granularity: insightsViewModel.currentGranularity
            ) {
                WealthChart(
                    dataPoints: insightsViewModel.periodDataPoints,
                    currency: insightsViewModel.baseCurrency,
                    granularity: insightsViewModel.currentGranularity,
                    compact: false
                )
            }

        } else {
            // Filtered mode — no section headers, all categories mixed
            ForEach(filtered) { insight in
                NavigationLink(
                    destination: InsightDetailView(
                        insight: insight,
                        currency: insightsViewModel.baseCurrency
                    )
                ) {
                    InsightsCardView(insight: insight)
                }
                .buttonStyle(.plain)
                .screenPadding()
            }
        }
    }
```

**Step 3: Build**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -5
```

Expected: `BUILD SUCCEEDED`

If `InsightsSectionView` is unresolved, the new file wasn't added to the Xcode target. Add it via Xcode and rebuild.

**Step 4: Commit**

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager
git add AIFinanceManager/Views/Insights/InsightsView.swift
git commit -m "$(cat <<'EOF'
refactor(insights): replace 6 InsightsSection calls with InsightsSectionView in InsightsView

InsightsView.insightSections now uses InsightsSectionView for all categories:
- Spending: passes onCategoryTap closure for CategoryDeepDiveView drill-down
- Income, Budget, Recurring: simple parameterised call
- CashFlow: @ViewBuilder PeriodCashFlowChart injection
- Wealth: @ViewBuilder WealthChart injection

Removes the separate wealthInsights isEmpty guard — InsightsSectionView
handles the empty check internally (if !insights.isEmpty).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Delete the 6 obsolete section files from Xcode project and filesystem

**Files:**
- Delete: `Components/SpendingInsightsSection.swift`
- Delete: `Components/IncomeInsightsSection.swift`
- Delete: `Components/BudgetInsightsSection.swift`
- Delete: `Components/RecurringInsightsSection.swift`
- Delete: `Components/CashFlowInsightsSection.swift`
- Delete: `Components/WealthInsightsSection.swift`

**Step 1: Remove files from Xcode project (required before deleting from disk)**

In Xcode Project Navigator: select each file → Delete → "Move to Trash".

OR remove filesystem + pbxproj references:

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager/AIFinanceManager/Views/Insights/Components
git rm SpendingInsightsSection.swift
git rm IncomeInsightsSection.swift
git rm BudgetInsightsSection.swift
git rm RecurringInsightsSection.swift
git rm CashFlowInsightsSection.swift
git rm WealthInsightsSection.swift
```

Then remove their `PBXBuildFile` + `PBXFileReference` entries from `project.pbxproj` (search for each filename).

**Step 2: Build to confirm nothing references the deleted types**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | head -10
```

Expected: `BUILD SUCCEEDED` — if `SpendingInsightsSection` is still referenced somewhere the error will be clear.

**Step 3: Commit**

```bash
cd /Users/dauletk/Documents/GitHub/AIFinanceManager
git add -A
git commit -m "$(cat <<'EOF'
refactor(insights): delete 6 obsolete *InsightsSection files

All section logic is now handled by InsightsSectionView.
Removes:
- SpendingInsightsSection, IncomeInsightsSection, BudgetInsightsSection
- RecurringInsightsSection, CashFlowInsightsSection, WealthInsightsSection

Net reduction: ~330 lines deleted, replaced by InsightsSectionView (~110 LOC).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Final Verification

After all tasks, confirm:

```bash
# Final build
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"

# Confirm no old section types remain in codebase
grep -r "SpendingInsightsSection\|IncomeInsightsSection\|BudgetInsightsSection\|RecurringInsightsSection\|CashFlowInsightsSection\|WealthInsightsSection" \
  AIFinanceManager/Views/ --include="*.swift"
# Expected: no output (all types deleted)

# Confirm new structure exists
ls AIFinanceManager/Views/Insights/Components/
# Expected: InsightsSectionHeader.swift, InsightsSectionView.swift,
#           InsightsSummaryHeader.swift, InsightsCardView.swift,
#           InsightsGranularityPicker.swift, and chart files
```

## Summary of Changes

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Subdirectories in Insights | 2 (`Sections/`, `Charts/`) | 1 (`Components/`) | −1 |
| Section files | 6 | 0 (deleted) | −6 |
| New components | — | 2 (`InsightsSectionHeader`, `InsightsSectionView`) | +2 |
| Net LOC (sections) | ~330 | ~110 | −220 |
| `private var sectionHeader` duplications | 6 | 0 | −6 |
| Structure matches project convention | ❌ | ✅ | — |
