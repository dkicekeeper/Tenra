//
//  InsightsService+Recurring.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: recurring cost totals, subscription growth, duplicate subscription detection.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Recurring Insights

    nonisolated func generateRecurringInsights(baseCurrency: String, granularity: InsightGranularity? = nil, recurringSeries: [RecurringSeries]) -> [Insight] {
        let activeSeries = recurringSeries.filter { $0.isActive }
        guard !activeSeries.isEmpty else {
            Self.logger.debug("🔁 [Insights] Recurring — SKIPPED (no active series)")
            return []
        }

        Self.logger.debug("🔁 [Insights] Recurring START — \(activeSeries.count) active series")

        let recurringItems: [RecurringInsightItem] = activeSeries.map { series in
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let rawMonthlyEquivalent: Double
            switch series.frequency {
            case .daily:   rawMonthlyEquivalent = amount * 30
            case .weekly:  rawMonthlyEquivalent = amount * 4.33
            case .monthly: rawMonthlyEquivalent = amount
            case .yearly:  rawMonthlyEquivalent = amount / 12
            }

            // Convert each item's monthly equivalent to baseCurrency before storing.
            let monthlyEquivalent: Double
            if series.currency != baseCurrency,
               let converted = CurrencyConverter.convertSync(
                   amount: rawMonthlyEquivalent,
                   from: series.currency,
                   to: baseCurrency
               ) {
                monthlyEquivalent = converted
                Self.logger.debug("   🔁 converted \(String(format: "%.0f", rawMonthlyEquivalent), privacy: .public) \(series.currency, privacy: .public) → \(String(format: "%.0f", monthlyEquivalent), privacy: .public) \(baseCurrency, privacy: .public)")
            } else {
                monthlyEquivalent = rawMonthlyEquivalent
                if series.currency != baseCurrency {
                    Self.logger.warning("   🔁 ⚠️ No exchange rate for \(series.currency, privacy: .public) → \(baseCurrency, privacy: .public), using raw amount")
                }
            }

            let name = series.description.isEmpty ? series.category : series.description
            Self.logger.debug("   🔁 '\(name, privacy: .public)' \(String(describing: series.frequency), privacy: .public) \(String(format: "%.0f", amount), privacy: .public) \(series.currency, privacy: .public) → monthly=\(String(format: "%.0f", monthlyEquivalent), privacy: .public) \(baseCurrency, privacy: .public)")
            return RecurringInsightItem(
                id: series.id,
                name: name,
                amount: series.amount,
                currency: series.currency,
                frequency: series.frequency,
                kind: series.kind,
                status: series.status,
                iconSource: series.iconSource,
                monthlyEquivalent: monthlyEquivalent
            )
        }

        let totalMonthly = recurringItems.reduce(0.0) { $0 + $1.monthlyEquivalent }

        // Phase 30: Scale to the selected granularity period (weekly/quarterly/yearly equivalent).
        let periodMultiplier: Double
        let periodUnit: String
        switch granularity {
        case .week:
            periodMultiplier = 7.0 / 30.0
            periodUnit       = String(localized: "insights.perWeek")
        case .quarter:
            periodMultiplier = 3.0
            periodUnit       = String(localized: "insights.perQuarter")
        case .year:
            periodMultiplier = 12.0
            periodUnit       = String(localized: "insights.perYear")
        case .month, .allTime, nil:
            periodMultiplier = 1.0
            periodUnit       = String(localized: "insights.perMonth")
        }
        let periodTotal = totalMonthly * periodMultiplier

        Self.logger.debug("🔁 [Insights] Recurring END — totalMonthly=\(String(format: "%.0f", totalMonthly), privacy: .public) → periodTotal=\(String(format: "%.0f", periodTotal), privacy: .public) ×\(String(format: "%.2f", periodMultiplier), privacy: .public) \(baseCurrency, privacy: .public)")

        return [Insight(
            id: "total_recurring",
            type: .totalRecurringCost,
            title: granularity?.totalRecurringTitle ?? String(localized: "insights.totalRecurring"),
            subtitle: String(format: String(localized: "insights.activeRecurring"), activeSeries.count),
            metric: InsightMetric(
                value: periodTotal,
                formattedValue: Formatting.formatCurrencySmart(periodTotal, currency: baseCurrency),
                currency: baseCurrency,
                unit: periodUnit
            ),
            trend: nil,
            severity: periodTotal > 0 ? .neutral : .positive,
            category: .recurring,
            detailData: .recurringList(recurringItems.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent })
        )]
    }

    // MARK: - Subscription Growth (Phase 24)

    /// Compares current monthly recurring total with the total 3 months ago.
    nonisolated func generateSubscriptionGrowth(baseCurrency: String, recurringSeries: [RecurringSeries]) -> Insight? {
        let activeSeries = recurringSeries.filter { $0.isActive }
        guard activeSeries.count >= 2 else { return nil }

        let calendar = Calendar.current
        let now = Date()
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) else { return nil }

        let dateFormatter = DateFormatters.dateFormatter

        let currentTotal = activeSeries.reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency) }
        let prevSeries = activeSeries.filter { series in
            guard let start = dateFormatter.date(from: series.startDate) else { return false }
            return start < threeMonthsAgo
        }
        let prevTotal = prevSeries.reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency) }

        guard prevTotal > 0, currentTotal > 0 else { return nil }
        let changePercent = ((currentTotal - prevTotal) / prevTotal) * 100
        guard abs(changePercent) > 5 else { return nil }

        let direction: TrendDirection = changePercent > 0 ? .up : .down
        let severity: InsightSeverity = changePercent > 10 ? .warning : (changePercent < -10 ? .positive : .neutral)
        Self.logger.debug("🔁 [Insights] SubscriptionGrowth — \(String(format: "%+.1f%%", changePercent), privacy: .public)")
        return Insight(
            id: "subscription_growth",
            type: .subscriptionGrowth,
            title: String(localized: "insights.subscriptionGrowth"),
            subtitle: String(localized: "insights.vsThreeMonthsAgo"),
            metric: InsightMetric(
                value: currentTotal,
                formattedValue: Formatting.formatCurrencySmart(currentTotal, currency: baseCurrency),
                currency: baseCurrency,
                unit: String(localized: "insights.perMonth")
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: changePercent,
                changeAbsolute: currentTotal - prevTotal,
                comparisonPeriod: String(localized: "insights.vsThreeMonthsAgo")
            ),
            severity: severity,
            category: .recurring,
            detailData: nil
        )
    }

    // MARK: - Duplicate Subscriptions (Phase 24 Behavioral)

    /// Detects possible duplicate subscriptions — active series with the same category
    /// OR monthly cost within 15% of each other.
    nonisolated func generateDuplicateSubscriptions(baseCurrency: String, recurringSeries: [RecurringSeries]) -> Insight? {
        let activeSeries = recurringSeries.filter { $0.isActive && $0.kind == .subscription }
        guard activeSeries.count >= 2 else { return nil }

        // Group by category; flag categories with 2+ subscriptions
        let grouped = Dictionary(grouping: activeSeries, by: \.category)
        let duplicateGroups = grouped.filter { $0.value.count >= 2 }
        guard !duplicateGroups.isEmpty else {
            // Secondary check: any two subscriptions with monthly cost within 15%
            let costs = activeSeries.map { seriesMonthlyEquivalent($0, baseCurrency: baseCurrency) }.sorted()
            var hasSimilarCost = false
            for i in 0..<costs.count - 1 {
                let a = costs[i]; let b = costs[i + 1]
                guard a > 0 else { continue }
                if abs(a - b) / a < 0.15 { hasSimilarCost = true; break }
            }
            guard hasSimilarCost else { return nil }

            let totalDuplicateCost = costs.dropFirst().reduce(0, +)
            return Insight(
                id: "duplicateSubscriptions",
                type: .duplicateSubscriptions,
                title: String(localized: "insights.duplicateSubscriptions.title"),
                subtitle: String(localized: "insights.duplicateSubscriptions.subtitle"),
                metric: InsightMetric(
                    value: totalDuplicateCost,
                    formattedValue: Formatting.formatCurrency(totalDuplicateCost, currency: baseCurrency),
                    currency: baseCurrency, unit: nil
                ),
                trend: nil,
                severity: .warning,
                category: .recurring,
                detailData: nil
            )
        }

        let duplicateCount = duplicateGroups.values.reduce(0) { $0 + $1.count }
        let duplicateCost = duplicateGroups.values.flatMap { $0 }
            .reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency) }
        return Insight(
            id: "duplicateSubscriptions",
            type: .duplicateSubscriptions,
            title: String(localized: "insights.duplicateSubscriptions.title"),
            subtitle: "\(duplicateCount) \(String(localized: "insights.duplicateSubscriptions.subtitle"))",
            metric: InsightMetric(
                value: duplicateCost,
                formattedValue: Formatting.formatCurrency(duplicateCost, currency: baseCurrency),
                currency: baseCurrency, unit: nil
            ),
            trend: nil,
            severity: .warning,
            category: .recurring,
            detailData: nil
        )
    }
}
