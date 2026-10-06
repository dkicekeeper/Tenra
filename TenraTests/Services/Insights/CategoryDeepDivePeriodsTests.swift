//
//  CategoryDeepDivePeriodsTests.swift
//  TenraTests
//
//  Pins `InsightsService.categoryDeepDivePeriods` — the figures behind every page of a
//  category drill-down: each period's total and breakdown rows, the previous period's
//  total for the comparison card, the realized-only gate, and the loan / deposit
//  account groupings of the synthetic categories.
//
//  Pure tests — no CoreData, no TransactionStore, no shared FX state (the rate table
//  is an explicit `RateSnapshot`).
//

import Testing
import Foundation
@testable import Tenra

@Suite("InsightsService.categoryDeepDivePeriods")
struct CategoryDeepDivePeriodsTests {

    private let base = "KZT"

    private func makeTx(
        id: String = UUID().uuidString,
        date: String,
        amount: Double,
        currency: String = "KZT",
        type: TransactionType = .expense,
        category: String = "Food",
        subcategory: String? = nil,
        accountId: String? = "acc-1",
        accountName: String? = "Card",
        targetAccountId: String? = nil,
        targetAccountName: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "Test",
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            subcategory: subcategory,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: accountName,
            targetAccountName: targetAccountName,
            createdAt: 1_700_000_000
        )
    }

    /// Grouping key of a stored date at `granularity` — computed, not hard-coded, so the
    /// expectations follow the test machine's calendar exactly like the builder does.
    private func key(_ date: String, _ granularity: InsightGranularity = .month) -> String {
        granularity.groupingKey(for: FastDateParser.date(from: date)!)
    }

    private func periods(
        _ transactions: [Transaction],
        category: String = "Food",
        bucket: InsightsService.MoneyBucket = .expense,
        granularity: InsightGranularity = .month,
        keys: [String],
        rates: RateSnapshot = RateSnapshot(rates: [:]),
        links: [String: String] = [:]
    ) -> [CategoryDeepDivePeriod] {
        InsightsService.categoryDeepDivePeriods(
            categoryName: category,
            bucket: bucket,
            transactions: transactions,
            granularity: granularity,
            periodKeys: keys,
            baseCurrency: base,
            rates: rates,
            subcategoryName: { links[$0] }
        )
    }

    // MARK: - Per-period figures

    @Test("Each period gets its own total and subcategory rows, in pager order")
    func perPeriodTotalsAndRows() {
        let txs = [
            makeTx(id: "m1", date: "2025-03-05", amount: 10_000),
            makeTx(id: "m2", date: "2025-03-20", amount: 5_000),
            makeTx(id: "m3", date: "2025-03-25", amount: 3_000, subcategory: "Cafe"),
            makeTx(id: "a1", date: "2025-04-02", amount: 8_000),
            makeTx(id: "a2", date: "2025-04-10", amount: 2_000)
        ]
        // Linked subcategories win over the legacy `tx.subcategory` string.
        let links = ["m1": "Groceries", "m2": "Restaurants", "a2": "Groceries"]
        let keys = [key("2025-03-01"), key("2025-04-01"), key("2025-05-01")]

        let result = periods(txs, keys: keys, links: links)

        #expect(result.map(\.id) == keys)

        let march = result[0]
        #expect(march.total == 18_000)
        #expect(march.rows.map(\.name) == ["Groceries", "Restaurants", "Cafe"])
        #expect(march.rows.map(\.amount) == [10_000, 5_000, 3_000])
        let marchShares = march.rows.reduce(0.0) { $0 + $1.percentage }
        #expect(abs(marchShares - 100) < 0.0001)

        let april = result[1]
        #expect(april.total == 10_000)
        // No link and no legacy string → the "no subcategory" row.
        #expect(april.rows.map(\.name) == [String(localized: "insights.noSubcategory"), "Groceries"])
        #expect(abs(april.rows[0].percentage - 80) < 0.0001)
        #expect(abs(april.rows[1].percentage - 20) < 0.0001)

        // A period without activity still gets its page: empty, total 0.
        let may = result[2]
        #expect(may.total == 0)
        #expect(may.rows.isEmpty)
    }

    @Test("Other categories, non-money types and the other side of the ledger stay out")
    func onlyThisCategoryAndBucket() {
        let txs = [
            makeTx(date: "2025-03-05", amount: 10_000),
            makeTx(date: "2025-03-06", amount: 50_000, category: "Transport"),
            makeTx(date: "2025-03-07", amount: 70_000, type: .internalTransfer),
            // An income category with the same name: not part of the spending drill-down
            // (the breakdown it opens from counts expenses only), and vice versa.
            makeTx(date: "2025-03-08", amount: 3_000, type: .income)
        ]
        let keys = [key("2025-03-01")]
        #expect(periods(txs, keys: keys)[0].total == 10_000)
        #expect(periods(txs, bucket: .income, keys: keys)[0].total == 3_000)
    }

    @Test("Future-dated transactions are not counted (realized only)")
    func excludesFutureTransactions() {
        let today = Date()
        let past = FastDateParser.string(from: Calendar.current.date(byAdding: .day, value: -40, to: today)!)
        let future = FastDateParser.string(from: Calendar.current.date(byAdding: .day, value: 40, to: today)!)
        let txs = [
            makeTx(date: past, amount: 1_000),
            makeTx(date: future, amount: 9_000)
        ]
        let result = periods(txs, keys: [key(past), key(future)])
        let total = result.reduce(0.0) { $0 + $1.total }
        #expect(total == 1_000)
    }

    @Test("Equal rows are ordered by name, so pages don't reshuffle between reloads")
    func tieBreakByName() {
        let txs = [
            makeTx(date: "2025-03-05", amount: 4_000, subcategory: "Tea"),
            makeTx(date: "2025-03-06", amount: 4_000, subcategory: "Coffee")
        ]
        let result = periods(txs, keys: [key("2025-03-01")])
        #expect(result[0].rows.map(\.name) == ["Coffee", "Tea"])
    }

    // MARK: - Comparison with the previous period

    @Test("Previous total reads the period before, even outside the pager's periods")
    func previousPeriodTotals() {
        let txs = [
            makeTx(date: "2025-02-14", amount: 7_000),
            makeTx(date: "2025-03-05", amount: 18_000),
            makeTx(date: "2025-04-10", amount: 10_000)
        ]
        // February is not a page, but March still compares against it.
        let result = periods(txs, keys: [key("2025-03-01"), key("2025-04-01"), key("2025-05-01")])
        #expect(result.map(\.previousTotal) == [7_000, 18_000, 10_000])
        let previousLabels = result.compactMap(\.previousLabel)
        #expect(previousLabels.count == result.count)
    }

    @Test("All time is one bucket: no previous period, no comparison")
    func allTimeHasNoPreviousPeriod() {
        let txs = [
            makeTx(date: "2024-06-01", amount: 1_000),
            makeTx(date: "2025-03-05", amount: 2_000)
        ]
        let result = periods(txs, granularity: .allTime, keys: [InsightGranularity.allTime.currentPeriodKey])
        #expect(result.count == 1)
        #expect(result[0].total == 3_000)
        #expect(result[0].previousLabel == nil)
        #expect(result[0].previousTotal == 0)
    }

    @Test("Weekly pages bucket by week and compare with the week before")
    func weeklyBuckets() {
        // Tue 4 Mar and Wed 12 Mar 2025 sit in consecutive weeks whether weeks start on
        // Sunday or Monday; Thu 13 Mar shares the 12th's week.
        let txs = [
            makeTx(date: "2025-03-04", amount: 1_000),
            makeTx(date: "2025-03-12", amount: 2_000),
            makeTx(date: "2025-03-13", amount: 500)
        ]
        let first = key("2025-03-04", .week)
        let second = key("2025-03-12", .week)
        let result = periods(txs, granularity: .week, keys: [first, second])
        #expect(result.map(\.total) == [1_000, 2_500])
        #expect(result[1].previousTotal == 1_000)
    }

    // MARK: - Currency

    @Test("Amounts convert to base currency through the pinned rate table")
    func convertsThroughRateSnapshot() {
        let txs = [
            makeTx(date: "2025-03-05", amount: 10, currency: "USD"),
            makeTx(date: "2025-03-06", amount: 1_000),
            // No EUR rate: skipped (0), never blended in the wrong unit.
            makeTx(date: "2025-03-07", amount: 99, currency: "EUR")
        ]
        let result = periods(txs, keys: [key("2025-03-01")], rates: RateSnapshot(rates: ["USD": 500]))
        #expect(result[0].total == 6_000)
    }

    // MARK: - Synthetic categories

    @Test("Loan payments break down by loan account; a renamed loan stays one row")
    func loanPaymentsGroupByLoanAccount() {
        let txs = [
            makeTx(date: "2025-03-03", amount: 30_000, type: .loanPayment, category: "",
                   targetAccountId: "loan-1", targetAccountName: "Car loan"),
            makeTx(date: "2025-03-28", amount: 30_000, type: .loanPayment, category: "",
                   targetAccountId: "loan-1", targetAccountName: "Car loan 2025"),
            makeTx(date: "2025-03-15", amount: 50_000, type: .loanEarlyRepayment, category: "",
                   targetAccountId: "loan-2", targetAccountName: "Mortgage"),
            // A plain expense in another category stays out.
            makeTx(date: "2025-03-16", amount: 5_000)
        ]
        let result = periods(txs, category: TransactionType.loanPaymentCategoryName, keys: [key("2025-03-01")])

        #expect(result[0].total == 110_000)
        #expect(result[0].rows.map(\.id) == ["loan-1", "loan-2"])
        #expect(result[0].rows.map(\.amount) == [60_000, 50_000])
        // The most recent payment's name labels the row.
        #expect(result[0].rows.first?.name == "Car loan 2025")
    }

    @Test("Deposit interest breaks down by the deposit that paid it, whatever its stored label")
    func depositInterestGroupsByDeposit() {
        let txs = [
            makeTx(date: "2025-03-31", amount: 1_200, type: .depositInterestAccrual, category: "Interest",
                   accountId: "dep-1", accountName: "Savings"),
            makeTx(date: "2025-03-31", amount: 800, type: .depositInterestAccrual, category: "Проценты",
                   accountId: "dep-2", accountName: "Kaspi deposit")
        ]
        let result = periods(
            txs,
            category: TransactionType.depositInterestCategoryName,
            bucket: .income,
            keys: [key("2025-03-01")]
        )

        #expect(result[0].total == 2_000)
        #expect(result[0].rows.map(\.id) == ["dep-1", "dep-2"])
    }
}
