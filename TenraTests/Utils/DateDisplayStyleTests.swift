//
//  DateDisplayStyleTests.swift
//  TenraTests
//
//  `DateFormatters.day(_:includeYear:style:locale:)`: one day date in the chosen style.
//

import Testing
import Foundation
@testable import Tenra

struct DateDisplayStyleTests {
    /// 2026-11-03 noon, Gregorian, in the process time zone (the formatters use it).
    private var date: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 12))!
    }

    private let russian = Locale(identifier: "ru_KZ")
    private let american = Locale(identifier: "en_US")

    @Test func wordsRussian() {
        #expect(DateFormatters.day(date, includeYear: false, style: .words, locale: russian) == "3 ноября")
        #expect(DateFormatters.day(date, includeYear: true, style: .words, locale: russian) == "3 ноября 2026")
    }

    @Test func wordsUnitedStates() {
        #expect(DateFormatters.day(date, includeYear: false, style: .words, locale: american) == "November 3")
        #expect(DateFormatters.day(date, includeYear: true, style: .words, locale: american) == "November 3, 2026")
    }

    @Test func dots() {
        #expect(DateFormatters.day(date, includeYear: false, style: .dots, locale: russian) == "03.11")
        #expect(DateFormatters.day(date, includeYear: true, style: .dots, locale: russian) == "03.11.2026")
    }

    @Test func slash() {
        #expect(DateFormatters.day(date, includeYear: false, style: .slash, locale: american) == "11/03")
        #expect(DateFormatters.day(date, includeYear: true, style: .slash, locale: american) == "11/03/2026")
    }

    @Test func isoAlwaysWithYear() {
        #expect(DateFormatters.day(date, includeYear: false, style: .iso, locale: russian) == "2026-11-03")
        #expect(DateFormatters.day(date, includeYear: true, style: .iso, locale: american) == "2026-11-03")
    }
}
