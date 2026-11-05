import Testing
import Foundation
@testable import Tenra

@Suite("WeekStart — one first day of the week")
struct WeekStartTests {

    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private let sunday = WeekStartTests.calendar(firstWeekday: 1)
    private let monday = WeekStartTests.calendar(firstWeekday: 2)

    @Test func thisWeekFromSunday() {
        let now = Self.date(2026, 11, 8, 10, calendar: sunday)
        let range = TimeFilterPreset.thisWeek.dateRange(now: now, calendar: sunday)
        #expect(range.start == Self.date(2026, 11, 8, calendar: sunday))
        #expect(range.end == Self.date(2026, 11, 15, calendar: sunday))
    }

    @Test func thisWeekFromMonday() {
        let now = Self.date(2026, 11, 8, 10, calendar: monday)
        let range = TimeFilterPreset.thisWeek.dateRange(now: now, calendar: monday)
        #expect(range.start == Self.date(2026, 11, 2, calendar: monday))
        #expect(range.end == Self.date(2026, 11, 9, calendar: monday))
    }

    @Test @MainActor func weeklyBudgetFromSunday() {
        let now = Self.date(2026, 11, 8, 10, calendar: sunday)
        let period = CategoryBudgetService.weeklyPeriod(now: now, calendar: sunday)
        #expect(period.start == Self.date(2026, 11, 8, calendar: sunday))
    }

    @Test func digestOnSunday() {
        let after = Self.date(2026, 11, 5, 12, calendar: sunday)
        let fire = WeeklyDigestScheduler.nextFireDate(after: after, calendar: sunday)
        #expect(fire == Self.date(2026, 11, 8, 9, calendar: sunday))
    }

    /// Settings › Insight alerts names the digest's day: the first of the week.
    @Test func digestLabelNamesTheFirstDay() {
        #expect(InsightSignalSettingsView.digestLabel(calendar: sunday).contains(sunday.shortStandaloneWeekdaySymbols[0]))
        #expect(InsightSignalSettingsView.digestLabel(calendar: monday).contains(monday.shortStandaloneWeekdaySymbols[1]))
        #expect(!InsightSignalSettingsView.digestLabel(calendar: monday).contains("%@"))
    }

    @Test func digestOnMonday() {
        let after = Self.date(2026, 11, 5, 12, calendar: monday)
        let fire = WeeklyDigestScheduler.nextFireDate(after: after, calendar: monday)
        #expect(fire == Self.date(2026, 11, 9, 9, calendar: monday))
    }
}
