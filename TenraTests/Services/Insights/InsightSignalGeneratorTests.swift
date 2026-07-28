//
//  InsightSignalGeneratorTests.swift
//  TenraTests
//
//  Tests for the audit-2026-07 signal generators:
//    - generateSubscriptionPriceIncreases (Emma/Rocket-style price bump detection)
//    - generateLargeTransaction (Copilot-style big non-recurring expense)
//
//  @MainActor: InsightsService's dependencies (TransactionStore, CategoryBudgetService)
//  are MainActor-isolated under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct InsightSignalGeneratorTests {

    private let kCurrency = "KZT"

    // Returns the store too — it must be retained for the service's lifetime (CLAUDE.md).
    private static func makeService() -> (InsightsService, TransactionStore) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: recurring)
        let service = InsightsService(
            transactionStore: store,
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: store)
        )
        return (service, store)
    }

    private func dateString(daysAgo: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return DateFormatters.dateFormatter.string(from: d)
    }

    private func makeTx(
        daysAgo: Int,
        amount: Double,
        type: TransactionType = .expense,
        category: String = "Развлечения",
        seriesId: String? = nil,
        currency: String? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: dateString(daysAgo: daysAgo),
            description: "Test",
            amount: amount,
            currency: currency ?? kCurrency,
            type: type,
            category: category,
            recurringSeriesId: seriesId
        )
    }

    private func makeSeries(
        id: String = UUID().uuidString,
        amount: Decimal,
        category: String = "Развлечения",
        frequency: RecurringFrequency = .monthly,
        isActive: Bool = true
    ) -> RecurringSeries {
        RecurringSeries(
            id: id,
            isActive: isActive,
            amount: amount,
            currency: kCurrency,
            category: category,
            description: "Netflix",
            frequency: frequency,
            startDate: dateString(daysAgo: 90)
        )
    }

    private var expenseCategories: [CustomCategory] {
        [CustomCategory(name: "Развлечения", colorHex: "#FF0000", type: .expense),
         CustomCategory(name: "Зарплата", colorHex: "#00FF00", type: .income)]
    }

    // MARK: - Price Increase

    @Test("price increase >5% between the two latest charges is detected")
    func priceIncreaseDetected() {
        let (service, store) = Self.makeService()
        _ = store
        let series = makeSeries(id: "s1", amount: 5_000)
        let txs = [
            makeTx(daysAgo: 35, amount: 5_000, seriesId: "s1"),
            makeTx(daysAgo: 3, amount: 6_000, seriesId: "s1")
        ]
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [series], categories: expenseCategories, transactions: txs
        )
        #expect(insights.count == 1)
        #expect(insights.first?.id == "price_increase_s1")
        #expect(insights.first?.severity == .warning)
        #expect(insights.first?.type == .subscriptionPriceIncrease)
        // +20% change
        #expect(abs((insights.first?.trend?.changePercent ?? 0) - 20) < 0.01)
    }

    @Test("increase within the 5% tolerance does not fire")
    func smallIncreaseIgnored() {
        let (service, store) = Self.makeService()
        _ = store
        let series = makeSeries(id: "s1", amount: 5_000)
        let txs = [
            makeTx(daysAgo: 35, amount: 5_000, seriesId: "s1"),
            makeTx(daysAgo: 3, amount: 5_200, seriesId: "s1") // +4%
        ]
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [series], categories: expenseCategories, transactions: txs
        )
        #expect(insights.isEmpty)
    }

    @Test("single occurrence falls back to the series amount as baseline")
    func singleOccurrenceUsesSeriesAmount() {
        let (service, store) = Self.makeService()
        _ = store
        let series = makeSeries(id: "s1", amount: 5_000)
        let txs = [makeTx(daysAgo: 3, amount: 7_000, seriesId: "s1")] // +40% vs series amount
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [series], categories: expenseCategories, transactions: txs
        )
        #expect(insights.count == 1)
        #expect(abs((insights.first?.trend?.changePercent ?? 0) - 40) < 0.01)
    }

    @Test("inactive and income series never fire")
    func inactiveAndIncomeSeriesExcluded() {
        let (service, store) = Self.makeService()
        _ = store
        let paused = makeSeries(id: "s1", amount: 5_000, isActive: false)
        let income = makeSeries(id: "s2", amount: 5_000, category: "Зарплата")
        let txs = [
            makeTx(daysAgo: 35, amount: 5_000, seriesId: "s1"),
            makeTx(daysAgo: 3, amount: 9_000, seriesId: "s1"),
            makeTx(daysAgo: 35, amount: 5_000, type: .income, category: "Зарплата", seriesId: "s2"),
            makeTx(daysAgo: 3, amount: 9_000, type: .income, category: "Зарплата", seriesId: "s2")
        ]
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [paused, income], categories: expenseCategories, transactions: txs
        )
        #expect(insights.isEmpty)
    }

    @Test("emits at most 3 insights, largest increase first")
    func cappedAtThreeSortedByPercent() {
        let (service, store) = Self.makeService()
        _ = store
        var series: [RecurringSeries] = []
        var txs: [Transaction] = []
        // 4 series with increases +10%, +20%, +30%, +40%
        for (i, pct) in [10.0, 20.0, 30.0, 40.0].enumerated() {
            let id = "s\(i)"
            series.append(makeSeries(id: id, amount: 1_000))
            txs.append(makeTx(daysAgo: 35, amount: 1_000, seriesId: id))
            txs.append(makeTx(daysAgo: 3, amount: 1_000 * (1 + pct / 100), seriesId: id))
        }
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: series, categories: expenseCategories, transactions: txs
        )
        #expect(insights.count == 3)
        #expect(insights.first?.id == "price_increase_s3") // +40%
        #expect(insights.last?.id == "price_increase_s1")  // +20% (s0 +10% dropped)
    }

    @Test("monthly→yearly plan switch is not a price increase (Wolt bug)")
    func planSwitchSuppressed() {
        let (service, store) = Self.makeService()
        _ = store
        // Series edited to yearly 9 588; history: monthly 1 199 charges, then the
        // first yearly charge ~30 days after the last monthly one.
        let series = makeSeries(id: "s1", amount: 9_588, frequency: .yearly)
        let txs = [
            makeTx(daysAgo: 65, amount: 1_199, seriesId: "s1"),
            makeTx(daysAgo: 33, amount: 1_199, seriesId: "s1"),
            makeTx(daysAgo: 3, amount: 9_588, seriesId: "s1")
        ]
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [series], categories: expenseCategories, transactions: txs
        )
        #expect(insights.isEmpty)
    }

    @Test("same-period jump above 300% is treated as a plan switch, not a hike")
    func implausibleJumpSuppressed() {
        let (service, store) = Self.makeService()
        _ = store
        // Series still marked monthly but the latest charge is a yearly-plan amount.
        let series = makeSeries(id: "s1", amount: 1_199)
        let txs = [
            makeTx(daysAgo: 33, amount: 1_199, seriesId: "s1"),
            makeTx(daysAgo: 3, amount: 9_588, seriesId: "s1") // +699.7%
        ]
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [series], categories: expenseCategories, transactions: txs
        )
        #expect(insights.isEmpty)
    }

    @Test("charge gap that doesn't match the series frequency does not fire")
    func gapMismatchSuppressed() {
        let (service, store) = Self.makeService()
        _ = store
        // Monthly series, but 100 days between the compared charges (missed /
        // unlinked months) — baseline is stale, comparison unreliable.
        let series = makeSeries(id: "s1", amount: 5_000)
        let txs = [
            makeTx(daysAgo: 103, amount: 5_000, seriesId: "s1"),
            makeTx(daysAgo: 3, amount: 6_000, seriesId: "s1")
        ]
        let insights = service.generateSubscriptionPriceIncreases(
            recurringSeries: [series], categories: expenseCategories, transactions: txs
        )
        #expect(insights.isEmpty)
    }

    // MARK: - Large Transaction

    /// 25 small expenses (1 000 each) spread over the last 90 days as baseline noise.
    private func baselineNoise() -> [Transaction] {
        (0..<25).map { makeTx(daysAgo: 40 + $0, amount: 1_000) }
    }

    @Test("a non-recurring expense ≥4× the 90d average is detected")
    func largeTransactionDetected() {
        let (service, store) = Self.makeService()
        _ = store
        var txs = baselineNoise()
        txs.append(makeTx(daysAgo: 5, amount: 30_000)) // ~×14.5 the average
        let insight = service.generateLargeTransaction(baseCurrency: kCurrency, transactions: txs)
        #expect(insight != nil)
        #expect(insight?.type == .largeTransaction)
        #expect(insight?.severity == .warning) // ≥8× → warning
        #expect(insight?.id.hasPrefix("large_tx_") == true)
    }

    @Test("recurring charges never fire the large-transaction signal")
    func recurringExcluded() {
        let (service, store) = Self.makeService()
        _ = store
        var txs = baselineNoise()
        txs.append(makeTx(daysAgo: 5, amount: 30_000, seriesId: "rent")) // recurring — excluded
        let insight = service.generateLargeTransaction(baseCurrency: kCurrency, transactions: txs)
        #expect(insight == nil)
    }

    @Test("thin history (<20 baseline transactions) returns nil")
    func thinBaselineReturnsNil() {
        let (service, store) = Self.makeService()
        _ = store
        var txs = (0..<10).map { makeTx(daysAgo: 40 + $0, amount: 1_000) }
        txs.append(makeTx(daysAgo: 5, amount: 30_000))
        let insight = service.generateLargeTransaction(baseCurrency: kCurrency, transactions: txs)
        #expect(insight == nil)
    }

    @Test("an expense below the 4× threshold returns nil")
    func belowThresholdReturnsNil() {
        let (service, store) = Self.makeService()
        _ = store
        var txs = baselineNoise()
        txs.append(makeTx(daysAgo: 5, amount: 2_500)) // ~2.3× avg — below 4×
        let insight = service.generateLargeTransaction(baseCurrency: kCurrency, transactions: txs)
        #expect(insight == nil)
    }
}
