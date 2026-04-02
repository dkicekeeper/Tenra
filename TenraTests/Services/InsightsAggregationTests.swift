//
//  InsightsAggregationTests.swift
//  AIFinanceManagerTests
//
//  Unit tests for InsightsService static aggregation helpers:
//    - computeMonthlyTotals
//    - computeCategoryMonthTotals
//    - PreAggregatedData.build (single O(N) pass)
//    - PreAggregatedData.monthlyTotalsInRange
//
//  All tests are pure — no CoreData, no TransactionStore, no async.
//  TEST-06
//

import Testing
import Foundation
@testable import AIFinanceManager

// MARK: - Test Fixtures

private let kCurrency = "KZT"

/// Calendar utility: creates a Date from year/month/day, forcing UTC-midnight so
/// test results are timezone-independent.
private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: comps)!
}

private func dateString(year: Int, month: Int, day: Int) -> String {
    let d = utcDate(year: year, month: month, day: day)
    return DateFormatters.dateFormatter.string(from: d)
}

// MARK: - Suite

@Suite("InsightsService Aggregation Tests", .serialized)
struct InsightsAggregationTests {

    // MARK: - Transaction Factory

    private func makeTx(
        date: String,
        amount: Double,
        type: TransactionType,
        category: String = "Misc",
        accountId: String = "acc-1"
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "Test",
            amount: amount,
            currency: kCurrency,
            convertedAmount: nil,
            type: type,
            category: category,
            subcategory: nil,
            accountId: accountId,
            accountName: "TestAccount",
            createdAt: 1_700_000_000
        )
    }

    /// A fixed set of transactions spanning Jan–Mar 2026:
    ///   Jan: income=50_000; expenses=10_000 (Food 8K + Transport 2K)
    ///   Feb: income=20_000; expenses=10_000 (Food 4K + Entertainment 6K)
    ///   Mar: income=0;      expenses=7_000  (Food 7K)
    ///   + 1 internal transfer (must be excluded from monthly totals)
    private func makeTestTransactions() -> [Transaction] {
        [
            // January 2026
            makeTx(date: "2026-01-15", amount: 50_000, type: .income, category: "Salary", accountId: "acc-1"),
            makeTx(date: "2026-01-15", amount: 5_000,  type: .expense, category: "Food",      accountId: "acc-1"),
            makeTx(date: "2026-01-20", amount: 3_000,  type: .expense, category: "Food",      accountId: "acc-1"),
            makeTx(date: "2026-01-25", amount: 2_000,  type: .expense, category: "Transport", accountId: "acc-2"),
            // February 2026
            makeTx(date: "2026-02-10", amount: 20_000, type: .income,  category: "Freelance", accountId: "acc-1"),
            makeTx(date: "2026-02-10", amount: 4_000,  type: .expense, category: "Food",      accountId: "acc-1"),
            makeTx(date: "2026-02-20", amount: 6_000,  type: .expense, category: "Entertainment", accountId: "acc-2"),
            // March 2026
            makeTx(date: "2026-03-15", amount: 7_000,  type: .expense, category: "Food",      accountId: "acc-1"),
            // Internal transfer — must NOT appear in income/expense totals
            makeTx(date: "2026-01-10", amount: 10_000, type: .internalTransfer, category: "", accountId: "acc-1"),
        ]
    }

    private func jan2026Start() -> Date { utcDate(year: 2026, month: 1, day: 1) }
    private func apr2026Start() -> Date { utcDate(year: 2026, month: 4, day: 1) }

    // MARK: - computeMonthlyTotals

    @Test("computeMonthlyTotals: correct totals for 3 months")
    func testComputeMonthlyTotalsBasic() throws {
        let txs = makeTestTransactions()
        let totals = InsightsService.computeMonthlyTotals(
            from: txs,
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )

        let jan = totals.first { $0.year == 2026 && $0.month == 1 }
        let feb = totals.first { $0.year == 2026 && $0.month == 2 }
        let mar = totals.first { $0.year == 2026 && $0.month == 3 }

        let janValue = try #require(jan, "January 2026 must be present")
        #expect(abs(janValue.totalIncome   - 50_000) < 0.01)
        #expect(abs(janValue.totalExpenses - 10_000) < 0.01)

        let febValue = try #require(feb, "February 2026 must be present")
        #expect(abs(febValue.totalIncome   - 20_000) < 0.01)
        #expect(abs(febValue.totalExpenses - 10_000) < 0.01)

        let marValue = try #require(mar, "March 2026 must be present")
        #expect(abs(marValue.totalIncome   - 0)      < 0.01)
        #expect(abs(marValue.totalExpenses - 7_000)  < 0.01)
    }

    @Test("computeMonthlyTotals: sorted chronologically")
    func testComputeMonthlyTotalsSortOrder() {
        let totals = InsightsService.computeMonthlyTotals(
            from: makeTestTransactions(),
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )
        #expect(totals.count == 3, "Exactly 3 months with data")
        for i in 1..<totals.count {
            let prev = totals[i - 1], curr = totals[i]
            let prevIsEarlier = prev.year < curr.year || (prev.year == curr.year && prev.month < curr.month)
            #expect(prevIsEarlier, "Months must be sorted ascending")
        }
    }

    @Test("computeMonthlyTotals: internalTransfer excluded")
    func testComputeMonthlyTotalsExcludesInternal() {
        let txs = makeTestTransactions()
        let totals = InsightsService.computeMonthlyTotals(
            from: txs,
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )
        // Jan total income must be exactly 50K (not +10K from internal transfer)
        let jan = totals.first { $0.year == 2026 && $0.month == 1 }!
        #expect(abs(jan.totalIncome - 50_000) < 0.01)
    }

    @Test("computeMonthlyTotals: empty transactions returns empty")
    func testComputeMonthlyTotalsEmpty() {
        let totals = InsightsService.computeMonthlyTotals(
            from: [],
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )
        #expect(totals.isEmpty)
    }

    @Test("computeMonthlyTotals: transactions outside range excluded")
    func testComputeMonthlyTotalsRangeBound() {
        let txs = makeTestTransactions()
        // Range: only Feb 2026
        let febStart = utcDate(year: 2026, month: 2, day: 1)
        let marStart = utcDate(year: 2026, month: 3, day: 1)
        let totals = InsightsService.computeMonthlyTotals(
            from: txs,
            from: febStart,
            to: marStart,
            baseCurrency: kCurrency
        )
        #expect(totals.count == 1, "Only February should be in range")
        #expect(totals.first?.month == 2)
    }

    @Test("computeMonthlyTotals: netFlow = income - expenses")
    func testComputeMonthlyTotalsNetFlow() {
        let totals = InsightsService.computeMonthlyTotals(
            from: makeTestTransactions(),
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )
        for t in totals {
            #expect(abs(t.netFlow - (t.totalIncome - t.totalExpenses)) < 0.01)
        }
    }

    // MARK: - computeCategoryMonthTotals

    @Test("computeCategoryMonthTotals: correct grouping by category × month")
    func testComputeCategoryMonthTotals() throws {
        let result = InsightsService.computeCategoryMonthTotals(
            from: makeTestTransactions(),
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )

        let janFood      = result.first { $0.categoryName == "Food"      && $0.year == 2026 && $0.month == 1 }
        let janTransport = result.first { $0.categoryName == "Transport" && $0.year == 2026 && $0.month == 1 }
        let febFood      = result.first { $0.categoryName == "Food"      && $0.year == 2026 && $0.month == 2 }
        let marFood      = result.first { $0.categoryName == "Food"      && $0.year == 2026 && $0.month == 3 }

        let janFoodVal      = try #require(janFood,      "Jan Food must exist")
        let janTransportVal = try #require(janTransport, "Jan Transport must exist")
        let febFoodVal      = try #require(febFood,      "Feb Food must exist")
        let marFoodVal      = try #require(marFood,      "Mar Food must exist")

        #expect(abs(janFoodVal.totalExpenses      - 8_000) < 0.01)
        #expect(abs(janTransportVal.totalExpenses - 2_000) < 0.01)
        #expect(abs(febFoodVal.totalExpenses      - 4_000) < 0.01)
        #expect(abs(marFoodVal.totalExpenses      - 7_000) < 0.01)
    }

    @Test("computeCategoryMonthTotals: income excluded")
    func testComputeCategoryMonthTotalsExcludesIncome() {
        let result = InsightsService.computeCategoryMonthTotals(
            from: makeTestTransactions(),
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )
        let salary = result.first { $0.categoryName == "Salary" }
        #expect(salary == nil, "Income category 'Salary' must be excluded")
    }

    // MARK: - PreAggregatedData.build

    @Test("PreAggregatedData: monthly totals match computeMonthlyTotals")
    func testPreAggregatedMonthlyTotalsMatch() throws {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)
        let canonical = InsightsService.computeMonthlyTotals(
            from: txs,
            from: jan2026Start(),
            to: apr2026Start(),
            baseCurrency: kCurrency
        )

        for month in canonical {
            let key = InsightsService.PreAggregatedData.MonthKey(year: month.year, month: month.month)
            let aggTotals = agg.monthlyTotals[key]
            let totals = try #require(aggTotals, "Month \(month.year)-\(month.month) must exist in PreAggregatedData")
            #expect(abs(totals.income   - month.totalIncome)   < 0.01)
            #expect(abs(totals.expenses - month.totalExpenses) < 0.01)
        }
    }

    @Test("PreAggregatedData: txDateMap has unique entries for each date string")
    func testPreAggregatedTxDateMap() {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)

        let uniqueDates = Set(txs.map(\.date))
        #expect(agg.txDateMap.count == uniqueDates.count,
                "txDateMap must have one entry per unique date string")
    }

    @Test("PreAggregatedData: firstDate and lastDate are correctly detected")
    func testPreAggregatedDateRange() throws {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)

        let first = try #require(agg.firstDate, "firstDate must not be nil")
        let last  = try #require(agg.lastDate,  "lastDate must not be nil")
        #expect(first <= last, "firstDate must be ≤ lastDate")

        // Earliest: "2026-01-10" (internal transfer), latest: "2026-03-15"
        let calendar = Calendar.current
        let firstComps = calendar.dateComponents([.year, .month, .day], from: first)
        let lastComps  = calendar.dateComponents([.year, .month, .day], from: last)
        #expect(firstComps.year == 2026 && firstComps.month == 1 && firstComps.day == 10)
        #expect(lastComps.year  == 2026 && lastComps.month  == 3 && lastComps.day  == 15)
    }

    @Test("PreAggregatedData: accountTransactionCounts includes all types")
    func testPreAggregatedAccountCounts() {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)

        // acc-1: Salary(Jan), Food(Jan×2), Freelance(Feb), Food(Feb), Food(Mar), internal(Jan) = 7
        // acc-2: Transport(Jan), Entertainment(Feb) = 2
        let acc1Count = agg.accountTransactionCounts["acc-1"] ?? 0
        let acc2Count = agg.accountTransactionCounts["acc-2"] ?? 0
        #expect(acc1Count == 7, "acc-1 must have 7 transactions (all types)")
        #expect(acc2Count == 2, "acc-2 must have 2 transactions")
    }

    @Test("PreAggregatedData: categoryTotals aggregates all-time expenses per category")
    func testPreAggregatedCategoryTotals() {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)

        // Food: 5000+3000+4000+7000 = 19000
        let foodTotal = agg.categoryTotals["Food"] ?? 0
        #expect(abs(foodTotal - 19_000) < 0.01)

        // Transport: 2000
        let transportTotal = agg.categoryTotals["Transport"] ?? 0
        #expect(abs(transportTotal - 2_000) < 0.01)

        // Salary is income — must not appear in categoryTotals
        let salaryTotal = agg.categoryTotals["Salary"]
        #expect(salaryTotal == nil, "Income categories must not appear in categoryTotals")
    }

    @Test("PreAggregatedData: empty transactions builds empty aggregation")
    func testPreAggregatedEmpty() {
        let agg = InsightsService.PreAggregatedData.build(from: [], baseCurrency: kCurrency)
        #expect(agg.monthlyTotals.isEmpty)
        #expect(agg.categoryMonthExpenses.isEmpty)
        #expect(agg.txDateMap.isEmpty)
        #expect(agg.firstDate == nil)
        #expect(agg.lastDate == nil)
    }

    // MARK: - PreAggregatedData.monthlyTotalsInRange

    @Test("monthlyTotalsInRange: returns only months within range")
    func testMonthlyTotalsInRange() throws {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)

        // Use Calendar.current (local timezone) to match monthlyTotalsInRange's Calendar.current.
        // utcDate() creates UTC-midnight dates which can bleed into the next local month in +UTC
        // timezones, causing `cursor < end` to include an extra month.
        let calendar = Calendar.current
        let febStart = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let marStart = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let result = agg.monthlyTotalsInRange(from: febStart, to: marStart)

        #expect(result.count == 1, "Only February should be in range")
        let feb = try #require(result.first)
        #expect(feb.month == 2)
        #expect(abs(feb.totalIncome   - 20_000) < 0.01)
        #expect(abs(feb.totalExpenses - 10_000) < 0.01)
    }

    @Test("monthlyTotalsInRange: full range returns all months with data")
    func testMonthlyTotalsInRangeFull() {
        let txs = makeTestTransactions()
        let agg = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: kCurrency)
        let result = agg.monthlyTotalsInRange(from: jan2026Start(), to: apr2026Start())
        #expect(result.count == 3, "Full range must return Jan, Feb, Mar")
    }
}
