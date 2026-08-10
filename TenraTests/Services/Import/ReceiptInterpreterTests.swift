//
//  ReceiptInterpreterTests.swift
//  TenraTests
//
//  Pins the deterministic receipt fallback. The Apple Intelligence path cannot
//  be unit-tested (it needs an eligible device and a downloaded model), so the
//  heuristic path is the one that must be provably correct.
//

import Testing
@testable import Tenra

struct ReceiptInterpreterTests {

    private func receipt(_ lines: [String]) -> DocumentSnapshot {
        DocumentSnapshot(
            pages: [.init(index: 0, tables: [], lines: lines, barcodes: [])],
            hadTextLayer: false
        )
    }

    @Test("total is taken from the line labelled as total")
    func totalFromLabel() {
        let snapshot = receipt([
            "MAGNUM CASH & CARRY",
            "Milk 1L            450",
            "Bread              320",
            "Subtotal           770",
            "TOTAL            2 500",
            "08.01.2026 17:19"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.total == 2500)
        #expect(draft?.date == "2026-01-08")
    }

    @Test("merchant is the first substantial non-numeric line")
    func merchantFromFirstLine() {
        let snapshot = receipt([
            "MAGNUM CASH & CARRY",
            "TOTAL            2 500"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.merchant == "MAGNUM CASH & CARRY")
    }

    @Test("without a total label the largest amount wins")
    func largestAmountFallback() {
        let snapshot = receipt([
            "CAFE",
            "Espresso   1 200",
            "Cake       2 400",
            "3 600"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "EUR")
        #expect(draft?.total == 3600)
    }

    @Test("a receipt with no amount yields nil")
    func noAmount() {
        let snapshot = receipt(["THANK YOU", "COME AGAIN"])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "EUR") == nil)
    }

    @Test("currency from the receipt overrides the default")
    func currencyFromReceipt() {
        let snapshot = receipt(["CAFE", "TOTAL  12,50 €"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "USD")
        #expect(draft?.currency == "EUR")
    }
}
