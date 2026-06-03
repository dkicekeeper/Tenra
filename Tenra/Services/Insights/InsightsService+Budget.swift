//
//  InsightsService+Budget.swift
//  Tenra
//
//  Budget overspend detection, projected overspend, under-utilization.
//

import Foundation
import os
import SwiftUI

extension InsightsService {

    // MARK: - Budget Insights

    nonisolated func generateBudgetInsights(
        transactions: [Transaction],
        timeFilter: TimeFilter,
        baseCurrency: String,
        categories: [CustomCategory]
    ) -> [Insight] {
        var insights: [Insight] = []
        let categoriesWithBudget = categories.filter { $0.budgetAmount != nil && $0.type == .expense }
        guard !categoriesWithBudget.isEmpty else {
            Self.logger.debug("💼 [Insights] Budget — SKIPPED (no budget categories)")
            return insights
        }

        Self.logger.debug("💼 [Insights] Budget START — \(categoriesWithBudget.count) categories with budget")

        let calendar = Calendar.current
        let now = Date()
        var budgetItems: [BudgetInsightItem] = []
        var overBudgetCount = 0

        for category in categoriesWithBudget {
            // Insights runs nonisolated on a background actor; it cannot read the
            // MainActor-isolated aggregate indexes, so it uses the legacy array-scan
            // path against the snapshot we were handed. This intentionally does
            // O(N_tx) work — Insights is async/background and not on a hot path.
            guard let progress = CategoryBudgetService.budgetProgress(
                for: category,
                transactions: transactions,
                baseCurrency: baseCurrency
            ) else {
                Self.logger.debug("   💼 \(category.name, privacy: .public): budgetProgress returned nil — SKIPPED")
                continue
            }

            let periodStart = CategoryBudgetService.legacyBudgetPeriodStart(for: category)
            let daysElapsed = max(1, calendar.dateComponents([.day], from: periodStart, to: now).day ?? 1)

            let totalDays: Int
            switch category.budgetPeriod {
            case .weekly:  totalDays = 7
            case .monthly: totalDays = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            case .yearly:  totalDays = calendar.range(of: .day, in: .year,  for: now)?.count ?? 365
            }

            let daysRemaining = max(0, totalDays - daysElapsed)
            // Extrapolating "projected spend" from only a day or two of data produces
            // false alarms (a category at 7 % of budget on day 2 "projects" an overspend).
            // Require at least a quarter of the period (min 7 days) elapsed before we
            // trust the run-rate; until then, project the actual spend with no extrapolation.
            let minDaysForProjection = max(7, totalDays / 4)
            let projectedSpend: Double
            if daysElapsed >= minDaysForProjection && totalDays > 0 {
                projectedSpend = (progress.spent / Double(daysElapsed)) * Double(totalDays)
            } else {
                projectedSpend = progress.spent
            }
            let color = Color(hex: category.colorHex)

            if progress.isOverBudget { overBudgetCount += 1 }

            Self.logger.debug("   💼 \(category.name, privacy: .public): budget=\(String(format: "%.0f", progress.budgetAmount), privacy: .public), spent=\(String(format: "%.0f", progress.spent), privacy: .public), pct=\(String(format: "%.1f%%", progress.percentage), privacy: .public), over=\(progress.isOverBudget), daysLeft=\(daysRemaining), projected=\(String(format: "%.0f", projectedSpend), privacy: .public)")

            budgetItems.append(BudgetInsightItem(
                id: category.id,
                categoryName: category.name,
                budgetAmount: progress.budgetAmount,
                spent: progress.spent,
                percentage: progress.percentage,
                isOverBudget: progress.isOverBudget,
                color: color,
                daysRemaining: daysRemaining,
                projectedSpend: projectedSpend,
                iconSource: category.iconSource
            ))
        }

        // Single pass to partition budget items
        var overBudgetItems: [BudgetInsightItem] = []
        var projectedOverspendItems: [BudgetInsightItem] = []
        var underBudgetItems: [BudgetInsightItem] = []
        for item in budgetItems {
            if item.isOverBudget {
                overBudgetItems.append(item)
            } else if item.projectedSpend > item.budgetAmount {
                projectedOverspendItems.append(item)
            } else if item.percentage < 80 {
                // Include 0 %-spent budgets — an untouched budget has the most headroom,
                // and hiding them made the list look near-empty (only 1 category showing).
                underBudgetItems.append(item)
            }
        }

        if !overBudgetItems.isEmpty {
            // Metric = how much over budget in total (an amount), not a category count —
            // the count already lives in the subtitle, so showing it big duplicated it.
            let totalOver = overBudgetItems.reduce(0.0) { $0 + max(0, $1.spent - $1.budgetAmount) }
            insights.append(Insight(
                id: "budget_over",
                type: .budgetOverspend,
                title: String(localized: "insights.budgetOver"),
                subtitle: String(format: String(localized: "insights.categoriesOverBudget"), overBudgetCount),
                metric: InsightMetric(
                    value: totalOver,
                    formattedValue: Formatting.formatCurrencySmart(totalOver, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .critical,
                category: .budget,
                detailData: .budgetProgressList(budgetItems.sorted { $0.percentage > $1.percentage })
            ))
        }

        if !projectedOverspendItems.isEmpty {
            // Metric = total projected overshoot (an amount). The category count is in
            // the subtitle, so a big "2" duplicated it.
            let totalProjectedOver = projectedOverspendItems.reduce(0.0) { $0 + max(0, $1.projectedSpend - $1.budgetAmount) }
            insights.append(Insight(
                id: "budget_projected_over",
                type: .projectedOverspend,
                title: String(localized: "insights.projectedOverspend"),
                subtitle: String(format: String(localized: "insights.categoriesAtRisk"), projectedOverspendItems.count),
                metric: InsightMetric(
                    value: totalProjectedOver,
                    formattedValue: Formatting.formatCurrencySmart(totalProjectedOver, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: nil,
                severity: .warning,
                category: .budget,
                detailData: .budgetProgressList(projectedOverspendItems.sorted { $0.projectedSpend / $0.budgetAmount > $1.projectedSpend / $1.budgetAmount })
            ))
        }

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

        let projectedCount = projectedOverspendItems.count
        let underCount = underBudgetItems.count
        Self.logger.debug("💼 [Insights] Budget END — \(insights.count) insights, over=\(overBudgetCount), atRisk=\(projectedCount), under=\(underCount)")
        return insights
    }
}
