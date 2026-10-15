//
//  ProjectedBalanceTests.swift
//  TenraTests
//
//  The projected-balance insight subtracts the average expenses of the last 3 buckets from
//  the recurring net for one period of the granularity. A bucket already is one period, so
//  its average is not scaled again: a yearly bucket projects a year of spending, not 12.
//
//  @MainActor: InsightsService's collaborators are MainActor types.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct ProjectedBalanceTests {

    private func makeService() -> InsightsService {
        InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: nil)
        )
    }

    /// Three consecutive buckets of `granularity` ending with the current one, each with
    /// `expenses` and no income.
    private func points(_ granularity: InsightGranularity, expenses: Double) -> [PeriodDataPoint] {
        let unit: Calendar.Component
        let step: Int
        switch granularity {
        case .week: (unit, step) = (.weekOfYear, 1)
        case .month: (unit, step) = (.month, 1)
        case .quarter: (unit, step) = (.month, 3)
        case .year, .allTime: (unit, step) = (.year, 1)
        }
        return (0..<3).reversed().map { back in
            let date = Calendar.current.date(byAdding: unit, value: -back * step, to: Date())!
            let key = granularity.groupingKey(for: date)
            let start = granularity.periodStart(for: key)
            return PeriodDataPoint(
                id: key, granularity: granularity, key: key,
                periodStart: start,
                periodEnd: Calendar.current.date(byAdding: unit, value: step, to: start)!,
                label: key, income: 0, expenses: expenses, cumulativeBalance: nil
            )
        }
    }

    private func projectedChange(_ granularity: InsightGranularity, expenses: Double) -> Double? {
        let account = Account(id: "a", name: "Card", currency: "KZT", initialBalance: 0, balance: 0)
        let insights = makeService().generateCashFlowInsightsFromPeriodPoints(
            periodPoints: points(granularity, expenses: expenses),
            allTransactions: [],
            granularity: granularity,
            baseCurrency: "KZT",
            snapshot: InsightsService.DataSnapshot(
                transactions: [],
                categories: [],
                recurringSeries: [],
                accounts: [account],
                balanceFor: { _ in 5_000_000 }
            )
        )
        return insights.first { $0.type == .projectedBalance }?.metric.value
    }

    @Test("A year projects one year of spending")
    func year() {
        #expect(projectedChange(.year, expenses: 1_200_000) == Double(-1_200_000))
    }

    @Test("A quarter projects one quarter of spending")
    func quarter() {
        #expect(projectedChange(.quarter, expenses: 300_000) == Double(-300_000))
    }

    @Test("A week projects one week of spending")
    func week() {
        #expect(projectedChange(.week, expenses: 25_000) == Double(-25_000))
    }

    @Test("A month projects one month of spending")
    func month() {
        #expect(projectedChange(.month, expenses: 100_000) == Double(-100_000))
    }
}
