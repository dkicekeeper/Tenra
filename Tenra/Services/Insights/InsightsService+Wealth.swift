//
//  InsightsService+Wealth.swift
//  Tenra
//
//  Money on the accounts (total wealth), wealth growth, net worth, account dormancy detection.
//

import Foundation
import os

extension InsightsService {

    // MARK: - Wealth Insights

    nonisolated func generateWealthInsights(
        periodPoints: [PeriodDataPoint],
        allTransactions: [Transaction],
        granularity: InsightGranularity,
        baseCurrency: String,
        currencyService: TransactionCurrencyService,
        balanceFor: (String) -> Double,
        accountTransactionCounts: [String: Int]? = nil,
        accounts: [Account]
    ) -> [Insight] {
        guard !accounts.isEmpty else { return [] }

        // Loans are liabilities — their balance represents debt remaining, not owned capital.
        // Exclude them, and accounts the user excluded from balance, from total wealth
        // and from the per-account breakdown.
        let assetAccounts = accounts.filter { !$0.isLoan && $0.includeInBalance }
        // Each account's balance in the base currency: the total, the ranking and the donut add
        // them up; the per-account rows keep the account's own currency.
        let baseBalances = Dictionary(uniqueKeysWithValues: assetAccounts.map {
            ($0.id, Self.baseBalance(of: $0, balanceFor: balanceFor, baseCurrency: baseCurrency))
        })
        let totalWealth = baseBalances.values.reduce(0, +)

        // Use pre-computed counts (O(1) lookup) instead of O(N*M) allTransactions.filter
        let accountItems: [AccountInsightItem] = assetAccounts.map { account in
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
        }.sorted { (baseBalances[$0.id] ?? 0) > (baseBalances[$1.id] ?? 0) }

        // Build cumulative balance data points (shared derivation — the Insights
        // balance stat card plots the same line from the same helper).
        let cumulativePoints = Self.cumulativeBalancePoints(periodPoints, endingBalance: totalWealth)

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

        // Composition donut: positive balances only (a liability can't be a slice),
        // top 6 accounts + the rest folded into "other" — mirrors DonutSlice.from.
        // Colors are decorative (no legend in the mini slot); hash-based like the
        // category fallback palette.
        let positiveAccounts = accountItems.filter { (baseBalances[$0.id] ?? 0) > 0 }
        var wealthSlices = positiveAccounts.prefix(6).map { item in
            let amount = baseBalances[item.id] ?? 0
            return DonutSlice(
                id: item.id,
                amount: amount,
                color: CategoryColors.color(for: item.accountName),
                label: item.accountName,
                percentage: totalWealth > 0 ? amount / totalWealth * 100 : 0
            )
        }
        let foldedBalance = positiveAccounts.dropFirst(6).reduce(0.0) { $0 + (baseBalances[$1.id] ?? 0) }
        if foldedBalance > 0 {
            wealthSlices.append(DonutSlice(
                id: "other",
                amount: foldedBalance,
                color: AppColors.textTertiary,
                label: String(localized: "insights.other"),
                percentage: totalWealth > 0 ? foldedBalance / totalWealth * 100 : 0
            ))
        }

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
            detailData: .wealthBreakdown(accountItems),
            cardVisual: wealthSlices.isEmpty ? nil : .donut(wealthSlices)
        ))

        // Wealth Growth
        if let pct = changePercent, abs(pct) > 1 {
            let wealthGrowthSeverity: InsightSeverity = currentPeriodNetFlow > 0 ? .positive : .warning
            // Build an explicit comparison label "May 2026 vs April 2026" so the
            // text doesn't depend on a granularity-keyed string elsewhere.
            let curLabel = granularity.headingLabel(for: currentKey)
            let prevLabel = granularity.headingLabel(for: prevKey)
            let comparison = String(
                format: String(localized: "insights.wealth.growth.compare"),
                curLabel, prevLabel
            )
            wealthInsights.append(Insight(
                id: "wealth_growth",
                type: .wealthGrowth,
                title: String(localized: "insights.wealthGrowth"),
                subtitle: comparison,
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
                    comparisonPeriod: comparison
                ),
                severity: wealthGrowthSeverity,
                category: .wealth,
                detailData: .periodTrend(cumulativePoints)
            ))
        }

        return wealthInsights
    }

    // MARK: - Account Dormancy

    /// Flags accounts that have been idle for 30+ days but still hold a positive balance.
    /// Uses PreAggregatedData.lastAccountDates — O(accounts) instead of O(N) date-parsing loop.
    nonisolated func generateAccountDormancy(allTransactions: [Transaction], baseCurrency: String, balanceFor: (String) -> Double, preAggregated: PreAggregatedData? = nil, accounts: [Account]) -> Insight? {
        let now = Date()
        guard let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) else { return nil }

        // Use pre-computed lastAccountDates (O(1) per account) when available.
        // Falls back to O(N) date-parsing loop when preAggregated is nil.
        let lastDates: [String: Date]
        if let preAgg = preAggregated {
            lastDates = preAgg.lastAccountDates
        } else {
            var computed: [String: Date] = [:]
            for tx in allTransactions {
                guard let accountId = tx.accountId, !accountId.isEmpty,
                      let txDate = FastDateParser.date(from: tx.date) else { continue }
                if let existing = computed[accountId] {
                    if txDate > existing { computed[accountId] = txDate }
                } else {
                    computed[accountId] = txDate
                }
            }
            lastDates = computed
        }

        let dormantAccounts: [AccountInsightItem] = accounts.compactMap { account in
            // Accounts excluded from balance are out of analytics entirely.
            guard account.includeInBalance else { return nil }
            let balance = balanceFor(account.id)
            guard balance > 0 else { return nil }
            // Deposit/savings accounts are expected to be inactive — don't flag them
            guard !account.isDeposit else { return nil }
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

        // Metric = total balance sitting idle (an amount). The account count is in the
        // subtitle, so a big "N" duplicated it in the detail header.
        let totalIdleBalance = dormantAccounts.reduce(0.0) { $0 + Self.toBase($1.balance, currency: $1.currency, baseCurrency: baseCurrency) }
        return Insight(
            id: "accountDormancy",
            type: .accountDormancy,
            title: String(localized: "insights.accountDormancy.title"),
            subtitle: "\(dormantAccounts.count) \(String(localized: "insights.accountDormancy.subtitle"))",
            metric: InsightMetric(
                value: totalIdleBalance,
                formattedValue: Formatting.formatCurrencySmart(totalIdleBalance, currency: baseCurrency),
                currency: baseCurrency, unit: nil
            ),
            trend: nil,
            severity: .neutral,
            category: .wealth,
            detailData: .accountComparison(dormantAccounts)
        )
    }


    // MARK: - Net worth

    /// Net worth (NetWorthCalculator): money on the accounts, the assets at the person's share and
    /// what others owe them, less what is left of the loans and what they owe, in the base
    /// currency. Free, like all of Insights: without assets it still counts the money, the debts
    /// and the loans. The same for every granularity (a state, not a period).
    nonisolated func generateNetWorth(snapshot: DataSnapshot, baseCurrency: String) -> Insight? {
        guard !snapshot.accounts.isEmpty else { return nil }
        let result = NetWorthCalculator.compute(
            accounts: snapshot.accounts,
            balanceFor: snapshot.balanceFor,
            holdings: snapshot.netWorthHoldings,
            baseCurrency: baseCurrency
        )
        let severity: InsightSeverity = result.total >= 0 ? .positive : .critical
        let rows: [InsightFormulaRow] = result.lines.compactMap { line in
            // Money always; the other parts once there is something in them.
            guard line.kind == .money || line.amount > 0 else { return nil }
            return InsightFormulaRow(
                id: line.kind.rawValue,
                labelKey: "insights.formula.netWorth.row.\(line.kind.rawValue)",
                value: line.signedAmount,
                kind: .currency
            )
        } + [
            InsightFormulaRow(id: "total", labelKey: "insights.formula.netWorth.row.total", value: result.total, kind: .currency, isEmphasised: true)
        ]
        let model = InsightFormulaModel(
            id: "netWorth",
            titleKey: "insights.formula.netWorth.title",
            icon: "building.columns.circle.fill",
            color: severity.color,
            heroValueText: Formatting.formatCurrencySmart(result.total, currency: baseCurrency),
            heroLabelKey: "insights.formula.netWorth.heroLabel",
            formulaHeaderKey: "insights.formula.netWorth.formulaHeader",
            formulaRows: rows,
            explainerKey: "insights.formula.netWorth.explainer",
            recommendation: result.amount(.assets) > 0
                ? String(localized: "insights.formula.netWorth.rec.withAssets")
                : String(localized: "insights.formula.netWorth.rec.addAssets"),
            baseCurrency: baseCurrency
        )
        // What the person has, as a bar: money, assets, what others owe.
        let palette: [NetWorthCalculator.Line.Kind: Color] = [
            .money: AppColors.accent, .assets: AppColors.income, .owedToMe: AppColors.transfer,
        ]
        let owned = result.lines.filter { !$0.kind.isLiability && $0.amount > 0 }
        let ownedTotal = owned.reduce(0) { $0 + $1.amount }
        let segments = owned.map { line in
            DonutSlice(
                id: line.kind.rawValue,
                amount: line.amount,
                color: palette[line.kind] ?? AppColors.accent,
                label: String(localized: String.LocalizationValue("insights.formula.netWorth.row.\(line.kind.rawValue)")),
                percentage: ownedTotal > 0 ? line.amount / ownedTotal * 100 : 0
            )
        }
        return Insight(
            id: "net_worth",
            type: .netWorth,
            title: String(localized: "insights.netWorth.title"),
            subtitle: String(localized: "insights.netWorth.subtitle"),
            metric: InsightMetric(
                value: result.total,
                formattedValue: Formatting.formatCurrencySmart(result.total, currency: baseCurrency),
                currency: baseCurrency,
                unit: nil
            ),
            trend: nil,
            severity: severity,
            category: .wealth,
            detailData: .formulaBreakdown(model),
            cardVisual: segments.count >= 2 ? .proportionBar(segments) : nil
        )
    }
}
