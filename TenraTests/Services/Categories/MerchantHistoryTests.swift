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

    @Test("This month, this year and the last 24 months, future operations left out")
    func months() {
        let summary = summary()
        #expect(summary.spentThisMonth == 10_000)
        #expect(summary.spentThisYear == 20_000)
        #expect(summary.months.count == MerchantHistory.monthsShown)
        #expect(MerchantHistory.monthsShown == 24)
        #expect(summary.months.first?.key == "2024-11")
        #expect(summary.months.suffix(2).map(\.key) == ["2026-09", "2026-10"])
        #expect(summary.months.suffix(2).map(\.total) == [10_000, 10_000])
        #expect(summary.months.dropLast(2).allSatisfy { $0.total == 0 })
        #expect(summary.months.last?.isCurrent == true)
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

    @Test("A brand counts its points together; a point alone counts only itself")
    func brand() {
        let points = history + [
            tx("t8", "2026-10-10", 3_000, "ZARA MEGA"),
            tx("t9", "2026-10-11", 5_000, "ZARA DOSTYK PLAZA")
        ]
        let brand = MerchantGroupStore.Selection(merchants: ["zara mega", "zara dostyk plaza"], links: [:])
        let whole = MerchantHistory.summary(
            of: brand, in: points, periodStart: october.0, periodEnd: october.1, baseCurrency: "KZT", now: now
        )
        #expect(whole.transactions.map(\.id) == ["t9", "t8"])
        #expect(whole.spentInPeriod == 8_000)
        let mega = MerchantHistory.summary(
            of: MerchantGroupStore.Selection(merchants: ["zara mega"], links: [:]),
            in: points, periodStart: october.0, periodEnd: october.1, baseCurrency: "KZT", now: now
        )
        #expect(mega.transactions.map(\.id) == ["t8"])
        #expect(mega.spentInPeriod == 3_000)
    }

    @Test("An operation linked by hand counts as the merchant's, whatever its description")
    func linked() {
        let points = history + [tx("t10", "2026-10-12", 2_500, "Молоко")]
        let selection = MerchantGroupStore.Selection(merchants: ["greenmart"], links: ["t10": "greenmart", "t1": "corner bakery"])
        let result = MerchantHistory.summary(
            of: selection, in: points, periodStart: october.0, periodEnd: october.1, baseCurrency: "KZT", now: now
        )
        // t1 is linked to another merchant: no longer GreenMart's.
        #expect(result.transactions.map(\.id) == ["t5", "t4", "t2", "t10", "t3"])
        #expect(result.spentInPeriod == 8_500)
    }

    @Test("The words a brand's points start with name it")
    func sharedName() {
        #expect(MerchantGroupStore.sharedLeadingWords(of: ["ZARA MEGA ALMATY", "ZARA DOSTYK PLAZA"]) == "ZARA")
        #expect(MerchantGroupStore.sharedLeadingWords(of: ["Coffee Boom 12", "COFFEE BOOM ESENTAI"]) == "Coffee Boom")
        #expect(MerchantGroupStore.sharedLeadingWords(of: ["MAGNUM", "SMALL"]) == nil)
        #expect(MerchantGroupStore.sharedLeadingWords(of: ["ZARA"]) == nil)
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
