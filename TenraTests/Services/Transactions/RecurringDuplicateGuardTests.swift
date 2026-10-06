//
//  RecurringDuplicateGuardTests.swift
//  TenraTests
//
//  A recurring series must never get a second transaction on a day it already has one.
//  The generator skipped a day only through its occurrence records (saved 300 ms after a
//  change) or a matching transaction id, and ids hash with a seed that changes every
//  launch: a series whose records were lost started over from its start date and added a
//  copy of every transaction it already had. The days of the series' own transactions now
//  count as occurrences, and a batch never adds an id the store already holds.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct RecurringDuplicateGuardTests {

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

    /// "yyyy-MM-dd" for today moved by `months`.
    private static func date(months: Int = 0) -> String {
        let moved = Calendar.current.date(byAdding: .month, value: months, to: Date())!
        return DateFormatters.dateFormatter.string(from: moved)
    }

    private static var today: String { date() }

    private static func monthlySeries(startDate: String) -> RecurringSeries {
        RecurringSeries(
            amount: 5000, currency: "KZT", category: "Food", description: "Gym",
            accountId: "a1", frequency: .monthly, startDate: startDate
        )
    }

    private static let account = Account(id: "a1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0)

    private static func seriesTransactions(_ store: TransactionStore, _ seriesId: String) -> [Transaction] {
        store.transactions.filter { $0.recurringSeriesId == seriesId }
    }

    // MARK: - Generator

    @Test("Days the series already has a transaction on are not generated again")
    func transactionDaysCountAsOccurrences() {
        let generator = RecurringTransactionGenerator(dateFormatter: DateFormatters.dateFormatter)
        let series = Self.monthlySeries(startDate: Self.date(months: -2))

        let full = generator.generateUpToNextFuture(
            series: series, existingOccurrences: [], existingTransactionIds: [],
            accounts: [Self.account], baseCurrency: "KZT"
        )
        let scheduled = full.transactions.map(\.date)
        #expect(scheduled.count >= 3, "two past occurrences and the next one at least")

        // No occurrence records and different ids (another launch), but the series already
        // has transactions on its first two days.
        let alreadyThere = Set(scheduled.prefix(2))
        let resumed = generator.generateUpToNextFuture(
            series: series, existingOccurrences: [], existingTransactionIds: [],
            transactionDays: alreadyThere,
            accounts: [Self.account], baseCurrency: "KZT"
        )

        #expect(Set(resumed.transactions.map(\.date)) == Set(scheduled.dropFirst(2)))
    }

    @Test("The horizon generator skips the series' transaction days too")
    func horizonGeneratorSkipsTransactionDays() {
        let generator = RecurringTransactionGenerator(dateFormatter: DateFormatters.dateFormatter)
        let series = Self.monthlySeries(startDate: Self.date(months: -2))

        let full = generator.generateTransactions(
            series: [series], existingOccurrences: [], existingTransactionIds: [],
            accounts: [Self.account], baseCurrency: "KZT"
        )
        let all = Set(full.transactions.map(\.date))
        let alreadyThere = Set(full.transactions.map(\.date).sorted().prefix(2))

        let again = generator.generateTransactions(
            series: [series], existingOccurrences: [], existingTransactionIds: [],
            transactionDaysBySeries: [series.id: alreadyThere],
            accounts: [Self.account], baseCurrency: "KZT"
        )

        #expect(Set(again.transactions.map(\.date)) == all.subtracting(alreadyThere))
    }

    // MARK: - Store

    @Test("A batch never adds a transaction the store already holds")
    func bulkAddSkipsKnownIds() async throws {
        let store = Self.makeStore()
        let tx = Transaction(
            id: "dup", date: Self.today, description: "Coffee", amount: 1200, currency: "KZT",
            type: .expense, category: "Food", accountId: "a1"
        )

        try await store.addBatch([tx])
        try await store.addBatch([tx])

        #expect(store.transactions.filter { $0.id == "dup" }.count == 1)
        #expect(store.transactionsCount == 1)
    }

    @Test("Lost occurrence records and other ids: extending the horizon adds no copies")
    func extendAfterLostOccurrencesAddsNoCopies() async throws {
        let store = Self.makeStore()
        let series = Self.monthlySeries(startDate: Self.date(months: -2))
        try await store.createSeries(series)
        let generated = Self.seriesTransactions(store, series.id).sorted { $0.date < $1.date }
        #expect(generated.count >= 3)

        // As after a relaunch whose hash seed differs and whose occurrence save never
        // landed: the same days under other ids, and no occurrence records.
        for tx in generated {
            try await store.delete(tx)
        }
        let previousLaunch = generated.enumerated().map { index, tx in
            Transaction(
                id: "previous-\(index)", date: tx.date, description: tx.description,
                amount: tx.amount, currency: tx.currency, type: tx.type, category: tx.category,
                accountId: tx.accountId, recurringSeriesId: series.id, createdAt: tx.createdAt
            )
        }
        try await store.addBatch(previousLaunch)
        store.recurringStore.removeOccurrences(seriesId: series.id, afterDate: .distantPast)
        #expect(store.recurringOccurrences.filter { $0.seriesId == series.id }.isEmpty)

        // The future occurrence has come due (it is gone), so the series gets extended.
        let today = Self.today
        if let future = Self.seriesTransactions(store, series.id).first(where: { $0.date > today }) {
            try await store.delete(future)
        }

        await store.extendAllActiveSeriesHorizons()

        let linked = Self.seriesTransactions(store, series.id)
        let perDay = Dictionary(grouping: linked, by: \.date)
        #expect(perDay.values.allSatisfy { $0.count == 1 }, "one transaction per day: \(perDay.mapValues(\.count))")
        let pastIds = Set(linked.filter { $0.date <= today }.map(\.id))
        #expect(pastIds == Set(previousLaunch.filter { $0.date <= today }.map(\.id)),
                "the days already there keep their transactions and get no copies")
        #expect(linked.filter { $0.date > today }.count == 1, "the next occurrence is generated again")
    }
}
