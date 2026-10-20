//
//  TopMerchantInsightTests.swift
//  TenraTests
//
//  Pins `generateTopMerchant`: one merchant across its store numbers, the share of the
//  bucket's realized expenses (loan payments and category-name notes included in the total,
//  never as merchants), the current bucket only, and no card for fewer than three merchants.
//
//  @MainActor: InsightsService's dependencies are MainActor-isolated.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TopMerchantInsightTests {

    private let currency = "KZT"

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

    private func tx(
        _ description: String,
        _ amount: Double,
        daysAgo: Int = 0,
        type: TransactionType = .expense,
        category: String = "Food"
    ) -> Transaction {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return Transaction(
            id: UUID().uuidString,
            date: DateFormatters.dateFormatter.string(from: date),
            description: description,
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            accountId: "a1"
        )
    }

    private func topMerchant(_ transactions: [Transaction], granularity: InsightGranularity = .allTime) -> Insight? {
        let (service, store) = Self.makeService()
        _ = store
        return service.generateTopMerchant(
            transactions: transactions,
            granularity: granularity,
            periodPoints: [],
            txDateMap: nil,
            baseCurrency: currency,
            categories: []
        )
    }

    @Test("Store numbers are one merchant; the share is of every realized expense")
    func topMerchantAndShare() throws {
        let insight = try #require(topMerchant([
            tx("MAGNUM 12", 4_000, daysAgo: 3),
            tx("MAGNUM 45", 5_000, daysAgo: 2),
            tx("SMALL", 2_000),
            tx("COFFEE BOOM", 1_000),
            tx("Food", 2_000),                                         // a note, not a merchant
            tx("Loan", 1_000, type: .loanPayment, category: "Loan"),    // no shop
            tx("SALARY", 50_000, type: .income),
            tx("MAGNUM 12", 9_000, daysAgo: -5)                         // future: not realized
        ]))
        #expect(insight.type == .topMerchant)
        #expect(insight.subtitle == "Magnum")
        #expect(insight.metric.value == 9_000)
        guard case .categoryBreakdown(let items) = insight.detailData else {
            Issue.record("expected a breakdown")
            return
        }
        #expect(items.map(\.id) == ["magnum", "small", "coffee boom"])
        #expect(abs(items[0].percentage - 60) < 0.001)
    }

    @Test("Fewer than three merchants make no card")
    func tooFewMerchants() {
        #expect(topMerchant([tx("MAGNUM 12", 4_000), tx("SMALL", 2_000)]) == nil)
    }

    @Test("Only the current bucket counts")
    func currentBucketOnly() throws {
        let insight = try #require(topMerchant([
            tx("SMALL", 300),
            tx("COFFEE BOOM", 200),
            tx("GREENMART", 100),
            tx("MAGNUM 12", 90_000, daysAgo: 70)
        ], granularity: .month))
        #expect(insight.subtitle == "Small")
        guard case .categoryBreakdown(let items) = insight.detailData else {
            Issue.record("expected a breakdown")
            return
        }
        #expect(!items.contains { $0.id == "magnum" })
    }
}
