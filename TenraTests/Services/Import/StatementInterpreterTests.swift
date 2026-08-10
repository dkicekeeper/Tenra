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
        // Amount is rendered with explicit two-decimal formatting (Fix 5):
        // bare `String(Double)` would emit "24.5", which the downstream CSV
        // re-parse handles fine for this value but not for whole amounts
        // (see wholeAmountRendersWithTwoDecimals) or very large magnitudes
        // that flip to scientific notation.
        #expect(csv.rows[0][2] == "24.50")
        #expect(csv.rows[0][3] == "EUR")
        #expect(csv.rows[0][4] == "UBER TRIP")
    }

    // MARK: - Fix 1: incompatible tables are reported, not dropped

    @Test("a table whose shape doesn't match the resolved roles has all its rows reported skipped")
    func incompatibleTableRowsAreReported() {
        // roles.date == 2, so a table with fewer than 3 columns can never be
        // interpreted with these roles.
        let roles = ColumnRoles(date: 2, amount: 3, debit: nil, credit: nil,
                                currency: nil, description: 1, confidence: 1.0)

        let matchingTable = DocumentSnapshot.Table(rows: [
            ["x", "Groceries", "08.01.2026", "100"]
        ])
        let narrowTable = DocumentSnapshot.Table(rows: [
            ["01.01.2026", "50"],
            ["02.01.2026", "75"]
        ])
        let doc = DocumentSnapshot(
            pages: [.init(index: 0, tables: [matchingTable, narrowTable], lines: [], barcodes: [])],
            hadTextLayer: true
        )

        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        #expect(result.transactions.count == 1)
        #expect(result.skipped.count == 2)
        #expect(result.skipped.allSatisfy { $0.reason == "import.skip.tableShapeMismatch" })
        #expect(result.skipped.contains { $0.cells == ["01.01.2026", "50"] })
        #expect(result.skipped.contains { $0.cells == ["02.01.2026", "75"] })
    }

    // MARK: - Fix 2: header detection requires no digits, not just no money

    @Test("a genuine text-only header row is not reported as skipped")
    func genuineHeaderStaysOutOfSkipped() {
        let roles = ColumnRoles(date: 0, amount: 2, debit: nil, credit: nil,
                                currency: nil, description: 1, confidence: 1.0)
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["08.01.2026", "Coffee", "5.00"]
        ])

        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        #expect(result.transactions.count == 1)
        #expect(result.skipped.isEmpty)
    }

    @Test("a digit-bearing row with an unparseable date is reported skipped, not swallowed as a header")
    func digitBearingRowWithBadDateIsReported() {
        let roles = ColumnRoles(date: 0, amount: 1, debit: nil, credit: nil,
                                currency: nil, description: 2, confidence: 1.0)
        // Column 0 is not a valid calendar date (February has no 31st), so
        // DateTokenParser.parse fails and no cell looks like money (the only
        // other digit-bearing cell, column 2, is itself a *valid* date and so
        // is excluded from MoneyTokenParser.looksLikeMoney by design). The
        // old amount-based heuristic would have misread this as a header.
        let doc = snapshot([
            ["31.02.2026", "note", "01.03.2026"]
        ])

        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        #expect(result.transactions.isEmpty)
        #expect(result.skipped.count == 1)
        #expect(result.skipped[0].reason == "import.skip.noDate")
        #expect(result.skipped[0].cells == ["31.02.2026", "note", "01.03.2026"])
    }

    // MARK: - Fix 3: debit/credit direction respects the parsed sign

    @Test("a negative debit is income and a negative credit is expense, magnitude preserved")
    func debitCreditRespectsSign() {
        let doc = snapshot([
            ["Datum", "Buchungstext", "Soll", "Haben"],
            ["08.01.2026", "STORNO REWE", "-24,50", ""],
            ["09.01.2026", "STORNO GEHALT", "", "-3 200,00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].direction == .income)
        #expect(result.transactions[0].amount == 24.50)
        #expect(result.transactions[1].direction == .expense)
        #expect(result.transactions[1].amount == 3200.00)
    }

    // MARK: - Fix 4: fallback description excludes unassigned money columns

    @Test("fallback description omits an unassigned trailing balance column")
    func fallbackDescriptionExcludesBalanceColumn() {
        // description: nil forces the fallback join path.
        let roles = ColumnRoles(date: 0, amount: 2, debit: nil, credit: nil,
                                currency: nil, description: nil, confidence: 1.0)
        let doc = snapshot([
            ["08.01.2026", "Grocery Store", "24.50", "1200.00"]
        ])

        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions.count == 1)
        #expect(result.transactions[0].descriptionText == "Grocery Store")
        #expect(!result.transactions[0].descriptionText.contains("1200"))
    }

    // MARK: - Fix 5: amount rendering

    @Test("a whole amount renders with two decimal places, not scientific or bare notation")
    func wholeAmountRendersWithTwoDecimals() {
        let doc = snapshot([
            ["Дата", "Операция", "Детали", "Сумма", "Валюта"],
            ["09.01.2026", "Пополнение", "SALARY", "300 000", "KZT"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "KZT")
        let csv = StatementInterpreter.csvFile(from: result)

        #expect(csv.rows[0][2] == "300000.00")
    }

    @Test("a US-ordered date column is read month-first across every row")
    func usDateOrdering() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["01/25/2026", "TESCO", "-13.20"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        // 01/25 can only be month-first, which pins the whole column, so
        // 01/08 must read as 8 January and not 1 August.
        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].date == "2026-01-08")
        #expect(result.transactions[1].date == "2026-01-25")
    }
}
