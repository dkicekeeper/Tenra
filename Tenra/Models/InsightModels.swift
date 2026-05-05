//
//  InsightModels.swift
//  Tenra
//
//  Phase 17: Financial Insights Feature
//  Data models for smart financial insights and analytics
//

import SwiftUI

// MARK: - Core Insight Model

/// Represents a single actionable financial insight
struct Insight: Identifiable, Hashable {
    let id: String
    let type: InsightType
    let title: String
    let subtitle: String
    let metric: InsightMetric
    let trend: InsightTrend?
    let severity: InsightSeverity
    let category: InsightCategory
    let detailData: InsightDetailData?

    // Custom Hashable/Equatable: hash and compare by id only.
    // detailData contains Color values which are not Hashable.
    static func == (lhs: Insight, rhs: Insight) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Insight Type

enum InsightType: String, Hashable {
    case topSpendingCategory
    case spendingSpike
    case monthOverMonthChange
    case averageDailySpending
    case incomeGrowth
    case incomeSourceBreakdown
    case incomeVsExpenseRatio
    case budgetOverspend
    case budgetUnderutilized
    case projectedOverspend
    case categoryTrend
    case subcategoryBreakdown
    case totalRecurringCost
    case subscriptionGrowth
    case netCashFlow
    case bestMonth
    case worstMonth
    case projectedBalance
    case accountActivity
    case totalWealth      // Current sum of all account balances
    case wealthGrowth     // Monthly/period growth of accumulated balance
    case savingsRate       // (income - expenses) / income %
    case emergencyFund     // months of expenses covered by balance
    case spendingForecast  // projected 30-day spend
    case balanceRunway     // months until balance runs out at current burn
    case yearOverYear      // this month vs same month last year
    case duplicateSubscriptions // possible duplicate recurring items
    case accountDormancy        // accounts idle 30+ days with non-zero balance
}

// MARK: - Insight Metric

struct InsightMetric: Hashable {
    let value: Double
    let formattedValue: String
    let currency: String?
    let unit: String?
}

// MARK: - Insight Trend

struct InsightTrend: Hashable {
    let direction: TrendDirection
    let changePercent: Double?
    let changeAbsolute: Double?
    let comparisonPeriod: String

    var trendColor: Color {
        switch direction {
        case .up: return AppColors.income
        case .down: return AppColors.destructive
        case .flat: return AppColors.textSecondary
        }
    }

    var trendIcon: String {
        switch direction {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }
}

enum TrendDirection: Hashable {
    case up, down, flat
}

// MARK: - Trend Direction Semantics

extension InsightType {
    /// Whether an upward trend is *bad* for the user (e.g., expenses growing,
    /// budget overshoot increasing). Used to colour the trend badge contextually:
    /// when `true`, `.up` renders red and `.down` renders green — inverting the
    /// default which assumes growth is good.
    var upIsBadForUser: Bool {
        switch self {
        case .spendingSpike, .monthOverMonthChange, .averageDailySpending,
             .categoryTrend, .totalRecurringCost, .subscriptionGrowth, .duplicateSubscriptions,
             .budgetOverspend, .budgetUnderutilized, .projectedOverspend, .accountDormancy,
             .yearOverYear, .spendingForecast:
            return true
        case .topSpendingCategory, .incomeGrowth, .incomeSourceBreakdown, .incomeVsExpenseRatio,
             .netCashFlow, .bestMonth, .worstMonth, .projectedBalance, .accountActivity,
             .totalWealth, .wealthGrowth, .savingsRate, .emergencyFund, .balanceRunway,
             .subcategoryBreakdown:
            return false
        }
    }
}

extension Insight {
    /// Colour override for the trend badge — applied when `type.upIsBadForUser`
    /// flips the default semantics. Returns `nil` when default colouring
    /// (trend.direction → income/destructive) is correct.
    var trendBadgeColorOverride: Color? {
        guard let trend, type.upIsBadForUser else { return nil }
        switch trend.direction {
        case .up:   return AppColors.destructive
        case .down: return AppColors.success
        case .flat: return AppColors.textSecondary
        }
    }
}

// MARK: - Insight Severity

enum InsightSeverity: String, Hashable {
    case positive
    case neutral
    case warning
    case critical

