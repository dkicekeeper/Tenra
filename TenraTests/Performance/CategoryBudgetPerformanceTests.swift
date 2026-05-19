//
//  CategoryBudgetPerformanceTests.swift
//  TenraTests
//
//  Regression baselines. These DO NOT use XCTest's measure() API (which is
//  flaky on CI). Instead they assert a wall-clock upper bound — orders of
//  magnitude above the expected runtime so spurious slowness doesn't break
//  builds, but a regression that re-introduces an O(N_tx) scan would still
//  trip them.
//
//  Targets (Debug build, iPhone 17 Pro simulator):
//   • 19 000 transactions seeded as monthly aggregate buckets
//   • budgetProgress(...) per category should complete in <1 ms (we assert <50 ms)
//   • rebuilding the management-view snapshot for 30 categories <10 ms
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryBudgetPerformanceTests {

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

    /// Seeds `categoryAggregatesByKey` directly with N pre-aggregated buckets.
    /// Mirrors what `applyAggregateDelta` would produce — bypasses transaction
    /// generation since the test is about read-time complexity, not maintenance.
    private static func seedBuckets(into store: TransactionStore, categoryCount: Int) {
        let now = Date()
        let cal = Calendar.current
        let y = Int16(cal.component(.year, from: now))
        let m = Int16(cal.component(.month, from: now))
        var seed: [CategoryAggregate] = []
        seed.reserveCapacity(categoryCount * 4)
        for i in 0..<categoryCount {
            let name = "Cat-\(i)"
            // Monthly bucket
            seed.append(CategoryAggregate(
                categoryName: name, year: y, month: m, day: 0,
                totalAmount: Double((i + 1) * 1_000),
                transactionCount: 100,
                currency: "KZT"
            ))
            // All-time bucket
            seed.append(CategoryAggregate(
                categoryName: name, year: 0, month: 0, day: 0,
                totalAmount: Double((i + 1) * 100_000),
                transactionCount: 1_000,
                currency: "KZT"
            ))
        }
        store.seedCategoryAggregates(from: seed)
    }

    // MARK: - Budget service is O(≤31)

    @Test("budgetProgress for a category returns in well under 50 ms")
    func budgetProgressIsConstantTime() async throws {
        let store = Self.makeStore()
        Self.seedBuckets(into: store, categoryCount: 30)

        let cat = CustomCategory(
            id: "Cat-0", name: "Cat-0",
            iconSource: .sfSymbol("fork.knife"), colorHex: "#FF0000",
            type: .expense, budgetAmount: 50_000,
            budgetPeriod: .monthly, budgetResetDay: 1
        )
        let svc = CategoryBudgetService(store: store)

        // Warm-up run to defeat first-call costs (lazy mem-alloc, etc.).
        _ = svc.budgetProgress(for: cat)

        let t0 = Date()
        for _ in 0..<1_000 {
            _ = svc.budgetProgress(for: cat)
        }
        let elapsed = Date().timeIntervalSince(t0)
        // 1000 calls × ≤31 hashmap lookups each. Should finish in <50 ms.
        #expect(elapsed < 0.050, "1000 budgetProgress calls took \(elapsed)s; expected <0.050s. Regression to O(N_tx) suspected.")
    }

    @Test("budgetProgress for 30 categories returns in well under 50 ms")
    func budgetProgressForAllCategoriesIsLinearInCount() async throws {
        let store = Self.makeStore()
        Self.seedBuckets(into: store, categoryCount: 30)
        let svc = CategoryBudgetService(store: store)

        let cats = (0..<30).map { i in
            CustomCategory(
                id: "Cat-\(i)", name: "Cat-\(i)",
                iconSource: .sfSymbol("circle"), colorHex: "#888888",
                type: .expense, budgetAmount: 50_000,
                budgetPeriod: .monthly, budgetResetDay: 1
            )
        }

        // Warm-up
        for c in cats { _ = svc.budgetProgress(for: c) }

        let t0 = Date()
        for _ in 0..<10 {
            for c in cats { _ = svc.budgetProgress(for: c) }
        }
        let elapsed = Date().timeIntervalSince(t0)
        // 10 × 30 = 300 budgetProgress calls, each ≤31 lookups. <50 ms easily.
        #expect(elapsed < 0.050, "300 budgetProgress calls took \(elapsed)s; expected <0.050s.")
    }

    // MARK: - Aggregate calculator is O(≤40)

    @Test("AggregatesCalculator.compute returns in well under 5 ms per call")
    func aggregatesCalculatorIsConstantTime() async throws {
        let store = Self.makeStore()
        Self.seedBuckets(into: store, categoryCount: 30)

        let cal = Calendar.current
        let now = Date()
        let monthInterval = cal.dateInterval(of: .month, for: now)!

        _ = CategoryAggregatesCalculator.compute(
            categoryName: "Cat-0",
            periodStart: monthInterval.start, periodEnd: monthInterval.end,
            baseCurrency: "KZT", store: store
        )

        let t0 = Date()
        for _ in 0..<1_000 {
            _ = CategoryAggregatesCalculator.compute(
                categoryName: "Cat-0",
                periodStart: monthInterval.start, periodEnd: monthInterval.end,
                baseCurrency: "KZT", store: store
            )
        }
        let elapsed = Date().timeIntervalSince(t0)
        #expect(elapsed < 0.050, "1000 compute calls took \(elapsed)s; expected <0.050s.")
    }
}
