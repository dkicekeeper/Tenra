//
//  StatementBalanceParserTests.swift
//  TenraTests
//
//  The closing balance a statement prints (for the review screen's balance
//  check), in the two shapes seen on real Kazakh statements, and the import's
//  effect on the account up to that date. Lines are anonymized.
//

import Testing
import Foundation
@testable import Tenra

struct StatementBalanceParserTests {

    @Test func labelledLinesTakeTheLatestDate() {
        let lines = [
            "по Kaspi Gold за период с 24.08.26 по 24.09.26",
            "Доступно на 24.08.26 + 10 500,00 ₸ Остаток зарплатных денег 0,00 ₸",
            "Доступно на 24.09.26: + 12 345,67 ₸ Валюта счета: тенге"
        ]
        #expect(StatementBalanceParser.closingBalances(in: lines) == [
            StatementBalance(amount: 12_345.67, currency: "KZT", asOf: "2026-09-24")
        ])
    }

    @Test func accountTableRowsAreDatedByThePeriodEnd() {
        // The period word sits on its own line, as Freedom prints it.
        let lines = [
            "Выписка по Deposit Card",
            "за с 01.09.2026 по 20.09.2026",
            "период",
            "KZ00000A0000000001 USD 0.77 $",
            "KZ00000A0000000002 CNY 0.00 ¥",
            "KZ00000A0000000003 KZT 27,000.50 ₸"
        ]
        #expect(StatementBalanceParser.periodEnd(in: lines) == "2026-09-20")
        #expect(StatementBalanceParser.closingBalances(in: lines) == [
            StatementBalance(amount: 0, currency: "CNY", asOf: "2026-09-20"),
            StatementBalance(amount: 27_000.5, currency: "KZT", asOf: "2026-09-20"),
            StatementBalance(amount: 0.77, currency: "USD", asOf: "2026-09-20")
        ])
    }

    @Test func negativeBalanceKeepsItsSign() {
        let lines = ["Statement period 01/08/2026 - 31/08/2026", "Closing balance -1 250.00"]
        #expect(StatementBalanceParser.closingBalances(in: lines) == [
            StatementBalance(amount: -1_250, currency: nil, asOf: "2026-08-31")
        ])
    }

    @Test func nothingWithoutCentsOrADate() {
        #expect(StatementBalanceParser.closingBalances(in: ["Остаток на 20.09.2026: 5000"]).isEmpty)
        #expect(StatementBalanceParser.closingBalances(in: ["Closing balance 1 250.00"]).isEmpty)
        #expect(StatementBalanceParser.closingBalances(in: ["24.09.26 - 995,00 ₸ Покупка MAGNUM"]).isEmpty)
    }

    @Test func importEffectCountsCheckedRowsUpToTheClosingDate() {
        func row(_ date: String, _ amount: Double, _ type: TransactionType) -> Transaction {
            Transaction(id: UUID().uuidString, date: date, description: "row", amount: amount,
                        currency: "KZT", type: type, category: "", accountId: nil)
        }
        let rows = [
            row("2026-09-10", 100, .income),
            row("2026-09-12", 30, .expense),
            row("2026-09-25", 5, .expense),   // after the closing date
            row("2026-09-01", 50, .income)    // before the account existed: compensated
        ]
        #expect(ImportReconciliation.importEffect(of: rows, asOf: "2026-09-20", compensatedBefore: "2026-09-05") == 70)
        #expect(ImportReconciliation.importEffect(of: rows, asOf: "2026-09-20", compensatedBefore: nil) == 120)
    }
}
