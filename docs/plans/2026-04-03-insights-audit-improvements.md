# Insights Audit Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix logic bugs, remove low-value metrics, improve Health Score accuracy, add severity-based sorting, and consolidate duplicated metrics based on the audit findings.

**Architecture:** All changes are in InsightsService extensions (nonisolated, background-thread safe). No new files needed. Changes are backward-compatible — insight IDs stay stable, UI adapts automatically via existing InsightsCardView/InsightsSectionView.

**Tech Stack:** Swift, InsightsService extensions, InsightModels.swift, InsightsViewModel.swift

---

## Task 1: Fix spendingSpike — Remove Arbitrary avg < 100 Threshold

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Spending.swift` (line ~358)

**Step 1: Fix the threshold logic**

Replace the hardcoded `guard histAvg > 100 else { continue }` with a relative threshold: skip categories where the historical average is less than 1% of total expenses in the window.

```swift
// Before (line 358):
guard histAvg > 100 else { continue }

// After:
// Skip noise: categories < 1% of total spending aren't meaningful spikes
let totalExpensesInWindow = byCategory.values.flatMap { $0 }.reduce(0.0) { $0 + $1.totalExpenses }
guard totalExpensesInWindow > 0 else { continue }
guard histAvg / totalExpensesInWindow > 0.01 else { continue }
```

Note: `totalExpensesInWindow` should be computed ONCE before the loop, not inside the loop. Move it above the `for (catName, records) in byCategory` loop.

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+Spending.swift
git commit -m "fix(insights): replace hardcoded avg<100 threshold in spendingSpike with relative 1% filter"
```

---

## Task 2: Fix accountDormancy — Exclude Deposit Accounts

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Wealth.swift` (generateAccountDormancy function, ~line 163)

**Step 1: Add deposit filter**

After the `guard balance > 0 else { return nil }` line, add:

```swift
// Deposit/savings accounts are expected to be inactive — don't flag them
guard !account.isDeposit else { return nil }
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+Wealth.swift
git commit -m "fix(insights): exclude deposit accounts from accountDormancy detection"
```

---

## Task 3: Fix Health Score — Cash Flow Gradient Instead of Binary

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+HealthScore.swift` (~line 89)

**Step 1: Replace binary cash flow score with gradient**

```swift
// Before (line 89):
let cashflowScore = latestNetFlow > 0 ? 100 : 0

// After: Gradient score based on net flow relative to income
let cashflowScore: Int
if totalIncome > 0 {
    // net flow as % of income: +20% or more = 100, 0% = 50, -20% or worse = 0
    let netFlowRatio = latestNetFlow / totalIncome
    cashflowScore = Int(min(100, max(0, (netFlowRatio + 0.2) / 0.4 * 100)).rounded())
} else {
    cashflowScore = latestNetFlow >= 0 ? 50 : 0
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+HealthScore.swift
git commit -m "fix(insights): replace binary cash flow health score with gradient based on net/income ratio"
```

---

## Task 4: Fix Health Score — Align Emergency Fund Baseline & Budget Adherence

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+HealthScore.swift` (~lines 62, 86)

**Step 1: Change Emergency Fund baseline from 6 to 3 months**

```swift
// Before (line 86):
let emergencyFundScore = Int(min(monthsCovered / 6.0 * 100, 100).rounded())

// After — align with emergencyFund insight (3-month baseline):
let emergencyFundScore = Int(min(monthsCovered / 3.0 * 100, 100).rounded())
```

**Step 2: Fix Budget Adherence — exclude component when no budgets, redistribute weight**

```swift
// Before (lines 60-62):
let budgetAdherenceScore = totalBudgetCount > 0
    ? Int((Double(onBudgetCount) / Double(totalBudgetCount) * 100).rounded())
    : 50 // neutral when no budgets set

// After:
let budgetAdherenceScore = totalBudgetCount > 0
    ? Int((Double(onBudgetCount) / Double(totalBudgetCount) * 100).rounded())
    : -1 // sentinel: no budgets set — exclude from weighted total
```

And update the weighted total calculation:

```swift
// Before:
let total = Double(savingsRateScore)     * 0.30
          + Double(budgetAdherenceScore) * 0.25
          + Double(recurringRatioScore)  * 0.20
          + Double(emergencyFundScore)   * 0.15
          + Double(cashflowScore)        * 0.10
let score = Int(total.rounded())

