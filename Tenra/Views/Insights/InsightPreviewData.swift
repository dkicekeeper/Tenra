//
//  InsightPreviewData.swift
//  Tenra
//
//  Phase 17: Financial Insights Feature
//  Shared mock data used exclusively by #Preview blocks across Insights views.
//  Not shipped in production — all symbols are internal and preview-only.
//

import SwiftUI


// MARK: - Mock Category Breakdown

extension CategoryBreakdownItem {
    static func mockItems() -> [CategoryBreakdownItem] {
        [
            CategoryBreakdownItem(id: "food",     categoryName: "Еда",         amount: 85_000, percentage: 32, color: .orange,  iconSource: .sfSymbol("fork.knife"),         subcategories: []),
            CategoryBreakdownItem(id: "transport",categoryName: "Транспорт",   amount: 52_000, percentage: 20, color: .blue,    iconSource: .sfSymbol("car.fill"),            subcategories: []),
            CategoryBreakdownItem(id: "shopping", categoryName: "Покупки",     amount: 43_000, percentage: 16, color: .pink,    iconSource: .sfSymbol("bag.fill"),            subcategories: []),
            CategoryBreakdownItem(id: "health",   categoryName: "Здоровье",    amount: 35_000, percentage: 13, color: .green,   iconSource: .sfSymbol("heart.fill"),          subcategories: []),
            CategoryBreakdownItem(id: "other",    categoryName: "Другое",      amount: 50_000, percentage: 19, color: .gray,    iconSource: .sfSymbol("ellipsis.circle.fill"), subcategories: [])
        ]
    }
}

// MARK: - Mock Budget Items

extension BudgetInsightItem {
    static func mockItems() -> [BudgetInsightItem] {
        [
            BudgetInsightItem(id: "food",     categoryName: "Еда",       budgetAmount: 80_000,  spent: 85_000,  percentage: 106, isOverBudget: true,  color: .orange, daysRemaining: 0,  projectedSpend: 85_000,  iconSource: .sfSymbol("fork.knife")),
            BudgetInsightItem(id: "shopping", categoryName: "Покупки",   budgetAmount: 60_000,  spent: 43_000,  percentage: 72,  isOverBudget: false, color: .pink,   daysRemaining: 8,  projectedSpend: 58_000,  iconSource: .sfSymbol("bag.fill")),
            BudgetInsightItem(id: "health",   categoryName: "Здоровье",  budgetAmount: 50_000,  spent: 35_000,  percentage: 70,  isOverBudget: false, color: .green,  daysRemaining: 8,  projectedSpend: 44_000,  iconSource: .sfSymbol("heart.fill"))
        ]
    }
}

// MARK: - Mock Recurring Items

extension RecurringInsightItem {
    static func mockItems() -> [RecurringInsightItem] {
        [
            RecurringInsightItem(id: "netflix",  name: "Netflix",     amount: 4_990,   currency: "KZT", frequency: .monthly, kind: .subscription, status: .active, iconSource: .sfSymbol("play.rectangle.fill"),    monthlyEquivalent: 4_990),
            RecurringInsightItem(id: "spotify",  name: "Spotify",     amount: 1_990,   currency: "KZT", frequency: .monthly, kind: .subscription, status: .active, iconSource: .sfSymbol("music.note"),             monthlyEquivalent: 1_990),
            RecurringInsightItem(id: "gym",      name: "Фитнес зал",  amount: 15_000,  currency: "KZT", frequency: .monthly, kind: .generic,      status: .active, iconSource: .sfSymbol("dumbbell.fill"),          monthlyEquivalent: 15_000),
            RecurringInsightItem(id: "salary",   name: "Зарплата",    amount: 450_000, currency: "KZT", frequency: .monthly, kind: .generic,      status: .active, iconSource: .sfSymbol("dollarsign.circle.fill"), monthlyEquivalent: 450_000)
        ]
    }
}

// MARK: - Mock Insights

