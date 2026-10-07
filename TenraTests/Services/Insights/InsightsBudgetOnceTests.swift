//
//  InsightsBudgetOnceTests.swift
//  TenraTests
//
//  Budget insights used to be generated for each of the five granularities, though a
//  budget's spent covers the budget's own period (week, month from the reset day, year)
//  whatever the granularity, and each run parsed every expense of the category with a
//  DateFormatter. Pins: the spent figure is the one the DateFormatter + filter/reduce
//  version produced; every granularity gets the same budget insights; a reused set is
//  taken as is (not recomputed) and keeps its place in the feed.
//
//  @MainActor + .sharedProcessState: conversion reads the process-global
//  CurrencyRateStore.shared, seeded per test and cleared in init; the Insights
//  collaborators are MainActor types.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct InsightsBudgetOnceTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Reference: calculateSpentLegacy before 2026-10, verbatim

    private static func referenceSpent(
        for category: CustomCategory,
        transactions: [Transaction],
        baseCurrency: String?
    ) -> Double {
        let periodStart = CategoryBudgetService.legacyBudgetPeriodStart(for: category)
        let periodEnd = Date()
        let dateFormatter = DateFormatters.dateFormatter

        return transactions
            .filter { tx in
                guard tx.category == category.name,
                      tx.type == .expense,
                      let d = dateFormatter.date(from: tx.date) else { return false }
                return d >= periodStart && d <= periodEnd
            }
            .reduce(0) { sum, tx in
                guard let base = baseCurrency else { return sum + tx.amount }
                return sum + CategoryBudgetCurrency.toBase(amount: tx.amount, from: tx.currency, base: base).amount
            }
    }

    // MARK: - Fixture

    private static func seedRates() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 512.37, "EUR": 553.91],
            date: Date(),
            providerName: "test"
        ))
    }

    private static func day(_ offset: Int) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        return DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: offset, to: today)!
        )
    }

    private static func tx(
        _ id: String,
        _ date: String,
        _ amount: Double,
        category: String,
        type: TransactionType = .expense,
        currency: String = "KZT"
    ) -> Transaction {
        Transaction(
            id: id, date: date, description: "", amount: amount, currency: currency,
            type: type, category: category, accountId: "a1"
        )
    }

    private static func budget(
        _ id: String,
        _ name: String,
        amount: Double,
        period: CustomCategory.BudgetPeriod,
        resetDay: Int = 1
    ) -> CustomCategory {
        CustomCategory(
            id: id, name: name, iconSource: .sfSymbol("cart"), colorHex: "#22c55e",
            type: .expense, budgetAmount: amount, budgetPeriod: period, budgetResetDay: resetDay
        )
    }

    /// ~2 years of expenses in three currencies (one without a rate), with income and loan
    /// payments tagged to the same categories, future-dated rows and unparseable dates.
    private static func randomTransactions() -> [Transaction] {
        let categories = ["Food", "Transport", "Fun"]
        let currencies = ["KZT", "KZT", "USD", "ZZZ"]
        let types: [TransactionType] = [.expense, .expense, .expense, .income, .loanPayment]
        var seed: UInt64 = 7
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        return (0..<2_000).map { i in
            let date = next(80) == 0 ? ["garbage", "", "2026-13-01"][next(3)] : day(next(760) - 730)
            return tx(
                "r\(i)", date, Double(next(2_000_000)) / 100,
                category: categories[next(categories.count)],
                type: types[next(types.count)],
                currency: currencies[next(currencies.count)]
            )
        }
    }

    /// A small book that produces an over-budget and an under-budget card plus regular
    /// spending / income insights around them.
    private static func feedFixture() -> (transactions: [Transaction], categories: [CustomCategory]) {
        var transactions: [Transaction] = [
            tx("f1", day(0), 30_000, category: "Food"),
            tx("f2", day(0), 50, category: "Food", currency: "USD"),
            tx("f3", day(5), 9_999, category: "Food"),           // future: not spent yet
            tx("t1", day(0), 1_000, category: "Transport"),
        ]
        for month in 1...14 {
            let offset = -30 * month
            transactions.append(tx("s\(month)", day(offset), 400_000, category: "Salary", type: .income))
            transactions.append(tx("e\(month)", day(offset + 2), Double(20_000 + month * 1_000), category: "Food"))
            transactions.append(tx("u\(month)", day(offset + 3), 7_000, category: "Transport"))
        }
        let categories = [
            budget("food", "Food", amount: 10_000, period: .monthly),
            budget("transport", "Transport", amount: 1_000_000, period: .weekly),
            budget("fun", "Fun", amount: 500_000, period: .yearly),
            CustomCategory(id: "salary", name: "Salary", iconSource: .sfSymbol("banknote"),
                           colorHex: "#3b82f6", type: .income)
        ]
        return (transactions, categories)
    }

    private func makeService() -> InsightsService {
        InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: nil)
        )
    }

    private func compute(
        _ granularities: [InsightGranularity],
        service: InsightsService,
        transactions: [Transaction],
        categories: [CustomCategory],
        sharedInsights: [Insight]? = nil
    ) -> (results: [InsightGranularity: (insights: [Insight], periodPoints: [PeriodDataPoint])], sharedInsights: [Insight]) {
        service.computeGranularities(
            granularities,
            transactions: transactions,
            baseCurrency: "KZT",
            cacheManager: TransactionCacheManager(),
            currencyService: TransactionCurrencyService(),
            snapshot: InsightsService.DataSnapshot(
                transactions: transactions,
                categories: categories,
                recurringSeries: [],
                accounts: [],
                balanceFor: { _ in 0 }
            ),
            firstTransactionDate: nil,
            sharedInsights: sharedInsights
        )
    }

    private func budgetInsights(_ insights: [Insight]) -> [Insight] {
        insights.filter { InsightsService.budgetInsightIDs.contains($0.id) }
    }

    // MARK: - Spent

    @Test("spent equals the DateFormatter + filter/reduce version for every period and base")
    func spentMatchesReference() {
        Self.seedRates()
        let transactions = Self.randomTransactions()
        let categories = [
            Self.budget("w", "Food", amount: 1, period: .weekly),
            Self.budget("m1", "Food", amount: 1, period: .monthly, resetDay: 1),
            Self.budget("m15", "Transport", amount: 1, period: .monthly, resetDay: 15),
            Self.budget("m31", "Fun", amount: 1, period: .monthly, resetDay: 31),
            Self.budget("y", "Fun", amount: 1, period: .yearly)
        ]
        var anySpent = false

        for category in categories {
            for base in ["KZT", "USD", nil] as [String?] {
                let reference = Self.referenceSpent(for: category, transactions: transactions, baseCurrency: base)
                let live = CategoryBudgetService.calculateSpentLegacy(
                    for: category, transactions: transactions, baseCurrency: base
                )
                let frozen = CategoryBudgetService.calculateSpentLegacy(
                    for: category, transactions: transactions, baseCurrency: base, rates: RateSnapshot()
                )
                #expect(live == reference, "\(category.id) in \(base ?? "raw")")
                #expect(frozen == reference, "\(category.id) in \(base ?? "raw"), rate snapshot")
                if base == "KZT", reference > 0 { anySpent = true }
            }
        }
        #expect(anySpent, "fixture produced no spent at all")
    }

    // MARK: - Once per refresh

    @Test("every granularity gets the same budget insights, computed from all transactions")
    func sameBudgetInsightsForEveryGranularity() throws {
        Self.seedRates()
        let (transactions, categories) = Self.feedFixture()
        let service = makeService()

        let direct = service.generateBudgetInsights(
            transactions: transactions,
            baseCurrency: "KZT",
            categories: categories
        )
        #expect(Set(direct.map(\.id)) == ["budget_over", "budget_under"])

        let results = compute(InsightGranularity.allCases, service: service,
                              transactions: transactions, categories: categories).results
        for granularity in InsightGranularity.allCases {
            let insights = try #require(results[granularity]?.insights)
            #expect(budgetInsights(insights) == direct, "\(granularity)")
        }
    }

    @Test("a later granularity takes the shared budget insights as they are, in the same slot")
    func reusedBudgetInsightsKeepTheirSlot() throws {
        Self.seedRates()
        let (transactions, categories) = Self.feedFixture()
        let service = makeService()

        let fresh = compute([.month], service: service, transactions: transactions, categories: categories)
        let freshInsights = try #require(fresh.results[.month]?.insights)
        #expect(!budgetInsights(freshInsights).isEmpty)

        // Mark the shared budget insights: a recomputation would not carry the mark.
        let marked = fresh.sharedInsights.map { insight -> Insight in
            guard InsightsService.budgetInsightIDs.contains(insight.id) else { return insight }
            return Insight(
                id: insight.id, type: insight.type, title: "shared", subtitle: insight.subtitle,
                metric: insight.metric, trend: insight.trend, severity: insight.severity,
                category: insight.category, detailData: insight.detailData,
                cardVisual: insight.cardVisual
            )
        }
        let reused = try #require(compute(
            [.month], service: service, transactions: transactions,
            categories: categories, sharedInsights: marked
        ).results[.month]?.insights)

        let reusedBudget = budgetInsights(reused)
        #expect(reusedBudget.map(\.id) == budgetInsights(freshInsights).map(\.id))
        #expect(reusedBudget.allSatisfy { $0.title == "shared" })

        // Same feed order once the other shared insights (appended at the end when
        // reused, a pre-existing behaviour) are set aside: the budget cards did not move.
        let otherShared = Set(fresh.sharedInsights.map(\.id)).subtracting(InsightsService.budgetInsightIDs)
        #expect(
            reused.map(\.id).filter { !otherShared.contains($0) }
                == freshInsights.map(\.id).filter { !otherShared.contains($0) }
        )
    }
}
