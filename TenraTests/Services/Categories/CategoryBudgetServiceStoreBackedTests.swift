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

    // MARK: - Limit semantics

    @Test("spent equal to budget reports isOverBudget=false and 100%")
    func spentEqualsBudgetNotOver() async throws {
        let store = Self.makeStore()
        let (y, m) = Self.currentYearMonth()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food", year: y, month: m, day: 0, total: 200)
        ])
        let cat = CustomCategory(
            id: "id-food", name: "Food",
            iconSource: .sfSymbol("fork.knife"), colorHex: "#FF0000",
            type: .expense, budgetAmount: 200,
            budgetPeriod: .monthly, budgetResetDay: 1
        )
        let progress = CategoryBudgetService(store: store).budgetProgress(for: cat)
        #expect(progress?.spent == 200)
        #expect(progress?.percentage == 100)
        #expect(progress?.isOverBudget == false)
    }

    @Test("spent above budget reports negative remaining and isOverBudget=true")
    func spentAboveBudget() async throws {
        let store = Self.makeStore()
        let (y, m) = Self.currentYearMonth()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food", year: y, month: m, day: 0, total: 350)
        ])
        let cat = CustomCategory(
            id: "id-food", name: "Food",
            iconSource: .sfSymbol("fork.knife"), colorHex: "#FF0000",
            type: .expense, budgetAmount: 200,
            budgetPeriod: .monthly, budgetResetDay: 1
        )
        let progress = CategoryBudgetService(store: store).budgetProgress(for: cat)
        #expect(progress?.isOverBudget == true)
        #expect(progress?.remaining == -150)
    }

    // MARK: - Category isolation

    @Test("buckets for unrelated category do not bleed into result")
    func onlyMatchingCategoryCounted() async throws {
        let store = Self.makeStore()
        let (y, m) = Self.currentYearMonth()
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Food",   year: y, month: m, day: 0, total: 150),
            Self.aggregate(category: "Travel", year: y, month: m, day: 0, total: 900_000)
        ])
        let cat = CustomCategory(
            id: "id-food", name: "Food",
            iconSource: .sfSymbol("fork.knife"), colorHex: "#FF0000",
            type: .expense, budgetAmount: 200,
            budgetPeriod: .monthly, budgetResetDay: 1
        )
        let progress = CategoryBudgetService(store: store).budgetProgress(for: cat)
        #expect(progress?.spent == 150, "Travel must not bleed into Food")
    }

    // MARK: - Reset-day semantics

    @Test("budgetPeriodStart returns reset day in current or previous month")
    func budgetPeriodStartHonoursResetDay() async throws {
        let svc = CategoryBudgetService(store: nil)
        let resetDay = 15
        let cat = CustomCategory(
            id: "id-rs", name: "RS",
            iconSource: .sfSymbol("calendar"), colorHex: "#888888",
            type: .expense, budgetAmount: 1000,
            budgetPeriod: .monthly, budgetResetDay: resetDay
        )
        let cal = Calendar.current
        let start = svc.budgetPeriodStart(for: cat)
        let startDay = cal.component(.day, from: start)
        let startMonth = cal.component(.month, from: start)
        let thisMonth = cal.component(.month, from: Date())
        let currentDay = cal.component(.day, from: Date())

        #expect(startDay == resetDay)
        if currentDay >= resetDay {
            #expect(startMonth == thisMonth, "Period starts this month when today >= resetDay")
        } else {
            let previousMonth = thisMonth == 1 ? 12 : thisMonth - 1
            #expect(startMonth == previousMonth, "Period started in previous month")
        }
    }

    // MARK: - Weekly

    @Test("weekly budget sums daily buckets within current week")
    func weeklyBudgetReadsDailyBuckets() async throws {
        let store = Self.makeStore()
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        store.seedCategoryAggregates(from: [
            Self.aggregate(category: "Coffee",
                           year: Int16(comps.year ?? 0),
                           month: Int16(comps.month ?? 0),
                           day: Int16(comps.day ?? 0),
                           total: 750)
        ])
        let cat = CustomCategory(
            id: "id-coffee", name: "Coffee",
            iconSource: .sfSymbol("cup.and.saucer"), colorHex: "#AA8855",
            type: .expense, budgetAmount: 3000,
            budgetPeriod: .weekly, budgetResetDay: 1
        )
        let progress = CategoryBudgetService(store: store).budgetProgress(for: cat)
        #expect(progress?.spent == 750)
    }
}
