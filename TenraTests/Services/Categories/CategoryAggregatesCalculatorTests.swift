//
//  CategoryAggregatesCalculatorTests.swift
//  TenraTests
//
//  Replaces the legacy `TenraTests/Views/CategoryAggregatesTests.swift`,
//  which was authored against the array-scan API. The calculator now reads
//  pre-aggregated buckets from `TransactionStore.categoryAggregatesByKey`
//  in O(≤40) lookups; these tests assert that contract.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryAggregatesCalculatorTests {

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

    private static func aggregate(
        category: String,
        year: Int16, month: Int16, day: Int16,
        total: Double,
        count: Int32 = 1
    ) -> CategoryAggregate {
        CategoryAggregate(
            categoryName: category,
            year: year, month: month, day: day,
            totalAmount: total,
            transactionCount: count,
            currency: "KZT"
        )
    }

    private static func nowComps() -> (y: Int16, m: Int16) {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return (Int16(comps.year ?? 0), Int16(comps.month ?? 0))
    }

    // MARK: - Empty store

    @Test("empty store yields all-zero aggregates")
    func emptyStoreZeros() async throws {
        let store = Self.makeStore()
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: Date(timeIntervalSinceNow: -86_400 * 30),
            periodEnd: Date(),
            baseCurrency: "KZT",
            store: store
        )
        #expect(r.amountAllTime == 0)
        #expect(r.amountInPeriod == 0)
        #expect(r.avgMonthlyLast6 == 0)
        #expect(r.totalTransactions == 0)
    }

    // MARK: - All-time bucket

    @Test("all-time bucket is read in O(1)")
    func allTimeBucket() async throws {
        let store = Self.makeStore()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food", year: 0, month: 0, day: 0, total: 12_500, count: 42)
        ])
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: Date(), periodEnd: Date(),
            baseCurrency: "KZT", store: store
        )
        #expect(r.amountAllTime == 12_500)
        #expect(r.totalTransactions == 42)
    }

    // MARK: - Exact-month fast path

    @Test("exact-month period window uses the monthly bucket")
    func exactMonthFastPath() async throws {
        let store = Self.makeStore()
        let (y, m) = Self.nowComps()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food", year: y, month: m, day: 0, total: 8_888)
        ])

        let cal = Calendar.current
        let monthInterval = cal.dateInterval(of: .month, for: Date())!
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: monthInterval.start,
            periodEnd: monthInterval.end,
            baseCurrency: "KZT",
            store: store
        )
        #expect(r.amountInPeriod == 8_888)
    }

    // MARK: - Daily fallback (custom window)

    @Test("custom window sums matching daily buckets only")
    func customWindowDailyBuckets() async throws {
        let store = Self.makeStore()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        func comps(_ d: Date) -> (y: Int16, m: Int16, d: Int16) {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return (Int16(c.year ?? 0), Int16(c.month ?? 0), Int16(c.day ?? 0))
        }

        let t = comps(today)
        let y = comps(yesterday)
        let z = comps(twoDaysAgo)

        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food", year: t.y, month: t.m, day: t.d, total: 100),
            Self.aggregate(category: "Food", year: y.y, month: y.m, day: y.d, total: 200),
            // Two-days-ago bucket exists but must NOT be counted.
            Self.aggregate(category: "Food", year: z.y, month: z.m, day: z.d, total: 999_999)
        ])

        // Window: yesterday 00:00 → tomorrow 00:00 (covers yesterday and today).
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: yesterday, periodEnd: tomorrow,
            baseCurrency: "KZT", store: store
        )
        #expect(r.amountInPeriod == 300, "Should sum today + yesterday only")
    }

    // MARK: - 6-month average

    @Test("avg-monthly-6 divides by observed (non-zero) months only")
    func avgMonthlyLast6DividesByObserved() async throws {
        let store = Self.makeStore()
        let cal = Calendar.current
        let now = Date()
        // Seed three months back-to-back with 300, 600, 900 — observed = 3, avg = 600.
        var seeded: [CategoryAggregate] = []
        for offset in 0..<3 {
            let d = cal.date(byAdding: .month, value: -offset, to: now)!
            let c = cal.dateComponents([.year, .month], from: d)
            seeded.append(Self.aggregate(
                category: "Food",
                year: Int16(c.year ?? 0),
                month: Int16(c.month ?? 0),
                day: 0,
                total: Double(300 * (offset + 1))
            ))
        }
        store.seedCategoryAggregates(from: seeded)

        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: now, periodEnd: now,
            baseCurrency: "KZT", store: store
        )
        // 300 + 600 + 900 = 1800; observed = 3; avg = 600.
        #expect(r.avgMonthlyLast6 == 600)
    }

    // MARK: - Category isolation

    @Test("aggregates for other categories are not visible")
    func categoryIsolation() async throws {
        let store = Self.makeStore()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food",   year: 0, month: 0, day: 0, total: 100),
            Self.aggregate(category: "Travel", year: 0, month: 0, day: 0, total: 999_999)
        ])
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: Date(), periodEnd: Date(),
            baseCurrency: "KZT", store: store
        )
        #expect(r.amountAllTime == 100)
    }
}
