//
//  SubscriptionNextChargeDateTests.swift
//  TenraTests
//
//  Pins the reminder date math (SubscriptionNotificationScheduler), which had no
//  tests. Dates come from RecurringDateMath, the same anchored math the
//  generator uses, so reminders and recorded occurrences agree on the day.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct SubscriptionNextChargeDateTests {

    private func series(start: String, frequency: RecurringFrequency = .monthly, status: SubscriptionStatus? = .active) -> RecurringSeries {
        RecurringSeries(
            amount: 4990, currency: "KZT", category: "Subscriptions", description: "Netflix",
            frequency: frequency, startDate: start, kind: .subscription, status: status
        )
    }

    private func next(_ series: RecurringSeries, today: String) -> String? {
        let date = SubscriptionNotificationScheduler.shared.calculateNextChargeDate(
            for: series, today: DateFormatters.dateFormatter.date(from: today)!
        )
        return date.map { DateFormatters.dateFormatter.string(from: $0) }
    }

    @Test func nextMonthlyChargeInTheSameMonth() {
        #expect(next(series(start: "2026-01-15"), today: "2026-09-10") == "2026-09-15")
    }

    /// A charge due today counts as passed: its reminders fired before today.
    @Test func chargeDueTodayMovesToNextPeriod() {
        #expect(next(series(start: "2026-01-15"), today: "2026-09-15") == "2026-10-15")
    }

    @Test func monthEndSeriesKeepsItsDay() {
        #expect(next(series(start: "2025-01-31"), today: "2026-03-01") == "2026-03-31")
        #expect(next(series(start: "2025-01-31"), today: "2026-04-01") == "2026-04-30")
    }

    @Test func futureStartIsTheNextCharge() {
        #expect(next(series(start: "2026-12-01"), today: "2026-09-10") == "2026-12-01")
    }

    @Test func weeklyAndYearly() {
        #expect(next(series(start: "2026-09-01", frequency: .weekly), today: "2026-09-10") == "2026-09-15")
        #expect(next(series(start: "2024-02-29", frequency: .yearly), today: "2026-01-10") == "2026-02-28")
    }

    @Test func pausedSubscriptionHasNoNextCharge() {
        #expect(next(series(start: "2026-01-15", status: .paused), today: "2026-09-10") == nil)
    }
}
