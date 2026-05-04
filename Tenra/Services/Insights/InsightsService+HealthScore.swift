//
//  InsightsService+HealthScore.swift
//  Tenra
//
//  Composite financial health score (0-100, 5 weighted components).
//

import Foundation
import SwiftUI

extension InsightsService {

    // MARK: - Financial Health Score

    /// Computes a composite 0-100 financial health score from five weighted components.
    /// Call after `generateAllInsights` once totals and period data points are available.
    /// Receives pre-captured snapshots — safe to call from Task.detached.
    nonisolated func computeHealthScore(
        totalIncome: Double,
        totalExpenses: Double,
        latestNetFlow: Double,
        baseCurrency: String,
        balanceFor: (String) -> Double,
        allTransactions: [Transaction],
        categories: [CustomCategory],
        recurringSeries: [RecurringSeries],
        accounts: [Account],
        preAggregated: PreAggregatedData? = nil
    ) -> FinancialHealthScore {
        guard totalIncome > 0 else { return .unavailable() }

        let calendar = Calendar.current
        let now = Date()

        // --- Component 1: Savings Rate (weight 0.30) ---
        let savingsRate = (totalIncome - totalExpenses) / totalIncome * 100
        let savingsRateScore = Int(min(savingsRate / 20.0 * 100, 100).rounded())

        // --- Component 2: Budget Adherence (weight 0.25) ---
        let monthStart = startOfMonth(calendar, for: now)
        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let currentMonthAggregates: [InMemoryCategoryMonthTotal]
        if let preAggregated {
            currentMonthAggregates = preAggregated.categoryMonthTotalsInRange(from: monthStart, to: now)
        } else {
            currentMonthAggregates = Self.computeCategoryMonthTotals(
                from: allTransactions, from: monthStart, to: now, baseCurrency: baseCurrency
            )
        }
        let categoriesWithBudget = categories.filter { ($0.budgetAmount ?? 0) > 0 }
        // Index aggregates by category name once — replaces O(M²) scan
        // (categoriesWithBudget × currentMonthAggregates) with O(M) build + O(M) lookups.
        var expensesByCategoryName: [String: Double] = [:]
        expensesByCategoryName.reserveCapacity(currentMonthAggregates.count)
        for agg in currentMonthAggregates {
            expensesByCategoryName[agg.categoryName] = agg.totalExpenses
        }
        let onBudgetCount = categoriesWithBudget.filter { category in
            let spent = expensesByCategoryName[category.name] ?? 0
            return spent <= (category.budgetAmount ?? 0)
        }.count
        let totalBudgetCount = categoriesWithBudget.count
        let budgetAdherenceScore = totalBudgetCount > 0
            ? Int((Double(onBudgetCount) / Double(totalBudgetCount) * 100).rounded())
            : -1 // sentinel: exclude from weighted total when no budgets

        // --- Component 3: Recurring Ratio (weight 0.20) ---
        // Index categories by name once — replaces `categories.first` per active series.
        var categoryTypeByName: [String: TransactionType] = [:]
        categoryTypeByName.reserveCapacity(categories.count)
        for cat in categories {
            categoryTypeByName[cat.name] = cat.type
        }
        let recurringCost = recurringSeries
            .filter { $0.isActive }
            .reduce(0.0) { total, series in
                let isExpense = categoryTypeByName[series.category] != .income
                return isExpense ? total + seriesMonthlyEquivalent(series, baseCurrency: baseCurrency, cache: preAggregated?.seriesMonthlyEquivalents) : total
            }
        let recurringRatioScore = Int(max(0, (1.0 - recurringCost / max(totalIncome, 1)) * 100).rounded())

        // --- Component 4: Emergency Fund (weight 0.15) ---
        let totalBalance = accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        // Use preAggregated O(M) lookup when available; fall back to O(N) scan
        let last3Months: [InMemoryMonthlyTotal]
        if let preAggregated {
            last3Months = preAggregated.lastMonthlyTotals(3)
        } else {
            last3Months = Self.computeLastMonthlyTotals(3, from: allTransactions, baseCurrency: baseCurrency)
        }
        let avgMonthlyExpenses = last3Months.isEmpty
            ? totalExpenses / 12
            : last3Months.reduce(0.0) { $0 + $1.totalExpenses } / Double(last3Months.count)
        let monthsCovered = avgMonthlyExpenses > 0 ? totalBalance / avgMonthlyExpenses : 0
        let emergencyFundScore = Int(min(monthsCovered / 3.0 * 100, 100).rounded())

        // --- Component 5: Cash Flow (weight 0.10) ---
        let cashflowScore: Int
        if totalIncome > 0 {
            // net flow as % of income: +20% or more = 100, 0% = 50, -20% or worse = 0
            let netFlowRatio = latestNetFlow / totalIncome
            cashflowScore = Int(min(100, max(0, (netFlowRatio + 0.2) / 0.4 * 100)).rounded())
        } else {
            cashflowScore = latestNetFlow >= 0 ? 50 : 0
        }

        // --- Weighted Total ---
        let total: Double
        if budgetAdherenceScore >= 0 {
            total = Double(savingsRateScore)     * 0.30
                  + Double(budgetAdherenceScore) * 0.25
                  + Double(recurringRatioScore)  * 0.20
                  + Double(emergencyFundScore)   * 0.15
                  + Double(cashflowScore)        * 0.10
        } else {
            // No budgets — redistribute 25% proportionally
            total = Double(savingsRateScore)     * 0.40
                  + Double(recurringRatioScore)  * 0.267
                  + Double(emergencyFundScore)   * 0.20
                  + Double(cashflowScore)        * 0.133
        }
        let score = Int(total.rounded())

        let (grade, gradeColor): (String, Color)
        switch score {
        case 80...100: (grade, gradeColor) = (String(localized: "insights.healthGrade.excellent"),      AppColors.success)
        case 60..<80:  (grade, gradeColor) = (String(localized: "insights.healthGrade.good"),           AppColors.accent)
        case 40..<60:  (grade, gradeColor) = (String(localized: "insights.healthGrade.fair"),           AppColors.warning)
        default:       (grade, gradeColor) = (String(localized: "insights.healthGrade.needsAttention"), AppColors.destructive)
        }

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

    // MARK: - Test Convenience

    /// Static forwarding wrapper — identical parameters to the instance method.
    /// Tests that don't have a full `InsightsService` graph can call this instead.
    /// `seriesMonthlyEquivalent` is stateless (delegates to `computeSeriesMonthlyEquivalent`),
    /// so a temporary ephemeral instance is safe.
    nonisolated static func computeHealthScore(
        totalIncome: Double,
        totalExpenses: Double,
        latestNetFlow: Double,
        baseCurrency: String,
        balanceFor: (String) -> Double,
        allTransactions: [Transaction],
        categories: [CustomCategory],
        recurringSeries: [RecurringSeries],
        accounts: [Account],
        preAggregated: PreAggregatedData? = nil
    ) -> FinancialHealthScore {
        // `seriesMonthlyEquivalent` is purely functional — no stored state accessed.
        // We therefore bypass the real init by calling the underlying static directly.
        guard totalIncome > 0 else { return .unavailable() }

        let recurringCost = recurringSeries
            .filter { $0.isActive }
            .reduce(0.0) { total, series in
                // Mirror the instance method: treat non-income categories as expenses
                let isExpense = categories.first(where: { $0.name == series.category })?.type != .income
                return isExpense
                    ? total + computeSeriesMonthlyEquivalent(series, baseCurrency: baseCurrency)
                    : total
            }

        // Delegate the full computation by temporarily constructing a lightweight value.
        // Re-use the shared static helpers for all sub-computations.
        let calendar = Calendar.current
        let now = Date()
        let monthStart: Date = {
            let c = calendar.dateComponents([.year, .month], from: now)
            return calendar.date(from: c) ?? now
        }()
        let currentMonthAggregates = computeCategoryMonthTotals(
            from: allTransactions, from: monthStart, to: now, baseCurrency: baseCurrency
        )
        let categoriesWithBudget = categories.filter { ($0.budgetAmount ?? 0) > 0 }
        var expensesByCategoryName: [String: Double] = [:]
        for agg in currentMonthAggregates { expensesByCategoryName[agg.categoryName] = agg.totalExpenses }
        let onBudgetCount = categoriesWithBudget.filter { expensesByCategoryName[$0.name] ?? 0 <= ($0.budgetAmount ?? 0) }.count
        let totalBudgetCount = categoriesWithBudget.count
        let budgetAdherenceScore = totalBudgetCount > 0
            ? Int((Double(onBudgetCount) / Double(totalBudgetCount) * 100).rounded()) : -1

        let savingsRate = (totalIncome - totalExpenses) / totalIncome * 100
        let savingsRateScore = Int(min(savingsRate / 20.0 * 100, 100).rounded())
        let recurringRatioScore = Int(max(0, (1.0 - recurringCost / max(totalIncome, 1)) * 100).rounded())

        let totalBalance = accounts.reduce(0.0) { $0 + balanceFor($1.id) }
        let last3Months = computeLastMonthlyTotals(3, from: allTransactions, baseCurrency: baseCurrency)
        let avgMonthlyExpenses = last3Months.isEmpty
            ? totalExpenses / 12
            : last3Months.reduce(0.0) { $0 + $1.totalExpenses } / Double(last3Months.count)
        let monthsCovered = avgMonthlyExpenses > 0 ? totalBalance / avgMonthlyExpenses : 0
        let emergencyFundScore = Int(min(monthsCovered / 3.0 * 100, 100).rounded())

        let netFlowRatio = latestNetFlow / totalIncome
        let cashflowScore = Int(min(100, max(0, (netFlowRatio + 0.2) / 0.4 * 100)).rounded())

        let total: Double
        if budgetAdherenceScore >= 0 {
            total = Double(savingsRateScore) * 0.30
                  + Double(budgetAdherenceScore) * 0.25
                  + Double(recurringRatioScore) * 0.20
                  + Double(emergencyFundScore) * 0.15
                  + Double(cashflowScore) * 0.10
        } else {
            total = Double(savingsRateScore) * 0.40
                  + Double(recurringRatioScore) * 0.267
                  + Double(emergencyFundScore) * 0.20
                  + Double(cashflowScore) * 0.133
        }
        let score = Int(total.rounded())

        let (grade, gradeColor): (String, Color)
        switch score {
        case 80...100: (grade, gradeColor) = (String(localized: "insights.healthGrade.excellent"),      AppColors.success)
        case 60..<80:  (grade, gradeColor) = (String(localized: "insights.healthGrade.good"),           AppColors.accent)
        case 40..<60:  (grade, gradeColor) = (String(localized: "insights.healthGrade.fair"),           AppColors.warning)
        default:       (grade, gradeColor) = (String(localized: "insights.healthGrade.needsAttention"), AppColors.destructive)
        }

        let netFlowPercent = (latestNetFlow / totalIncome) * 100

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
            recurringPercentOfIncome: (recurringCost / totalIncome) * 100,
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