// After: Redistribute budget weight when no budgets set
let total: Double
if budgetAdherenceScore >= 0 {
    total = Double(savingsRateScore)     * 0.30
          + Double(budgetAdherenceScore) * 0.25
          + Double(recurringRatioScore)  * 0.20
          + Double(emergencyFundScore)   * 0.15
          + Double(cashflowScore)        * 0.10
} else {
    // No budgets — redistribute 25% to other components proportionally
    // savings 30→40, recurring 20→26.7, emergency 15→20, cashflow 10→13.3
    total = Double(savingsRateScore)     * 0.40
          + Double(recurringRatioScore)  * 0.267
          + Double(emergencyFundScore)   * 0.20
          + Double(cashflowScore)        * 0.133
}
let score = Int(total.rounded())
```

Also update the `FinancialHealthScore` return to handle no-budget case:
```swift
budgetAdherenceScore: max(0, min(budgetAdherenceScore, 100)),
// becomes:
budgetAdherenceScore: budgetAdherenceScore >= 0 ? max(0, min(budgetAdherenceScore, 100)) : 0,
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+HealthScore.swift
git commit -m "fix(insights): align emergency fund baseline to 3mo, redistribute health score weights when no budgets"
```

---

## Task 5: Improve duplicateSubscriptions — Rename & Rephrase

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Recurring.swift` (generateDuplicateSubscriptions, ~lines 162-216)

**Step 1: Improve detection logic — keep category-based but rephrase as "similar"**

The category-based detection IS useful (multiple subscriptions in same category worth reviewing), but the naming is misleading. Keep the logic, improve the messaging.

In the category-based path (line ~199), change subtitle to include category names:

```swift
// Before:
subtitle: "\(duplicateCount) \(String(localized: "insights.duplicateSubscriptions.subtitle"))",

// After — show which categories have multiple subscriptions:
let categoryNames = duplicateGroups.keys.prefix(3).joined(separator: ", ")
// subtitle:
subtitle: categoryNames,
```

Remove the cost-based secondary check entirely (the 15% proximity check produces too many false positives). Replace the `guard !duplicateGroups.isEmpty else { ... }` block:

```swift
// Before: secondary check with cost proximity
guard !duplicateGroups.isEmpty else {
    let costs = activeSeries.map { seriesMonthlyEquivalent($0, baseCurrency: baseCurrency) }.sorted()
    var hasSimilarCost = false
    // ... 15% check ...
    guard hasSimilarCost else { return nil }
    // ... return insight
}

// After: just return nil if no category duplicates
guard !duplicateGroups.isEmpty else { return nil }
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+Recurring.swift
git commit -m "fix(insights): remove false-positive cost proximity check from duplicateSubscriptions, show category names"
```

---

## Task 6: Remove incomeSeasonality Metric

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Forecasting.swift` — delete `generateIncomeSeasonality` function and its call
- Modify: `Tenra/Models/InsightModels.swift` — remove `case incomeSeasonality` from InsightType enum

**Step 1: Remove the call in generateForecastingInsights**

In `InsightsService+Forecasting.swift`, find and delete:
```swift
if let seasonality = generateIncomeSeasonality(transactions: snapshot.transactions, baseCurrency: baseCurrency, preAggregated: preAggregated) {
    insights.append(seasonality)
}
```

**Step 2: Delete the generateIncomeSeasonality function**

Delete the entire `private nonisolated func generateIncomeSeasonality(...)` function (~lines 236-291).

**Step 3: Remove the enum case**

In `InsightModels.swift`, delete:
```swift
case incomeSeasonality // historically strongest/weakest income months
```

**Step 4: Grep for any remaining references**

Run: `grep -r "incomeSeasonality" Tenra/ --include="*.swift"`
Fix any remaining references (likely none beyond the deleted code).

**Step 5: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor(insights): remove incomeSeasonality metric (requires 12+ months data, rarely triggers)"
```

---

## Task 7: Merge spendingVelocity into averageDailySpending

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Forecasting.swift` — delete `generateSpendingVelocity` and its call
- Modify: `Tenra/Models/InsightModels.swift` — remove `case spendingVelocity`

**Step 1: Remove the call in generateForecastingInsights**

Delete:
```swift
if let velocity = generateSpendingVelocity(transactions: snapshot.transactions, baseCurrency: baseCurrency, preAggregated: preAggregated) {
    insights.append(velocity)
}
```

**Step 2: Delete the generateSpendingVelocity function**

Delete the entire function (~lines 294-349).

**Step 3: Remove the enum case**

In `InsightModels.swift`, delete:
```swift
case spendingVelocity  // daily spend pace vs last month
```

**Step 4: Grep for remaining references and fix**

Run: `grep -r "spendingVelocity" Tenra/ --include="*.swift"`

**Step 5: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor(insights): remove spendingVelocity (duplicates averageDailySpending with period comparison)"
```

---

