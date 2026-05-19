//
//  CategoryBudgetServiceTests.swift
//  TenraTests
//
//  Verifies the O(1) read path for budget progress against pre-seeded
//  `CategoryAggregate` buckets — no transactions array, no FX conversion,
//  no DateFormatter scans. These tests will catch regressions where someone
//  re-introduces a O(N_tx) walk into CategoryBudgetService.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CategoryBudgetServiceTests {

    // MARK: - Helpers

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
        year: Int16,
        month: Int16,
        day: Int16,
        total: Double
    ) -> CategoryAggregate {
        CategoryAggregate(
            categoryName: category,
            year: year, month: month, day: day,
            totalAmount: total,
            transactionCount: 1,
            currency: "KZT"
        )
    }

    private static func currentYearMonth() -> (Int16, Int16) {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return (Int16(comps.year ?? 0), Int16(comps.month ?? 0))
    }

    // MARK: - Monthly (resetDay = 1)

    @Test("monthly budget with resetDay=1 reads the single monthly bucket")
    func monthlyBudgetResetDay1ReadsMonthlyBucket() async throws {
        let store = Self.makeStore()
        let (y, m) = Self.currentYearMonth()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food", year: y, month: m, day: 0, total: 12_345)
        ])

        let cat = CustomCategory(
            id: "id-food",
            name: "Food",
            iconSource: .sfSymbol("fork.knife"),
            colorHex: "#FF0000",
            type: .expense,
            budgetAmount: 50_000,
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
        let svc = CategoryBudgetService(store: store)

        let progress = svc.budgetProgress(for: cat)
        #expect(progress != nil)
        #expect(progress?.spent == 12_345)
        #expect(progress?.budgetAmount == 50_000)
    }

    // MARK: - Yearly

    @Test("yearly budget reads the single yearly bucket")
    func yearlyBudgetReadsYearlyBucket() async throws {
        let store = Self.makeStore()
        let (y, _) = Self.currentYearMonth()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Travel", year: y, month: 0, day: 0, total: 999_000)
        ])

        let cat = CustomCategory(
            id: "id-travel",
            name: "Travel",
            iconSource: .sfSymbol("airplane"),
            colorHex: "#00FF00",
            type: .expense,
            budgetAmount: 1_500_000,
            budgetPeriod: .yearly,
            budgetResetDay: 1
        )
        let svc = CategoryBudgetService(store: store)

        let progress = svc.budgetProgress(for: cat)
        #expect(progress?.spent == 999_000)
    }

    // MARK: - Income / no-budget guards

    @Test("income category never returns budget progress")
    func incomeCategoryNoBudget() async throws {
        let store = Self.makeStore()
        let cat = CustomCategory(
            id: "id-salary",
            name: "Salary",
            iconSource: .sfSymbol("briefcase"),
            colorHex: "#0000FF",
            type: .income,
            budgetAmount: 1_000_000,
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
        #expect(CategoryBudgetService(store: store).budgetProgress(for: cat) == nil)
    }

    @Test("category without budget returns nil progress")
    func noBudgetReturnsNil() async throws {
        let store = Self.makeStore()
        let cat = CustomCategory(
            id: "id-other",
            name: "Other",
            iconSource: .sfSymbol("circle"),
            colorHex: "#888888",
            type: .expense,
            budgetAmount: nil,
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
        #expect(CategoryBudgetService(store: store).budgetProgress(for: cat) == nil)
    }

    @Test("zero budget returns nil progress")
    func zeroBudgetReturnsNil() async throws {
        let store = Self.makeStore()
        let cat = CustomCategory(
            id: "id-z",
            name: "Z",
            iconSource: .sfSymbol("circle"),
            colorHex: "#888888",
            type: .expense,
            budgetAmount: 0,
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
        #expect(CategoryBudgetService(store: store).budgetProgress(for: cat) == nil)
    }

    @Test("nil store returns nil progress")
    func nilStoreReturnsNil() async throws {
        let cat = CustomCategory(
            id: "id-x",
            name: "X",
            iconSource: .sfSymbol("circle"),
            colorHex: "#888888",
            type: .expense,
            budgetAmount: 1000,
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
        #expect(CategoryBudgetService(store: nil).budgetProgress(for: cat) == nil)
    }

    // MARK: - Missing bucket = zero spend

    @Test("missing aggregate bucket yields zero spent")
    func missingBucketYieldsZero() async throws {
        let store = Self.makeStore()
        // No seed — empty index.
        let cat = CustomCategory(
            id: "id-empty",
            name: "Empty",
            iconSource: .sfSymbol("circle"),
            colorHex: "#888888",
            type: .expense,
            budgetAmount: 1000,
            budgetPeriod: .monthly,
            budgetResetDay: 1
        )
        let progress = CategoryBudgetService(store: store).budgetProgress(for: cat)
        #expect(progress?.spent == 0)
    }
}