    var color: Color {
        switch self {
        case .positive: return AppColors.success
        case .neutral: return AppColors.accent
        case .warning: return AppColors.warning
        case .critical: return AppColors.destructive
        }
    }

    var icon: String {
        switch self {
        case .positive: return "checkmark.circle.fill"
        case .neutral: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .warning:  return 1
        case .neutral:  return 2
        case .positive: return 3
        }
    }
}

// MARK: - Insight Category

enum InsightCategory: String, CaseIterable, Hashable {
    case spending
    case income
    case budget
    case recurring
    case cashFlow
    case wealth      // Accumulated capital card
    case savings
    case forecasting

    var displayName: String {
        switch self {
        case .spending:    return String(localized: "insights.spending")
        case .income:      return String(localized: "insights.income")
        case .budget:      return String(localized: "insights.budget")
        case .recurring:   return String(localized: "insights.recurring")
        case .cashFlow:    return String(localized: "insights.cashFlow")
        case .wealth:      return String(localized: "insights.wealth")
        case .savings:     return String(localized: "insights.savings")
        case .forecasting: return String(localized: "insights.forecasting")
        }
    }

    var icon: String {
        switch self {
        case .spending:    return "arrow.down.circle"
        case .income:      return "arrow.up.circle"
        case .budget:      return "gauge.with.dots.needle.33percent"
        case .recurring:   return "repeat.circle"
        case .cashFlow:    return "chart.line.uptrend.xyaxis"
        case .wealth:      return "banknote"
        case .savings:     return "banknote.fill"
        case .forecasting: return "chart.line.uptrend.xyaxis.circle"
        }
    }
}

// MARK: - Detail Data

enum InsightDetailData: Hashable {
    case categoryBreakdown([CategoryBreakdownItem])
    case periodTrend([PeriodDataPoint])         // Granularity-aware trend
    case budgetProgressList([BudgetInsightItem])
    case recurringList([RecurringInsightItem])
    case accountComparison([AccountInsightItem])
    case wealthBreakdown([AccountInsightItem])   // Per-account balances
    case formulaBreakdown(InsightFormulaModel)   // Header + hero + formula rows + recommendation
}

// MARK: - Category Breakdown

struct CategoryBreakdownItem: Identifiable, Hashable {
    let id: String
    let categoryName: String
    let amount: Double
    let percentage: Double
    let color: Color
    let iconSource: IconSource?
    let subcategories: [SubcategoryBreakdownItem]

    // Color is not Hashable; hash and compare by id only (consistent Hashable contract).
    static func == (lhs: CategoryBreakdownItem, rhs: CategoryBreakdownItem) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SubcategoryBreakdownItem: Identifiable, Hashable {
    let id: String
    let name: String
    let amount: Double
    let percentage: Double
}

// MARK: - Budget Insight Item

struct BudgetInsightItem: Identifiable, Hashable {
    let id: String
    let categoryName: String
    let budgetAmount: Double
    let spent: Double
    let percentage: Double
    let isOverBudget: Bool
    let color: Color
    let daysRemaining: Int
    let projectedSpend: Double
    let iconSource: IconSource?

    // Color is not Hashable; hash and compare by id only (consistent Hashable contract).
    static func == (lhs: BudgetInsightItem, rhs: BudgetInsightItem) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Recurring Insight Item

struct RecurringInsightItem: Identifiable, Hashable {
    let id: String
    let name: String
    let amount: Decimal
    let currency: String
    let frequency: RecurringFrequency
    let kind: RecurringSeriesKind
    let status: SubscriptionStatus?
    let iconSource: IconSource?
    let monthlyEquivalent: Double
}

// MARK: - Account Insight Item

struct AccountInsightItem: Identifiable, Hashable {
    let id: String
    let accountName: String
    let currency: String
    let balance: Double
    let transactionCount: Int
    let lastActivityDate: Date?
    let iconSource: IconSource?
}

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
    let monthsInWindow:          Int     // # of monthly aggregates the score is built from
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
            isBudgetComponentActive: false,
            monthsInWindow: 0
        )
    }
}
