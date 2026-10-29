//
//  SpendingByDayInsightTests.swift
//  TenraTests
//
//  Pins `generateSpendingByDay` ("By day"): each weekday's average over the last 16 weeks,
//  subscriptions and one-offs far above the usual expense left out, the busiest weekday as the
//  metric, and what stands out (weekends, a category on its weekday).
//
//  @MainActor: InsightsService's dependencies are MainActor-isolated.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct SpendingByDayInsightTests {

    /// Wednesday 28 October 2026, noon.
    private let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)
    private let longAgo = FastDateParser.date(from: "2026-01-01")!

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

    private func tx(_ date: Date, _ amount: Double, category: String, series: String? = nil) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: DateFormatters.dateFormatter.string(from: date), description: "",
            amount: amount, currency: "KZT", type: .expense, category: category, accountId: "a1",
            recurringSeriesId: series
        )
    }

    /// Every day of the last 16 weeks: 5 000 at restaurants on Saturdays, 1 000 on food the
    /// other days.
    private func everyday() -> [Transaction] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<112).compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return calendar.component(.weekday, from: day) == 7
                ? tx(day, 5_000, category: "Restaurants")
                : tx(day, 1_000, category: "Food")
        }
    }

    private func insight(_ transactions: [Transaction], firstTransactionDate: Date? = nil) -> Insight? {
        let (service, store) = Self.makeService()
        _ = store
        return service.generateSpendingByDay(
            baseCurrency: "KZT", transactions: transactions, categories: [],
            firstTransactionDate: firstTransactionDate ?? longAgo, now: now
        )
    }

    private func dayOfWeek(_ weekday: Int, back weeks: Int) -> Date {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        while calendar.component(.weekday, from: day) != weekday {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return calendar.date(byAdding: .day, value: -7 * weeks, to: day)!
    }

    @Test("Saturday is the busiest; a subscription and a one-off far above the usual are left out")
    func busiestWeekday() throws {
        let extra = [
            tx(dayOfWeek(3, back: 2), 50_000, category: "Rent", series: "s1"),   // a Tuesday's rent
            tx(dayOfWeek(2, back: 3), 100_000, category: "Electronics"),         // a Monday's laptop
        ]
        let found = try #require(insight(everyday() + extra))
        #expect(found.type == .spendingByDay)
        #expect(found.id == "spending_by_day")
        #expect(found.metric.value == 5_000)
        guard case .weekdayPattern(let detail)? = found.detailData else {
            Issue.record("expected the weekday pattern")
            return
        }
        let byId = Dictionary(uniqueKeysWithValues: detail.weekdays.map { ($0.id, $0) })
        #expect(byId[7]?.average == 5_000)
        #expect(byId[2]?.average == 1_000)
        #expect(byId[3]?.average == 1_000)
        #expect(detail.weekdays[detail.busiestIndex].id == 7)
        #expect(detail.patterns.contains { $0.id == "weekends" })
        #expect(detail.patterns.contains { $0.id == "category_Restaurants" })
        guard case .weekdayBars(let values, let highlighted, let labels)? = found.cardVisual else {
            Issue.record("expected the weekday bars")
            return
        }
        #expect(values.count == 7)
        #expect(labels.count == 7)
        #expect(highlighted == detail.busiestIndex)
    }

    @Test("Too few expenses or too short a history make no card")
    func notOffered() {
        #expect(insight(Array(everyday().prefix(10))) == nil)
        let recent = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        #expect(insight(everyday(), firstTransactionDate: recent) == nil)
    }
}
