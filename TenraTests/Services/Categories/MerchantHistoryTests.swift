//
//  MerchantHistoryTests.swift
//  TenraTests
//
//  Pins the merchant screen's figures: which transactions are the merchant's, and that
//  its money follows the app's rules (summaryContribution, future operations left out).
//  All amounts are in the base currency, so no FX state is involved.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct MerchantHistoryTests {

    private let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)
    private let october = (FastDateParser.date(from: "2026-10-01")!, FastDateParser.date(from: "2026-11-01")!)

    private func tx(
        _ id: String,
        _ date: String,
        _ amount: Double,
        _ description: String = "GREENMART 12",
        type: TransactionType = .expense,
        category: String = "Продукты"
    ) -> Transaction {
        Transaction(id: id, date: date, description: description, amount: amount, currency: "KZT", type: type, category: category, accountId: "a1")
    }

    private var history: [Transaction] {
        [
            tx("t1", "2026-10-03", 4_000),
            tx("t2", "2026-10-20", 6_000, "Greenmart 14"),
            tx("t3", "2026-09-15", 10_000, "GREENMART", category: "Кафе"),
            tx("t4", "2026-10-21", 1_000, type: .income, category: "Возвраты"),
            tx("t5", "2026-10-30", 9_999),
            tx("t6", "2026-10-05", 50_000, "CORNER BAKERY"),
            tx("t7", "2026-10-06", 70_000, type: .internalTransfer, category: "")
        ]
    }

    private func summary() -> MerchantHistory.Summary {
        MerchantHistory.summary(
            merchant: "greenmart",
            in: history,
            periodStart: october.0,
            periodEnd: october.1,
            baseCurrency: "KZT",
            now: now
        )
    }

    @Test("Every description of the merchant counts; other merchants and transfers don't")
    func merchantsTransactions() {
        #expect(summary().transactions.map(\.id) == ["t5", "t4", "t2", "t1", "t3"])
    }

    @Test("Spending follows the app rules: income and future operations left out")
    func spending() {
        let result = summary()
        #expect(result.spentInPeriod == 10_000)
        #expect(result.visitsInPeriod == 2)
        #expect(result.spentAllTime == 20_000)
        #expect(result.visitsAllTime == 3)
    }

    @Test("The last visit is the latest expense up to today; the usual category the most frequent")
    func lastVisitAndCategory() {
        let result = summary()
        #expect(result.lastVisit == "2026-10-20")
        #expect(result.usualCategory == "Продукты")
    }

    @Test("A merchant too short to name anything has no history")
    func tooShort() {
        let result = MerchantHistory.summary(
            merchant: "gm",
            in: history,
            periodStart: october.0,
            periodEnd: october.1,
            baseCurrency: "KZT",
            now: now
        )
        #expect(result == .empty)
    }
}
