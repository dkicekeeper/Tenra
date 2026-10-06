//
//  RecurringFirstOccurrenceTests.swift
//  TenraTests
//
//  Making a one-off transaction recurring left two transactions on its date. The edit
//  screen called `createSeries(_:)`, whose generator emits occurrence 0 on the series
//  start date (the transaction's own date), and then linked the edited transaction to
//  the same series. `createSeries(_:firstOccurrence:)` makes the existing transaction
//  that occurrence instead, so the generator resumes from the next period.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct RecurringFirstOccurrenceTests {

    // MARK: - Harness

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        // validateSeries / validate require the category by name and the account by id.
        store.categories = [
            CustomCategory(name: "Food", iconSource: .sfSymbol("cart"),
                           colorHex: "#22c55e", type: .expense)
        ]
        store.accounts = [
            Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        return store
    }

    /// "yyyy-MM-dd" for today moved by `months`, then `days`.
    private static func date(months: Int = 0, days: Int = 0) -> String {
        let calendar = Calendar.current
        let moved = calendar.date(byAdding: .month, value: months, to: Date())!
        return DateFormatters.dateFormatter.string(from: calendar.date(byAdding: .day, value: days, to: moved)!)
    }

    /// A saved one-off expense, as the edit screen finds it.
    private static func addOneOff(_ store: TransactionStore, date: String) async throws -> Transaction {
        try await store.add(Transaction(
            id: "t1", date: date, description: "Gym", amount: 5000, currency: "KZT",
            type: .expense, category: "Food", accountId: "a1"
        ))
    }

    private static func monthlySeries(startDate: String) -> RecurringSeries {
        RecurringSeries(
            amount: 5000, currency: "KZT", category: "Food", description: "Gym",
            accountId: "a1", frequency: .monthly, startDate: startDate
        )
    }

    private static func seriesTransactions(_ store: TransactionStore, _ seriesId: String) -> [Transaction] {
        store.transactions.filter { $0.recurringSeriesId == seriesId }
    }

    // MARK: - Tests

    @Test("The existing transaction is the first occurrence: one transaction on the start date")
    func existingTransactionIsTheFirstOccurrence() async throws {
        let store = Self.makeStore()
        let today = Self.date()
        let original = try await Self.addOneOff(store, date: today)
        store.addSubcategory(Subcategory(id: "s1", name: "Membership"))
        store.updateTransactionSubcategoryLinks([
            TransactionSubcategoryLink(transactionId: "t1", subcategoryId: "s1")
        ])
        let series = Self.monthlySeries(startDate: today)

        try await store.createSeries(series, firstOccurrence: original)

        let onStartDate = store.transactions.filter { $0.date == today }.map(\.id)
        #expect(onStartDate == ["t1"], "no generated copy of the user's transaction on the start date")
        #expect(store.transactionById["t1"]?.recurringSeriesId == series.id)
        let linked = Self.seriesTransactions(store, series.id)
        #expect(linked.count == 2, "the user's transaction plus the next occurrence")
        let ahead = linked.filter { $0.date > today }
        #expect(ahead.count == 1, "the next occurrence is generated ahead")
        let occurrences = store.recurringOccurrences.filter { $0.seriesId == series.id }
        #expect(occurrences.count == 2)
        #expect(occurrences.contains { $0.transactionId == "t1" && $0.occurrenceDate == today })
        // Red Flag 5: the first transaction keeps its id, so its subcategory links survive.
        #expect(store.subcategoryIdsByTransactionId["t1"] == ["s1"])
    }

    @Test("A past first occurrence backfills each later period once, then one ahead")
    func pastFirstOccurrenceBackfillsWithoutDuplicates() async throws {
        let store = Self.makeStore()
        let start = Self.date(months: -2)
        let today = Self.date()
        let original = try await Self.addOneOff(store, date: start)
        let series = Self.monthlySeries(startDate: start)

        try await store.createSeries(series, firstOccurrence: original)

        let dates = Self.seriesTransactions(store, series.id).map(\.date)
        #expect(Set(dates).count == dates.count, "one transaction per occurrence date")
        let onStartDate = store.transactions.filter { $0.date == start }.map(\.id)
        #expect(onStartDate == ["t1"])
        let ahead = dates.filter { $0 > today }
        #expect(ahead.count == 1)
        #expect(dates.count == 4, "start, two backfilled periods, one ahead")
    }

    @Test("A future first occurrence already is the series' next occurrence")
    func futureFirstOccurrenceGeneratesNothingMore() async throws {
        let store = Self.makeStore()
        let start = Self.date(days: 10)
        let original = try await Self.addOneOff(store, date: start)
        let series = Self.monthlySeries(startDate: start)

        try await store.createSeries(series, firstOccurrence: original)

        let linkedIds = Self.seriesTransactions(store, series.id).map(\.id)
        #expect(linkedIds == ["t1"])
        let occurrences = store.recurringOccurrences.filter { $0.seriesId == series.id }
        #expect(occurrences.count == 1)
    }

    @Test("A transaction that is not in the store changes nothing")
    func missingTransactionChangesNothing() async throws {
        let store = Self.makeStore()
        let today = Self.date()
        let ghost = Transaction(
            id: "ghost", date: today, description: "Gym", amount: 5000, currency: "KZT",
            type: .expense, category: "Food", accountId: "a1"
        )

        var thrown: TransactionStoreError?
        do {
            try await store.createSeries(Self.monthlySeries(startDate: today), firstOccurrence: ghost)
        } catch let error as TransactionStoreError {
            thrown = error
        }

        guard case .transactionNotFound = thrown else {
            Issue.record("expected .transactionNotFound, got \(String(describing: thrown))")
            return
        }
        #expect(store.recurringSeries.isEmpty)
        #expect(store.transactions.isEmpty)
    }
}
