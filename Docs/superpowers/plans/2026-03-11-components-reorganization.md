# Components Reorganization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize all reusable UI components into `Views/Components/` with 9 logical subfolders (Cards, Rows, Forms, Icons, Input, Charts, Headers, Feedback, Skeleton).

**Architecture:** The project uses Xcode 16's `PBXFileSystemSynchronizedRootGroup` — Xcode automatically discovers files from the filesystem, so **no changes to project.pbxproj are required**. Moving files on disk is sufficient; a successful build confirms correctness. No Swift imports change (same module).

**Tech Stack:** Swift / SwiftUI / Xcode 16+ (filesystem-synced groups)

---

## Before You Start

Verify clean build baseline:

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
```

Expected: `BUILD SUCCEEDED`

---

## Task 1: Create subdirectory structure

**Files:**
- Create directories inside `AIFinanceManager/Views/Components/`

**Step 1: Create all 9 subdirectories**

```bash
cd AIFinanceManager/Views/Components
mkdir -p Cards Rows Forms Icons Input Charts Headers Feedback Skeleton
```

**Step 2: Verify directories exist**

```bash
ls AIFinanceManager/Views/Components/
```

Expected: `Cards  Charts  Feedback  Forms  Headers  Icons  Input  Rows  Skeleton` (plus existing .swift files)

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Components/
git commit -m "chore: create Components/ subdirectory structure"
```

---

## Task 2: Move Cards/

**Files to move** — all into `Views/Components/Cards/`:

| From | File |
|------|------|
| `Views/Components/` | `AnalyticsCard.swift` |
| `Views/Components/` | `TransactionsSummaryCard.swift` |
| `Views/Insights/Components/` | `InsightsCardView.swift` |
| `Views/Insights/Components/` | `PeriodComparisonCard.swift` |
| `Views/Subscriptions/Components/` | `SubscriptionCard.swift` |
| `Views/Subscriptions/` | `SubscriptionsCardView.swift` |
| `Views/Transactions/Components/` | `TransactionCard.swift` |
| `Views/Transactions/Components/` | `TransactionCardComponents.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Cards

mv $BASE/Components/AnalyticsCard.swift $DEST/
mv $BASE/Components/TransactionsSummaryCard.swift $DEST/
mv $BASE/Insights/Components/InsightsCardView.swift $DEST/
mv $BASE/Insights/Components/PeriodComparisonCard.swift $DEST/
mv $BASE/Subscriptions/Components/SubscriptionCard.swift $DEST/
mv $BASE/Subscriptions/SubscriptionsCardView.swift $DEST/
mv $BASE/Transactions/Components/TransactionCard.swift $DEST/
mv $BASE/Transactions/Components/TransactionCardComponents.swift $DEST/
```

**Step 2: Verify**

```bash
ls AIFinanceManager/Views/Components/Cards/
```

Expected: 8 `.swift` files

**Step 3: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output (no errors)

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: move card components to Components/Cards/"
```

---

## Task 3: Move Rows/

**Files to move** — all into `Views/Components/Rows/`:

| From | File |
|------|------|
| `Views/Components/` | `ColorPickerRow.swift` |
| `Views/Components/` | `DatePickerRow.swift` |
| `Views/Components/` | `FormLabeledRow.swift` |
| `Views/Components/` | `InfoRow.swift` |
| `Views/Components/` | `MenuPickerRow.swift` |
| `Views/Components/` | `UniversalRow.swift` |
| `Views/Insights/Components/` | `BudgetProgressRow.swift` |
| `Views/Insights/Components/` | `InsightsTotalsRow.swift` |
| `Views/Insights/Components/` | `PeriodBreakdownRow.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Rows

mv $BASE/Components/ColorPickerRow.swift $DEST/
mv $BASE/Components/DatePickerRow.swift $DEST/
mv $BASE/Components/FormLabeledRow.swift $DEST/
mv $BASE/Components/InfoRow.swift $DEST/
mv $BASE/Components/MenuPickerRow.swift $DEST/
mv $BASE/Components/UniversalRow.swift $DEST/
mv $BASE/Insights/Components/BudgetProgressRow.swift $DEST/
mv $BASE/Insights/Components/InsightsTotalsRow.swift $DEST/
mv $BASE/Insights/Components/PeriodBreakdownRow.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move row components to Components/Rows/"
```

---

## Task 4: Move Forms/

**Files to move** — all into `Views/Components/Forms/`:

| From | File |
|------|------|
| `Views/Components/` | `BudgetSettingsSection.swift` |
| `Views/Components/` | `EditSheetContainer.swift` |
| `Views/Components/` | `EditableHeroSection.swift` |
| `Views/Components/` | `FormSection.swift` |
| `Views/Components/` | `FormTextField.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Forms

