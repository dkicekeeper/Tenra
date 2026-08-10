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
        #expect(DateTokenParser.parse("13/25/2026") == nil)
    }

    @Test("looksLikeDate agrees with parse")
    func looksLikeDateAgrees() {
        #expect(DateTokenParser.looksLikeDate("08.01.2026"))
        #expect(!DateTokenParser.looksLikeDate("YANDEX.GO"))
    }

    @Test("looksLikeDate is order-agnostic so US date columns are still detected")
    func looksLikeDateIsOrderAgnostic() {
        // Invalid day-first, valid month-first. ColumnRoleResolver must still
        // count this cell towards the date-column score.
        #expect(DateTokenParser.looksLikeDate("08.13.2026"))
        #expect(DateTokenParser.looksLikeDate("12/25/2026"))
        // Valid under neither order.
        #expect(!DateTokenParser.looksLikeDate("13/25/2026"))
        #expect(!DateTokenParser.looksLikeDate("YANDEX.GO"))
    }

    @Test("explicit month-first order reads US dates correctly")
    func explicitMonthFirst() {
        #expect(DateTokenParser.parse("01/08/2026", order: .monthFirst) == "2026-01-08")
        #expect(DateTokenParser.parse("12/25/2026", order: .monthFirst) == "2026-12-25")
    }

    @Test("explicit day-first order reads EU dates correctly")
    func explicitDayFirst() {
        #expect(DateTokenParser.parse("01/08/2026", order: .dayFirst) == "2026-08-01")
        #expect(DateTokenParser.parse("13/08/2026", order: .dayFirst) == "2026-08-13")
    }

    @Test("an explicit order falls back to the other order when its own reading is invalid")
    func explicitOrderFallsBack() {
        // Told month-first, but 25 is not a month, so day-first is the only
        // valid reading. Better a correct date than a dropped row.
        #expect(DateTokenParser.parse("25/12/2026", order: .monthFirst) == "2026-12-25")
    }

    @Test("ISO tokens ignore the order parameter")
    func isoIgnoresOrder() {
        #expect(DateTokenParser.parse("2026-01-08", order: .monthFirst) == "2026-01-08")
        #expect(DateTokenParser.parse("2026-01-08", order: .dayFirst) == "2026-01-08")
    }
}
