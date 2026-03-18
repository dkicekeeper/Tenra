# Insights: Full Intelligence Suite — Design Document

**Date:** 2026-02-22
**Author:** Claude (Sonnet 4.6)
**Status:** Design approved, pending implementation plan
**Approach:** Phased expansion — Savings + Forecasting categories + stub implementations + Health Score + Behavioral

---

## Context

The current Insights module delivers 13 active cards across 6 categories (spending, income, budget, recurring, cashFlow, wealth). The system is well-optimized (Phase 22-23) with O(M) CoreData aggregate lookups and lazy, pre-computed granularity caching.

**Key Gap:** 8 InsightType cases are already defined in the enum (`spendingSpike`, `worstMonth`, `accountActivity`, `subscriptionGrowth`, `wealthGrowth`, `incomeSourceBreakdown`, `categoryTrend`, `subcategoryBreakdown`) but **never generated** by InsightsService — immediate low-risk wins.

**Goal:** Expand from 13 → ~31 insight cards, 6 → 8 categories, adding actionable financial intelligence aligned with best practices from YNAB, Copilot, and Monarch Money.

---

## Current Insights — Mechanics Reference

### Category: spending (3 cards)

| Card | Mechanic | Data Source | Severity Logic |
|------|----------|-------------|----------------|
| **Top Spending Category** | `CategoryAggregateService.fetchRange()` O(M) → sort desc → top 1 + top 5 subcategories | CategoryAggregateService (Phase 22 fast path) | warning if top cat > 50% of total |
| **MoM Spending Change** | Single O(N) pass: thisMonthExpenses vs prevMonthExpenses → changePercent | Transaction scan | warning if ↑>20%; positive if ↓>10% |
| **Average Daily Spending** | totalExpenses ÷ daysInRange | Period summary | neutral always |

### Category: income (2 cards)

| Card | Mechanic | Data Source | Severity Logic |
|------|----------|-------------|----------------|
| **Income Growth** | thisMonthIncome vs prevMonthIncome → growth% | MonthlyAggregateService | positive if ↑>10%; warning if ↓>10% |
| **Income vs Expense Ratio** | totalIncome ÷ totalExpenses | Period summary | positive ≥1.5x; neutral ≥1.0x; critical <1.0x |

### Category: budget (3 cards)

| Card | Mechanic | Data Source | Severity Logic |
|------|----------|-------------|----------------|
| **Budget Overspend** | BudgetSpendingCacheService O(1) → filter spent > budget | BudgetSpendingCacheService | critical |
| **Projected Overspend** | dailyBurnRate = spent÷daysElapsed; projected = burnRate×totalDays → filter > budget | Cache + calendar | warning |
| **Budget Underutilized** | filter (spent÷budget) < 0.8 AND daysRemaining < 7 | Cache + calendar | positive |

### Category: recurring (1 card)

| Card | Mechanic | Data Source | Severity Logic |
|------|----------|-------------|----------------|
| **Total Recurring Cost** | activeSeries → monthlyEquivalent (currency converted via CurrencyConverter.convertSync) → sum | RecurringRepository | neutral |

### Category: cashFlow (3 cards)

| Card | Mechanic | Data Source | Severity Logic |
|------|----------|-------------|----------------|
| **Net Cash Flow** | MonthlyAggregateService.fetchLast(12) → latestNetFlow vs 12mo avg | MonthlyAggregateService O(M) | positive >0; critical <0 |
| **Best Month** | max(netFlow) from fetchLast(12) | MonthlyAggregateService | positive |
| **Projected Balance** | currentBalance + (recurringIncome − recurringExpenses) × daysRemaining÷30 | Account balances + recurring | positive >0; critical <0 |

### Category: wealth (1 card)

| Card | Mechanic | Data Source | Severity Logic |
|------|----------|-------------|----------------|
| **Total Wealth** | sum(accountBalances MainActor snapshot) + MoP netFlow delta | TransactionStore.accounts | positive >0; critical <0 |

---

## New Insights — Full Specification

### Phase 1: Stub Implementations + Savings Category

**Target:** +8 new cards, +1 category (savings)

