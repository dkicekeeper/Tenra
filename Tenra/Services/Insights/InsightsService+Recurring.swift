//
//  InsightsService+Recurring.swift
//  Tenra
//
//  Recurring transaction, subscription growth, and duplicate subscription insights.
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
            case .daily:     rawMonthlyEquivalent = amount * 30
            case .weekly:    rawMonthlyEquivalent = amount * 4.33
            case .monthly:   rawMonthlyEquivalent = amount
            case .quarterly: rawMonthlyEquivalent = amount / 3
            case .yearly:    rawMonthlyEquivalent = amount / 12
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

        // Scale to the selected granularity period (weekly/quarterly/yearly equivalent).
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

    // MARK: - Subscription Growth

    /// Compares current monthly recurring total with the total a granularity-scaled
    /// lookback ago (week→1mo, month→3mo, quarter→6mo, year→12mo, allTime→12mo).
    nonisolated func generateSubscriptionGrowth(
        baseCurrency: String,
        granularity: InsightGranularity,
        recurringSeries: [RecurringSeries],
        seriesMonthlyEquivalents: [String: Double]? = nil
    ) -> Insight? {
        let activeSeries = recurringSeries.filter { $0.isActive }
        guard activeSeries.count >= 2 else { return nil }

        let lookbackMonths: Int
        switch granularity {
        case .week:    lookbackMonths = 1
        case .month:   lookbackMonths = 3
        case .quarter: lookbackMonths = 6
        case .year:    lookbackMonths = 12
        case .allTime: lookbackMonths = 12
        }

        let calendar = Calendar.current
        let now = Date()
        guard let lookbackDate = calendar.date(byAdding: .month, value: -lookbackMonths, to: now) else { return nil }

        let dateFormatter = DateFormatters.dateFormatter

        let currentTotal = activeSeries.reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency, cache: seriesMonthlyEquivalents) }
        let prevSeries = activeSeries.filter { series in
            guard let start = dateFormatter.date(from: series.startDate) else { return false }
            return start < lookbackDate
        }
        let newSeries = activeSeries.filter { series in
            guard let start = dateFormatter.date(from: series.startDate) else { return false }
            return start >= lookbackDate
        }
        let prevTotal = prevSeries.reduce(0.0) { $0 + seriesMonthlyEquivalent($1, baseCurrency: baseCurrency, cache: seriesMonthlyEquivalents) }

        guard prevTotal > 0, currentTotal > 0 else { return nil }
        let changePercent = ((currentTotal - prevTotal) / prevTotal) * 100
        guard abs(changePercent) > 5 else { return nil }

        let direction: TrendDirection = changePercent > 0 ? .up : .down
        let severity: InsightSeverity = changePercent > 10 ? .warning : (changePercent < -10 ? .positive : .neutral)

        let lookbackPhrase = String(
            format: String(localized: "insights.subscriptionGrowth.compareAgo"),
            lookbackMonths
        )

        let recommendation: String
        if changePercent > 10 {
            recommendation = String(
                format: String(localized: "insights.formula.subscriptionGrowth.rec.growing"),
                Formatting.formatCurrencySmart(currentTotal - prevTotal, currency: baseCurrency)
            )
        } else if changePercent < -10 {
            recommendation = String(localized: "insights.formula.subscriptionGrowth.rec.shrinking")
        } else {
            recommendation = String(localized: "insights.formula.subscriptionGrowth.rec.stable")
        }

        let model = InsightFormulaModel(
            id: "subscriptionGrowth",
            titleKey: "insights.formula.subscriptionGrowth.title",
            icon: "arrow.up.right.circle.fill",
            color: severity.color,
            heroValueText: String(format: "%+.1f%%", changePercent),
            heroLabelKey: "insights.formula.subscriptionGrowth.heroLabel",
            formulaHeaderKey: "insights.formula.subscriptionGrowth.formulaHeader",
            formulaRows: [
                InsightFormulaRow(
                    id: "lookback",
                    labelKey: "insights.formula.subscriptionGrowth.row.lookback",
                    value: 0,
                    kind: .rawText(lookbackPhrase)
                ),
                InsightFormulaRow(id: "previous", labelKey: "insights.formula.subscriptionGrowth.row.previous", value: prevTotal, kind: .currency),
                InsightFormulaRow(id: "current", labelKey: "insights.formula.subscriptionGrowth.row.current", value: currentTotal, kind: .currency),
                InsightFormulaRow(id: "addedCount", labelKey: "insights.formula.subscriptionGrowth.row.addedCount", value: Double(newSeries.count), kind: .rawText("\(newSeries.count)")),
                InsightFormulaRow(id: "delta", labelKey: "insights.formula.subscriptionGrowth.row.delta", value: changePercent, kind: .percent, isEmphasised: true)
            ],
            explainerKey: "insights.formula.subscriptionGrowth.explainer",
            recommendation: recommendation,
            baseCurrency: baseCurrency
        )

        Self.logger.debug("🔁 [Insights] SubscriptionGrowth — \(String(format: "%+.1f%%", changePercent), privacy: .public), lookback=\(lookbackMonths)mo")
        return Insight(
            id: "subscription_growth",
            type: .subscriptionGrowth,
            title: String(localized: "insights.subscriptionGrowth"),
            subtitle: lookbackPhrase,
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
                comparisonPeriod: lookbackPhrase
            ),
            severity: severity,
            category: .recurring,
            detailData: .formulaBreakdown(model)
        )
    }

    // MARK: - Duplicate Subscriptions

    /// Detects possible duplicate subscriptions using TWO signals together:
    ///   • normalised name similarity (same first 4 letters of the description after
    ///     stripping non-letters, lowercased) — catches "Spotify" vs "Spotify Family"
    ///   • OR monthly cost within 5% of each other (catches services priced similarly,
    ///     a stronger signal than category alone — most subscriptions cluster in
    ///     "Entertainment" so category overlap was producing false positives).
    /// Returns a list of duplicate *pairs* in detail.
    nonisolated func generateDuplicateSubscriptions(
        baseCurrency: String,
        recurringSeries: [RecurringSeries],
        seriesMonthlyEquivalents: [String: Double]? = nil
    ) -> Insight? {
        let activeSeries = recurringSeries.filter { $0.isActive && $0.kind == .subscription }
        guard activeSeries.count >= 2 else { return nil }

        // Pre-compute normalised name and monthly cost per series.
        struct Probe {
            let series: RecurringSeries
            let normalisedName: String  // lowercased letters only
            let monthly: Double
        }
        let probes: [Probe] = activeSeries.map { series in
            let raw = series.description.isEmpty ? series.category : series.description
            let normalised = raw.lowercased().filter { $0.isLetter }
            let monthly = seriesMonthlyEquivalent(series, baseCurrency: baseCurrency, cache: seriesMonthlyEquivalents)
            return Probe(series: series, normalisedName: normalised, monthly: monthly)
        }

        // Find candidate-duplicate pairs.
        var pairedIds = Set<String>()
        var pairs: [(Probe, Probe)] = []
        for i in 0..<probes.count {
            for j in (i + 1)..<probes.count {
                let a = probes[i], b = probes[j]
                let nameMatch: Bool
                if a.normalisedName.count >= 4 && b.normalisedName.count >= 4 {
                    nameMatch = a.normalisedName.prefix(4) == b.normalisedName.prefix(4)
                } else {
                    nameMatch = a.normalisedName == b.normalisedName && !a.normalisedName.isEmpty
                }
                let amountMatch: Bool
                if a.monthly > 0 && b.monthly > 0 {
                    let diff = abs(a.monthly - b.monthly) / max(a.monthly, b.monthly)
                    amountMatch = diff < 0.05
                } else {
                    amountMatch = false
                }
                if nameMatch || amountMatch {
                    pairs.append((a, b))
                    pairedIds.insert(a.series.id)
                    pairedIds.insert(b.series.id)
                }
            }
        }

        guard !pairs.isEmpty else { return nil }

        // Build the detail list — one row per series that participated in any pair.
        let dupSeries = activeSeries.filter { pairedIds.contains($0.id) }
        let recurringItems: [RecurringInsightItem] = dupSeries.map { series in
            let name = series.description.isEmpty ? series.category : series.description
            let monthly = seriesMonthlyEquivalent(series, baseCurrency: baseCurrency, cache: seriesMonthlyEquivalents)
            return RecurringInsightItem(
                id: series.id, name: name, amount: series.amount, currency: series.currency,
                frequency: series.frequency, kind: series.kind, status: series.status,
                iconSource: series.iconSource, monthlyEquivalent: monthly
            )
        }.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }

        let totalCost = recurringItems.reduce(0.0) { $0 + $1.monthlyEquivalent }
        let pairCount = pairs.count

        Self.logger.debug("🔁 [Insights] DuplicateSubscriptions — \(pairCount) pair(s), \(dupSeries.count) series")
        return Insight(
            id: "duplicateSubscriptions",
            type: .duplicateSubscriptions,
            title: String(localized: "insights.duplicateSubscriptions.title"),
            subtitle: String(format: String(localized: "insights.duplicateSubscriptions.subtitle"), pairCount),
            metric: InsightMetric(
                value: totalCost,
                formattedValue: Formatting.formatCurrency(totalCost, currency: baseCurrency),
                currency: baseCurrency, unit: String(localized: "insights.perMonth")
            ),
            trend: nil,
            severity: .warning,
            category: .recurring,
            detailData: .recurringList(recurringItems)
        )
    }
}
