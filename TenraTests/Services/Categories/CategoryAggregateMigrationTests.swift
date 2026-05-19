//
//  CategoryAggregateMigrationTests.swift
//  TenraTests
//
//  Verifies the cold-start migration path for `CategoryAggregateEntity`:
//  • An empty CoreData snapshot (first launch / fresh install) triggers
//    `rebuildCategoryIndexes` over the in-memory `transactions` array.
//  • The resulting `categoryAggregatesByKey` has the expected bucket structure.
//  • `seedCategoryAggregates` round-trips an existing snapshot without rebuilding.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryAggregateMigrationTests {

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
        date: String,
        amount: Double,
        category: String = "Food"
    ) -> Transaction {
        Transaction(
            id: id, date: date,
            description: "t",
            amount: amount, currency: "KZT",
            type: .expense, category: category,
            accountId: "a1"
        )
    }

    // MARK: - First-launch path

    @Test("rebuildCategoryIndexes produces 4 buckets per unique day/category combo")
    func rebuildProducesAllGranularities() async throws {
        let store = Self.makeStore()
        store.transactions = [
            Self.tx(date: "2026-05-19", amount: 100, category: "Food"),
            Self.tx(date: "2026-05-19", amount: 200, category: "Food")
        ]
        store.rebuildCategoryIndexes()

        // Expect 4 buckets for Food (daily, monthly, yearly, all-time)
        let dailyKey = CategoryAggregate.makeId(category: "Food", year: 2026, month: 5, day: 19)
        let monthlyKey = CategoryAggregate.makeId(category: "Food", year: 2026, month: 5, day: 0)
        let yearlyKey = CategoryAggregate.makeId(category: "Food", year: 2026, month: 0, day: 0)
        let allTimeKey = CategoryAggregate.makeId(category: "Food", year: 0, month: 0, day: 0)

        #expect(store.categoryAggregatesByKey[dailyKey]?.totalAmount == 300)
        #expect(store.categoryAggregatesByKey[monthlyKey]?.totalAmount == 300)
        #expect(store.categoryAggregatesByKey[yearlyKey]?.totalAmount == 300)
        #expect(store.categoryAggregatesByKey[allTimeKey]?.totalAmount == 300)
        #expect(store.categoryAggregatesByKey[dailyKey]?.transactionCount == 2)
    }

    // MARK: - Warm-start path

    @Test("seedCategoryAggregates uses the CoreData snapshot verbatim, skipping rebuild")
    func warmStartSkipsRebuild() async throws {
        let store = Self.makeStore()
        // Populate transactions WITHOUT calling rebuild — simulating warm path.
        store.transactions = [
            Self.tx(date: "2026-05-19", amount: 100, category: "Food")
        ]
        // Synthetic CoreData snapshot with a deliberately wrong total to prove the
        // seed wins over rebuild.
        let snapshot = [
            CategoryAggregate(
                categoryName: "Food", year: 0, month: 0, day: 0,
                totalAmount: 999_999, transactionCount: 7, currency: "KZT"
            )
        ]
        store.seedCategoryAggregates(from: snapshot)
        let allTime = CategoryAggregate.makeId(category: "Food", year: 0, month: 0, day: 0)
        #expect(store.categoryAggregatesByKey[allTime]?.totalAmount == 999_999)
        #expect(store.categoryAggregatesByKey[allTime]?.transactionCount == 7)
    }

    @Test("seedCategoryAggregates rebuilds transactionsByCategoryName from in-memory tx")
    func warmStartRebuildsByCategoryName() async throws {
        let store = Self.makeStore()
        store.transactions = [
            Self.tx(id: "1", date: "2026-05-19", amount: 100, category: "Food"),
            Self.tx(id: "2", date: "2026-05-20", amount: 50, category: "Food"),
            Self.tx(id: "3", date: "2026-05-21", amount: 30, category: "Travel")
        ]
        store.seedCategoryAggregates(from: [])  // empty snapshot; only the byCategoryName rebuild runs
        #expect(store.transactionsByCategoryName["Food"]?.count == 2)
        #expect(store.transactionsByCategoryName["Travel"]?.count == 1)
    }

    // MARK: - FX staleness flag

    @Test("rebuildCategoryIndexes clears aggregatesAreFXStale on fresh rebuild")
    func fxStaleClearedOnRebuild() async throws {
        let store = Self.makeStore()
        store.aggregatesAreFXStale = true
        store.transactions = [Self.tx(date: "2026-05-19", amount: 100)]
        store.rebuildCategoryIndexes()
        // All-KZT transactions don't trigger FX stale; flag should be false.
        #expect(store.aggregatesAreFXStale == false)
    }
}
