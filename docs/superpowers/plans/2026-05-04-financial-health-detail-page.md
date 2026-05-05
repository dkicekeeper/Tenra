# Financial Health Detail Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated educational + diagnostic detail screen for the Financial Health score in the Insights tab, fixing the navigation bug where the totals card and the health-score badge currently push the same destination.

**Architecture:** Extend `FinancialHealthScore` with raw values (already computed inside the formula). Add a pure-function `HealthRecommendationBuilder` that maps those raw values to localized recommendation copy. Build three new visual components (Hero, Weighting, ComponentCard) and one new screen (`FinancialHealthDetailView`). Split the shared `NavigationLink` in `InsightsView` into two and delete the obsolete `InsightsSummaryHeader` wrapper.

**Tech Stack:** SwiftUI (iOS 26+, Liquid Glass), Swift 6 patterns under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift Testing (`import Testing`), `.strings`-based localization (en + ru), existing design tokens (`AppSpacing`/`AppTypography`/`AppColors`/`AppAnimation`).

**Spec:** `docs/superpowers/specs/2026-05-04-financial-health-detail-page-design.md`

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `Tenra/Services/Insights/HealthRecommendationBuilder.swift` | Pure functions: `FinancialHealthScore` → localized recommendation copy per component. |
| `Tenra/Views/Components/Cards/HealthScoreHeroCard.swift` | Large progress ring + score number + grade capsule + subtitle. |
| `Tenra/Views/Components/Cards/HealthScoreWeightingCard.swift` | Stacked weight bar + 5- or 4-row legend. |
| `Tenra/Views/Components/Cards/HealthComponentCard.swift` | One component card: header, score contribution, current value/target, progress bar, explainer, recommendation. |
| `Tenra/Views/Insights/FinancialHealthDetailView.swift` | Root screen composing Hero, Weighting, and 5× ComponentCard. |
| `TenraTests/Insights/FinancialHealthScoreTests.swift` | Unit tests for `unavailable()` defaults and raw-field population. |
| `TenraTests/Insights/HealthRecommendationBuilderTests.swift` | Table-driven tests per component × branch. |

### Modified files

| Path | Change |
|---|---|
| `Tenra/Models/InsightModels.swift` | Add raw fields to `FinancialHealthScore`; update `unavailable()`. |
| `Tenra/Services/Insights/InsightsService+HealthScore.swift` | Populate new raw fields in `return`. |
| `Tenra/Views/Insights/InsightPreviewData.swift` | Update `mockGood()` and `mockNeedsAttention()` initialisers with new fields. |
| `Tenra/Views/Insights/InsightsView.swift` | Split shared `NavigationLink`, add `navigationDestination(for: FinancialHealthScore.self)`. |
| `Tenra/en.lproj/Localizable.strings` | Add new keys. |
| `Tenra/ru.lproj/Localizable.strings` | Add new keys. |

### Deleted files

| Path | Reason |
|---|---|
| `Tenra/Views/Components/Headers/InsightsSummaryHeader.swift` | Only wraps `InsightsTotalsCard` + `HealthScoreBadge`; replaced by inline composition in `InsightsView`. Verified zero non-self consumers. |

---

## Build / Test Commands

Use these throughout (copy verbatim — destinations are version-pinned for Xcode 26 beta):

```bash
# Quick build — surface compile errors only
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -30

# Full build (use if grep above is silent — sometimes asset compile is transient)
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run a single test by name
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/FinancialHealthScoreTests

# Run all unit tests
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests
```

---

## Task 1: Extend `FinancialHealthScore` model with raw fields

**Files:**
- Modify: `Tenra/Models/InsightModels.swift:263-289`
- Modify: `Tenra/Views/Insights/InsightPreviewData.swift:323-365`

- [ ] **Step 1: Replace the `FinancialHealthScore` struct with the extended one**

Open `Tenra/Models/InsightModels.swift`, find the `// MARK: - Financial Health Score` block, and replace lines 260–289 entirely with:

```swift
// MARK: - Financial Health Score (Phase 24)

/// A composite 0-100 score summarising the user's financial wellness.
struct FinancialHealthScore {
    let score: Int           // 0-100
    let grade: String        // "Excellent" / "Good" / "Fair" / "Needs Attention"
    let gradeColor: Color

    let savingsRateScore:      Int    // 0-100, weight 0.30
    let budgetAdherenceScore:  Int    // 0-100, weight 0.25
    let recurringRatioScore:   Int    // 0-100, weight 0.20
    let emergencyFundScore:    Int    // 0-100, weight 0.15
    let cashflowScore:         Int    // 0-100, weight 0.10

    // MARK: Raw values (for the detail screen)

    let savingsRatePercent:      Double  // e.g. 12.4
    let budgetsOnTrack:          Int     // e.g. 7
    let budgetsTotal:            Int     // 0 = budget component excluded
    let recurringMonthlyTotal:   Double  // baseCurrency, monthly equivalent
    let recurringPercentOfIncome: Double // e.g. 38.5
    let monthsCovered:           Double  // e.g. 1.8
    let avgMonthlyExpenses:      Double  // baseCurrency
    let avgMonthlyNetFlow:       Double  // baseCurrency, signed
    let totalBalance:            Double  // baseCurrency
    let netFlowPercent:          Double  // e.g. -7.2
    let totalIncomeWindow:       Double  // baseCurrency
    let totalExpensesWindow:     Double  // baseCurrency
    let baseCurrency:            String
    let isBudgetComponentActive: Bool    // mirrors budgetsTotal > 0
}

extension FinancialHealthScore {
    /// Returns a placeholder when there is not enough data to compute a score.
    nonisolated static func unavailable() -> FinancialHealthScore {
        FinancialHealthScore(
            score: 0,
            grade: String(localized: "insights.healthGrade.needsAttention"),
            gradeColor: AppColors.destructive,
            savingsRateScore: 0,
            budgetAdherenceScore: 0,
            recurringRatioScore: 0,
            emergencyFundScore: 0,
            cashflowScore: 0,
            savingsRatePercent: 0,
            budgetsOnTrack: 0,
            budgetsTotal: 0,
            recurringMonthlyTotal: 0,
            recurringPercentOfIncome: 0,
            monthsCovered: 0,
            avgMonthlyExpenses: 0,
            avgMonthlyNetFlow: 0,
            totalBalance: 0,
            netFlowPercent: 0,
            totalIncomeWindow: 0,
            totalExpensesWindow: 0,
            baseCurrency: "",
            isBudgetComponentActive: false
        )
    }
}
```

- [ ] **Step 2: Update both mocks in `InsightPreviewData.swift`**

Open `Tenra/Views/Insights/InsightPreviewData.swift`, replace lines 321–367 entirely with:

```swift
// MARK: - Mock FinancialHealthScore

extension FinancialHealthScore {
    static func mockGood() -> FinancialHealthScore {
        FinancialHealthScore(
            score: 72,
            grade: "Good",
            gradeColor: AppColors.success,
            savingsRateScore: 75,
            budgetAdherenceScore: 80,
            recurringRatioScore: 65,
            emergencyFundScore: 60,
            cashflowScore: 100,
            savingsRatePercent: 15.0,
            budgetsOnTrack: 8,
            budgetsTotal: 10,
            recurringMonthlyTotal: 220_000,
            recurringPercentOfIncome: 35.0,
            monthsCovered: 1.8,
            avgMonthlyExpenses: 400_000,
            avgMonthlyNetFlow: 80_000,
            totalBalance: 720_000,
            netFlowPercent: 13.0,
            totalIncomeWindow: 600_000,
            totalExpensesWindow: 510_000,
            baseCurrency: "KZT",
            isBudgetComponentActive: true
        )
    }

    static func mockNeedsAttention() -> FinancialHealthScore {
        FinancialHealthScore(
            score: 38,
            grade: "Needs Attention",
            gradeColor: AppColors.destructive,
            savingsRateScore: 20,
            budgetAdherenceScore: 40,
            recurringRatioScore: 50,
            emergencyFundScore: 30,
            cashflowScore: 0,
            savingsRatePercent: 4.0,
            budgetsOnTrack: 4,
            budgetsTotal: 10,
            recurringMonthlyTotal: 350_000,
            recurringPercentOfIncome: 58.0,
            monthsCovered: 0.9,
            avgMonthlyExpenses: 580_000,
            avgMonthlyNetFlow: -40_000,
            totalBalance: 520_000,
            netFlowPercent: -8.0,
            totalIncomeWindow: 600_000,
            totalExpensesWindow: 580_000,
            baseCurrency: "KZT",
            isBudgetComponentActive: true
        )
    }
}
```

