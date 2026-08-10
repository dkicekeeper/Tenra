//
//  ColumnRoleResolverTests.swift
//  TenraTests
//
//  Pins bank-agnostic column detection. Each test is a real statement layout.
//

import Testing
@testable import Tenra

struct ColumnRoleResolverTests {

    @Test("Russian header keywords resolve")
    func russianHeaders() {
        let table = DocumentSnapshot.Table(rows: [
            ["Дата", "Операция", "Детали", "Сумма", "Валюта"],
            ["08.01.2026", "Покупка", "YANDEX.GO", "2 500", "KZT"],
            ["09.01.2026", "Покупка", "MAGNUM", "7 300", "KZT"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 3)
        #expect(roles?.currency == 4)
        #expect(roles?.description == 2)
    }

    @Test("English header keywords resolve")
    func englishHeaders() {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Description", "Amount", "Balance"],
            ["01/08/2026", "UBER TRIP", "-24.50", "1 200.00"],
            ["01/09/2026", "TESCO", "-13.20", "1 186.80"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.description == 1)
        #expect(roles?.amount == 2)
    }

    @Test("separate debit and credit columns are detected")
    func debitCreditColumns() {
        let table = DocumentSnapshot.Table(rows: [
            ["Datum", "Buchungstext", "Soll", "Haben"],
            ["08.01.2026", "REWE MARKT", "24,50", ""],
            ["09.01.2026", "GEHALT", "", "3 200,00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.debit == 2)
        #expect(roles?.credit == 3)
    }

    @Test("headerless tables resolve by column content")
    func contentBasedFallback() {
        // No recognizable header. Column 0 is all dates, column 2 is all money,
        // column 1 is all text. That is enough.
        let table = DocumentSnapshot.Table(rows: [
            ["08.01.2026", "YANDEX.GO", "2 500"],
            ["09.01.2026", "MAGNUM", "7 300"],
            ["10.01.2026", "WOLT", "3 100"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 2)
        #expect(roles?.description == 1)
    }

    @Test("a table with no date column resolves to nil")
    func noDateColumn() {
        let table = DocumentSnapshot.Table(rows: [
            ["Account", "Holder"],
            ["KZ51998PB00009669873", "IVANOV I"]
        ])
        #expect(ColumnRoleResolver.resolve(table: table) == nil)
    }

    @Test("low-confidence resolution is reported as such")
    func lowConfidenceIsReported() {
        // Dates present but only one body row and an unrecognized header:
        // usable, but the caller should consider asking Apple Intelligence.
        let table = DocumentSnapshot.Table(rows: [
            ["Kol1", "Kol2", "Kol3"],
            ["08.01.2026", "SOMETHING", "2 500"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles != nil)
        #expect(roles!.confidence < 0.7)
    }

    // MARK: - Fix 1: deterministic tie-breaking

    @Test("a date-score tie resolves to the lower column index, every time")
    func dateColumnTieBreaksToLowerIndexDeterministically() {
        // Two columns both fully parse as dates (e.g. a "posting date" and a
        // "value date" pair). Dictionary.max(by:) over [Int: Double] would
        // pick whichever key iteration happened to surface first, which
        // Swift randomizes per process. The lower index must win, and it
        // must win the same way on every call within this process.
        let table = DocumentSnapshot.Table(rows: [
            ["Col1", "Col2", "Amount"],
            ["08.01.2026", "09.01.2026", "2 500"],
            ["09.01.2026", "10.01.2026", "7 300"],
            ["10.01.2026", "11.01.2026", "3 100"]
        ])

        for _ in 0..<20 {
            let roles = ColumnRoleResolver.resolve(table: table)
            #expect(roles?.date == 0)
        }
    }

    // MARK: - Fix 2: amount+balance vs debit/credit adjacency

    @Test("a headerless debit/credit pair still resolves to debit/credit")
    func headerlessDebitCreditPairResolves() {
        // No recognizable header. Two adjacent money columns where each row
        // populates exactly one of the two - the debit/credit signature.
        let table = DocumentSnapshot.Table(rows: [
            ["07.01.2026", "10.00", ""],
            ["08.01.2026", "24.50", ""],
            ["09.01.2026", "", "3 200.00"],
            ["10.01.2026", "15.00", ""]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.debit == 1)
        #expect(roles?.credit == 2)
    }

    @Test("a headerless amount+balance pair resolves to amount only, never debit/credit")
    func headerlessAmountBalancePairResolvesToAmountOnly() {
        // No recognizable header. Two adjacent money columns, but both are
        // populated on essentially every row - a running balance, not a
        // debit/credit pair. Must not be read as income.
        let table = DocumentSnapshot.Table(rows: [
            ["07.01.2026", "500", "10500"],
            ["08.01.2026", "-200", "10300"],
            ["09.01.2026", "1000", "11300"],
            ["10.01.2026", "-150", "11150"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 1)
        #expect(roles?.debit == nil)
        #expect(roles?.credit == nil)
    }

    // MARK: - Fix 3: "operation"/"операция" restored as weak description fallback

    @Test("Operation is used as description when it is the only narrative column")
    func operationOnlyColumnResolvesAsDescription() {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Operation", "Amount"],
            ["08.01.2026", "UBER TRIP", "-24.50"],
            ["09.01.2026", "TESCO", "-13.20"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 2)
        #expect(roles?.description == 1)
    }

    // MARK: - Fix 4: debit-only header match no longer strands a named amount column

    @Test("a debit column plus a separately named Amount column both resolve")
    func debitColumnWithSeparateAmountColumnResolves() {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Narrative", "Debit", "Amount"],
            ["08.01.2026", "REWE MARKT", "24.50", ""],
            ["09.01.2026", "GEHALT", "", "500.00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.debit == 2)
        #expect(roles?.credit == nil)
        #expect(roles?.amount == 3)
    }
}
