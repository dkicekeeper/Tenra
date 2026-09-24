//
//  RecurringDateMathTests.swift
//  TenraTests
//
//  Occurrence k is start + k periods (anchored), so month-end series keep their
//  day: Jan 31 → Feb 28 → Mar 31 → Apr 30. The old "previous + 1 month" stepping
//  drifted to the 28th forever after February.
//

import Testing
import Foundation
@testable import Tenra

struct RecurringDateMathTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private func d(_ key: String) -> Date { formatter.date(from: key)! }
    private func key(_ date: Date?) -> String? { date.map { formatter.string(from: $0) } }

    private func occurrences(_ start: String, _ frequency: RecurringFrequency, _ indices: [Int]) -> [String?] {
        indices.map { key(RecurringDateMath.occurrence($0, start: d(start), frequency: frequency, calendar: calendar)) }
    }

    @Test func monthlyFromJan31KeepsMonthEnd() {
        #expect(occurrences("2025-01-31", .monthly, [0, 1, 2, 3, 4])
                == ["2025-01-31", "2025-02-28", "2025-03-31", "2025-04-30", "2025-05-31"])
    }

    @Test func monthlyLeapFebruary() {
        #expect(occurrences("2024-01-31", .monthly, [1]) == ["2024-02-29"])
    }

    @Test func yearlyFromFeb29() {
        #expect(occurrences("2024-02-29", .yearly, [1, 4]) == ["2025-02-28", "2028-02-29"])
    }

    @Test func quarterlyFromNov30() {
        #expect(occurrences("2025-11-30", .quarterly, [1, 2]) == ["2026-02-28", "2026-05-30"])
    }

    @Test func weeklyAndDailyAreSimpleAddition() {
        #expect(occurrences("2026-09-01", .weekly, [1, 2]) == ["2026-09-08", "2026-09-15"])
        #expect(occurrences("2026-09-30", .daily, [1, 2]) == ["2026-10-01", "2026-10-02"])
    }

    @Test func resumingAfterDriftedOccurrenceSkipsItsMonth() {
        let next = RecurringDateMath.occurrence(
            afterPeriodOf: d("2025-03-28"), start: d("2025-01-31"), frequency: .monthly, calendar: calendar)
        #expect(key(next) == "2025-04-30")
    }

    @Test func periodIndexIgnoresDayForMonthBased() {
        #expect(RecurringDateMath.periodIndex(of: d("2025-03-28"), start: d("2025-01-31"), frequency: .monthly, calendar: calendar) == 2)
        #expect(RecurringDateMath.periodIndex(of: d("2024-12-01"), start: d("2025-01-31"), frequency: .monthly, calendar: calendar) == 0)
    }

    @Test func firstOccurrenceStrictlyAfter() {
        let start = d("2025-01-31")
        #expect(key(RecurringDateMath.firstOccurrence(after: d("2025-03-10"), start: start, frequency: .monthly, calendar: calendar)) == "2025-03-31")
        #expect(key(RecurringDateMath.firstOccurrence(after: d("2025-03-31"), start: start, frequency: .monthly, calendar: calendar)) == "2025-04-30")
        #expect(key(RecurringDateMath.firstOccurrence(after: d("2026-09-15"), start: d("2026-01-15"), frequency: .monthly, calendar: calendar)) == "2026-10-15")
    }
}