## Task 8: Reformulate budgetUnderutilized → "Budget Headroom"

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Budget.swift` (~lines 129-146)

**Step 1: Change metric to show remaining amount instead of count**

Replace the underBudgetItems insight creation:

```swift
// Before:
if !underBudgetItems.isEmpty {
    insights.append(Insight(
        id: "budget_under",
        type: .budgetUnderutilized,
        title: String(localized: "insights.budgetUnder"),
        subtitle: String(format: String(localized: "insights.categoriesUnderBudget"), underBudgetItems.count),
        metric: InsightMetric(
            value: Double(underBudgetItems.count),
            formattedValue: "\(underBudgetItems.count)",
            currency: nil,
            unit: String(localized: "insights.categoriesUnit")
        ),
        trend: nil,
        severity: .positive,
        category: .budget,
        detailData: .budgetProgressList(underBudgetItems.sorted { $0.percentage < $1.percentage })
    ))
}

// After — show total remaining headroom amount:
if !underBudgetItems.isEmpty {
    let totalHeadroom = underBudgetItems.reduce(0.0) { $0 + ($1.budgetAmount - $1.spent) }
    insights.append(Insight(
        id: "budget_under",
        type: .budgetUnderutilized,
        title: String(localized: "insights.budgetHeadroom"),
        subtitle: String(format: String(localized: "insights.categoriesUnderBudget"), underBudgetItems.count),
        metric: InsightMetric(
            value: totalHeadroom,
            formattedValue: Formatting.formatCurrencySmart(totalHeadroom, currency: baseCurrency),
            currency: baseCurrency,
            unit: nil
        ),
        trend: nil,
        severity: .positive,
        category: .budget,
        detailData: .budgetProgressList(underBudgetItems.sorted { $0.percentage < $1.percentage })
    ))
}
```

Note: The `baseCurrency` parameter needs to be available. Check the function signature — `generateBudgetInsights` receives `baseCurrency`. If `BudgetInsightItem` has a `spent` property, use it; if it's named differently (e.g., `currentSpend`), adjust accordingly.

**Step 2: Add localization key**

Add `"insights.budgetHeadroom"` to the Localizable strings (or verify the existing localization file pattern). If localization files aren't directly accessible, use the key and it will display as-is until localized.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+Budget.swift
git commit -m "refactor(insights): reformulate budgetUnderutilized as Budget Headroom showing remaining amount"
```

---

## Task 9: Add Severity-Based Sorting Within Sections

**Files:**
- Modify: `Tenra/ViewModels/InsightsViewModel.swift` (~lines 109-116)

**Step 1: Add sorting to all category computed properties**

```swift
// Before:
var spendingInsights: [Insight]     { insights.filter { $0.category == .spending } }
var incomeInsights: [Insight]       { insights.filter { $0.category == .income } }
// ... etc

// After — sort by severity (critical → warning → neutral → positive):
private func sortedBySeverity(_ items: [Insight]) -> [Insight] {
    items.sorted { lhs, rhs in
        lhs.severity.sortOrder < rhs.severity.sortOrder
    }
}

var spendingInsights: [Insight]     { sortedBySeverity(insights.filter { $0.category == .spending }) }
var incomeInsights: [Insight]       { sortedBySeverity(insights.filter { $0.category == .income }) }
var budgetInsights: [Insight]       { sortedBySeverity(insights.filter { $0.category == .budget }) }
var recurringInsights: [Insight]    { sortedBySeverity(insights.filter { $0.category == .recurring }) }
var cashFlowInsights: [Insight]     { sortedBySeverity(insights.filter { $0.category == .cashFlow }) }
var wealthInsights: [Insight]       { sortedBySeverity(insights.filter { $0.category == .wealth }) }
var savingsInsights: [Insight]      { sortedBySeverity(insights.filter { $0.category == .savings }) }
var forecastingInsights: [Insight]  { sortedBySeverity(insights.filter { $0.category == .forecasting }) }
```

**Step 2: Add sortOrder to InsightSeverity**

In `InsightModels.swift`, add to the `InsightSeverity` enum:

```swift
var sortOrder: Int {
    switch self {
    case .critical: return 0
    case .warning:  return 1
    case .neutral:  return 2
    case .positive: return 3
    }
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```bash
git add Tenra/ViewModels/InsightsViewModel.swift Tenra/Models/InsightModels.swift
git commit -m "feat(insights): sort insights by severity within each section (critical first)"
```

---

## Task 10: Improve projectedBalance — Include Average Non-Recurring Expenses

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+CashFlow.swift` (~lines 117-153, projectedBalance legacy path)
- Also check the period-aware path (~lines 242-289)

**Step 1: Add average non-recurring expenses to projection**

In the legacy path, after computing `recurringNet`:

