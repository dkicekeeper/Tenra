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

    @Test("a bank receipt's recipient is the merchant, its fee is never the amount")
    func transferReceipt() {
        let sameLine = receipt([
            "Bank of Tenra",
            "Перевод по номеру телефона",
            "Получатель: Иван И.",
            "Сумма 5 000 ₸",
            "Сумма комиссии 150 ₸",
            "20.10.2026 12:19"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: sameLine, defaultCurrency: "KZT")
        #expect(draft?.merchant == "Иван И.")
        #expect(draft?.isRecipient == true)
        #expect(draft?.total == 5000)
        #expect(draft?.date == "2026-10-20")

        let nextLine = receipt(["Bank of Tenra", "Продавец", "SMALL", "Итого 2 300 ₸"])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: nextLine, defaultCurrency: "KZT")?.merchant == "SMALL")

        // The text layer joins a two-column receipt's label and value with a space.
        let columns = receipt(["Bank of Tenra", "Получатель платежа ТОО Альфа", "Сумма 7 000 ₸"])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: columns, defaultCurrency: "KZT")?.merchant == "ТОО Альфа")
    }

    @Test("a shop's lines that start like a label name no recipient")
    func notRecipientLabels() {
        #expect(ReceiptInterpreter.labelledRecipient(["Продавец-консультант: Анна"]) == nil)
        #expect(ReceiptInterpreter.labelledRecipient(["Магазин «Пятёрочка»"]) == nil)
        #expect(ReceiptInterpreter.labelledRecipient(["Продавец Иванова А."]) == nil)
        #expect(ReceiptInterpreter.labelledRecipient(["Получатель платежей банка"]) == nil)
        #expect(ReceiptInterpreter.labelledRecipient(["Магазины рядом"]) == nil)
        #expect(ReceiptInterpreter.labelledRecipient(["Продавец : SMALL"]) == "SMALL")

        let shop = receipt(["Магазин «Пятёрочка»", "Хлеб 320", "Итого 320"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: shop, defaultCurrency: "KZT")
        #expect(draft?.merchant == "Магазин «Пятёрочка»")
        #expect(draft?.isRecipient == false)
    }

    @Test("a fee is never the amount, a total that includes it is")
    func feeInclusiveTotal() {
        let snapshot = receipt([
            "Bank of Tenra",
            "Комиссия 150 ₸",
            "Итого с учетом комиссии 5 150 ₸"
        ])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")?.total == 5150)

        let feeLargest = receipt(["Bank of Tenra", "Перевод 900 ₸", "Комиссия за перевод 1 000 ₸"])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: feeLargest, defaultCurrency: "KZT")?.total == 900)
    }

    @Test("only one page with few dates and a labelled total or recipient reads as one payment")
    func onePaymentShape() {
        #expect(ReceiptInterpreter.looksLikeOnePayment(receipt(["Bank of Tenra", "Получатель: SMALL", "Сумма 2 300 ₸"])))
        #expect(!ReceiptInterpreter.looksLikeOnePayment(receipt(["Bank of Tenra", "SMALL 2 300 ₸"])))
        let rows = ["01.10.2026 SMALL 2 300", "02.10.2026 MAGNUM 5 000", "03.10.2026 TAXI 1 200", "04.10.2026 CAFE 900"]
        #expect(!ReceiptInterpreter.looksLikeOnePayment(receipt(["Выписка", "Итого 9 400"] + rows)))
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

    // MARK: - Fix 1: Cyrillic homoglyph in "мwst"

    @Test("a Latin MwSt line is excluded from the largest-amount fallback")
    func germanVATLineExcludedFromFallback() {
        // Regression for the "мwst" entry that was spelled with Cyrillic У+043C
        // instead of Latin "m": a real, all-Latin "MwSt" line never matched it,
        // so the VAT amount leaked into the largest-amount fallback and beat
        // the real (smaller) line item.
        let snapshot = receipt([
            "REWE",
            "Milch 1L        1,29",
            "MwSt 19%       25,00"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "EUR")
        #expect(draft?.total == 1.29)
    }

    // MARK: - Fix 2: word-boundary keyword matching

    @Test("TAXI TOTAL is not excluded as a tax line")
    func taxiNotExcludedAsTax() {
        // "tax" used to be matched as a bare substring, so it matched inside
        // "taxi" and suppressed the real total on ride-hailing receipts.
        let snapshot = receipt(["YANDEX GO", "TAXI TOTAL 25.00"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "USD")
        #expect(draft?.total == 25.00)
    }

    @Test("a genuine subtotal line is still excluded under word-boundary matching")
    func genuineSubtotalStillExcluded() {
        let snapshot = receipt(["CAFE", "Subtotal 10.00", "TOTAL 12.00"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "USD")
        #expect(draft?.total == 12.00)
    }

    // MARK: - Fix 3: rightmost money-shaped run, not field splitting

    @Test("a quantity marker is not concatenated into the amount")
    func quantityMarkerNotFabricatedIntoAmount() {
        // The old field split fell through to parsing the whole line when
        // there was no wide gap, and MoneyTokenParser.parse concatenated
        // every digit run: "Item x2 500" became 2500, a number that appears
        // nowhere on the receipt.
        let snapshot = receipt(["SHOP", "Item x2 500"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "USD")
        #expect(draft?.total == 500)
    }

    @Test("the rightmost money run keeps its trailing currency marker")
    func rightmostAmountKeepsCurrencyMarker() {
        let snapshot = receipt(["CAFE", "TOTAL   1 200,50 €"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "USD")
        #expect(draft?.total == 1200.50)
        #expect(draft?.currency == "EUR")
    }

    // MARK: - Fix 1 (CRITICAL): totals of 1000+ were fragmented by the money-run regex

    @Test("a comma-grouped total over 1000 is read whole, not fragmented to its last group")
    func commaGroupedTotalOver1000ReadWhole() {
        // Before the fix, moneyRunRanges produced ["1,23", "4.56"] for this
        // line: `\d{1,3}` was willing to stop after 1-3 leading digits with
        // no lookahead stopping it mid-run, so lastAmount took "4.56" as the
        // total instead of the real 1234.56.
        // Currency is deliberately not asserted here: `lastAmount` slices from
        // the money run's *start* to end of line (see rightmostAmountKeepsCurrencyMarker
        // below), so a leading "$" before the digits was never captured even
        // before this fix — only a trailing marker like "€" is. That is a
        // separate, pre-existing limitation, not something Fix 1 touches.
        let snapshot = receipt(["SHOP", "TOTAL $1,234.56"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.total == 1234.56)
    }

    @Test("a dot-grouped, comma-decimal total over 1000 is read whole")
    func dotGroupedCommaDecimalTotalReadWhole() {
        let snapshot = receipt(["SHOP", "TOTAL 1.234,56 €"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.total == 1234.56)
        #expect(draft?.currency == "EUR")
    }

    @Test("a plain 4-digit decimal total with no grouping separator is read whole")
    func plainFourDigitDecimalTotalReadWhole() {
        // Before the fix this fragmented into ["123", "4.56"] even with no
        // thousands separator at all, because the grouping alternative could
        // match just the leading "123" and stop.
        let snapshot = receipt(["SHOP", "TOTAL 1234.56"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.total == 1234.56)
    }

    @Test("space-grouped totals under 1000 still parse correctly after the fix")
    func spaceGroupedTotalStillWorks() {
        // Regression guard: the fix must not disturb the existing
        // space-grouping behavior these two cases already pinned.
        let quantitySnapshot = receipt(["SHOP", "Item x2 500"])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: quantitySnapshot, defaultCurrency: "USD")?.total == 500)

        let totalSnapshot = receipt([
            "MAGNUM CASH & CARRY",
            "TOTAL            2 500",
            "08.01.2026 17:19"
        ])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: totalSnapshot, defaultCurrency: "KZT")?.total == 2500)
    }
}
