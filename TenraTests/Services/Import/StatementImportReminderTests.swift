//
//  StatementImportReminderTests.swift
//  TenraTests
//
//  Pins when the statement reminders come: every interval from the day of the last import,
//  at 10:00, only the ones still ahead; none when off or before the first import.
//

import Testing
import Foundation
@testable import Tenra

struct StatementImportReminderTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func dates(lastImport: Date?, interval: Int = 7, now: Date) -> [Date] {
        StatementImportReminder.reminderDates(
            lastImport: lastImport, intervalDays: interval, now: now, count: 3, calendar: calendar
        )
    }

    @Test("Every week from the import's day, at ten in the morning")
    func weekly() {
        #expect(dates(lastImport: date(1, 18), now: date(2)) == [date(8, 10), date(15, 10), date(22, 10)])
    }

    @Test("Reminders already behind now are skipped, the next ones keep the rhythm")
    func skipsPast() {
        #expect(dates(lastImport: date(1), now: date(16)) == [date(22, 10), date(29, 10), date(5, 10, month: 11)])
        // On the reminder's day after ten, that day's reminder is behind.
        #expect(dates(lastImport: date(1), now: date(8, 11)).first == date(15, 10))
    }

    @Test("A longer interval is counted the same way")
    func monthly() {
        #expect(dates(lastImport: date(1), interval: 30, now: date(2)).first == date(31, 10))
    }

    @Test("None when off or before the first statement import")
    func noneWhenOffOrNeverImported() {
        #expect(dates(lastImport: date(1), interval: 0, now: date(2)).isEmpty)
        #expect(dates(lastImport: nil, now: date(2)).isEmpty)
    }
}
