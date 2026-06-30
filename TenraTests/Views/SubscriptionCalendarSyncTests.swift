//
//  SubscriptionCalendarSyncTests.swift
//  TenraTests
//
//  Covers the week/month collapse anchoring for the subscription calendar — specifically
//  the regression where collapsing the current month jumped today's week to the month's
//  first week ("29 июня–5 июля" → "1 июня–7 июня").
//

import Testing
import Foundation
@testable import Tenra

struct SubscriptionCalendarSyncTests {

    /// Mirror the view's week array: 8 weeks before today's week + today's week (index 8) + ahead.
    private func makeWeeks(today: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let thisWeekStart = calendar.date(byAdding: .day, value: -offset, to: start)!
        return (0..<56).compactMap { calendar.date(byAdding: .weekOfYear, value: $0 - 8, to: thisWeekStart) }
    }

    private func month(_ y: Int, _ m: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: 1))!
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }

    @Test("collapsing the current month keeps today's week (the reported bug)")
    func keepsTodaysWeekOnCurrentMonth() {
        let cal = calendar
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        let weeks = makeWeeks(today: today, calendar: cal)

        // Expand→collapse on June leaves currentWeekIndex at today's week (8).
        let result = SubscriptionCalendarSync.collapsedWeekIndex(
            displayedMonth: month(2026, 6, cal),
            currentWeekIndex: 8,
            weeks: weeks,
            today: today,
            calendar: cal
        )

        #expect(result == 8) // today's week (29 июня), NOT the month's first week (1 июня)
    }

    @Test("collapsing after swiping to a future month anchors to that month's first week")
    func anchorsToFirstWeekOfSwipedMonth() {
        let cal = calendar
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        let weeks = makeWeeks(today: today, calendar: cal)

        // Viewing August while currentWeekIndex still points at June's week.
        let result = SubscriptionCalendarSync.collapsedWeekIndex(
            displayedMonth: month(2026, 8, cal),
            currentWeekIndex: 8,
            weeks: weeks,
            today: today,
            calendar: cal
        )

        let picked = weeks[result]
        // The picked week must contain 1 August 2026.
        let augFirst = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let weekEnd = cal.date(byAdding: .day, value: 7, to: picked)!
        #expect(picked <= augFirst && augFirst < weekEnd)
    }

    @Test("a week already inside the displayed month is preserved unchanged")
    func preservesWeekAlreadyInMonth() {
        let cal = calendar
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        let weeks = makeWeeks(today: today, calendar: cal)

        // Index 6 = two weeks before today's week → 15 июня, squarely inside June.
        let result = SubscriptionCalendarSync.collapsedWeekIndex(
            displayedMonth: month(2026, 6, cal),
            currentWeekIndex: 6,
            weeks: weeks,
            today: today,
            calendar: cal
        )

        #expect(result == 6) // unchanged — user's swiped week context is kept
    }

    @Test("out-of-range index is returned unchanged (no crash)")
    func outOfRangeIsSafe() {
        let cal = calendar
        let today = cal.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        let weeks = makeWeeks(today: today, calendar: cal)

        let result = SubscriptionCalendarSync.collapsedWeekIndex(
            displayedMonth: month(2026, 6, cal),
            currentWeekIndex: 999,
            weeks: weeks,
            today: today,
            calendar: cal
        )

        #expect(result == 999)
    }
}