- [ ] **Step 3: Run quick build to surface call sites that fail to compile**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -30
```

Expected: errors only inside `InsightsService+HealthScore.swift:132-141` (the `FinancialHealthScore(...)` initializer is missing the new fields). The `unavailable()` and the two mocks are already updated. **Do not fix `InsightsService+HealthScore.swift` yet — that is Task 3.**

- [ ] **Step 4: Commit**

```bash
git add Tenra/Models/InsightModels.swift Tenra/Views/Insights/InsightPreviewData.swift
git commit -m "feat(health-score): extend FinancialHealthScore with raw fields

Adds 14 raw-value fields needed by the upcoming Financial Health
detail screen for educational text and contextual recommendations.
Updates unavailable() and both mocks. Service population follows in
the next commit (build is intentionally red between commits).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

The build is **intentionally red** at this point. Task 3 fixes it.

---

## Task 2: Test `unavailable()` initializer defaults

**Files:**
- Create: `TenraTests/Insights/FinancialHealthScoreTests.swift`

- [ ] **Step 1: Create directory if needed**

```bash
mkdir -p TenraTests/Insights
```

- [ ] **Step 2: Write the failing test**

Create `TenraTests/Insights/FinancialHealthScoreTests.swift`:

```swift
//
//  FinancialHealthScoreTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

struct FinancialHealthScoreTests {

    @Test("unavailable() initialises every numeric field to zero")
    func testUnavailableDefaults() {
        let score = FinancialHealthScore.unavailable()

        #expect(score.score == 0)
        #expect(score.savingsRateScore == 0)
        #expect(score.budgetAdherenceScore == 0)
        #expect(score.recurringRatioScore == 0)
        #expect(score.emergencyFundScore == 0)
        #expect(score.cashflowScore == 0)

        #expect(score.savingsRatePercent == 0)
        #expect(score.budgetsOnTrack == 0)
        #expect(score.budgetsTotal == 0)
        #expect(score.recurringMonthlyTotal == 0)
        #expect(score.recurringPercentOfIncome == 0)
        #expect(score.monthsCovered == 0)
        #expect(score.avgMonthlyExpenses == 0)
        #expect(score.avgMonthlyNetFlow == 0)
        #expect(score.totalBalance == 0)
        #expect(score.netFlowPercent == 0)
        #expect(score.totalIncomeWindow == 0)
        #expect(score.totalExpensesWindow == 0)
        #expect(score.baseCurrency == "")
        #expect(score.isBudgetComponentActive == false)
    }
}
```

- [ ] **Step 3: Run the test (skip — build is still red from Task 1)**

The full build won't succeed until Task 3 lands. Skip running the test now — it will be exercised at the end of Task 3.

- [ ] **Step 4: Commit**

```bash
git add TenraTests/Insights/FinancialHealthScoreTests.swift
git commit -m "test(health-score): assert unavailable() defaults

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Populate raw fields in `computeHealthScore`

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService+HealthScore.swift:132-141`

- [ ] **Step 1: Replace the `return FinancialHealthScore(...)` call**

Open `Tenra/Services/Insights/InsightsService+HealthScore.swift`. Replace lines 132–141 (the `return FinancialHealthScore(...)` block) with:

```swift
        let netFlowPercent = totalIncome > 0 ? (latestNetFlow / totalIncome) * 100 : 0

        return FinancialHealthScore(
            score: score,
            grade: grade,
            gradeColor: gradeColor,
            savingsRateScore:     max(0, min(savingsRateScore, 100)),
            budgetAdherenceScore: budgetAdherenceScore >= 0 ? max(0, min(budgetAdherenceScore, 100)) : 0,
            recurringRatioScore:  max(0, min(recurringRatioScore, 100)),
            emergencyFundScore:   max(0, min(emergencyFundScore, 100)),
            cashflowScore:        cashflowScore,
            savingsRatePercent:      savingsRate,
            budgetsOnTrack:          onBudgetCount,
            budgetsTotal:            totalBudgetCount,
            recurringMonthlyTotal:   recurringCost,
            recurringPercentOfIncome: totalIncome > 0 ? (recurringCost / totalIncome) * 100 : 0,
            monthsCovered:           monthsCovered,
            avgMonthlyExpenses:      avgMonthlyExpenses,
            avgMonthlyNetFlow:       last3Months.isEmpty
                                         ? 0
                                         : last3Months.reduce(0.0) { $0 + $1.netFlow } / Double(last3Months.count),
            totalBalance:            totalBalance,
            netFlowPercent:          netFlowPercent,
            totalIncomeWindow:       totalIncome,
            totalExpensesWindow:     totalExpenses,
            baseCurrency:            baseCurrency,
            isBudgetComponentActive: totalBudgetCount > 0
        )
    }
}
```

All values referenced (`savingsRate`, `onBudgetCount`, `totalBudgetCount`, `recurringCost`, `monthsCovered`, `avgMonthlyExpenses`, `last3Months`, `totalBalance`, `latestNetFlow`, `totalIncome`, `totalExpenses`, `baseCurrency`) already exist as locals in the function — no new computation passes are added.

- [ ] **Step 2: Run quick build**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -30
```

Expected: silent (no errors). If errors persist, inspect them and fix; the most likely cause would be a typo in a field name.

- [ ] **Step 3: Run the unavailable() test from Task 2**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/FinancialHealthScoreTests
```

Expected: PASS.

- [ ] **Step 4: Add a smoke test for the populated fields**

Append to `TenraTests/Insights/FinancialHealthScoreTests.swift` (inside the `struct` brace, after the existing test):

```swift
    @Test("computeHealthScore populates raw fields from formula inputs")
    func testComputeHealthScorePopulatesRawFields() {
        let service = InsightsService()
        let score = service.computeHealthScore(
            totalIncome: 600_000,
            totalExpenses: 510_000,
            latestNetFlow: 90_000,
            baseCurrency: "KZT",
            balanceFor: { _ in 240_000 },
            allTransactions: [],
            categories: [],
            recurringSeries: [],
            accounts: [
                Account(id: "a1", name: "A1", currency: "KZT", balance: 240_000)
            ]
        )

        // 600k income, 510k expense → 15% rate
        #expect(abs(score.savingsRatePercent - 15.0) < 0.01)
        #expect(score.totalIncomeWindow == 600_000)
        #expect(score.totalExpensesWindow == 510_000)
        #expect(score.totalBalance == 240_000)
        #expect(score.baseCurrency == "KZT")
        #expect(score.isBudgetComponentActive == false)  // no budgets passed
        #expect(score.budgetsTotal == 0)
        // recurringPercentOfIncome should be 0 with no recurring series
        #expect(score.recurringPercentOfIncome == 0)
    }
```

> **`Account` initializer reference (from `Tenra/Models/Transaction.swift:475`):**
> `init(id:name:currency:iconSource:depositInfo:loanInfo:createdDate:shouldCalculateFromTransactions:initialBalance:balance:order:)` — every parameter except `name` and `currency` has a default. The minimal call above uses `id`, `name`, `currency`, and `balance`.

