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
    /// Purpose-built mini-visual for the feed card (2026-07 visual refresh). When set,
    /// InsightsCardView renders it instead of deriving a chart from `detailData`; `nil`
    /// falls back to the legacy detailData-driven mini-chart. Defaulted so the dozens of
    /// existing construction sites stay valid.
    var cardVisual: InsightCardVisual? = nil

    // Hash by id only (detailData holds non-Hashable Colors). Equality is VALUE-BASED on the
    // display-affecting fields, though — insight ids are stable across granularities
    // (e.g. "top_spending_Дом" when "Дом" tops every period), so id-only equality made
    // SwiftUI treat a new granularity's card as unchanged and skip re-rendering, leaving stale
    // numbers. Comparing the rendered fields lets SwiftUI detect the change. (Hashable contract
    // holds: equal values share an id, hence the same hash.)
    static func == (lhs: Insight, rhs: Insight) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.metric == rhs.metric &&
        lhs.trend == rhs.trend &&
        lhs.severity == rhs.severity &&
        lhs.category == rhs.category &&
        lhs.cardVisual == rhs.cardVisual
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Card Visual (2026-07 visual refresh)

/// Purpose-built mini-visual for an insight's feed card, rendered in the trailing
/// 120×60pt slot. Generators set ready-to-draw values; deliberately decoupled from
/// `InsightDetailData` (the detail-screen contract, which stays untouched).
///
/// Visual grammar (docs/domains/charts.md §Insight mini-visuals): solid fill = fact,
/// translucent/dashed = forecast, gray = comparison base, tick = norm/target marker.
enum InsightCardVisual: Equatable {
    /// Two-bar was/now comparison: muted gray `previous`, `color`-tinted `current`.
    /// `isProjection` renders the current bar translucent with a dashed outline.
    case barPair(previous: Double, current: Double, color: Color, isProjection: Bool)
    /// Half-circle gauge: `value` against a `norm` tick on a relative scale
    /// (scale = max(value × 1.15, norm × 2), so the norm tick never hugs an edge).
    case halfGauge(value: Double, norm: Double, color: Color)
    /// Budget-consumption ring (ProgressRing reuse), `progress` 0…1+.
    case ring(progress: Double, isOverBudget: Bool)
    /// Composition donut (MiniDonut reuse).
    case donut([DonutSlice])
    /// Up to 3 thin per-category budget bars (LinearProgressBar reuse) — a
    /// "N categories over budget" card must show N offenders, not just the worst.
    case budgetBars([CardBudgetBar])
    /// Segmented milestone scale (emergency fund): `value` filled out of
    /// `maxValue` segments, target tick at `target`.
    case milestoneGauge(value: Double, target: Double, maxValue: Double, color: Color)
    /// Sparkline with extras the plain detailData fallback can't express:
    /// a dashed projection tail to `projectedValue` (hollow endpoint), and/or
    /// min/max extreme markers (period records). Generators pass the points
    /// they want shown (already sliced/cumulative) — no card-side slicing.
    case sparkline(points: [PeriodDataPoint], series: PeriodChartSeries, projectedValue: Double?, markExtremes: Bool)
    /// Horizontal stacked composition bar (MiniProportionBar) — e.g. the
    /// recurring total split into top subscriptions + "other".
    case proportionBar([DonutSlice])
}

/// One row of the `.budgetBars` card visual.
struct CardBudgetBar: Equatable {
    let id: String
    /// Raw budget consumption, 0–100+.
    let percentage: Double
    let isOverBudget: Bool
    /// End-of-period projection (0–100+). When set, LinearProgressBar renders the
    /// span from `percentage` to it as a translucent forecast segment with the
    /// 100% limit tick visible.
    let projectedPercentage: Double?
    let color: Color
}

// MARK: - Insight Type

enum InsightType: String, Hashable {
    case topSpendingCategory
    case spendingSpike
    case monthOverMonthChange
    case averageDailySpending
    case incomeGrowth
    case incomeSourceBreakdown
    case budgetOverspend
    case budgetUnderutilized
    case projectedOverspend
    case categoryTrend
    case subcategoryBreakdown
    case totalRecurringCost
    case subscriptionGrowth
    case netCashFlow
    case bestMonth       // merged "period records" card (best + worst rankings in detail)
    case projectedBalance
    case accountActivity
    case totalWealth      // Current sum of all account balances
    case wealthGrowth     // Monthly/period growth of accumulated balance
    case savingsRate       // (income - expenses) / income %
    case emergencyFund     // months of expenses covered by balance
    case spendingForecast  // projected 30-day spend
    case yearOverYear      // this month vs same month last year
    case duplicateSubscriptions // possible duplicate recurring items
    case accountDormancy        // accounts idle 30+ days with non-zero balance
    case subscriptionPriceIncrease // latest charge higher than the previous one (audit 2026-07)
    case largeTransaction          // big non-recurring expense vs 90d average (audit 2026-07)
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

nonisolated enum TrendDirection: Hashable {
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
             .yearOverYear, .spendingForecast, .subscriptionPriceIncrease, .largeTransaction:
            return true
        case .topSpendingCategory, .incomeGrowth, .incomeSourceBreakdown,
             .netCashFlow, .bestMonth, .projectedBalance, .accountActivity,
             .totalWealth, .wealthGrowth, .savingsRate, .emergencyFund,
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

nonisolated enum InsightSeverity: String, Hashable {
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

// MARK: - Insight Filter

/// Feed filter selection: everything, the cross-section «Важное» slice
/// (critical/warning severities + health score), or a single category.
enum InsightFilter: Hashable {
    case all
    case urgent
    case category(InsightCategory)
}

// MARK: - Detail Data

enum InsightDetailData: Hashable {
    case categoryBreakdown([CategoryBreakdownItem])
    case categoryBreakdownPaged(CategoryBreakdownPages)  // One breakdown per period, swipeable
    case periodTrend([PeriodDataPoint])         // Granularity-aware trend
    case budgetProgressList([BudgetInsightItem])
    case recurringList([RecurringInsightItem])
    case accountComparison([AccountInsightItem])
    case wealthBreakdown([AccountInsightItem])   // Per-account balances
    case formulaBreakdown(InsightFormulaModel)   // Header + hero + formula rows + recommendation
}

// MARK: - Paged Category Breakdown

/// A category breakdown for a single period (week / month / quarter / year).
/// `items` is empty when the period had no realized activity — the detail view
/// renders an empty state for that page so the user can keep swiping.
///
/// Flavor-neutral: used for both expense categories (`topSpendingCategory`) and
/// income sources (`incomeSourceBreakdown`), so `total` is the period's realized
/// expense OR income total depending on which generator built it.
struct PeriodCategoryBreakdown: Identifiable, Hashable {
    let id: String           // period grouping key (e.g. "2026-06")
    let label: String        // human-readable period label (e.g. "June 2026")
    let total: Double
    let items: [CategoryBreakdownItem]
}

/// Ordered (chronological) per-period category breakdowns plus the index of the
/// current period, so the detail pager opens on "today" and swipes back to the
/// first transaction's period.
struct CategoryBreakdownPages: Hashable {
    let periods: [PeriodCategoryBreakdown]
    let currentIndex: Int
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
