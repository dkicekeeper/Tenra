//
//  DateOrderDetectorTests.swift
//  TenraTests
//
//  A single token cannot tell DD/MM from MM/DD. A column can: one token with a
//  component above 12 pins the order for every other token in that column.
//

import Testing
@testable import Tenra

struct DateOrderDetectorTests {

    @Test("a day above 12 anywhere in the column pins day-first")
    func dayFirstEvidence() {
        let tokens = ["01/08/2026", "13/08/2026", "05/09/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .dayFirst)
    }

    @Test("a month position above 12 anywhere in the column pins month-first")
    func monthFirstEvidence() {
        let tokens = ["01/08/2026", "01/25/2026", "02/03/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .monthFirst)
    }

    @Test("a fully ambiguous column defaults to day-first")
    func ambiguousDefaultsToDayFirst() {
        let tokens = ["01/08/2026", "02/09/2026", "03/10/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .dayFirst)
    }

    @Test("ISO tokens carry no ambiguity and do not sway the verdict")
    func isoTokensIgnored() {
        let tokens = ["2026-01-08", "2026-08-13", "01/25/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .monthFirst)
    }

    @Test("conflicting evidence favours day-first, the dominant world convention")
    func conflictingEvidence() {
        // A column cannot really be both. Real cause is OCR noise, so prefer
        // the convention used by more of the app's markets rather than
        // rejecting the whole column.
        let tokens = ["13/08/2026", "01/25/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .dayFirst)
    }

    @Test("an empty or dateless column defaults to day-first")
    func noDates() {
        #expect(DateOrderDetector.detect(tokens: []) == .dayFirst)
        #expect(DateOrderDetector.detect(tokens: ["Purchase", "Total"]) == .dayFirst)
    }
}
