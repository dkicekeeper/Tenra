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
}
