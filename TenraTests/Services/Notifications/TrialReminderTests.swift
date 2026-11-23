//
//  TrialReminderTests.swift
//  TenraTests
//
//  Pins the reminder before a Tenra Pro trial ends: two calendar days before the trial's last
//  day at 10:00, none once that moment has passed, and the words for renewal on (with the plan's
//  price) and off.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TrialReminderTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func reminder(expiration: Date, now: Date) -> Date? {
        TrialReminder.reminderDate(expiration: expiration, now: now, calendar: calendar)
    }

    @Test("Two calendar days before the trial's last day, at ten in the morning")
    func twoDaysBeforeAtTen() {
        #expect(reminder(expiration: date(25, 1, 11), now: date(11, 1, 11)) == date(23, 10))
        #expect(reminder(expiration: date(30, 16, 58), now: date(16, 16, 58)) == date(28, 10))
    }

    @Test("None once the reminder's moment has passed")
    func noneWhenPast() {
        #expect(reminder(expiration: date(25, 1, 11), now: date(23, 10, 1)) == nil)
        #expect(reminder(expiration: date(25, 1, 11), now: date(24)) == nil)
        // Just before ten on the day it is still ahead.
        #expect(reminder(expiration: date(25, 1, 11), now: date(23, 9, 59)) == date(23, 10))
    }

    @Test("Renewal on names the plan's price; without a price the subscription still is named")
    func renewsText() {
        #expect(TrialReminder.body(.renews(.annual, price: "7 990 ₸"))
            == String(format: String(localized: "trialReminder.body.annual"), "7 990 ₸"))
        #expect(TrialReminder.body(.renews(.monthly, price: "1 490 ₸"))
            == String(format: String(localized: "trialReminder.body.monthly"), "1 490 ₸"))
        #expect(TrialReminder.body(.renews(.annual, price: nil)) == String(localized: "trialReminder.body.noPrice"))
        #expect(TrialReminder.body(.renews(.unknown, price: "7 990 ₸")) == String(localized: "trialReminder.body.noPrice"))
        #expect(TrialReminder.body(.renews(.annual, price: "7 990 ₸")).contains("7 990 ₸"))
    }

    @Test("Renewal off says no charge comes")
    func cancelledText() {
        #expect(TrialReminder.body(.cancelled) == String(localized: "trialReminder.body.cancelled"))
    }

    @Test("A trial's status carries the flag; a paid one does not")
    func statusFlag() {
        let trial = ProStatus(plan: .annual, expirationDate: date(25), willRenew: true, managementURL: nil, isTrial: true)
        let paid = ProStatus(plan: .annual, expirationDate: date(25), willRenew: true, managementURL: nil)
        #expect(trial.isTrial)
        #expect(!paid.isTrial)
        #expect(trial != paid)
    }
}