mv $BASE/Components/BudgetSettingsSection.swift $DEST/
mv $BASE/Components/EditSheetContainer.swift $DEST/
mv $BASE/Components/EditableHeroSection.swift $DEST/
mv $BASE/Components/FormSection.swift $DEST/
mv $BASE/Components/FormTextField.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move form components to Components/Forms/"
```

---

## Task 5: Move Icons/

**Files to move** — all into `Views/Components/Icons/`:

| From | File |
|------|------|
| `Views/Components/` | `IconPickerView.swift` |
| `Views/Components/` | `IconView.swift` |
| `Views/Components/` | `IconView+Previews.swift` |
| `Views/Subscriptions/Components/` | `StaticSubscriptionIconsView.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Icons

mv $BASE/Components/IconPickerView.swift $DEST/
mv $BASE/Components/IconView.swift $DEST/
mv $BASE/Components/"IconView+Previews.swift" $DEST/
mv $BASE/Subscriptions/Components/StaticSubscriptionIconsView.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move icon components to Components/Icons/"
```

---

## Task 6: Move Input/

**Files to move** — all into `Views/Components/Input/`:

| From | File |
|------|------|
| `Views/Components/` | `AnimatedAmountInput.swift` |
| `Views/Components/` | `AnimatedInputComponents.swift` |
| `Views/Components/` | `CategoryGridView.swift` |
| `Views/Components/` | `CurrencySelectorView.swift` |
| `Views/Components/` | `DateButtonsView.swift` |
| `Views/Components/` | `FormattedAmountText.swift` |
| `Views/Components/` | `SegmentedPickerView.swift` |
| `Views/Components/` | `UniversalCarousel.swift` |
| `Views/Components/` | `UniversalFilterButton.swift` |
| `Views/Transactions/Components/` | `AmountInputView.swift` |
| `Views/Transactions/Components/` | `FormattedAmountView.swift` |
| `Views/Insights/Components/` | `InsightsGranularityPicker.swift` |
| `Views/Subscriptions/Components/` | `SubscriptionCalendarView.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Input

mv $BASE/Components/AnimatedAmountInput.swift $DEST/
mv $BASE/Components/AnimatedInputComponents.swift $DEST/
mv $BASE/Components/CategoryGridView.swift $DEST/
mv $BASE/Components/CurrencySelectorView.swift $DEST/
mv $BASE/Components/DateButtonsView.swift $DEST/
mv $BASE/Components/FormattedAmountText.swift $DEST/
mv $BASE/Components/SegmentedPickerView.swift $DEST/
mv $BASE/Components/UniversalCarousel.swift $DEST/
mv $BASE/Components/UniversalFilterButton.swift $DEST/
mv $BASE/Transactions/Components/AmountInputView.swift $DEST/
mv $BASE/Transactions/Components/FormattedAmountView.swift $DEST/
mv $BASE/Insights/Components/InsightsGranularityPicker.swift $DEST/
mv $BASE/Subscriptions/Components/SubscriptionCalendarView.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move input components to Components/Input/"
```

---

## Task 7: Move Charts/

**Files to move** — all into `Views/Components/Charts/`:

| From | File |
|------|------|
| `Views/Components/` | `BudgetProgressCircle.swift` |
| `Views/Insights/Components/` | `BudgetProgressBar.swift` |
| `Views/Insights/Components/` | `DonutChart.swift` |
| `Views/Insights/Components/` | `PeriodBarChart.swift` |
| `Views/Insights/Components/` | `PeriodLineChart.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Charts

mv $BASE/Components/BudgetProgressCircle.swift $DEST/
mv $BASE/Insights/Components/BudgetProgressBar.swift $DEST/
mv $BASE/Insights/Components/DonutChart.swift $DEST/
mv $BASE/Insights/Components/PeriodBarChart.swift $DEST/
mv $BASE/Insights/Components/PeriodLineChart.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move chart components to Components/Charts/"
```

---

## Task 8: Move Headers/

**Files to move** — all into `Views/Components/Headers/`:

| From | File |
|------|------|
| `Views/Components/` | `DateSectionHeaderView.swift` |
| `Views/Components/` | `HeroSection.swift` |
| `Views/Components/` | `SectionHeaderView.swift` |
| `Views/Insights/Components/` | `InsightsSectionView.swift` |
| `Views/Insights/Components/` | `InsightsSummaryHeader.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Headers

mv $BASE/Components/DateSectionHeaderView.swift $DEST/
mv $BASE/Components/HeroSection.swift $DEST/
mv $BASE/Components/SectionHeaderView.swift $DEST/
mv $BASE/Insights/Components/InsightsSectionView.swift $DEST/
mv $BASE/Insights/Components/InsightsSummaryHeader.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move header components to Components/Headers/"
```

---

## Task 9: Move Feedback/

**Files to move** — all into `Views/Components/Feedback/`:

| From | File |
|------|------|
| `Views/Components/` | `HighlightedText.swift` |
| `Views/Components/` | `InlineStatusText.swift` |
| `Views/Components/` | `MessageBanner.swift` |
| `Views/Components/` | `StatusIndicatorBadge.swift` |
| `Views/Insights/Components/` | `HealthScoreBadge.swift` |
| `Views/Insights/Components/` | `InsightTrendBadge.swift` |
| `Views/Subscriptions/Components/` | `NotificationPermissionView.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Feedback

