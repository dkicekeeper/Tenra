//
//  InsightsService+Wealth.swift
//  AIFinanceManager
//
//  Phase 38: Extracted from InsightsService monolith (2832 LOC → domain files).
//  Responsible for: total wealth, wealth growth, account dormancy detection.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Wealth Insights (Phase 18)

    nonisolated func generateWealthInsights(
        periodPoints: [PeriodDataPoint],
        allTransactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        accountTransactionCounts: [String: Int]? = nil,   // Phase 42d: pre-computed from PreAggregatedData
        accounts: [Account]
    ) -> [Insight] {
        guard !accounts.isEmpty else { return [] }

        let totalWealth = accounts.reduce(0.0) { $0 + balanceFor($1.id) }

        // Phase 42d: Use pre-computed counts (O(1) lookup) instead of O(N×M) allTransactions.filter
        let accountItems: [AccountInsightItem] = accounts.map { account in
            let txCount: Int
            if let counts = accountTransactionCounts {
                txCount = counts[account.id] ?? 0
            } else {
                txCount = allTransactions.filter { $0.accountId == account.id }.count
            }
            return AccountInsightItem(
                id: account.id,
                accountName: account.name,
                currency: account.currency,
                balance: balanceFor(account.id),
                transactionCount: txCount,
                lastActivityDate: nil,
                iconSource: account.iconSource
            )
        }.sorted { $0.balance > $1.balance }

        // Build cumulative balance data points
        let initialBalance = totalWealth - periodPoints.reduce(0.0) { $0 + $1.netFlow }
        var running = initialBalance
        let cumulativePoints: [PeriodDataPoint] = periodPoints.map { point in
            running += point.netFlow
            return PeriodDataPoint(
                id: point.id,
                granularity: point.granularity,
                key: point.key,
                periodStart: point.periodStart,
                periodEnd: point.periodEnd,
                label: point.label,
                income: point.income,
                expenses: point.expenses,
                cumulativeBalance: running
            )
        }

        // Period-over-period comparison
        let currentKey = granularity.currentPeriodKey
        let prevKey = granularity.previousPeriodKey
        let currentPeriodNetFlow = periodPoints.first(where: { $0.key == currentKey })?.netFlow ?? 0
        let prevPeriodNetFlow = periodPoints.first(where: { $0.key == prevKey })?.netFlow ?? 0

        let changePercent: Double? = prevPeriodNetFlow != 0
            ? ((currentPeriodNetFlow - prevPeriodNetFlow) / abs(prevPeriodNetFlow)) * 100
            : nil
        let direction: TrendDirection = currentPeriodNetFlow > 0 ? .up : (currentPeriodNetFlow < 0 ? .down : .flat)

        var wealthInsights: [Insight] = []

        wealthInsights.append(Insight(
            id: "total_wealth",
            type: .totalWealth,
            title: String(localized: "insights.wealth.title"),
            subtitle: String(localized: "insights.wealth.subtitle"),
            metric: InsightMetric(
                value: totalWealth,
                formattedValue: Formatting.formatCurrencySmart(totalWealth, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: InsightTrend(
                direction: direction,
                changePercent: changePercent,
                changeAbsolute: currentPeriodNetFlow,
                comparisonPeriod: granularity.comparisonPeriodName
            ),
            severity: totalWealth >= 0 ? .positive : .critical,
            category: .wealth,
            detailData: .wealthBreakdown(accountItems)
        ))

        // Wealth Growth (Phase 24)
        if let pct = changePercent, abs(pct) > 1 {
            let wealthGrowthSeverity: InsightSeverity = currentPeriodNetFlow > 0 ? .positive : .warning
            wealthInsights.append(Insight(
                id: "wealth_growth",
                type: .wealthGrowth,
                title: String(localized: "insights.wealthGrowth"),
                subtitle: granularity.comparisonPeriodName,
                metric: InsightMetric(
                    value: currentPeriodNetFlow,
                    formattedValue: Formatting.formatCurrencySmart(currentPeriodNetFlow, currency: baseCurrency),
                    currency: baseCurrency,
                    unit: nil
                ),
                trend: InsightTrend(
                    direction: direction,
                    changePercent: pct,
                    changeAbsolute: nil,
                    comparisonPeriod: granularity.comparisonPeriodName
                ),
                severity: wealthGrowthSeverity,
                category: .wealth,
                detailData: .periodTrend(cumulativePoints)
            ))
        }

        return wealthInsights
    }

    // MARK: - Account Dormancy (Phase 24 Behavioral)

    /// Flags accounts that have been idle for 30+ days but still hold a positive balance.
    /// Phase 42: Replaced CoreData fetchLastTransactionDates with in-memory computation.
    /// Phase 42e: Uses PreAggregatedData.lastAccountDates — O(accounts) instead of O(N) date-parsing loop.
    nonisolated func generateAccountDormancy(allTransactions: [Transaction], balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil, accounts: [Account]) -> Insight? {
        let now = Date()
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return nil }

        // Phase 42e: Use pre-computed lastAccountDates (O(1) per account) when available.
        // Falls back to O(N) date-parsing loop when preAggregated is nil.
        let lastDates: [String: Date]
        if let preAgg = preAggregated {
            lastDates = preAgg.lastAccountDates
        } else {
            let dateFormatter = DateFormatters.dateFormatter
            var computed: [String: Date] = [:]
            for tx in allTransactions {
                guard let accountId = tx.accountId, !accountId.isEmpty,
                      let txDate = dateFormatter.date(from: tx.date) else { continue }
                if let existing = computed[accountId] {
                    if txDate > existing { computed[accountId] = txDate }
                } else {
                    computed[accountId] = txDate
                }
            }
            lastDates = computed
        }

        let dormantAccounts: [AccountInsightItem] = accounts.compactMap { account in
            let balance = balanceFor(account.id)
            guard balance > 0 else { return nil }
            guard let last = lastDates[account.id], last < thirtyDaysAgo else { return nil }
            return AccountInsightItem(
                id: account.id,
                accountName: account.name,
                currency: account.currency,
                balance: balance,
                transactionCount: 0,
                lastActivityDate: last,
                iconSource: account.iconSource
            )
        }
        guard !dormantAccounts.isEmpty else { return nil }

        return Insight(
            id: "accountDormancy",
            type: .accountDormancy,
            title: String(localized: "insights.accountDormancy.title"),
            subtitle: "\(dormantAccounts.count) \(String(localized: "insights.accountDormancy.subtitle"))",
            metric: InsightMetric(
                value: Double(dormantAccounts.count),
                formattedValue: "\(dormantAccounts.count)",
                currency: nil, unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .wealth,
            detailData: .accountComparison(dormantAccounts)
        )
    }

    // Phase 42: fetchLastTransactionDates (CoreData) deleted — replaced by in-memory
    // computation above. All transactions are in memory since Phase 40.
}