#### Spending additions (2 new)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `spendingSpike` | **Spending Spike** | For each category: compute mean+stddev daily spend over 90d. If current month daily avg > mean + 2σ → spike. Show: category name, current vs expected. | `CategoryAggregateService.fetchRange(last90d)` | warning |
| `categoryTrend` | **Category Trend** | Top spending category over 6 months → compute month-over-month delta sequence → if 3+ consecutive increases → "rising for N months". Metric: last delta% | `MonthlyAggregateService.fetchLast(6)` per category | warning if rising; positive if falling |

**Detail data:** `periodTrend` — 6 `PeriodDataPoint` showing category spend per month

#### cashFlow additions (1 new)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `worstMonth` | **Worst Month** | min(netFlow) from last 12 months. Complements Best Month. Shows: month label + amount | `MonthlyAggregateService.fetchLast(12)` | warning if recent (last 3mo); neutral if historical |

#### recurring additions (1 new)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `subscriptionGrowth` | **Subscription Growth** | currentMonthRecurringCost vs cost 3 months ago → delta%. If >10% → "subscriptions grew by X%" | `RecurringRepository.activeSeries` snapshot × 2 time points | warning if ↑>10%; positive if ↓>10% |

#### wealth additions (1 new)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `wealthGrowth` | **Wealth Growth** | currentWealth vs wealth at start of current period (from cumulativeBalance in PeriodDataPoint) → delta% | `PeriodDataPoint.cumulativeBalance` array | positive if growing; critical if declining |

#### NEW category: savings (3 new cards)

New `InsightCategory.savings` with SF Symbol `"banknote.fill"`.

| InsightType | Title | Mechanic | Benchmark | Severity |
|-------------|-------|----------|-----------|----------|
| `savingsRate` | **Savings Rate** | `(totalIncome − totalExpenses) / totalIncome × 100`. Shows: rate%, absolute saved amount, trend vs last 3 months | Period summary | critical <10%; warning 10-20%; positive >20% |
| `emergencyFund` | **Emergency Fund** | `sum(allAccountBalances) / avgMonthlyExpenses(last3mo)`. Shows: months covered, current balance, target balance (3mo expenses) | avg from MonthlyAggregateService + account snapshots | critical <1 month; warning 1-3 months; positive ≥3 months |
| `savingsMomentum` | **Savings Momentum** | thisMonthSavingsRate vs avg(last3mo savingsRate) → delta. "You're saving 5% more than your 3-month average" | MonthlyAggregateService.fetchLast(4) → compute per-month savingsRate | positive if ↑>2%; warning if ↓>2%; neutral otherwise |

**Detail data for savings:** `monthlyTrend` — 3-month history of savings rates as `MonthlyDataPoint`

---

### Phase 2: Forecasting Category + YoY + Expand Spending/Income

**Target:** +7 new cards, +1 category (forecasting)

#### NEW category: forecasting (4 new cards)

New `InsightCategory.forecasting` with SF Symbol `"chart.line.uptrend.xyaxis.circle"`.

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `spendingForecast` | **30-Day Spending Forecast** | `avgDailySpending(last30d) × daysLeftInMonth + sum(recurringExpenses.remaining this month)`. Compares to current income | CategoryAggregateService last 30d + RecurringRepository | warning if forecast > income; neutral otherwise |
| `balanceRunway` | **Balance Runway** | If avgMonthlyNetExpenses < 0: `currentBalance ÷ abs(avgMonthlyNetExpenses)` → "Your balance will last X months". If positive net: "You're building savings at X/month" | Account balances + MonthlyAggregateService.fetchLast(3) | critical <1mo; warning 1-3mo; positive >3mo |
| `yearOverYear` | **Year-over-Year** | thisMonth expenses vs sameMonthLastYear expenses → delta%. "February spending is 15% lower than last year" | `MonthlyAggregateService.fetchRange(lastYear.thisMonth, today)` — 2 specific records | positive if ↓; warning if ↑>15%; neutral otherwise |
| `incomeSeasonality` | **Income Seasonality** | All-time monthly aggregates → group by month number (1-12) → find max/min month. "Historically, your income peaks in December (+40% above average)" | MonthlyAggregateService all records grouped by calendar month | neutral (informational) |

**Detail data for forecasting:** `periodTrend` showing historical vs projected values.

#### Income additions (1 new)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `incomeSourceBreakdown` | **Income Sources** | Group income transactions by expense category (Salary, Freelance, Investments, Other) → distribution %. "Salary 80%, Freelance 15%, Other 5%" | `CategoryAggregateService.fetchRange()` income side | neutral (informational) |