- [ ] **Step 5: Run the full file's tests**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/FinancialHealthScoreTests
```

Expected: both tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Insights/InsightsService+HealthScore.swift TenraTests/Insights/FinancialHealthScoreTests.swift
git commit -m "feat(health-score): populate raw fields in computeHealthScore

Wires the raw values already computed inside computeHealthScore
through the FinancialHealthScore return type. No formula changes,
no new passes over transactions. Adds a smoke test that locks the
field-wiring shape against future regressions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Add localization keys

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

> **Convention:** Existing health keys live around line 880 in both files (after `// MARK: - Insights`). Append the new keys at the end of the file under a new MARK comment so they're easy to find.

- [ ] **Step 1: Append English keys**

Append to `Tenra/en.lproj/Localizable.strings`:

```
// MARK: - Financial Health Detail Page

"insights.health.subtitle.excellent" = "Excellent shape — your finances are resilient.";
"insights.health.subtitle.good" = "Solid finances with room to optimise.";
"insights.health.subtitle.fair" = "Decent footing, but a few areas need attention.";
"insights.health.subtitle.needsAttention" = "Several aspects of your finances need work.";

"insights.health.unavailable.title" = "Not enough data";
"insights.health.unavailable.message" = "Add income and expense transactions — we'll evaluate your financial health once enough data is available.";

"insights.health.howItWorks" = "How it's computed";
"insights.health.explainer" = "A 0-100 weighted score across five aspects of financial health. Higher means more financial resilience.";
"insights.health.weightLabel" = "%d%%";
"insights.health.weights.redistributed" = "No budgets configured — the 25%% weight is redistributed across the other four components.";

"insights.health.component.savingsRate.title" = "Savings Rate";
"insights.health.component.savingsRate.short" = "Savings";
"insights.health.component.savingsRate.explainer" = "How much of your income you keep. A higher savings rate means more resilience.";

"insights.health.component.budgetAdherence.title" = "Budget Adherence";
"insights.health.component.budgetAdherence.short" = "Budgets";
"insights.health.component.budgetAdherence.explainer" = "How many of your category budgets you stay within this month.";

"insights.health.component.recurringRatio.title" = "Recurring Ratio";
"insights.health.component.recurringRatio.short" = "Recurring";
"insights.health.component.recurringRatio.explainer" = "Share of income locked into subscriptions and recurring payments. Lower means more flexibility.";

"insights.health.component.emergencyFund.title" = "Emergency Fund";
"insights.health.component.emergencyFund.short" = "Emergency";
"insights.health.component.emergencyFund.explainer" = "How many months of expenses your account balances cover.";

"insights.health.component.cashFlow.title" = "Cash Flow";
"insights.health.component.cashFlow.short" = "Cash flow";
"insights.health.component.cashFlow.explainer" = "How much your income exceeds your expenses in the latest period.";

"insights.health.currentValue" = "Current value";
"insights.health.target" = "Target";
"insights.health.scoreContribution" = "%d / 100";

"insights.health.target.savingsRate" = "≥ 20%%";
"insights.health.target.budgetAdherence" = "100%% of categories within budget";
"insights.health.target.recurringRatio" = "< 50%% of income";
"insights.health.target.emergencyFund" = "≥ 3 months";
"insights.health.target.cashFlow" = "≥ 0";

"insights.health.rec.savingsRate.below" = "To reach 20%%, cut expenses by ≈ %@ per month or grow income by ≈ %@ per month.";
"insights.health.rec.savingsRate.healthy" = "Excellent — keep the pace. 20%%+ is the recommended level for long-term resilience.";

"insights.health.rec.budgetAdherence.empty" = "Budgets aren't configured. Set them up on your categories — this component will then count toward the score.";
"insights.health.rec.budgetAdherence.partial" = "%d categories are over budget. Open them to find the source of overspend.";
"insights.health.rec.budgetAdherence.full" = "Every category is within budget — excellent.";

"insights.health.rec.recurringRatio.high" = "Subscriptions and recurring payments are %.0f%% of your income. Aim for under 50%% — review and cancel what you don't need.";
"insights.health.rec.recurringRatio.healthy" = "%.0f%% of your income goes to recurring payments — a healthy level.";

"insights.health.rec.emergencyFund.below" = "You need ≈ %@ more to cover 3 months of expenses.";
"insights.health.rec.emergencyFund.belowWithProjection" = "You need ≈ %@ more to cover 3 months of expenses. At your current saving pace, that's about %.1f months away.";
"insights.health.rec.emergencyFund.healthy" = "%.1f months of expenses on hand — enough cushion for the unexpected.";

"insights.health.rec.cashFlow.negative" = "You're spending more than you earn (−%.1f%% of income this period). Cut expenses or find an additional income source.";
"insights.health.rec.cashFlow.positive" = "Your income exceeds expenses by %.1f%% — a healthy positive flow.";
```

- [ ] **Step 2: Append Russian translations**

Append to `Tenra/ru.lproj/Localizable.strings`:

```
// MARK: - Financial Health Detail Page

"insights.health.subtitle.excellent" = "Отличная форма — финансы устойчивы.";
"insights.health.subtitle.good" = "Хорошее состояние, есть куда оптимизировать.";
"insights.health.subtitle.fair" = "Неплохо, но есть аспекты, требующие внимания.";
"insights.health.subtitle.needsAttention" = "Несколько направлений требуют работы.";

"insights.health.unavailable.title" = "Недостаточно данных";
"insights.health.unavailable.message" = "Добавьте транзакции дохода и расхода — после этого мы сможем оценить ваше финансовое здоровье.";

"insights.health.howItWorks" = "Как считается";
"insights.health.explainer" = "Скор от 0 до 100 — взвешенная оценка пяти аспектов финансового здоровья. Чем выше, тем устойчивее финансы.";
"insights.health.weightLabel" = "%d%%";
"insights.health.weights.redistributed" = "Бюджеты не настроены — вес 25%% перераспределён между четырьмя оставшимися компонентами.";

"insights.health.component.savingsRate.title" = "Норма сбережений";
"insights.health.component.savingsRate.short" = "Сбережения";
"insights.health.component.savingsRate.explainer" = "Какую долю дохода вы откладываете. Чем выше, тем устойчивее финансы.";

"insights.health.component.budgetAdherence.title" = "Соблюдение бюджета";
"insights.health.component.budgetAdherence.short" = "Бюджеты";
"insights.health.component.budgetAdherence.explainer" = "Сколько бюджетов категорий вы выдерживаете в этом месяце.";

"insights.health.component.recurringRatio.title" = "Доля регулярных платежей";
"insights.health.component.recurringRatio.short" = "Регулярные";
"insights.health.component.recurringRatio.explainer" = "Какая часть дохода уходит на подписки и регулярные платежи. Меньше — больше свободы.";

"insights.health.component.emergencyFund.title" = "Финансовая подушка";
"insights.health.component.emergencyFund.short" = "Подушка";
"insights.health.component.emergencyFund.explainer" = "Сколько месяцев расходов покрывают ваши счета.";

"insights.health.component.cashFlow.title" = "Денежный поток";
"insights.health.component.cashFlow.short" = "Поток";
"insights.health.component.cashFlow.explainer" = "Насколько доходы превышают расходы в последнем периоде.";

"insights.health.currentValue" = "Текущее значение";
"insights.health.target" = "Цель";
"insights.health.scoreContribution" = "%d / 100";

"insights.health.target.savingsRate" = "≥ 20%%";
"insights.health.target.budgetAdherence" = "100%% категорий в рамках бюджета";
"insights.health.target.recurringRatio" = "< 50%% дохода";
"insights.health.target.emergencyFund" = "≥ 3 месяцев";
"insights.health.target.cashFlow" = "≥ 0";

"insights.health.rec.savingsRate.below" = "Чтобы выйти на 20%%, сократите расходы на ≈ %@ в месяц или увеличьте доход на ≈ %@ в месяц.";
"insights.health.rec.savingsRate.healthy" = "Отлично — сохраняйте темп. 20%%+ это рекомендованный уровень для долгосрочной устойчивости.";

"insights.health.rec.budgetAdherence.empty" = "Бюджеты не настроены. Установите их в категориях — это включит этот компонент в скор.";
"insights.health.rec.budgetAdherence.partial" = "%d категорий вышли за бюджет. Откройте их, чтобы понять, где перерасход.";
"insights.health.rec.budgetAdherence.full" = "Все категории в рамках бюджета — превосходно.";

"insights.health.rec.recurringRatio.high" = "Подписки и регулярные платежи — %.0f%% дохода. Целевой уровень меньше 50%%. Просмотрите подписки и отмените ненужные.";
"insights.health.rec.recurringRatio.healthy" = "%.0f%% дохода уходит на регулярные платежи — здоровый уровень.";

"insights.health.rec.emergencyFund.below" = "Чтобы покрыть 3 месяца расходов, нужно ещё ≈ %@.";
"insights.health.rec.emergencyFund.belowWithProjection" = "Чтобы покрыть 3 месяца расходов, нужно ещё ≈ %@. При текущей скорости накоплений это около %.1f месяцев.";
"insights.health.rec.emergencyFund.healthy" = "У вас %.1f месяцев расходов на счетах — этого достаточно для непредвиденных ситуаций.";

"insights.health.rec.cashFlow.negative" = "Тратите больше, чем зарабатываете (−%.1f%% от дохода в этом периоде). Сократите расходы или найдите дополнительный источник.";
"insights.health.rec.cashFlow.positive" = "Доход превышает расходы на %.1f%% — здоровый положительный поток.";
```

