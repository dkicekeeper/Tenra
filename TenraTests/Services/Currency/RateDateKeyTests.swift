//
//  RateDateKeyTests.swift
//  TenraTests
//
//  The dates in FX rate keys and rate API requests are Gregorian whatever the device region.
//  A DateFormatter without a POSIX locale takes the region's calendar: on a Thai (Buddhist)
//  region "yyyy" is 2569, so historical rates were stored and looked up under another year
//  and the National Bank was asked for a date that doesn't exist.
//

import Testing
import Foundation
@testable import Tenra

struct RateDateKeyTests {

    /// 12 October 2026, 12:00 UTC.
    private let date = Date(timeIntervalSince1970: 1_791_806_400)

    @Test("A region with another calendar would write another year")
    func otherCalendarsWriteAnotherYear() {
        let buddhist = DateFormatter()
        buddhist.locale = Locale(identifier: "th_TH@calendar=buddhist")
        buddhist.timeZone = TimeZone(identifier: "UTC")
        buddhist.dateFormat = "yyyy-MM-dd"
        #expect(buddhist.string(from: date) == "2569-10-12")
    }

    @Test("The rate formatter is Gregorian, POSIX and UTC")
    func rateFormatterIsFixed() {
        let formatter = DateFormatters.rateDateFormatter
        #expect(formatter.locale.identifier == "en_US_POSIX")
        #expect(formatter.calendar.identifier == .gregorian)
        #expect(formatter.timeZone == TimeZone(identifier: "UTC"))
        #expect(formatter.string(from: date) == "2026-10-12")
        #expect(formatter.date(from: "2026-10-12") == Date(timeIntervalSince1970: 1_791_763_200))
    }

    @Test("Historical rate keys use the rate formatter")
    func historicalKey() {
        #expect(CurrencyConverter.dateKey(for: date) == "2026-10-12")
    }

    @Test("The National Bank request date is Gregorian")
    func nationalBankRequestDate() {
        // The device's day: the noon UTC instant is the 12th in every time zone from UTC-11 to UTC+11.
        #expect(NationalBankKZProvider.requestDateString(for: date) == "12.10.2026")
    }
}
