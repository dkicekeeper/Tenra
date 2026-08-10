//
//  DocumentImportServiceTests.swift
//  TenraTests
//
//  Pins bestTable's selection: a statement page holds several tables
//  (account summary, fees, transactions); the transaction table must win.
//

import Testing
@testable import Tenra

struct DocumentImportServiceTests {

    @Test("prefers the larger table that resolves to usable roles over a smaller non-transaction table")
    func picksLargestResolvableTable() {
        let summaryTable = DocumentSnapshot.Table(rows: [
            ["Account", "Owner"],
            ["KZ123456789", "John Doe"]
        ])
        let transactionsTable = DocumentSnapshot.Table(rows: [
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["01/09/2026", "TESCO", "-13.20"],
            ["01/10/2026", "SALARY", "3200.00"]
        ])
        let page = DocumentSnapshot.Page(
            index: 0,
            tables: [summaryTable, transactionsTable],
            lines: [],
            barcodes: []
        )
        let snapshot = DocumentSnapshot(pages: [page], hadTextLayer: true)

        let best = DocumentImportService.bestTable(in: snapshot)
        #expect(best == transactionsTable)
    }

    @Test("falls back to the largest table overall when no table resolves usable roles")
    func fallsBackToLargestTableWhenNoneResolve() {
        // Neither table has a date column or money content, so
        // ColumnRoleResolver.resolve returns nil for both.
        let smallTable = DocumentSnapshot.Table(rows: [
            ["Foo"],
            ["Bar"]
        ])
        let largeTable = DocumentSnapshot.Table(rows: [
            ["Foo", "Bar"],
            ["Baz", "Qux"],
            ["Alpha", "Beta"]
        ])
        let page = DocumentSnapshot.Page(
            index: 0,
            tables: [smallTable, largeTable],
            lines: [],
            barcodes: []
        )
        let snapshot = DocumentSnapshot(pages: [page], hadTextLayer: true)

        let best = DocumentImportService.bestTable(in: snapshot)
        #expect(best == largeTable)
    }
}