- [ ] **Step 2.5: Build to verify the .strings parse**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:|warning: .*Localizable" | head -20
```

Expected: no localization parsing errors. The asset compile step also runs — if it surfaces a duplicate-key warning, search the file for the offender and de-duplicate.

- [ ] **Step 3: Commit**

```bash
git add Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "i18n(health-score): add localization keys for detail page

Adds the full set of strings needed by the Financial Health detail
page in English and Russian. Hero subtitles, explainer paragraph,
component titles/explainers/targets, and per-branch recommendation
copy with format placeholders.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `HealthRecommendationBuilder` — Savings Rate

**Files:**
- Create: `Tenra/Services/Insights/HealthRecommendationBuilder.swift`
- Create: `TenraTests/Insights/HealthRecommendationBuilderTests.swift`

- [ ] **Step 1: Create the builder skeleton with the Savings Rate method**

Create `Tenra/Services/Insights/HealthRecommendationBuilder.swift`:

```swift
//
//  HealthRecommendationBuilder.swift
//  Tenra
//
//  Pure functions: FinancialHealthScore raw values → localized recommendation copy.
//  One method per component. No I/O, no actor isolation, easy to unit-test.
//

import Foundation

nonisolated enum HealthRecommendationBuilder {

    // MARK: - Savings Rate

    static func savingsRateRecommendation(_ score: FinancialHealthScore) -> String {
        if score.savingsRatePercent >= 20 {
            return String(localized: "insights.health.rec.savingsRate.healthy")
        }

        let targetIncomeMinusExpense = 0.20 * score.totalIncomeWindow
        let currentDelta = score.totalIncomeWindow - score.totalExpensesWindow
        let gap = max(0, targetIncomeMinusExpense - currentDelta)

        // The user can close the gap by either cutting expenses by `gap` or growing
        // income enough that 20% of the new income equals the new gap. The two
        // amounts are equal in absolute terms when expressed against the same
        // baseline; we present `gap` as both choices for simplicity.
        let cutExpenses = Formatting.formatCurrencySmart(gap, currency: score.baseCurrency)
        let growIncome  = Formatting.formatCurrencySmart(gap / 0.8, currency: score.baseCurrency)

        let format = String(localized: "insights.health.rec.savingsRate.below")
        return String(format: format, cutExpenses, growIncome)
    }
}
```

> **Note on `growIncome`:** Increasing income by `Y` while expenses stay flat moves the savings rate by `Y / (income + Y)` of the new income, set to ≥ 20% → `Y ≥ (gap) / 0.8`. The `0.8` comes from `1 − 0.20`. This matches the recommendation copy.

- [ ] **Step 2: Write the failing tests**

Create `TenraTests/Insights/HealthRecommendationBuilderTests.swift`:

```swift
//
//  HealthRecommendationBuilderTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

struct HealthRecommendationBuilderTests {

    private func make(
        savingsRatePercent: Double = 0,
        budgetsOnTrack: Int = 0,
        budgetsTotal: Int = 0,
        recurringMonthlyTotal: Double = 0,
        recurringPercentOfIncome: Double = 0,
        monthsCovered: Double = 0,
        avgMonthlyExpenses: Double = 0,
        avgMonthlyNetFlow: Double = 0,
        totalBalance: Double = 0,
        netFlowPercent: Double = 0,
        totalIncomeWindow: Double = 0,
        totalExpensesWindow: Double = 0,
        isBudgetComponentActive: Bool = true
    ) -> FinancialHealthScore {
        FinancialHealthScore(
            score: 50, grade: "Fair", gradeColor: .gray,
            savingsRateScore: 50, budgetAdherenceScore: 50, recurringRatioScore: 50,
            emergencyFundScore: 50, cashflowScore: 50,
            savingsRatePercent: savingsRatePercent,
            budgetsOnTrack: budgetsOnTrack,
            budgetsTotal: budgetsTotal,
            recurringMonthlyTotal: recurringMonthlyTotal,
            recurringPercentOfIncome: recurringPercentOfIncome,
            monthsCovered: monthsCovered,
            avgMonthlyExpenses: avgMonthlyExpenses,
            avgMonthlyNetFlow: avgMonthlyNetFlow,
            totalBalance: totalBalance,
            netFlowPercent: netFlowPercent,
            totalIncomeWindow: totalIncomeWindow,
            totalExpensesWindow: totalExpensesWindow,
            baseCurrency: "KZT",
            isBudgetComponentActive: isBudgetComponentActive
        )
    }

    // MARK: - Savings Rate

    @Test("savingsRate ≥ 20% returns healthy copy")
    func testSavingsRateHealthy() {
        let score = make(savingsRatePercent: 25, totalIncomeWindow: 600_000, totalExpensesWindow: 450_000)
        let text = HealthRecommendationBuilder.savingsRateRecommendation(score)
        let expected = String(localized: "insights.health.rec.savingsRate.healthy")
        #expect(text == expected)
    }

    @Test("savingsRate < 20% returns below-target copy with both deltas")
    func testSavingsRateBelow() {
        let score = make(savingsRatePercent: 10, totalIncomeWindow: 600_000, totalExpensesWindow: 540_000)
        let text = HealthRecommendationBuilder.savingsRateRecommendation(score)
        // Must mention currency and not be the healthy string
        #expect(text.contains("KZT") || text.contains("₸"))
        #expect(text != String(localized: "insights.health.rec.savingsRate.healthy"))
    }
}
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/HealthRecommendationBuilderTests
```

Expected: both PASS.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Insights/HealthRecommendationBuilder.swift TenraTests/Insights/HealthRecommendationBuilderTests.swift
git commit -m "feat(health-score): builder + savings rate recommendation

Adds HealthRecommendationBuilder skeleton (nonisolated enum) with
the Savings Rate component. Below-target copy substitutes both
the expense-cut amount and the income-grow amount.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `HealthRecommendationBuilder` — Budget Adherence

**Files:**
- Modify: `Tenra/Services/Insights/HealthRecommendationBuilder.swift`
- Modify: `TenraTests/Insights/HealthRecommendationBuilderTests.swift`

- [ ] **Step 1: Add the `budgetAdherenceRecommendation` method**

