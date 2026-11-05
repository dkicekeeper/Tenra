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

    // Patterns on this SDK (ICU `dMMMM` / `dMMMMyyyy` / `dMMM` / `dMMMyyyy`):
    // ja "M月d日" / "yyyy年M月d日", ko "MMMM d일" / "yyyy년 MMMM d일",
    // de "d. MMMM" / "d. MMMM yyyy", es "d 'de' MMMM" / "d 'de' MMMM 'de' yyyy".
    @Test func wordsJapanese() {
        let ja = Locale(identifier: "ja_JP")
        #expect(DateFormatters.day(date, includeYear: false, style: .words, locale: ja) == "11月3日")
        #expect(DateFormatters.day(date, includeYear: true, style: .words, locale: ja) == "2026年11月3日")
    }

    @Test func wordsKorean() {
        let ko = Locale(identifier: "ko_KR")
        #expect(DateFormatters.day(date, includeYear: false, style: .words, locale: ko) == "11월 3일")
        #expect(DateFormatters.day(date, includeYear: true, style: .words, locale: ko) == "2026년 11월 3일")
    }

    @Test func wordsGerman() {
        let de = Locale(identifier: "de_DE")
        #expect(DateFormatters.day(date, includeYear: false, style: .words, locale: de) == "3. November")
        #expect(DateFormatters.day(date, includeYear: true, style: .words, locale: de) == "3. November 2026")
    }

    @Test func wordsSpanish() {
        let es = Locale(identifier: "es_ES")
        #expect(DateFormatters.day(date, includeYear: false, style: .words, locale: es) == "3 de noviembre")
        #expect(DateFormatters.day(date, includeYear: true, style: .words, locale: es) == "3 de noviembre de 2026")
    }

    // ru "dMMM" is "d MMM" (year variant fixed to "d MMM yyyy", no "г."); en_US "MMM d" / "MMM d, yyyy".
    @Test func abbreviatedWords() {
        #expect(DateFormatters.day(date, includeYear: false, abbreviated: true, style: .words, locale: russian) == "3 нояб.")
        #expect(DateFormatters.day(date, includeYear: true, abbreviated: true, style: .words, locale: russian) == "3 нояб. 2026")
        #expect(DateFormatters.day(date, includeYear: false, abbreviated: true, style: .words, locale: american) == "Nov 3")
        #expect(DateFormatters.day(date, includeYear: true, abbreviated: true, style: .words, locale: american) == "Nov 3, 2026")
    }

    @Test func abbreviatedIgnoredByNumericStyles() {
        #expect(DateFormatters.day(date, includeYear: false, abbreviated: true, style: .dots, locale: russian) == "03.11")
        #expect(DateFormatters.day(date, includeYear: false, abbreviated: true, style: .slash, locale: american) == "11/03")
        #expect(DateFormatters.day(date, includeYear: false, abbreviated: true, style: .iso, locale: american) == "2026-11-03")
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
