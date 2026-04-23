//
//  CategoryAggregatesTests.swift
//  TenraTests
//
//  Unit tests for CategoryAggregatesCalculator.
//

import XCTest
@testable import Tenra

final class CategoryAggregatesTests: XCTestCase {
    func test_emptyTransactions_returnsZeros() {
        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: Date(),
            periodEnd: Date(),
            baseCurrency: "USD",
            transactions: []
        )
        XCTAssertEqual(r.amountInPeriod, 0)
        XCTAssertEqual(r.amountAllTime, 0)
        XCTAssertEqual(r.avgMonthlyLast6, 0)
        XCTAssertEqual(r.totalTransactions, 0)
    }

    func test_sumsOnlyMatchingCategory() {
        let txs: [Transaction] = [
            makeTx(type: .expense, category: "Food", amount: 100, currency: "USD", date: "2026-04-10"),
            makeTx(type: .expense, category: "Food", amount: 200, currency: "USD", date: "2026-04-15"),
            makeTx(type: .expense, category: "Transport", amount: 999, currency: "USD", date: "2026-04-12"),
        ]
        let start = DateFormatters.dateFormatter.date(from: "2026-04-01")!
        let end = DateFormatters.dateFormatter.date(from: "2026-04-30")!

        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: start,
            periodEnd: end,
            baseCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(r.totalTransactions, 2)
        XCTAssertEqual(r.amountInPeriod, 300, accuracy: 0.001)
        XCTAssertEqual(r.amountAllTime, 300, accuracy: 0.001)
    }

    func test_periodBoundary_excludesEndDate() {
        let txs: [Transaction] = [
            makeTx(type: .expense, category: "Food", amount: 100, currency: "USD", date: "2026-03-31"),
            makeTx(type: .expense, category: "Food", amount: 200, currency: "USD", date: "2026-04-01"),
            makeTx(type: .expense, category: "Food", amount: 300, currency: "USD", date: "2026-04-30"),
            makeTx(type: .expense, category: "Food", amount: 400, currency: "USD", date: "2026-05-01"),
        ]
        // Half-open window: [2026-04-01, 2026-05-01) — matches TimeFilter.dateRange() convention.
        let start = DateFormatters.dateFormatter.date(from: "2026-04-01")!
        let end = DateFormatters.dateFormatter.date(from: "2026-05-01")!

        let r = CategoryAggregatesCalculator.compute(
            categoryName: "Food",
            periodStart: start,
            periodEnd: end,
            baseCurrency: "USD",
            transactions: txs
        )
        XCTAssertEqual(r.totalTransactions, 4)
        // April only: Apr 1 (200) + Apr 30 (300). Mar 31 before start, May 1 equals end (excluded).
        XCTAssertEqual(r.amountInPeriod, 500, accuracy: 0.001)
        XCTAssertEqual(r.amountAllTime, 1000, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeTx(
        type: TransactionType,
        category: String,
        amount: Double,
        currency: String,
        date: String
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "test",
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            accountId: "a1"
        )
    }
}
