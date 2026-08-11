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

    // MARK: - Fix 3 (CRITICAL): all-skipped statements must reach diagnostics, not throw

    @Test("a statement where every row is skipped returns an outcome instead of throwing")
    func allSkippedStatementReturnsOutcomeInsteadOfThrowing() async throws {
        // A table with a recognizable date column but no amount/debit/credit
        // column at all: every row fails extractMoney and is skipped with
        // "import.skip.noAmount". Before the fix this threw
        // PDFError.noTransactionsRecognized, discarding the whole
        // ParsedStatement (including its populated `skipped` array) and
        // leaving the diagnostics screen unreachable.
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Description"],
            ["01/08/2026", "UBER TRIP"],
            ["01/09/2026", "TESCO"],
            ["01/10/2026", "SALARY"]
        ])
        let page = DocumentSnapshot.Page(index: 0, tables: [table], lines: [], barcodes: [])
        let snapshot = DocumentSnapshot(pages: [page], hadTextLayer: true)

        let outcome = try await DocumentImportService.interpret(snapshot: snapshot, defaultCurrency: "USD")

        #expect(outcome.statement.transactions.isEmpty)
        #expect(outcome.statement.skipped.count == 3)
        #expect(outcome.statement.skipped.allSatisfy { $0.reason == "import.skip.noAmount" })
    }

    // MARK: - Fix 6: unreadable pages are reported, not silently dropped

    @Test("unreadable page indices are merged into skipped rows without disturbing recognized transactions")
    func unreadablePagesAreMergedIntoSkipped() async throws {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["01/09/2026", "TESCO", "-13.20"],
            ["01/10/2026", "SALARY", "3200.00"]
        ])
        let page = DocumentSnapshot.Page(index: 0, tables: [table], lines: [], barcodes: [])
        let snapshot = DocumentSnapshot(pages: [page], hadTextLayer: true)

        // Pages 1 and 3 (0-based indices 0 and 2) failed to rasterize.
        let outcome = try await DocumentImportService.interpret(
            snapshot: snapshot,
            defaultCurrency: "USD",
            unreadablePages: [0, 2]
        )

        // The real table's rows are untouched: recognition still succeeds.
        #expect(outcome.statement.transactions.count == 3)

        let pageSkips = outcome.statement.skipped.filter { $0.reason == "import.skip.pageUnreadable" }
        #expect(pageSkips.count == 2)
        // `cells` holds the raw 1-based page number (locale-independent);
        // ImportDiagnosticsView applies the localized "Page" label at
        // render time.
        #expect(Set(pageSkips.map { $0.cells.first }) == Set(["1", "3"]))
        // rowIndex must be unique per page (and disjoint from real row
        // indices, which are always positive) so SwiftUI's ForEach(id:) does
        // not collide when several pages are unreadable.
        #expect(Set(pageSkips.map { $0.rowIndex }) == Set([-1, -3]))
    }

    @Test("no unreadable pages means no page-level skips are added")
    func noUnreadablePagesAddsNoPageSkips() async throws {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"]
        ])
        let page = DocumentSnapshot.Page(index: 0, tables: [table], lines: [], barcodes: [])
        let snapshot = DocumentSnapshot(pages: [page], hadTextLayer: true)

        let outcome = try await DocumentImportService.interpret(snapshot: snapshot, defaultCurrency: "USD")

        #expect(outcome.statement.skipped.allSatisfy { $0.reason != "import.skip.pageUnreadable" })
    }
}