extension Insight {
    // Spending — top category with chart
    static func mockTopSpending() -> Insight {
        Insight(
            id: "preview_top",
            type: .topSpendingCategory,
            title: "Топ категория",
            subtitle: "Еда",
            metric: InsightMetric(value: 85_000, formattedValue: "85 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .down, changePercent: 32, changeAbsolute: nil, comparisonPeriod: "32% от общих"),
            severity: .warning,
            category: .spending,
            detailData: .categoryBreakdown(CategoryBreakdownItem.mockItems())
        )
    }

    // Month-over-month — no chart
    static func mockMoM() -> Insight {
        Insight(
            id: "preview_mom",
            type: .monthOverMonthChange,
            title: "Месяц к месяцу",
            subtitle: "Расходы",
            metric: InsightMetric(value: 320_000, formattedValue: "320 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 14.3, changeAbsolute: 40_000, comparisonPeriod: "vs прошлый месяц"),
            severity: .warning,
            category: .spending,
            detailData: nil
        )
    }

    // Average daily — no chart
    static func mockAvgDaily() -> Insight {
        Insight(
            id: "preview_avg",
            type: .averageDailySpending,
            title: "Средний день",
            subtitle: "31 день",
            metric: InsightMetric(value: 10_323, formattedValue: "10 323 ₸", currency: "KZT", unit: nil),
            trend: nil,
            severity: .neutral,
            category: .spending,
            detailData: nil
        )
    }

    // Income growth
    static func mockIncomeGrowth() -> Insight {
        Insight(
            id: "preview_income",
            type: .incomeGrowth,
            title: "Рост доходов",
            subtitle: "vs прошлый месяц",
            metric: InsightMetric(value: 530_000, formattedValue: "530 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 7.1, changeAbsolute: 35_000, comparisonPeriod: "vs прошлый месяц"),
            severity: .positive,
            category: .income,
            detailData: nil
        )
    }

    // Budget overspend
    static func mockBudgetOver() -> Insight {
        Insight(
            id: "preview_budget",
            type: .budgetOverspend,
            title: "Превышен бюджет",
            subtitle: "1 категория",
            metric: InsightMetric(value: 1, formattedValue: "1", currency: nil, unit: "категория"),
            trend: nil,
            severity: .critical,
            category: .budget,
            detailData: .budgetProgressList(BudgetInsightItem.mockItems())
        )
    }

    // Recurring total
    static func mockRecurring() -> Insight {
        Insight(
            id: "preview_recurring",
            type: .totalRecurringCost,
            title: "Регулярные платежи",
            subtitle: "3 активных",
            metric: InsightMetric(value: 21_980, formattedValue: "21 980 ₸", currency: "KZT", unit: "/ мес"),
            trend: nil,
            severity: .neutral,
            category: .recurring,
            detailData: .recurringList(RecurringInsightItem.mockItems())
        )
    }

    // Cash flow
    static func mockCashFlow() -> Insight {
        let trend = PeriodDataPoint.mockMonthly()
        return Insight(
            id: "preview_cashflow",
            type: .netCashFlow,
            title: "Чистый поток",
            subtitle: trend.last?.label ?? "Июнь",
            metric: InsightMetric(value: 210_000, formattedValue: "210 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: nil, changeAbsolute: 30_000, comparisonPeriod: "vs среднее"),
            severity: .positive,
            category: .cashFlow,
            detailData: .periodTrend(trend)
        )
    }

    // Projected balance
    static func mockProjectedBalance() -> Insight {
        Insight(
            id: "preview_balance",
            type: .projectedBalance,
            title: "Прогноз баланса",
            subtitle: "Через 30 дней",
            metric: InsightMetric(value: 1_250_000, formattedValue: "1 250 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: nil, changeAbsolute: 21_980, comparisonPeriod: "+21 980 ₸ прогноз"),
            severity: .positive,
            category: .cashFlow,
            detailData: nil
        )
    }

    // Period trend — granularity-aware cash flow
    static func mockPeriodTrend() -> Insight {
        Insight(
            id: "preview_period_trend",
            type: .netCashFlow,
            title: "Денежный поток",
            subtitle: "По месяцам",
            metric: InsightMetric(value: 210_000, formattedValue: "210 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 12.5, changeAbsolute: 23_500, comparisonPeriod: "vs прошлый месяц"),
            severity: .positive,
            category: .cashFlow,
            detailData: .periodTrend(PeriodDataPoint.mockMonthly())
        )
    }

    // Wealth breakdown — per-account balances
    static func mockWealthBreakdown() -> Insight {
        Insight(
            id: "preview_wealth",
            type: .totalWealth,
            title: "Общий капитал",
            subtitle: "3 счёта",
            metric: InsightMetric(value: 2_420_000, formattedValue: "2 420 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 8.4, changeAbsolute: 188_000, comparisonPeriod: "vs прошлый месяц"),
            severity: .positive,
            category: .wealth,
            detailData: .wealthBreakdown(AccountInsightItem.mockItems())
        )
    }

    // Savings rate
    static func mockSavingsRate() -> Insight {
        Insight(
            id: "preview_savings_rate",
            type: .savingsRate,
            title: "Норма сбережений",
            subtitle: "Текущий месяц",
            metric: InsightMetric(value: 39.6, formattedValue: "39.6%", currency: nil, unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 5.2, changeAbsolute: nil, comparisonPeriod: "vs прошлый месяц"),
            severity: .positive,
            category: .savings,
            detailData: nil
        )
    }

    // Spending forecast
    static func mockForecasting() -> Insight {
        Insight(
            id: "preview_forecast",
            type: .spendingForecast,
            title: "Прогноз расходов",
            subtitle: "Следующие 30 дней",
            metric: InsightMetric(value: 295_000, formattedValue: "295 000 ₸", currency: "KZT", unit: nil),
            trend: InsightTrend(direction: .up, changePercent: 7.8, changeAbsolute: 21_400, comparisonPeriod: "vs текущий темп"),
            severity: .warning,
            category: .forecasting,
            detailData: nil
        )
    }
}

// MARK: - Mock Period Data Points (additional granularities)

extension PeriodDataPoint {
    /// 12 weekly data points (rolling ~3 months).
    static func mockWeekly() -> [PeriodDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let incomes:  [Double] = [80_000, 120_000, 95_000, 110_000, 85_000, 130_000, 70_000, 105_000, 90_000, 115_000, 100_000, 125_000]
        let expenses: [Double] = [60_000,  90_000, 70_000,  80_000, 65_000,  95_000, 50_000,  75_000, 68_000,  85_000,  72_000,  88_000]
        var result: [PeriodDataPoint] = []
        for idx in 0..<12 {
            let offset = 11 - idx
            guard let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: now) else { continue }
            let key = InsightGranularity.week.groupingKey(for: date)
            result.append(PeriodDataPoint(
                id: key,
                granularity: .week,
                key: key,
                periodStart: date,
                periodEnd: calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date,
                label: InsightGranularity.week.periodLabel(for: key),
                income: incomes[idx],
                expenses: expenses[idx],
                cumulativeBalance: nil
            ))
        }
        return result
    }

    /// 6 quarterly data points (~1.5 years).
    static func mockQuarterly() -> [PeriodDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let incomes:  [Double] = [1_200_000, 980_000, 1_450_000, 1_100_000, 1_300_000, 1_590_000]
        let expenses: [Double] = [  850_000, 920_000, 1_050_000,   800_000,   950_000,   960_000]
        var result: [PeriodDataPoint] = []
        for idx in 0..<6 {
            let offset = 5 - idx
            guard let date = calendar.date(byAdding: .month, value: -offset * 3, to: now) else { continue }
            let key = InsightGranularity.quarter.groupingKey(for: date)
            result.append(PeriodDataPoint(
                id: key,
                granularity: .quarter,
                key: key,
                periodStart: date,
                periodEnd: calendar.date(byAdding: .month, value: 3, to: date) ?? date,
                label: InsightGranularity.quarter.periodLabel(for: key),
                income: incomes[idx],
                expenses: expenses[idx],
                cumulativeBalance: nil
            ))
        }
        return result
    }

    /// 6 monthly data points with a running `cumulativeBalance` (for wealth charts).
    static func mockMonthlyWealth() -> [PeriodDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        let incomes:  [Double] = [420_000, 385_000, 510_000, 470_000, 495_000, 530_000]
        let expenses: [Double] = [310_000, 340_000, 290_000, 360_000, 280_000, 320_000]
        var cumulative: Double = 800_000
        var result: [PeriodDataPoint] = []
        for idx in 0..<6 {
            let offset = 5 - idx
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let key = InsightGranularity.month.groupingKey(for: date)
            cumulative += incomes[idx] - expenses[idx]
            result.append(PeriodDataPoint(
                id: key,
                granularity: .month,
                key: key,
                periodStart: date,
                periodEnd: calendar.date(byAdding: .month, value: 1, to: date) ?? date,
                label: InsightGranularity.month.periodLabel(for: key),
                income: incomes[idx],
                expenses: expenses[idx],
                cumulativeBalance: cumulative
            ))
        }
        return result
    }
}

// MARK: - Mock FinancialHealthScore
//
// Mock values are realistic snapshots for #Previews. They simulate a
// 6-month data window: `totalIncomeWindow` / `totalExpensesWindow` are
// cumulative across those months, and per-month signals
// (`recurringMonthlyTotal`, `netFlowPercent`) are normalised against
// the window via `avgMonthlyIncome = totalIncomeWindow / monthsInWindow`.

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
            recurringPercentOfIncome: 36.7,
            monthsCovered: 1.8,
            avgMonthlyExpenses: 400_000,
            avgMonthlyNetFlow: 80_000,
            totalBalance: 720_000,
            netFlowPercent: 15.0,
            totalIncomeWindow: 3_600_000,
            totalExpensesWindow: 3_060_000,
            baseCurrency: "KZT",
            isBudgetComponentActive: true,
            monthsInWindow: 6
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
            recurringPercentOfIncome: 58.3,
            monthsCovered: 0.9,
            avgMonthlyExpenses: 580_000,
            avgMonthlyNetFlow: -40_000,
            totalBalance: 520_000,
            netFlowPercent: -8.0,
            totalIncomeWindow: 3_600_000,
            totalExpensesWindow: 3_456_000,
            baseCurrency: "KZT",
            isBudgetComponentActive: true,
            monthsInWindow: 6
        )
    }
}

// MARK: - Mock Account Items

extension AccountInsightItem {
    static func mockItems() -> [AccountInsightItem] {
        [
            AccountInsightItem(id: "kaspi",  accountName: "Kaspi Gold",    currency: "KZT", balance: 1_250_000, transactionCount: 48, lastActivityDate: Date(),  iconSource: .sfSymbol("creditcard.fill")),
            AccountInsightItem(id: "halyk",  accountName: "Halyk Bank",    currency: "KZT", balance: 320_000,   transactionCount: 12, lastActivityDate: Date(),  iconSource: .sfSymbol("building.columns.fill")),
            AccountInsightItem(id: "crypto", accountName: "Crypto Wallet", currency: "USD", balance: 850,       transactionCount: 5,  lastActivityDate: nil,     iconSource: .sfSymbol("bitcoinsign.circle.fill"))
        ]
    }
}
