//
//  TransactionStoreNewIndexesTests.swift
//  TenraTests
//
//  Regression coverage for Step I indexes added in the second audit:
//   • `transactionsBySeriesId`        — series → tx bucket
//   • `parsedDateByDateString`        — date string → parsed Date cache
//   • `accountAggregatesByAccountId`  — pre-aggregated income/expense per account
//   • `RecurringStore.occurrencesBySeriesId` — series → occurrence bucket
//
//  These are seeded via `loadData()` and patched via apply-time deltas;
//  the assertions exercise the seeding path through deterministic data, no
//  full TransactionStore.apply mutation flow (kept minimal for stability).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionStoreNewIndexesTests {

    private static func makeStore() -> TransactionStore {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let recurring = RecurringStore(repository: repo)
        let balance = BalanceCoordinator(repository: repo)
        return TransactionStore(
            repository: repo,
            balanceCoordinator: balance,
            recurringStore: recurring
        )
    }

    private static func tx(
        id: String = UUID().uuidString,
        date: String = "2026-05-19",
        amount: Double = 100,
        currency: String = "KZT",
        type: TransactionType = .expense,
        category: String = "Food",
        accountId: String? = "acct-1",
        targetAccountId: String? = nil,
        seriesId: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "test",
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            accountId: accountId,
            targetAccountId: targetAccountId,
            recurringSeriesId: seriesId
        )
    }

    // MARK: - parsedDateByDateString

    @Test("rebuildSeriesAndDateIndexes parses every distinct date once")
    func parsedDateByDateStringCovered() async throws {
        let store = Self.makeStore()
        store.transactions = [
            Self.tx(id: "a", date: "2026-01-15"),
            Self.tx(id: "b", date: "2026-02-20"),
            Self.tx(id: "c", date: "not-a-date")  // unparseable; must be absent
        ]
        store.rebuildSeriesAndDateIndexes()

        #expect(store.parsedDateByDateString["2026-01-15"] != nil)
        #expect(store.parsedDateByDateString["2026-02-20"] != nil)
        #expect(store.parsedDateByDateString["not-a-date"] == nil)
        #expect(store.parsedDateByDateString.count == 2)
    }

    @Test("transactions sharing a date collapse into one cache entry")
    func parsedDateByDateStringDeduplicates() async throws {
        let store = Self.makeStore()
        store.transactions = [
            Self.tx(id: "a", date: "2026-01-15"),
            Self.tx(id: "b", date: "2026-01-15"),
            Self.tx(id: "c", date: "2026-01-15"),
            Self.tx(id: "d", date: "2026-02-20")
        ]
        store.rebuildSeriesAndDateIndexes()

        // 4 transactions, 2 distinct dates — this dedup is the point of the key change.
        #expect(store.parsedDateByDateString.count == 2)
    }

    @Test("removing one transaction keeps the shared date entry for its siblings")
    func parsedDateSurvivesSiblingRemoval() async throws {
        let store = Self.makeStore()
        let a = Self.tx(id: "a", date: "2026-01-15")
        let b = Self.tx(id: "b", date: "2026-01-15")
        store.transactions = [a, b]
        store.rebuildSeriesAndDateIndexes()

        // Evicting by date on delete would break every other tx on that day.
        store.seriesIndexRemove(a)
        #expect(store.parsedDateByDateString["2026-01-15"] != nil)
    }

    // MARK: - transactionsBySeriesId

    @Test("transactionsBySeriesId buckets tx by recurringSeriesId")
    func seriesIndexBuckets() async throws {
        let store = Self.makeStore()
        store.transactions = [
            Self.tx(id: "a", seriesId: "S1"),
            Self.tx(id: "b", seriesId: "S1"),
            Self.tx(id: "c", seriesId: "S2"),
            Self.tx(id: "d", seriesId: nil)
        ]
        store.rebuildSeriesAndDateIndexes()

        #expect(store.transactionsBySeriesId["S1"]?.count == 2)
        #expect(store.transactionsBySeriesId["S2"]?.count == 1)
        #expect(store.transactionsBySeriesId[""] == nil)
        #expect(store.transactionsBySeriesId.keys.contains("nil") == false)
    }

    // MARK: - accountAggregatesByAccountId

    @Test("accountAggregatesByAccountId increments income and expense per account")
    func accountAggregatesIncomeAndExpense() async throws {
        let store = Self.makeStore()
        store.accounts = [
            Account(id: "acct-1", name: "Main", currency: "KZT", createdDate: Date(), balance: 0),
            Account(id: "acct-2", name: "Other", currency: "KZT", createdDate: Date(), balance: 0)
        ]
        store.rebuildAccountById()
        store.transactions = [
            Self.tx(id: "i1", amount: 5000, type: .income, category: "Salary", accountId: "acct-1"),
            Self.tx(id: "e1", amount: 100, type: .expense, category: "Food", accountId: "acct-1"),
            Self.tx(id: "e2", amount: 200, type: .expense, category: "Food", accountId: "acct-1"),
            Self.tx(id: "x1", amount: 999, type: .expense, category: "Food", accountId: "acct-2")
        ]
        store.rebuildAccountAggregates()

        let a1 = store.accountAggregatesByAccountId["acct-1"]
        #expect(a1?.totalTransactions == 3)
        #expect(a1?.totalIncome == 5000)
        #expect(a1?.totalExpense == 300)

        let a2 = store.accountAggregatesByAccountId["acct-2"]
        #expect(a2?.totalTransactions == 1)
        #expect(a2?.totalExpense == 999)
    }

    // MARK: - RecurringStore.occurrencesBySeriesId

    @Test("RecurringStore load seeds occurrencesBySeriesId by seriesId")
    func recurringOccurrenceIndex() async throws {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let store = RecurringStore(repository: repo)
        let occ1 = RecurringOccurrence(id: "o1", seriesId: "S1", occurrenceDate: "2026-01-15", transactionId: "t1")
        let occ2 = RecurringOccurrence(id: "o2", seriesId: "S1", occurrenceDate: "2026-02-15", transactionId: "t2")
        let occ3 = RecurringOccurrence(id: "o3", seriesId: "S2", occurrenceDate: "2026-01-20", transactionId: "t3")
        store.load(series: [], occurrences: [occ1, occ2, occ3])

        #expect(store.occurrencesBySeriesId["S1"]?.count == 2)
        #expect(store.occurrencesBySeriesId["S2"]?.count == 1)
    }

    @Test("removeAllOccurrences clears index entry for the series")
    func recurringOccurrenceRemoveAll() async throws {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        )
        let store = RecurringStore(repository: repo)
        let occ1 = RecurringOccurrence(id: "o1", seriesId: "S1", occurrenceDate: "2026-01-15", transactionId: "t1")
        let occ2 = RecurringOccurrence(id: "o2", seriesId: "S2", occurrenceDate: "2026-02-15", transactionId: "t2")
        store.load(series: [], occurrences: [occ1, occ2])
        store.removeAllOccurrences(for: "S1")

        #expect(store.occurrencesBySeriesId["S1"] == nil)
        #expect(store.occurrencesBySeriesId["S2"]?.count == 1)
        #expect(store.recurringOccurrences.count == 1)
    }
}
