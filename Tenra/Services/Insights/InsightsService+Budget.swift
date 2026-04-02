//
//  InsightsService+Budget.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: budget overspend detection, projected overspend, under-utilization.
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
            guard let progress = budgetService.budgetProgress(for: category, transactions: transactions) else {
                Self.logger.debug("   💼 \(category.name, privacy: .public): budgetProgress returned nil — SKIPPED")
                continue
            }

            let periodStart = budgetService.budgetPeriodStart(for: category)
            let daysElapsed = max(1, calendar.dateComponents([.day], from: periodStart, to: now).day ?? 1)

            let totalDays: Int
            switch category.budgetPeriod {
            case .weekly:  totalDays = 7
            case .monthly: totalDays = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            case .yearly:  totalDays = calendar.range(of: .day, in: .year,  for: now)?.count ?? 365
            }

            let daysRemaining = max(0, totalDays - daysElapsed)
            let projectedSpend = totalDays > 0
                ? (progress.spent / Double(daysElapsed)) * Double(totalDays)
                : progress.spent
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

        // Single pass to partition budget items (Phase 23-C P15)
        var overBudgetItems: [BudgetInsightItem] = []
        var projectedOverspendItems: [BudgetInsightItem] = []
        var underBudgetItems: [BudgetInsightItem] = []
        for item in budgetItems {
            if item.isOverBudget {
                overBudgetItems.append(item)
            } else if item.projectedSpend > item.budgetAmount {
                projectedOverspendItems.append(item)
            } else if item.percentage < 80 && item.percentage > 0 {
                underBudgetItems.append(item)
            }
        }

        if !overBudgetItems.isEmpty {
            insights.append(Insight(
                id: "budget_over",
                type: .budgetOverspend,
                title: String(localized: "insights.budgetOver"),
                subtitle: String(format: String(localized: "insights.categoriesOverBudget"), overBudgetCount),
                metric: InsightMetric(
                    value: Double(overBudgetCount),
                    formattedValue: "\(overBudgetCount)",
                    currency: nil,
                    unit: String(localized: "insights.categoriesUnit")
                ),
                trend: nil,
                severity: .critical,
                category: .budget,
                detailData: .budgetProgressList(budgetItems.sorted { $0.percentage > $1.percentage })
            ))
        }

        if !projectedOverspendItems.isEmpty {
            insights.append(Insight(
                id: "budget_projected_over",
                type: .projectedOverspend,
                title: String(localized: "insights.projectedOverspend"),
                subtitle: String(format: String(localized: "insights.categoriesAtRisk"), projectedOverspendItems.count),
                metric: InsightMetric(
                    value: Double(projectedOverspendItems.count),
                    formattedValue: "\(projectedOverspendItems.count)",
                    currency: nil,
                    unit: String(localized: "insights.categoriesUnit")
                ),
                trend: nil,
                severity: .warning,
                category: .budget,
                detailData: .budgetProgressList(projectedOverspendItems.sorted { $0.projectedSpend / $0.budgetAmount > $1.projectedSpend / $1.budgetAmount })
            ))
        }

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

        let projectedCount = projectedOverspendItems.count
        let underCount = underBudgetItems.count
        Self.logger.debug("💼 [Insights] Budget END — \(insights.count) insights, over=\(overBudgetCount), atRisk=\(projectedCount), under=\(underCount)")
        return insights
    }
}