```swift
// Before:
let projectedBalance = currentBalance + recurringNet

// After — include average non-recurring monthly expenses for more realistic projection:
// Compute average monthly non-recurring expenses from period points (if available)
let avgMonthlyNonRecurring: Double
if periodData.count >= 2 {
    let totalExpenses = periodData.suffix(3).reduce(0.0) { $0 + $1.expenses }
    let months = Double(min(periodData.count, 3))
    avgMonthlyNonRecurring = totalExpenses / months
} else {
    avgMonthlyNonRecurring = 0
}
let projectedBalance = currentBalance + recurringNet - avgMonthlyNonRecurring
```

Note: `periodData` is the same array used for bestMonth/worstMonth earlier in the function. Verify the variable name. The subtitle should also change to indicate it includes typical expenses.

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+CashFlow.swift
git commit -m "feat(insights): include average non-recurring expenses in projectedBalance for realistic projection"
```

---

## Task 11: Remove savingsMomentum Metric

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Savings.swift` — delete `generateSavingsMomentum` and its call
- Modify: `Tenra/Models/InsightModels.swift` — remove `case savingsMomentum`

**Step 1: Remove the call in generateSavingsInsights**

Delete:
```swift
if let momentum = generateSavingsMomentum(transactions: transactions, baseCurrency: baseCurrency, preAggregated: preAggregated) {
    insights.append(momentum)
}
```

**Step 2: Delete the generateSavingsMomentum function**

Delete the entire function (~lines 108-155).

**Step 3: Remove the enum case**

In `InsightModels.swift`, delete:
```swift
case savingsMomentum   // savings rate trend vs 3-month average
```

**Step 4: Grep for remaining references**

Run: `grep -r "savingsMomentum\|savings_momentum\|SavingsMomentum" Tenra/ --include="*.swift"`
Fix any references — likely in InsightsService.swift's `skipSharedGenerators` logic and possibly localization keys.

**Step 5: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor(insights): remove savingsMomentum (duplicates savingsRate trend, noisy with small deltas)"
```

---

## Task 12: Fix categoryTrend — Increase Minimum Streak to 3

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+Spending.swift` (generateCategoryTrend function)

**Step 1: Find the streak threshold check**

Look for the minimum streak check (likely `streak >= 2` or `risingStreak >= 2`). Change to 3:

```swift
// Before:
guard risingStreak >= 2 else { continue }
// or: if streak >= 2 { ... }

// After:
guard risingStreak >= 3 else { continue }
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+Spending.swift
git commit -m "fix(insights): increase categoryTrend minimum streak from 2 to 3 months to reduce false positives"
```

---

## Task 13: Update INSIGHTS_METRICS_REFERENCE.md

**Files:**
- Modify: `docs/INSIGHTS_METRICS_REFERENCE.md`

**Step 1: Update the reference doc**

Update to reflect all changes:
- `spendingSpike`: note relative 1% threshold instead of absolute 100
- `accountDormancy`: note deposit exclusion
- `incomeSeasonality`: mark as REMOVED
- `spendingVelocity`: mark as REMOVED
- `savingsMomentum`: mark as REMOVED
- `budgetUnderutilized`: rename to Budget Headroom, note new metric format
- `categoryTrend`: note 3-month minimum streak
- Health Score: update Cash Flow gradient formula, Emergency Fund 3-month baseline, Budget Adherence redistribution
- Add severity sorting note

**Step 2: Commit**

```bash
git add docs/INSIGHTS_METRICS_REFERENCE.md
git commit -m "docs: update INSIGHTS_METRICS_REFERENCE.md with audit changes"
```

---

## Task 14: Update CLAUDE.md with Changes

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update the InsightsService section**

- Remove references to `incomeSeasonality`, `spendingVelocity`, `savingsMomentum`
- Note severity sorting in InsightsViewModel
- Update Health Score component descriptions
- Note deposit exclusion in accountDormancy

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with insights audit changes"
```

---

## Summary of Changes

| Task | Type | Change |
|------|------|--------|
| 1 | Bug fix | spendingSpike: relative threshold instead of hardcoded 100 |
| 2 | Bug fix | accountDormancy: exclude deposit accounts |
| 3 | Bug fix | Health Score: gradient cash flow instead of binary |
| 4 | Bug fix | Health Score: align emergency fund baseline, redistribute budget weight |
| 5 | Improvement | duplicateSubscriptions: remove cost proximity false positives |
| 6 | Removal | incomeSeasonality: low value, high data requirements |
| 7 | Removal | spendingVelocity: duplicates averageDailySpending |
| 8 | Improvement | budgetUnderutilized → Budget Headroom with amount |
| 9 | Feature | Severity-based sorting within sections |
| 10 | Improvement | projectedBalance: include non-recurring expenses |
| 11 | Removal | savingsMomentum: duplicates savingsRate, noisy |
| 12 | Bug fix | categoryTrend: increase min streak to 3 months |
| 13 | Docs | Update metrics reference |
| 14 | Docs | Update CLAUDE.md |
