//
//  StatementInterpreterTests.swift
//  TenraTests
//
//  Pins table -> transactions. Also pins that unusable rows are REPORTED
//  rather than silently dropped, which was the old parser's worst failure mode.
//

import Testing
@testable import Tenra

struct StatementInterpreterTests {

    private func snapshot(_ rows: [[String]]) -> DocumentSnapshot {
        DocumentSnapshot(
            pages: [.init(index: 0,
                          tables: [DocumentSnapshot.Table(rows: rows)],
                          lines: [],
                          barcodes: [])],
            hadTextLayer: true
        )
    }

    @Test("single amount column with explicit currency parses")
    func singleAmountColumn() {
        let doc = snapshot([
            ["Дата", "Операция", "Детали", "Сумма", "Валюта"],
            ["08.01.2026", "Покупка", "YANDEX.GO", "2 500", "KZT"],
            ["09.01.2026", "Пополнение", "SALARY", "300 000", "KZT"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].date == "2026-01-08")
        #expect(result.transactions[0].amount == 2500)
        #expect(result.transactions[0].currency == "KZT")
        #expect(result.transactions[0].descriptionText == "YANDEX.GO")
        #expect(result.skipped.isEmpty)
    }

    @Test("negative amounts become expenses and positive become income")
    func signDrivesDirection() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["01/09/2026", "REFUND", "12.00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions[0].direction == .expense)
        #expect(result.transactions[0].amount == 24.50)
        #expect(result.transactions[1].direction == .income)
        // No currency in the cell, so the caller's default applies.
        #expect(result.transactions[0].currency == "EUR")
    }

    @Test("debit and credit columns drive direction")
    func debitCreditDirection() {
        let doc = snapshot([
            ["Datum", "Buchungstext", "Soll", "Haben"],
            ["08.01.2026", "REWE MARKT", "24,50", ""],
            ["09.01.2026", "GEHALT", "", "3 200,00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].direction == .expense)
        #expect(result.transactions[0].amount == 24.50)
        #expect(result.transactions[1].direction == .income)
        #expect(result.transactions[1].amount == 3200.00)
    }

    @Test("unusable rows are reported, not dropped")
    func skippedRowsAreReported() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["Subtotal", "", "-24.50"],          // no date
            ["01/10/2026", "MYSTERY", ""]        // no amount
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions.count == 1)
        #expect(result.skipped.count == 2)
        #expect(result.skipped.contains { $0.cells.contains("Subtotal") })
        #expect(result.skipped.contains { $0.cells.contains("MYSTERY") })
    }

    @Test("reference numbers are stripped from descriptions")
    func descriptionCleaning() {
        let doc = snapshot([
            ["Дата", "Операция", "Детали", "Сумма"],
            ["08.01.2026", "Покупка", "YANDEX.GO Референс: 600815665697 Код авторизации: 681997", "2 500"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "KZT")

        #expect(result.transactions[0].descriptionText == "YANDEX.GO")
    }

    @Test("csvFile output matches the existing CSV import contract")
    func csvFileShape() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            // "08/01/2026" is day-first (day 8, month 1) per DateTokenParser's
            // pinned convention (see DateTokenParserTests.slashedAndDashed:
            // parse("08/01/2026") == "2026-01-08"), matching the expected
            // "2026-01-08" below.
            ["08/01/2026", "UBER TRIP", "-24.50"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")
        let csv = StatementInterpreter.csvFile(from: result)

        #expect(csv.headers.count == 8)
        #expect(csv.rows.count == 1)
        #expect(csv.rows[0][0] == "2026-01-08")
        #expect(csv.rows[0][1] == "expense")
        #expect(csv.rows[0][2] == "24.5")
        #expect(csv.rows[0][3] == "EUR")
        #expect(csv.rows[0][4] == "UBER TRIP")
    }
}
