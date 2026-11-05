//
//  NewcomerAnalyticsTests.swift
//  TenraTests
//
//  Pins two things a newcomer met in Analytics after one expense (backlog "First run" item 4):
//  the daily average of the period under way divides by the days so far, not by the whole
//  period (3 500 ₸ on 5 November is 700 ₸ a day, not 117 ₸), and a health score that could not
//  be computed (no income yet) is not available, so the feed does not show it as "0 / 100".
//

import Testing
import Foundation
@testable import Tenra

struct NewcomerAnalyticsTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test("The month under way divides by the days so far, today included")
    func averageDividesByDaysSoFarInCurrentPeriod() {
        let days = InsightsService.daysForDailyAverage(
            periodStart: date(11, 1), periodEnd: date(12, 1), now: date(11, 5, 12), calendar: calendar
        )
        #expect(days == 5)
    }

    @Test("A past month divides by all its days")
    func averageDividesByAllDaysInPastPeriod() {
        let days = InsightsService.daysForDailyAverage(
            periodStart: date(10, 1), periodEnd: date(11, 1), now: date(11, 5, 12), calendar: calendar
        )
        #expect(days == 31)
    }

    @Test("The first morning of a month counts one day")
    func firstDayCountsOne() {
        let days = InsightsService.daysForDailyAverage(
            periodStart: date(11, 1), periodEnd: date(12, 1), now: date(11, 1, 8), calendar: calendar
        )
        #expect(days == 1)
    }

    @Test("A score that could not be computed is not available")
    func unavailableScoreIsNotAvailable() {
        #expect(!FinancialHealthScore.unavailable().isAvailable)
    }

    @Test("A top card's share is said in its subtitle, not shown as a trend")
    func shareOfSpendingInSubtitle() {
        let subtitle = InsightsService.shareOfSpendingSubtitle(name: "Продукты", sharePercent: 34.2)
        #expect(subtitle.contains("Продукты"))
        #expect(subtitle.contains("34"))
        #expect(!subtitle.contains("+"))
    }
}
