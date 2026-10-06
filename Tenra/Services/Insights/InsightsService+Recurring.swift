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
            detailData: .recurringList(recurringItems.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }),
            // Composition of the recurring total: top-3 subscriptions + "other".
            // A single subscription has no composition to show — stay nil.
            cardVisual: {
                let sorted = recurringItems
                    .filter { $0.monthlyEquivalent > 0 }
                    .sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
                guard sorted.count >= 2, totalMonthly > 0 else { return nil }
                var segments = sorted.prefix(3).map { item in
                    DonutSlice(
                        id: item.id,
                        amount: item.monthlyEquivalent,
                        color: CategoryColors.hexColor(for: item.name),
                        label: item.name,
                        percentage: item.monthlyEquivalent / totalMonthly * 100
                    )
                }
                let rest = sorted.dropFirst(3).reduce(0.0) { $0 + $1.monthlyEquivalent }
                if rest > 0 {
                    segments.append(DonutSlice(
                        id: "other",
                        amount: rest,
                        color: AppColors.textTertiary,
                        label: String(localized: "insights.other"),
                        percentage: rest / totalMonthly * 100
                    ))
                }
                return .proportionBar(segments)
            }()
        )]
    }

    // MARK: - Subscription Price Increase (audit 2026-07)

    /// Days a price increase stays in the feed, counted from the FIRST charge at the new
    /// price. Later charges at the same higher price do not extend it. Until 2026-10 there
    /// was no window: the card stayed until a newer charge was recorded (a whole year for
    /// a yearly series, indefinitely when none was) and its push repeated every 7 days.
    nonisolated static let priceIncreaseVisibleDays = 30

    /// Detects active expense series whose price went up recently: the first realized
    /// charge at the current price is noticeably higher than the last charge at the
    /// previous price (or than the series amount when only one charge is linked).
    /// Emma/Rocket-style "your subscription got more expensive" signal, shown for
    /// `priceIncreaseVisibleDays` after that first charge. Emits up to 3 insights,
    /// largest increase first. Granularity-independent (shared).
    nonisolated func generateSubscriptionPriceIncreases(
        recurringSeries: [RecurringSeries],
        categories: [CustomCategory],
        transactions: [Transaction],
        txDateMap: [String: Date]? = nil,
        now: Date = Date()
    ) -> [Insight] {
        let activeExpenseSeries = recurringSeries.filter { series in
            guard series.isActive else { return false }
            return categories.first { $0.name == series.category }?.type != .income
        }
        guard !activeExpenseSeries.isEmpty else { return [] }
        let activeIds = Set(activeExpenseSeries.map(\.id))

        // Single pass: collect realized occurrences per active series.
        var occurrences: [String: [(date: Date, amount: Double, currency: String)]] = [:]
        for tx in transactions where tx.type == .expense {
            guard let seriesId = tx.recurringSeriesId, activeIds.contains(seriesId) else { continue }
            guard let d = txDateMap?[tx.date] ?? FastDateParser.date(from: tx.date), d <= now else { continue }
            occurrences[seriesId, default: []].append((d, tx.amount, tx.currency))
        }
        guard !occurrences.isEmpty else { return [] }

        let calendar = Calendar.current
        var found: [(insight: Insight, changePercent: Double)] = []
        for series in activeExpenseSeries {
            guard var occ = occurrences[series.id], !occ.isEmpty else { continue }
            occ.sort { $0.date > $1.date }
            let latest = occ[0]
            // Only charges in the latest charge's currency are compared (a multi-currency
            // comparison would need FX and reads as noise). Newest first.
            let charges = occ.filter { $0.currency == latest.currency }

            let chargesPerYear: Double
            switch series.frequency {
            case .daily:     chargesPerYear = 365
            case .weekly:    chargesPerYear = 52
            case .monthly:   chargesPerYear = 12
            case .quarterly: chargesPerYear = 4
            case .yearly:    chargesPerYear = 1
            }
            let expectedGapDays = 365.25 / chargesPerYear

            // First charge at the current price: walk back over older charges within the
            // 5% noise band (FX wobble, rounding). The first bigger move between two
            // consecutive charges is the price change.
            var firstAtPrice = 0
            while firstAtPrice + 1 < charges.count {
                let newer = charges[firstAtPrice].amount
                let older = charges[firstAtPrice + 1].amount
                guard older > 0, abs(newer - older) / older * 100 <= 5 else { break }
                firstAtPrice += 1
            }
            let newCharge = charges[firstAtPrice]

            // Visibility window: shown for `priceIncreaseVisibleDays` after the first
            // charge at the new price, then gone even though the higher price persists.
            guard let visibleUntil = calendar.date(
                byAdding: .day, value: Self.priceIncreaseVisibleDays, to: newCharge.date
            ), now < visibleUntil else { continue }

            // Baseline: the last charge at the previous price; fall back to the series
            // amount when only one charge is linked.
            let baseline: Double
            if firstAtPrice + 1 < charges.count {
                let previous = charges[firstAtPrice + 1]
                // Billing-period guard: the previous charge covers roughly the span
                // up to the new one. If that span doesn't match the series'
                // current frequency, the billing period changed (monthly → yearly
                // plan switch) — comparing raw charge amounts would read as a huge
                // fake "price increase" (real bug: Wolt 1 199/mo → 9 588/yr = +699%).
                let gapDays = newCharge.date.timeIntervalSince(previous.date) / 86_400
                guard gapDays >= expectedGapDays * 0.5, gapDays <= expectedGapDays * 1.6 else { continue }
                baseline = previous.amount
            } else if charges.count == 1, series.currency == latest.currency {
                baseline = NSDecimalNumber(decimal: series.amount).doubleValue
            } else {
                continue
            }
            guard baseline > 0 else { continue }

            let delta = newCharge.amount - baseline
            let changePercent = (delta / baseline) * 100
            // >300% within one billing period is implausible as a price hike —
            // it's a plan/period switch or a mislinked charge, not a signal.
            guard changePercent > 5, changePercent <= 300 else { continue }

            let yearlyImpact = delta * chargesPerYear

            let name = series.description.isEmpty ? series.category : series.description
            let severity: InsightSeverity = .warning

            // All amounts here are in the CHARGE currency, so the model formats
            // .currency rows with it (not the app base currency).
            let model = InsightFormulaModel(
                id: "priceIncrease_\(series.id)",
                titleKey: "insights.formula.priceIncrease.title",
                icon: "arrow.up.forward.circle.fill",
                color: severity.color,
                heroValueText: String(format: "%+.1f%%", changePercent),
                heroLabelKey: "insights.formula.priceIncrease.heroLabel",
                formulaHeaderKey: "insights.formula.priceIncrease.formulaHeader",
                formulaRows: [
                    InsightFormulaRow(id: "name", labelKey: "insights.formula.priceIncrease.row.name", value: 0, kind: .rawText(name)),
                    InsightFormulaRow(id: "oldPrice", labelKey: "insights.formula.priceIncrease.row.oldPrice", value: baseline, kind: .currency),
                    InsightFormulaRow(id: "newPrice", labelKey: "insights.formula.priceIncrease.row.newPrice", value: newCharge.amount, kind: .currency),
                    InsightFormulaRow(id: "delta", labelKey: "insights.formula.priceIncrease.row.delta", value: changePercent, kind: .percent),
                    InsightFormulaRow(id: "yearlyImpact", labelKey: "insights.formula.priceIncrease.row.yearlyImpact", value: yearlyImpact, kind: .currency, isEmphasised: true)
                ],
                explainerKey: "insights.formula.priceIncrease.explainer",
                recommendation: String(localized: "insights.formula.priceIncrease.rec"),
                baseCurrency: newCharge.currency
            )

            Self.logger.debug("🔁 [Insights] PriceIncrease — '\(name, privacy: .public)' \(String(format: "%.0f", baseline), privacy: .public) → \(String(format: "%.0f", newCharge.amount), privacy: .public) \(newCharge.currency, privacy: .public) (\(String(format: "%+.1f%%", changePercent), privacy: .public))")
            found.append((Insight(
                id: "price_increase_\(series.id)",
                type: .subscriptionPriceIncrease,
                title: String(localized: "insights.priceIncrease"),
                subtitle: name,
                metric: InsightMetric(
                    value: newCharge.amount,
                    formattedValue: Formatting.formatCurrencySmart(newCharge.amount, currency: newCharge.currency),
                    currency: newCharge.currency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: .up,
                    changePercent: changePercent,
                    changeAbsolute: delta,
                    comparisonPeriod: String(
                        format: String(localized: "insights.priceIncrease.was"),
                        Formatting.formatCurrencySmart(baseline, currency: newCharge.currency)
                    )
                ),
                severity: severity,
                category: .recurring,
                detailData: .formulaBreakdown(model),
                // Old charge vs new charge — the card IS a two-value comparison.
                cardVisual: .barPair(
                    previous: baseline,
                    current: newCharge.amount,
                    color: AppColors.warning,
                    isProjection: false
                ),
                // One push per series + new amount: the same increase never pushes
                // again, a later increase (another amount) gets its own key.
                signalKey: "price_increase_\(series.id)@\(newCharge.currency):\(String(format: "%.2f", newCharge.amount))"
            ), changePercent))
        }

        return found
            .sorted { $0.changePercent > $1.changePercent }
            .prefix(3)
            .map(\.insight)
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
            detailData: .formulaBreakdown(model),
            cardVisual: .barPair(
                previous: prevTotal,
                current: currentTotal,
                color: changePercent > 0 ? AppColors.warning : AppColors.success,
                isProjection: false
            )
        )
    }

}