Append inside the `HealthRecommendationBuilder` enum, after `savingsRateRecommendation`:

```swift
    // MARK: - Budget Adherence

    static func budgetAdherenceRecommendation(_ score: FinancialHealthScore) -> String {
        if score.budgetsTotal == 0 {
            return String(localized: "insights.health.rec.budgetAdherence.empty")
        }
        let over = score.budgetsTotal - score.budgetsOnTrack
        if over == 0 {
            return String(localized: "insights.health.rec.budgetAdherence.full")
        }
        let format = String(localized: "insights.health.rec.budgetAdherence.partial")
        return String(format: format, over)
    }
```

- [ ] **Step 2: Append failing tests**

Inside `HealthRecommendationBuilderTests` struct, after the savings tests:

```swift
    // MARK: - Budget Adherence

    @Test("budgetAdherence with no budgets returns empty-state copy")
    func testBudgetAdherenceEmpty() {
        let score = make(budgetsOnTrack: 0, budgetsTotal: 0, isBudgetComponentActive: false)
        let text = HealthRecommendationBuilder.budgetAdherenceRecommendation(score)
        #expect(text == String(localized: "insights.health.rec.budgetAdherence.empty"))
    }

    @Test("budgetAdherence all on track returns full copy")
    func testBudgetAdherenceFull() {
        let score = make(budgetsOnTrack: 5, budgetsTotal: 5)
        let text = HealthRecommendationBuilder.budgetAdherenceRecommendation(score)
        #expect(text == String(localized: "insights.health.rec.budgetAdherence.full"))
    }

    @Test("budgetAdherence partial mentions number of over-budget categories")
    func testBudgetAdherencePartial() {
        let score = make(budgetsOnTrack: 3, budgetsTotal: 7)
        let text = HealthRecommendationBuilder.budgetAdherenceRecommendation(score)
        // 7 - 3 = 4 categories over budget
        #expect(text.contains("4"))
    }
```

- [ ] **Step 3: Run and commit**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/HealthRecommendationBuilderTests
```

Expected: PASS. Then:

```bash
git add Tenra/Services/Insights/HealthRecommendationBuilder.swift TenraTests/Insights/HealthRecommendationBuilderTests.swift
git commit -m "feat(health-score): budget adherence recommendation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: `HealthRecommendationBuilder` — Recurring Ratio

**Files:**
- Modify: `Tenra/Services/Insights/HealthRecommendationBuilder.swift`
- Modify: `TenraTests/Insights/HealthRecommendationBuilderTests.swift`

- [ ] **Step 1: Add the method**

Append to the builder enum:

```swift
    // MARK: - Recurring Ratio

    static func recurringRatioRecommendation(_ score: FinancialHealthScore) -> String {
        let key: String = score.recurringPercentOfIncome > 50
            ? "insights.health.rec.recurringRatio.high"
            : "insights.health.rec.recurringRatio.healthy"
        let format = String(localized: String.LocalizationValue(key))
        return String(format: format, score.recurringPercentOfIncome)
    }
```

> **Note:** Both branches share the `%.0f%%` placeholder shape; the format substitutes the same value. This keeps copy parallel between branches.

- [ ] **Step 2: Append tests**

```swift
    // MARK: - Recurring Ratio

    @Test("recurringRatio > 50% returns high-share copy")
    func testRecurringRatioHigh() {
        let score = make(recurringPercentOfIncome: 60)
        let text = HealthRecommendationBuilder.recurringRatioRecommendation(score)
        #expect(text.contains("60"))
        #expect(text != String(format: String(localized: "insights.health.rec.recurringRatio.healthy"), 60.0))
    }

    @Test("recurringRatio ≤ 50% returns healthy copy")
    func testRecurringRatioHealthy() {
        let score = make(recurringPercentOfIncome: 35)
        let text = HealthRecommendationBuilder.recurringRatioRecommendation(score)
        #expect(text.contains("35"))
        // Must NOT match the high-share format (different localization key)
        #expect(text != String(format: String(localized: "insights.health.rec.recurringRatio.high"), 35.0))
    }
```

- [ ] **Step 3: Run and commit**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/HealthRecommendationBuilderTests
```

Expected: PASS.

```bash
git add Tenra/Services/Insights/HealthRecommendationBuilder.swift TenraTests/Insights/HealthRecommendationBuilderTests.swift
git commit -m "feat(health-score): recurring ratio recommendation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: `HealthRecommendationBuilder` — Emergency Fund

**Files:**
- Modify: `Tenra/Services/Insights/HealthRecommendationBuilder.swift`
- Modify: `TenraTests/Insights/HealthRecommendationBuilderTests.swift`

- [ ] **Step 1: Add the method**

Append to the builder enum:

```swift
    // MARK: - Emergency Fund

    static func emergencyFundRecommendation(_ score: FinancialHealthScore) -> String {
        if score.monthsCovered >= 3 {
            let format = String(localized: "insights.health.rec.emergencyFund.healthy")
            return String(format: format, score.monthsCovered)
        }

        let targetBalance = 3.0 * score.avgMonthlyExpenses
        let gap = max(0, targetBalance - score.totalBalance)
        let gapFormatted = Formatting.formatCurrencySmart(gap, currency: score.baseCurrency)

        if score.avgMonthlyNetFlow > 0 {
            let monthsToTarget = gap / score.avgMonthlyNetFlow
            let format = String(localized: "insights.health.rec.emergencyFund.belowWithProjection")
            return String(format: format, gapFormatted, monthsToTarget)
        }

        let format = String(localized: "insights.health.rec.emergencyFund.below")
        return String(format: format, gapFormatted)
    }
```

- [ ] **Step 2: Append tests**

```swift
    // MARK: - Emergency Fund

    @Test("emergencyFund ≥ 3 months returns healthy copy with month count")
    func testEmergencyFundHealthy() {
        let score = make(monthsCovered: 4.5, avgMonthlyExpenses: 100_000, totalBalance: 450_000)
        let text = HealthRecommendationBuilder.emergencyFundRecommendation(score)
        #expect(text.contains("4.5") || text.contains("4,5"))
    }

    @Test("emergencyFund below target with positive net flow shows projection")
    func testEmergencyFundBelowWithProjection() {
        // 3 months target = 300k; balance 100k → gap 200k. Net flow +50k/mo → 4 months.
        let score = make(monthsCovered: 1, avgMonthlyExpenses: 100_000,
                         avgMonthlyNetFlow: 50_000, totalBalance: 100_000)
        let text = HealthRecommendationBuilder.emergencyFundRecommendation(score)
        // The projection clause distinguishes this branch from the plain "below"
        let plainBelow = String(format: String(localized: "insights.health.rec.emergencyFund.below"), "—")
        #expect(text != plainBelow)
        // Must contain "4" (months to target, formatted as %.1f)
        #expect(text.contains("4.0") || text.contains("4,0"))
    }

    @Test("emergencyFund below target with non-positive net flow omits projection")
    func testEmergencyFundBelowNoProjection() {
        let score = make(monthsCovered: 1, avgMonthlyExpenses: 100_000,
                         avgMonthlyNetFlow: -10_000, totalBalance: 100_000)
        let text = HealthRecommendationBuilder.emergencyFundRecommendation(score)
        let projectionFormat = String(localized: "insights.health.rec.emergencyFund.belowWithProjection")
        // Must not contain the projection key's distinctive phrasing
        // (the projection format has TWO arguments; the plain "below" has ONE)
        #expect(!text.contains("at your") && !text.contains("При текущей"))
    }
```

- [ ] **Step 3: Run and commit**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/HealthRecommendationBuilderTests
```

Expected: PASS.

```bash
git add Tenra/Services/Insights/HealthRecommendationBuilder.swift TenraTests/Insights/HealthRecommendationBuilderTests.swift
git commit -m "feat(health-score): emergency fund recommendation