**Detail data:** `categoryBreakdown` with income categories.

#### Spending additions (2 new in Phase 2)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `spendingVelocity` | **Spending Velocity** | `spentSoFar ÷ daysElapsed` vs `lastMonthTotal ÷ lastMonthDays` → ratio. "You're spending 40% faster than usual. At this rate, you'll spend 140% of last month's total" | CategoryAggregateService current period + MonthlyAggregateService.fetchLast(1) | warning if ratio > 1.2; positive if < 0.9 |
| `subcategoryBreakdown` | **Top Subcategories** | For the top spending category: expand subcategory breakdown into a standalone card (currently embedded in topSpendingCategory). Standalone card allows deeper drill-down | CategoryAggregateService + CategoryRepository.subcategories | warning/neutral based on parent category severity |

---

### Phase 3: Financial Health Score + Behavioral

**Target:** +3 insights/widgets, no new categories

#### Financial Health Score

Displayed in `InsightsSummaryHeader` as a prominent score alongside income/expenses/net.

**Composite score (0-100):**

```
Score = Σ(component × weight)

Components:
  savingsRate      = min(rate / 20 × 100, 100)  × 0.30  // 20% savings = 100pts
  budgetAdherence  = (onBudgetCount / totalCount) × 100  × 0.25
  recurringRatio   = (1 - recurringCost / totalIncome) × 100  × 0.20  // lower recurring = better
  emergencyFund    = min(monthsCovered / 6 × 100, 100)  × 0.15  // 6 months = 100pts
  cashflowTrend    = netFlow > 0 ? 100 : 0                        × 0.10
```

**Grade display:**
- 80-100: "Excellent" (green)
- 60-79:  "Good" (blue)
- 40-59:  "Fair" (orange)
- 0-39:   "Needs Attention" (red)

**Architecture:** New `FinancialHealthScore` struct in `InsightModels.swift`. Computed in `InsightsService.computeHealthScore()`. Stored in `InsightsViewModel.healthScore`. Displayed in `InsightsSummaryHeader` alongside existing totals.

#### Behavioral insights (2 new, extend spending)

| InsightType | Title | Mechanic | Data Source | Severity |
|-------------|-------|----------|-------------|----------|
| `duplicateSubscriptions` | **Possible Duplicate Subscriptions** | Group recurring series by category → find pairs where: (1) names have Levenshtein distance ≤ 3, OR (2) amount delta < 10% AND same category. "You may have 2 streaming subscriptions" | RecurringRepository.activeSeries | warning |
| `accountDormancy` | **Dormant Account** | Accounts with 0 transactions in last 30 days AND balance > 0 → "Account X has been inactive for Y days with Z balance sitting idle" | TransactionStore.transactions filtered by account + account balances | neutral/warning |

---

## Architecture Changes

### InsightModels.swift

```swift
// Extend InsightType (add new cases)
enum InsightType: String {
    // Existing stubs to implement:
    case spendingSpike      // Phase 1
    case categoryTrend      // Phase 1
    case worstMonth         // Phase 1
    case subscriptionGrowth // Phase 1
    case wealthGrowth       // Phase 1
    case incomeSourceBreakdown // Phase 2
    case subcategoryBreakdown  // Phase 2

    // New types:
    case savingsRate        // Phase 1
    case emergencyFund      // Phase 1
    case savingsMomentum    // Phase 1
    case spendingForecast   // Phase 2
    case balanceRunway      // Phase 2
    case yearOverYear       // Phase 2
    case incomeSeasonality  // Phase 2
    case spendingVelocity   // Phase 2
    case financialHealthScore // Phase 3 (summary widget, not a card)
    case duplicateSubscriptions // Phase 3
    case accountDormancy    // Phase 3
}

// Extend InsightCategory
enum InsightCategory: String, CaseIterable {
    case spending, income, budget, recurring, cashFlow, wealth
    case savings      // NEW Phase 1
    case forecasting  // NEW Phase 2
}

// New struct for Phase 3
struct FinancialHealthScore {
    let score: Int           // 0-100
    let grade: String        // "Excellent", "Good", "Fair", "Needs Attention"
    let color: Color
    let components: [HealthScoreComponent]
}

struct HealthScoreComponent {
    let name: String
    let score: Int
    let weight: Double
    let formattedValue: String
}
```

