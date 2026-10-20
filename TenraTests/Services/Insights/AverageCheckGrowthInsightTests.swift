//
//  AverageCheckGrowthInsightTests.swift
//  TenraTests
//
//  Pins `generateAverageCheckGrowth`: the last 90 days against the 90 before, 3+ visits in
//  each, up 15 % or more, the largest growth in money winning; subscriptions left out.
//
//  @MainActor: InsightsService's dependencies are MainActor-isolated.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct AverageCheckGrowthInsightTests {

    private let now = FastDateParser.date(from: "2026-10-20")!.addingTimeInterval(12 * 3600)

    // Returns the store too: it must be retained for the service's lifetime (CLAUDE.md).
    private static func makeService() -> (InsightsService, TransactionStore) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let balance = BalanceCoordinator(repository: repo)
        let recurring = RecurringStore(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: recurring)
        let service = InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: store)
        )
        return (service, store)
    }

    private func tx(_ description: String, _ date: String, _ amount: Double, series: String? = nil) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: date, description: description, amount: amount, currency: "KZT",
            type: .expense, category: "Food", accountId: "a1", recurringSeriesId: series
        )
    }

    /// Three or four visits before (May–June) and after (August–October).
    private func visits(_ description: String, before: Double, after: Double, count: Int = 3, series: String? = nil) -> [Transaction] {
        let earlier = ["2026-05-01", "2026-05-15", "2026-06-01", "2026-06-15"].prefix(count)
        let recent = ["2026-08-01", "2026-09-01", "2026-10-01", "2026-10-15"].prefix(count)
        return earlier.map { tx(description, $0, before, series: series) } + recent.map { tx(description, $0, after, series: series) }
    }

    private func insight(_ transactions: [Transaction]) -> Insight? {
        let (service, store) = Self.makeService()
        _ = store
        return service.generateAverageCheckGrowth(baseCurrency: "KZT", transactions: transactions, now: now)
    }

    @Test("The largest growth in money wins over the largest in percent")
    func largestInMoney() throws {
        let found = try #require(insight(
            visits("MAGNUM 12", before: 10_000, after: 13_000)           // +30 %, 9 000 more
                + visits("COFFEE BOOM 3", before: 1_000, after: 1_500, count: 4)  // +50 %, 2 000 more
        ))
        #expect(found.type == .averageCheckGrowth)
        #expect(found.subtitle == "Magnum")
        #expect(found.metric.value == 13_000)
        #expect(abs((found.trend?.changePercent ?? 0) - 30) < 0.001)
        guard case .barPair(let previous, let current, _, _)? = found.cardVisual else {
            Issue.record("expected a was/now pair")
            return
        }
        #expect(previous == 10_000)
        #expect(current == 13_000)
    }

    @Test("Too few visits, a small rise or a subscription make no card")
    func notOffered() {
        #expect(insight(visits("SMALL", before: 1_000, after: 2_000, count: 2)) == nil)
        #expect(insight(visits("GREENMART", before: 10_000, after: 11_000)) == nil)
        #expect(insight(visits("NETFLIX", before: 3_000, after: 4_500, series: "s1")) == nil)
    }
}