Three branches: healthy (≥3 months), below target with positive
net-flow projection, and below target without (negative net flow).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: `HealthRecommendationBuilder` — Cash Flow

**Files:**
- Modify: `Tenra/Services/Insights/HealthRecommendationBuilder.swift`
- Modify: `TenraTests/Insights/HealthRecommendationBuilderTests.swift`

- [ ] **Step 1: Add the method**

Append to the builder enum:

```swift
    // MARK: - Cash Flow

    static func cashFlowRecommendation(_ score: FinancialHealthScore) -> String {
        if score.netFlowPercent >= 0 {
            let format = String(localized: "insights.health.rec.cashFlow.positive")
            return String(format: format, score.netFlowPercent)
        }
        let format = String(localized: "insights.health.rec.cashFlow.negative")
        return String(format: format, abs(score.netFlowPercent))
    }
```

- [ ] **Step 2: Append tests**

```swift
    // MARK: - Cash Flow

    @Test("cashFlow with positive net flow returns positive copy")
    func testCashFlowPositive() {
        let score = make(netFlowPercent: 12.5)
        let text = HealthRecommendationBuilder.cashFlowRecommendation(score)
        #expect(text.contains("12.5") || text.contains("12,5"))
    }

    @Test("cashFlow with negative net flow returns negative copy with absolute value")
    func testCashFlowNegative() {
        let score = make(netFlowPercent: -8.2)
        let text = HealthRecommendationBuilder.cashFlowRecommendation(score)
        // Format substitutes abs value, so "8.2" should appear (no leading minus)
        #expect(text.contains("8.2") || text.contains("8,2"))
    }
```

- [ ] **Step 3: Run and commit**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/HealthRecommendationBuilderTests
```

Expected: all 11 tests in the suite PASS.

```bash
git add Tenra/Services/Insights/HealthRecommendationBuilder.swift TenraTests/Insights/HealthRecommendationBuilderTests.swift
git commit -m "feat(health-score): cash flow recommendation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: `HealthScoreHeroCard` component

**Files:**
- Create: `Tenra/Views/Components/Cards/HealthScoreHeroCard.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  HealthScoreHeroCard.swift
//  Tenra
//
//  Large hero card on the Financial Health detail screen:
//  progress ring + score + grade capsule + grade-band subtitle.
//

import SwiftUI

struct HealthScoreHeroCard: View {
    let score: FinancialHealthScore
    /// True when the score is meaningful (totalIncomeWindow > 0). When false,
    /// the ring and number are replaced with an "—" placeholder.
    let isAvailable: Bool

    private var ringProgress: Double {
        isAvailable ? Double(score.score) / 100.0 : 0
    }

    private var gradeBandSubtitleKey: String {
        switch score.score {
        case 80...100: return "insights.health.subtitle.excellent"
        case 60..<80:  return "insights.health.subtitle.good"
        case 40..<60:  return "insights.health.subtitle.fair"
        default:       return "insights.health.subtitle.needsAttention"
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .stroke(AppColors.textTertiary.opacity(0.15), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(score.gradeColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(AppAnimation.adaptiveSpring, value: ringProgress)

                VStack(spacing: AppSpacing.xs) {
                    Text(isAvailable ? "\(score.score)" : "—")
                        .font(AppTypography.h1.bold())
                        .foregroundStyle(isAvailable ? score.gradeColor : AppColors.textTertiary)

                    Text(score.grade)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(score.gradeColor)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(score.gradeColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 160, height: 160)

            Text(String(localized: isAvailable
                        ? String.LocalizationValue(gradeBandSubtitleKey)
                        : "insights.health.unavailable.title"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

// MARK: - Previews

#Preview("Good score") {
    HealthScoreHeroCard(score: .mockGood(), isAvailable: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Needs attention") {
    HealthScoreHeroCard(score: .mockNeedsAttention(), isAvailable: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Unavailable") {
    HealthScoreHeroCard(score: .unavailable(), isAvailable: false)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: silent.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Components/Cards/HealthScoreHeroCard.swift
git commit -m "feat(health-score): hero card with progress ring + grade band

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: `HealthScoreWeightingCard` component

**Files:**
- Create: `Tenra/Views/Components/Cards/HealthScoreWeightingCard.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  HealthScoreWeightingCard.swift
//  Tenra
//
//  Educational card explaining the 5-component weighting of the health score.
//  When budgets are absent the bar/legend collapses to 4 segments with
//  redistributed weights.
//

import SwiftUI

struct HealthScoreWeightingCard: View {
    let isBudgetComponentActive: Bool

    private struct Segment: Identifiable {
        let id: String
        let titleKey: String   // "insights.health.component.<name>.short"
        let icon: String
        let color: Color
        let weight: Double     // 0…100, will be summed for normalisation
    }