mv $BASE/Components/HighlightedText.swift $DEST/
mv $BASE/Components/InlineStatusText.swift $DEST/
mv $BASE/Components/MessageBanner.swift $DEST/
mv $BASE/Components/StatusIndicatorBadge.swift $DEST/
mv $BASE/Insights/Components/HealthScoreBadge.swift $DEST/
mv $BASE/Insights/Components/InsightTrendBadge.swift $DEST/
mv $BASE/Subscriptions/Components/NotificationPermissionView.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move feedback components to Components/Feedback/"
```

---

## Task 10: Move Skeleton/

**Files to move** — all into `Views/Components/Skeleton/`:

| From | File |
|------|------|
| `Views/Components/` | `InsightsSkeletonComponents.swift` |
| `Views/Components/` | `SkeletonLoadingModifier.swift` |
| `Views/Components/` | `SkeletonView.swift` |

**Step 1: Move files**

```bash
BASE=AIFinanceManager/Views
DEST=$BASE/Components/Skeleton

mv $BASE/Components/InsightsSkeletonComponents.swift $DEST/
mv $BASE/Components/SkeletonLoadingModifier.swift $DEST/
mv $BASE/Components/SkeletonView.swift $DEST/
```

**Step 2: Build check**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: no output

**Step 3: Commit**

```bash
git add -A
git commit -m "refactor: move skeleton components to Components/Skeleton/"
```

---

## Task 11: Clean up empty directories

After all moves, the old `Components/` subdirectory folders inside feature folders should be empty.

**Step 1: Check for empty directories**

```bash
find AIFinanceManager/Views/Insights/Components \
     AIFinanceManager/Views/Transactions/Components \
     AIFinanceManager/Views/Subscriptions/Components \
     -type d 2>/dev/null
```

If these directories exist and are empty, remove them:

```bash
rmdir AIFinanceManager/Views/Insights/Components 2>/dev/null
rmdir AIFinanceManager/Views/Transactions/Components 2>/dev/null
rmdir AIFinanceManager/Views/Subscriptions/Components 2>/dev/null
```

> Note: `rmdir` only removes empty directories — safe to run even if there are remaining files.

**Step 2: Verify what remains in Views/**

```bash
find AIFinanceManager/Views -name "*.swift" | grep "/Components/" | sort
```

Expected: all paths begin with `AIFinanceManager/Views/Components/Cards/`, `.../Rows/`, etc. No paths should contain `Insights/Components/`, `Transactions/Components/`, or `Subscriptions/Components/`.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove empty feature Components/ subdirectories"
```

---

## Task 12: Update CLAUDE.md

Update the project structure section in `CLAUDE.md` to reflect the new `Components/` layout.

**Step 1: Edit CLAUDE.md**

In the `Project Structure` section, replace:

```
├── Components/      # Shared reusable components (no extra nesting)
```

with:

```
├── Components/      # Shared reusable components
│   ├── Cards/       # Standalone card views (AnalyticsCard, TransactionCard, ...)
│   ├── Rows/        # List and form row views (UniversalRow, InfoRow, ...)
│   ├── Forms/       # Form containers (FormSection, EditSheetContainer, ...)
│   ├── Icons/       # Icon display and picking (IconView, IconPickerView)
│   ├── Input/       # Interactive input (AmountInput, CategoryGrid, Carousel, ...)
│   ├── Charts/      # Data visualization (DonutChart, PeriodBarChart, ...)
│   ├── Headers/     # Section headers and hero displays (HeroSection, ...)
│   ├── Feedback/    # Banners, badges, status (MessageBanner, StatusBadge, ...)
│   └── Skeleton/    # Loading states (SkeletonView, SkeletonLoadingModifier)
```

Also remove the `"no extra nesting"` reference in the CLAUDE.md `File Organization Rules` section if it exists.

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Components/ subdirectory structure"
```

---

## Task 13: Final build verification

**Step 1: Full build**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
```

Expected: `BUILD SUCCEEDED`

**Step 2: Run unit tests**

```bash
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIFinanceManagerTests 2>&1 \
  | grep -E "error:|Test Suite.*passed|Test Suite.*failed" | tail -5
```

Expected: `Test Suite 'All tests' passed`

**Step 3: Final commit if any changes remain**

```bash
git status
# If clean: done
# If anything staged: git add -A && git commit -m "chore: final cleanup after components reorganization"
```

---

## Troubleshooting

**Build error: "cannot find type X in scope"**
- Unlikely since `PBXFileSystemSynchronizedRootGroup` auto-discovers files
- If it occurs: verify the file was actually moved (`ls` in destination folder)
- Check Xcode has refreshed: close and reopen Xcode, or run `xcodebuild clean` first

**`rmdir: Directory not empty`**
- A file remains in the feature Components/ folder — check with `ls`
- Add it to the appropriate subfolder in Components/ and move it

**`mv: No such file or directory`**
- File may already have been moved in a previous step — verify with `ls`
