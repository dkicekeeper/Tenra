//
//  DateTokenParserTests.swift
//  TenraTests
//
//  Pins the statement date formats we accept. Every format here appeared in a
//  real bank statement; adding a bank means adding a case here first.
//

import Testing
@testable import Tenra

struct DateTokenParserTests {

    @Test("dotted day-first dates parse")
    func dottedDayFirst() {
        #expect(DateTokenParser.parse("08.01.2026") == "2026-01-08")
        #expect(DateTokenParser.parse("08.01.2026 17:19:46") == "2026-01-08")
        #expect(DateTokenParser.parse("8.1.2026") == "2026-01-08")
    }

    @Test("slashed and dashed dates parse")
    func slashedAndDashed() {
        #expect(DateTokenParser.parse("08/01/2026") == "2026-01-08")
        #expect(DateTokenParser.parse("2026-01-08") == "2026-01-08")
        #expect(DateTokenParser.parse("08-01-2026") == "2026-01-08")
    }

    @Test("two-digit years resolve into the 2000s")
    func twoDigitYear() {
        #expect(DateTokenParser.parse("08.01.26") == "2026-01-08")
    }

    @Test("unambiguous month-first dates parse day-second")
    func monthFirstDisambiguation() {
        // 13 cannot be a month, so this must be day-first.
        #expect(DateTokenParser.parse("13/01/2026") == "2026-01-13")
        // 31 cannot be a month either.
        #expect(DateTokenParser.parse("31.12.2025") == "2025-12-31")
    }

    @Test("invalid dates return nil rather than a wrong date")
    func invalidDates() {
        #expect(DateTokenParser.parse("") == nil)
        #expect(DateTokenParser.parse("Purchase") == nil)
        #expect(DateTokenParser.parse("2 500") == nil)
        #expect(DateTokenParser.parse("32.01.2026") == nil)
        #expect(DateTokenParser.parse("08.13.2026") == nil)
    }

    @Test("looksLikeDate agrees with parse")
    func looksLikeDateAgrees() {
        #expect(DateTokenParser.looksLikeDate("08.01.2026"))
        #expect(!DateTokenParser.looksLikeDate("YANDEX.GO"))
    }
}