    private var segments: [Segment] {
        if isBudgetComponentActive {
            return [
                Segment(id: "savingsRate",      titleKey: "insights.health.component.savingsRate.short",      icon: "banknote.fill",                       color: AppColors.success,     weight: 30),
                Segment(id: "budgetAdherence",  titleKey: "insights.health.component.budgetAdherence.short",  icon: "gauge.with.dots.needle.33percent",    color: AppColors.warning,     weight: 25),
                Segment(id: "recurringRatio",   titleKey: "insights.health.component.recurringRatio.short",   icon: "repeat.circle",                       color: AppColors.accent,      weight: 20),
                Segment(id: "emergencyFund",    titleKey: "insights.health.component.emergencyFund.short",    icon: "shield.lefthalf.filled",              color: AppColors.income,      weight: 15),
                Segment(id: "cashFlow",         titleKey: "insights.health.component.cashFlow.short",         icon: "chart.line.uptrend.xyaxis",           color: AppColors.destructive, weight: 10),
            ]
        } else {
            // Redistributed weights from computeHealthScore (40 / 26.7 / 20 / 13.3)
            return [
                Segment(id: "savingsRate",      titleKey: "insights.health.component.savingsRate.short",      icon: "banknote.fill",                       color: AppColors.success,     weight: 40),
                Segment(id: "recurringRatio",   titleKey: "insights.health.component.recurringRatio.short",   icon: "repeat.circle",                       color: AppColors.accent,      weight: 26.7),
                Segment(id: "emergencyFund",    titleKey: "insights.health.component.emergencyFund.short",    icon: "shield.lefthalf.filled",              color: AppColors.income,      weight: 20),
                Segment(id: "cashFlow",         titleKey: "insights.health.component.cashFlow.short",         icon: "chart.line.uptrend.xyaxis",           color: AppColors.destructive, weight: 13.3),
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(String(localized: "insights.health.howItWorks"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.textPrimary)

            Text(String(localized: "insights.health.explainer"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            stackBar
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(spacing: AppSpacing.sm) {
                ForEach(segments) { segment in
                    legendRow(segment)
                }
            }

            if !isBudgetComponentActive {
                Text(String(localized: "insights.health.weights.redistributed"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private var stackBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: proxy.size.width * segment.weight / 100.0)
                }
            }
        }
    }

    private func legendRow(_ segment: Segment) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: segment.icon)
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(segment.color)
                .frame(width: 24)

            Text(String(localized: String.LocalizationValue(segment.titleKey)))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(String(format: String(localized: "insights.health.weightLabel"), Int(segment.weight.rounded())))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

// MARK: - Previews

#Preview("With budgets") {
    HealthScoreWeightingCard(isBudgetComponentActive: true)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Without budgets — 4 segments") {
    HealthScoreWeightingCard(isBudgetComponentActive: false)
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: silent.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Components/Cards/HealthScoreWeightingCard.swift
git commit -m "feat(health-score): weighting card with stacked bar + legend

Five segments by default (30/25/20/15/10). Collapses to four
(40/26.7/20/13.3) when budgets are not configured, with an
explanatory note.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: `HealthComponentCard` component

**Files:**
- Create: `Tenra/Views/Components/Cards/HealthComponentCard.swift`

- [ ] **Step 1: Create the display model + file**

```swift
//
//  HealthComponentCard.swift
//  Tenra
//
//  One component card on the Financial Health detail screen.
//  Header → score contribution → current/target value → progress bar →
//  explainer → contextual recommendation.
//

import SwiftUI

/// Display-side model — value-type, Sendable, no domain coupling beyond the
/// single string it carries for the recommendation.
struct HealthComponentDisplayModel: Identifiable, Sendable {
    let id: String                // stable id, e.g. "savingsRate"
    let titleKey: String          // "insights.health.component.<name>.title"
    let explainerKey: String      // "insights.health.component.<name>.explainer"
    let icon: String              // SF Symbol name
    let color: Color              // tint for icon + bar accents
    let weight: Int               // 30 / 25 / 20 / 15 / 10
    let componentScore: Int       // 0…100
    let currentValueText: String  // pre-formatted, e.g. "12.4%" or "1.8 mo"
    let targetTextKey: String     // "insights.health.target.<name>"
    let progress: Double          // 0…1, normalised to target
    let recommendation: String    // ready-to-render localized copy
    let isMuted: Bool             // true when budgetAdherence is disabled
}

struct HealthComponentCard: View {
    let model: HealthComponentDisplayModel

    private var progressColor: Color {
        switch model.progress {
        case ..<0.33: return AppColors.destructive
        case ..<0.66: return AppColors.warning
        default:      return AppColors.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerRow
            scoreRow
            valueRow
            progressBar
            explainer
            recommendationBox
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .opacity(model.isMuted ? 0.6 : 1.0)
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

            Text(String(format: String(localized: "insights.health.weightLabel"), model.weight))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(AppColors.textSecondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Score

    private var scoreRow: some View {
        Text(String(format: String(localized: "insights.health.scoreContribution"), model.componentScore))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
    }

    // MARK: - Current vs Target

    private var valueRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(String(localized: "insights.health.currentValue"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(model.currentValueText)
                    .font(AppTypography.h2.bold())
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(String(localized: "insights.health.target"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(String(localized: String.LocalizationValue(model.targetTextKey)))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.textTertiary.opacity(0.15))

                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor)
                    .frame(width: proxy.size.width * max(0, min(model.progress, 1)))
            }
        }
        .frame(height: 8)
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

#Preview("Savings — below target") {
    HealthComponentCard(model: HealthComponentDisplayModel(
        id: "savingsRate",
        titleKey: "insights.health.component.savingsRate.title",
        explainerKey: "insights.health.component.savingsRate.explainer",
        icon: "banknote.fill",
        color: AppColors.success,
        weight: 30,
        componentScore: 50,
        currentValueText: "10.0%",
        targetTextKey: "insights.health.target.savingsRate",
        progress: 0.5,
        recommendation: "To reach 20%, cut expenses by ≈ 60 000 ₸/mo or grow income by ≈ 75 000 ₸/mo.",
        isMuted: false
    ))
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Budget — muted (no budgets)") {
    HealthComponentCard(model: HealthComponentDisplayModel(
        id: "budgetAdherence",
        titleKey: "insights.health.component.budgetAdherence.title",
        explainerKey: "insights.health.component.budgetAdherence.explainer",
        icon: "gauge.with.dots.needle.33percent",
        color: AppColors.warning,
        weight: 25,
        componentScore: 0,
        currentValueText: "—",
        targetTextKey: "insights.health.target.budgetAdherence",
        progress: 0,
        recommendation: "Budgets aren't configured. Set them up on your categories — this component will then count toward the score.",
        isMuted: true
    ))
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: silent.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Components/Cards/HealthComponentCard.swift
git commit -m "feat(health-score): per-component card with progress + recommendation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: `FinancialHealthDetailView` root screen

**Files:**
- Create: `Tenra/Views/Insights/FinancialHealthDetailView.swift`

- [ ] **Step 1: Create the screen**

```swift
//
//  FinancialHealthDetailView.swift
//  Tenra
//
//  Educational + diagnostic detail screen for the composite Financial
//  Health score. Hero, weighting explainer, five inline component cards.
//

import SwiftUI

struct FinancialHealthDetailView: View {
    let score: FinancialHealthScore

    private var isAvailable: Bool {
        score.totalIncomeWindow > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                HealthScoreHeroCard(score: score, isAvailable: isAvailable)
                    .screenPadding()

                HealthScoreWeightingCard(isBudgetComponentActive: score.isBudgetComponentActive)
                    .screenPadding()

                if isAvailable {
                    componentsSection
                } else {
                    EmptyStateView(
                        icon: "chart.bar.doc.horizontal",
                        title: String(localized: "insights.health.unavailable.title"),
                        description: String(localized: "insights.health.unavailable.message")
                    )
                    .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle(String(localized: "insights.healthScore"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Components

    private var componentsSection: some View {
        LazyVStack(spacing: AppSpacing.lg) {
            HealthComponentCard(model: makeSavingsRateModel())
            HealthComponentCard(model: makeBudgetAdherenceModel())
            HealthComponentCard(model: makeRecurringRatioModel())
            HealthComponentCard(model: makeEmergencyFundModel())
            HealthComponentCard(model: makeCashFlowModel())
        }
        .screenPadding()
    }

    // MARK: - Component model builders

    private func makeSavingsRateModel() -> HealthComponentDisplayModel {
        HealthComponentDisplayModel(
            id: "savingsRate",
            titleKey: "insights.health.component.savingsRate.title",
            explainerKey: "insights.health.component.savingsRate.explainer",
            icon: "banknote.fill",
            color: AppColors.success,
            weight: 30,
            componentScore: score.savingsRateScore,
            currentValueText: String(format: "%.1f%%", score.savingsRatePercent),
            targetTextKey: "insights.health.target.savingsRate",
            progress: min(max(score.savingsRatePercent, 0) / 20.0, 1),
            recommendation: HealthRecommendationBuilder.savingsRateRecommendation(score),
            isMuted: false
        )
    }

    private func makeBudgetAdherenceModel() -> HealthComponentDisplayModel {
        let muted = !score.isBudgetComponentActive
        let progress: Double = score.budgetsTotal > 0
            ? Double(score.budgetsOnTrack) / Double(score.budgetsTotal)
            : 0
        let valueText = score.budgetsTotal > 0
            ? "\(score.budgetsOnTrack)/\(score.budgetsTotal)"
            : "—"
        return HealthComponentDisplayModel(
            id: "budgetAdherence",
            titleKey: "insights.health.component.budgetAdherence.title",
            explainerKey: "insights.health.component.budgetAdherence.explainer",
            icon: "gauge.with.dots.needle.33percent",
            color: AppColors.warning,
            weight: 25,
            componentScore: score.budgetAdherenceScore,
            currentValueText: valueText,
            targetTextKey: "insights.health.target.budgetAdherence",
            progress: progress,
            recommendation: HealthRecommendationBuilder.budgetAdherenceRecommendation(score),
            isMuted: muted
        )
    }

    private func makeRecurringRatioModel() -> HealthComponentDisplayModel {
        // Bar fills as the recurring share *decreases*. 0% recurring → bar full.
        let progress = max(0, min(1, 1.0 - (score.recurringPercentOfIncome / 100.0)))
        return HealthComponentDisplayModel(
            id: "recurringRatio",
            titleKey: "insights.health.component.recurringRatio.title",
            explainerKey: "insights.health.component.recurringRatio.explainer",
            icon: "repeat.circle",
            color: AppColors.accent,
            weight: 20,
            componentScore: score.recurringRatioScore,
            currentValueText: String(format: "%.0f%%", score.recurringPercentOfIncome),
            targetTextKey: "insights.health.target.recurringRatio",
            progress: progress,
            recommendation: HealthRecommendationBuilder.recurringRatioRecommendation(score),
            isMuted: false
        )
    }

    private func makeEmergencyFundModel() -> HealthComponentDisplayModel {
        let progress = min(max(score.monthsCovered, 0) / 3.0, 1)
        let valueText: String
        if score.avgMonthlyExpenses == 0 {
            valueText = "12+"  // unbounded: cap display
        } else {
            valueText = String(format: "%.1f", score.monthsCovered)
        }
        return HealthComponentDisplayModel(
            id: "emergencyFund",
            titleKey: "insights.health.component.emergencyFund.title",
            explainerKey: "insights.health.component.emergencyFund.explainer",
            icon: "shield.lefthalf.filled",
            color: AppColors.income,
            weight: 15,
            componentScore: score.emergencyFundScore,
            currentValueText: valueText,
            targetTextKey: "insights.health.target.emergencyFund",
            progress: progress,
            recommendation: HealthRecommendationBuilder.emergencyFundRecommendation(score),
            isMuted: false
        )
    }

    private func makeCashFlowModel() -> HealthComponentDisplayModel {
        // Map -20% … +20% → 0 … 1, matching the formula's normalisation.
        let progress = max(0, min(1, (score.netFlowPercent + 20) / 40.0))
        return HealthComponentDisplayModel(
            id: "cashFlow",
            titleKey: "insights.health.component.cashFlow.title",
            explainerKey: "insights.health.component.cashFlow.explainer",
            icon: "chart.line.uptrend.xyaxis",
            color: AppColors.destructive,
            weight: 10,
            componentScore: score.cashflowScore,
            currentValueText: String(format: "%+.1f%%", score.netFlowPercent),
            targetTextKey: "insights.health.target.cashFlow",
            progress: progress,
            recommendation: HealthRecommendationBuilder.cashFlowRecommendation(score),
            isMuted: false
        )
    }
}

// MARK: - Previews

#Preview("Good") {
    NavigationStack {
        FinancialHealthDetailView(score: .mockGood())
    }
}

#Preview("Needs attention") {
    NavigationStack {
        FinancialHealthDetailView(score: .mockNeedsAttention())
    }
}

#Preview("Unavailable") {
    NavigationStack {
        FinancialHealthDetailView(score: .unavailable())
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: silent.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Insights/FinancialHealthDetailView.swift
git commit -m "feat(health-score): financial health detail screen

Composes hero, weighting explainer, and five inline component
cards. Builds HealthComponentDisplayModels per component using
the per-component progress normalisation defined in the spec
and the localized recommendations from HealthRecommendationBuilder.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Wire navigation in `InsightsView`, delete `InsightsSummaryHeader`

**Files:**
- Modify: `Tenra/Views/Insights/InsightsView.swift:42-46, 117-139`
- Delete: `Tenra/Views/Components/Headers/InsightsSummaryHeader.swift`

- [ ] **Step 1: Confirm `InsightsSummaryHeader` has no other consumers**

```bash
grep -rn "InsightsSummaryHeader" Tenra --include="*.swift" | grep -v "/InsightsSummaryHeader.swift"
```

Expected: a single line referring to `InsightsView.swift` plus historical comment headers (in `InsightsTotalsCard.swift` and `HealthScoreBadge.swift`). Comment-header references are fine; only check that no live code outside `InsightsView` references the type.

If anything live appears, **stop and report** — the spec verified zero non-self consumers, and a new one would invalidate the deletion plan.

- [ ] **Step 2: Replace `insightsSummaryHeaderSection` and the navigation destinations in `InsightsView`**

Open `Tenra/Views/Insights/InsightsView.swift`. Replace the body of `insightsSummaryHeaderSection` (lines 117–139) with two separate `NavigationLink`s:

```swift
    // MARK: - Summary Header Section

    private var insightsSummaryHeaderSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            NavigationLink(destination: InsightsSummaryDetailView(
                totalIncome: insightsViewModel.totalIncome,
                totalExpenses: insightsViewModel.totalExpenses,
                netFlow: insightsViewModel.netFlow,
                currency: insightsViewModel.baseCurrency,
                periodDataPoints: insightsViewModel.periodDataPoints,
                granularity: insightsViewModel.currentGranularity
            )) {
                InsightsTotalsCard(
                    income: insightsViewModel.totalIncome,
                    expenses: insightsViewModel.totalExpenses,
                    netFlow: insightsViewModel.netFlow,
                    currency: insightsViewModel.baseCurrency
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

- [ ] **Step 3: Delete `InsightsSummaryHeader.swift`**

```bash
git rm Tenra/Views/Components/Headers/InsightsSummaryHeader.swift
```

- [ ] **Step 4: Build**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \
  | grep -E "error:" | head -20
```

Expected: silent. If errors mention an unrelated `InsightsSummaryHeader` reference (e.g. an outdated comment in another file's #Preview), confirm it's a comment, leave it.

- [ ] **Step 5: Run all unit tests**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests
```

Expected: all PASS, including the new `FinancialHealthScoreTests` and `HealthRecommendationBuilderTests`.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Views/Insights/InsightsView.swift
git commit -m "fix(insights): split shared NavigationLink, route health-score badge to its own detail screen

The totals card and the health-score badge previously shared one
NavigationLink that pushed InsightsSummaryDetailView. Tapping the
health badge now opens the new FinancialHealthDetailView.

Removes the now-obsolete InsightsSummaryHeader wrapper — its only
production consumer was InsightsView itself.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Manual verification on simulator

No code changes. This task is a verification gate — do not skip.

- [ ] **Step 1: Build & launch on iPhone 17 Pro simulator**

Open `Tenra.xcodeproj` in Xcode, select **iPhone 17 Pro** (iOS 26.2) destination, press **Cmd-R**.

- [ ] **Step 2: Navigate to the Insights tab**

Verify that:
- The totals card and the health-score badge render normally.
- Tapping the **totals card** pushes `InsightsSummaryDetailView` with the cash-flow chart (existing behaviour, unchanged).
- Back, then tap the **health-score badge** → pushes `FinancialHealthDetailView`.

- [ ] **Step 3: Verify all four sections of the detail screen**

- Hero: progress ring + score number + grade capsule + grade-band subtitle.
- Explainer: stacked weight bar + legend (5 segments if you have at least one budget configured, otherwise 4).
- Five (or four) component cards in order: Savings Rate, Budget Adherence (if active), Recurring Ratio, Emergency Fund, Cash Flow. Each shows current value, target, progress bar, explainer, and a contextual recommendation.

- [ ] **Step 4: Edge-case spot checks**

If your dataset allows, verify:
- **No budgets** (delete all category budgets in Settings or use a fresh seed): Budget Adherence card renders muted, weighting card shows 4 segments + redistribution note.
- **All-time totalIncome == 0** (impossible if you've been using the app, but seed a fresh user to verify): the components section is replaced by the empty-state view.
- **Toggle dark mode** in iOS Settings → Display: contrast on grade capsules, recommendation tinted boxes, and the progress ring is acceptable.
- **Reduce Motion**: progress ring snaps to its target instead of springing.

- [ ] **Step 5: Mark task complete**

No commit. Manual verification is the gate; this plan ends here.

---

## Wrap-up

After Task 15:

```bash
git log --oneline -16
```

You should see 14 commits added on top of `08fa947` (the spec) — Tasks 1–14, each its own commit. Total LOC added is roughly:

| Layer | Files | LOC |
|---|---|---|
| Model | 1 modified | +35 |
| Service | 1 modified | +15 |
| Builder | 1 new | +90 |
| Views | 4 new | +600 |
| Localization | 2 modified | +90 |
| Tests | 2 new | +250 |
| Navigation | 1 modified, 1 deleted | +30 / -90 |

This is the full implementation. No follow-up plan is required for this scope. The audit appendix in the spec captures the next iteration (extending detail screens for the 6 other duplicate-detail insight types) as a separate, independent project.