### InsightsService.swift

New private methods to add:
```swift
// Phase 1
private func generateSavingsInsights(...) -> [Insight]
private func generateSpendingSpike(...) -> Insight?
private func generateCategoryTrend(...) -> Insight?
private func generateWorstMonth(...) -> Insight?
private func generateSubscriptionGrowth(...) -> Insight?
private func generateWealthGrowth(...) -> Insight?

// Phase 2
private func generateForecastingInsights(...) -> [Insight]
private func generateIncomeSourceBreakdown(...) -> Insight?
private func generateSpendingVelocity(...) -> Insight?

// Phase 3
func computeHealthScore(...) -> FinancialHealthScore
private func generateBehavioralInsights(...) -> [Insight]
```

### InsightsViewModel.swift

```swift
// New computed properties
var savingsInsights: [Insight] { insights.filter { $0.category == .savings } }
var forecastingInsights: [Insight] { insights.filter { $0.category == .forecasting } }
private(set) var healthScore: FinancialHealthScore? = nil
```

### InsightsView.swift

Two new `InsightsSectionView` blocks added to the scroll view:
```swift
InsightsSectionView(category: .savings, insights: savingsInsights, ...)
InsightsSectionView(category: .forecasting, insights: forecastingInsights, ...)
```

`InsightsSummaryHeader` updated to show `FinancialHealthScore` (Phase 3).

### No new CoreData entities needed

All computations use existing services:
- `CategoryAggregateService` (Phase 22) — category spending by period
- `MonthlyAggregateService` (Phase 22) — income/expense by month
- `BudgetSpendingCacheService` (Phase 22) — cached budget progress
- `RecurringRepository` — active recurring series
- Account balances via `TransactionStore.accounts`

---

## Implementation Phases

### Phase 1 (Priority: High)
Files to modify:
- `AIFinanceManager/Models/InsightModels.swift` — add InsightType cases + FinancialHealthScore struct skeleton
- `AIFinanceManager/Services/Insights/InsightsService.swift` — implement 5 stub generators + generateSavingsInsights()
- `AIFinanceManager/ViewModels/InsightsViewModel.swift` — add savingsInsights computed property
- `AIFinanceManager/Views/Insights/InsightsView.swift` — add savings section

### Phase 2 (Priority: Medium)
Files to modify:
- `AIFinanceManager/Models/InsightModels.swift` — add forecasting InsightType cases
- `AIFinanceManager/Services/Insights/InsightsService.swift` — implement generateForecastingInsights() + income source breakdown + velocity
- `AIFinanceManager/ViewModels/InsightsViewModel.swift` — add forecastingInsights property
- `AIFinanceManager/Views/Insights/InsightsView.swift` — add forecasting section

### Phase 3 (Priority: Normal)
Files to modify:
- `AIFinanceManager/Models/InsightModels.swift` — FinancialHealthScore struct
- `AIFinanceManager/Services/Insights/InsightsService.swift` — computeHealthScore() + behavioral generators
- `AIFinanceManager/ViewModels/InsightsViewModel.swift` — healthScore property
- `AIFinanceManager/Views/Insights/Components/InsightsSummaryHeader.swift` — add health score display

---

## Verification

After each phase:
1. Build: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
2. Run unit tests: `xcodebuild test -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:AIFinanceManagerTests`
3. Manual verification in simulator:
   - Open Insights tab → confirm new sections appear
   - Check granularity picker works with new categories
   - Verify severity colors match spec (green/blue/orange/red)
   - Test with empty data state (no transactions)
   - Test savings insights with accounts that have zero balance
   - Test forecasting with only 1 month of data (edge case)
4. Check InsightsCache invalidation triggers correctly on new transaction add

---

## Summary: Before vs After

| Metric | Before | After (All Phases) |
|--------|--------|--------------------|
| Insight cards | 13 | ~31 |
| Categories | 6 | 8 |
| Stub types implemented | 0 of 8 | 8 of 8 |
| New service methods | 0 | ~12 |
| New CoreData entities | — | 0 (reuse Phase 22) |
| Financial Health Score | ✗ | ✓ |
| Savings tracking | ✗ | ✓ |
| Forecasting | ✗ | ✓ |
| Behavioral detection | ✗ | ✓ |
