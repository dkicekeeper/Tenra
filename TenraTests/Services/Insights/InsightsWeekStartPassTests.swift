//
//  InsightsWeekStartPassTests.swift
//  TenraTests
//
//  One insights pass, one first day of the week: the week points take the calendar the pass
//  was handed (`DataSnapshot.calendar`) for the window, the cursor's keys, each key's start
//  and end, even when the stored choice (FormatSettings.snapshot) says another day.
//
//  @MainActor: InsightsService's dependencies are MainActor-isolated.
//  `.sharedProcessState`: writes `FormatSettings.snapshot`, and restores it.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite("Insights pass week start", .serialized, .sharedProcessState)
struct InsightsWeekStartPassTests {

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

    /// The stored choice: weeks from Monday.
    private static func storeMondayChoice() throws {
        let defaults = try #require(UserDefaults(suiteName: "InsightsWeekStartPassTests.\(UUID().uuidString)"))
        var choices = FormatChoices()
        choices.firstWeekday = 2
        defaults.set(try JSONEncoder().encode(choices), forKey: FormatSettings.storageKey)
        FormatSettings.resetSnapshot(defaults: defaults)
    }

    private func expense(_ day: Date, _ amount: Double) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: FastDateParser.string(from: day), description: "",
            amount: amount, currency: "KZT", type: .expense, category: "Food", accountId: "a1"
        )
    }

    /// A Sunday-calendar pass while the snapshot says Monday: every week point starts on a
    /// Sunday and ends a week later, and a Sunday and the Saturday after it are one week.
    @Test func aSundayPassGroupsWeeksFromSunday() throws {
        try Self.storeMondayChoice()
        defer { FormatSettings.resetSnapshot() }
        #expect(AppCalendar.current.firstWeekday == 2)

        var sunday = Calendar.current
        sunday.firstWeekday = 1
        let thisWeek = try #require(sunday.dateInterval(of: .weekOfYear, for: Date())).start
        let lastSunday = try #require(sunday.date(byAdding: .day, value: -7, to: thisWeek))
        let saturdayAfter = try #require(sunday.date(byAdding: .day, value: 6, to: lastSunday))
        let earlier = try #require(sunday.date(byAdding: .day, value: -30, to: lastSunday))

        let (service, store) = Self.makeService()
        _ = store
        let points = service.computePeriodDataPoints(
            transactions: [expense(earlier, 10), expense(lastSunday, 100), expense(saturdayAfter, 50)],
            granularity: .week,
            baseCurrency: "KZT",
            firstTransactionDate: earlier,
            calendar: sunday
        )

        #expect(!points.isEmpty)
        for point in points {
            #expect(sunday.component(.weekday, from: point.periodStart) == 1, "\(point.key) starts \(point.periodStart)")
            #expect(point.periodEnd == sunday.date(byAdding: .weekOfYear, value: 1, to: point.periodStart))
        }
        let week = try #require(points.first { $0.periodStart == lastSunday })
        #expect(week.expenses == 150)
        #expect(points.reduce(0) { $0 + $1.expenses } == 160)
    }
}
