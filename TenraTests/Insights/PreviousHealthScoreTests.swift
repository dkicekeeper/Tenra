//
//  PreviousHealthScoreTests.swift
//  TenraTests
//
//  The health hero's trend compares the score with the one at the end of last month: the
//  same computation over the months before the current one, with the balance less this
//  month's net flow.
//
//  @MainActor: InsightsService's collaborators are MainActor types.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct PreviousHealthScoreTests {

    private let account = Account(id: "a", name: "Card", currency: "KZT", initialBalance: 0, balance: 0)

    private func makeService() -> InsightsService {
        InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: nil)
        )
    }

    /// Monthly points of (income, expenses), the last one `endingMonthsAgo` months back
    /// (0: the current month).
    private func months(_ values: [(Double, Double)], endingMonthsAgo: Int = 0) -> [PeriodDataPoint] {
        let calendar = Calendar.current
        return values.enumerated().map { index, value in
            let back = values.count - 1 - index + endingMonthsAgo
            let date = calendar.date(byAdding: .month, value: -back, to: Date())!
            let key = InsightGranularity.month.groupingKey(for: date)
            let start = InsightGranularity.month.periodStart(for: key)
            return PeriodDataPoint(
                id: key, granularity: .month, key: key,
                periodStart: start,
                periodEnd: calendar.date(byAdding: .month, value: 1, to: start)!,
                label: key, income: value.0, expenses: value.1, cumulativeBalance: nil
            )
        }
    }

    private func previousScore(_ points: [PeriodDataPoint], balance: Double) -> Int? {
        makeService().computePreviousHealthScore(
            monthPoints: points,
            baseCurrency: "KZT",
            balanceFor: { _ in balance },
            allTransactions: [],
            categories: [],
            recurringSeries: [],
            accounts: [account]
        )
    }

    private func currentScore(_ points: [PeriodDataPoint], balance: Double) -> Int {
        makeService().computeHealthScore(
            totalIncome: points.reduce(0) { $0 + $1.income },
            totalExpenses: points.reduce(0) { $0 + $1.expenses },
            latestNetFlow: points.last?.netFlow ?? 0,
            monthsInWindow: points.count,
            baseCurrency: "KZT",
            balanceFor: { _ in balance },
            allTransactions: [],
            categories: [],
            recurringSeries: [],
            accounts: [account]
        ).score
    }

    @Test("No previous score when the window does not end with the current month")
    func windowEndsEarlier() {
        let points = months([(500_000, 400_000), (500_000, 400_000)], endingMonthsAgo: 1)
        #expect(previousScore(points, balance: 1_000_000) == nil)
    }

    @Test("No previous score when nothing came in before the current month")
    func noEarlierIncome() {
        #expect(previousScore(months([(500_000, 400_000)]), balance: 1_000_000) == nil)
        #expect(previousScore(months([(0, 50_000), (500_000, 400_000)]), balance: 1_000_000) == nil)
    }

    @Test("The current month does not count: same earlier months, same balance at their end")
    func currentMonthLeftOut() {
        let earlier: [(Double, Double)] = [(500_000, 350_000), (500_000, 450_000)]
        // +100 000 this month on 1 100 000 and −300 000 on 700 000: 1 000 000 at the end of last month.
        let calm = previousScore(months(earlier + [(500_000, 400_000)]), balance: 1_100_000)
        let rough = previousScore(months(earlier + [(0, 300_000)]), balance: 700_000)
        #expect(calm != nil)
        #expect(calm == rough)
    }

    @Test("It is the score of the earlier months, with the balance at their end")
    func scoreOfEarlierMonths() {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: Date())!.start
        let expected = makeService().computeHealthScore(
            totalIncome: 1_000_000,
            totalExpenses: 800_000,
            latestNetFlow: 50_000,
            monthsInWindow: 2,
            baseCurrency: "KZT",
            balanceFor: { _ in 600_000 },
            allTransactions: [],
            categories: [],
            recurringSeries: [],
            accounts: [account],
            asOf: calendar.date(byAdding: .second, value: -1, to: monthStart)!,
            balanceAdjustment: -400_000
        ).score
        let points = months([(500_000, 350_000), (500_000, 450_000), (600_000, 200_000)])
        #expect(previousScore(points, balance: 600_000) == expected)
    }

    @Test("A month that saves more raises the score above the previous one")
    func savingMonthRaisesScore() {
        let points = months([(500_000, 500_000), (500_000, 500_000), (500_000, 100_000)])
        let previous = previousScore(points, balance: 1_000_000)
        let current = currentScore(points, balance: 1_000_000)
        #expect(previous.map { $0 < current } == true)
    }
}

@MainActor
struct HealthTrendTextTests {

    @Test("The change reads in points with its sign, a minus sign for a fall")
    func pointsText() {
        #expect(HealthScoreHeroCard.pointsText(5) == "+5")
        #expect(HealthScoreHeroCard.pointsText(-3) == "\u{2212}3")
        #expect(HealthScoreHeroCard.pointsText(0) == "0")
    }
}

@MainActor
struct SavingsRateHeroCardTests {

    @Test("Bands at 10% and 20%, a deficit below 0")
    func bands() {
        #expect(SavingsRateHeroCard.band(for: 27.8) == String(localized: "insights.savingsRate.band.onTarget"))
        #expect(SavingsRateHeroCard.band(for: 20) == String(localized: "insights.savingsRate.band.onTarget"))
        #expect(SavingsRateHeroCard.band(for: 12.4) == String(localized: "insights.savingsRate.band.belowTarget"))
        #expect(SavingsRateHeroCard.band(for: 4) == String(localized: "insights.savingsRate.band.low"))
        #expect(SavingsRateHeroCard.band(for: 0) == String(localized: "insights.savingsRate.band.low"))
        #expect(SavingsRateHeroCard.band(for: -6.2) == String(localized: "insights.savingsRate.band.deficit"))
    }

    @Test("The scale is 0–40%, wider past a higher rate")
    func scale() {
        #expect(SavingsRateHeroCard.scale(for: 12.4) == 40)
        #expect(SavingsRateHeroCard.scale(for: -6.2) == 40)
        #expect(SavingsRateHeroCard.scale(for: 60) == 69)
    }
}
