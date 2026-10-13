//
//  AssistantAllowanceTests.swift
//  TenraTests
//
//  The assistant's free allowance: 30 answers in the 7 days after the first question, then 10
//  a calendar month; the trial does not count against the first month.
//

import Foundation
import Testing
@testable import Tenra

struct AssistantAllowanceTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }()

    private func day(_ value: String, hour: Int = 12) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    private func spend(_ count: Int, from usage: AssistantUsage, at date: Date) -> AssistantUsage {
        (0..<count).reduce(usage) { current, _ in AssistantAllowance.recording(current, now: date, calendar: calendar) }
    }

    @Test func beforeTheFirstQuestionTheTrialIsWhole() {
        let status = AssistantAllowance.status(AssistantUsage(), now: day("2026-10-13"), calendar: calendar)
        #expect(status == .init(remaining: 30, limit: 30, isTrial: true, renewsAt: nil))
    }

    @Test func theTrialLastsSevenDays() {
        let start = day("2026-10-13")
        let usage = spend(30, from: AssistantUsage(), at: start)
        let exhausted = AssistantAllowance.status(usage, now: day("2026-10-19"), calendar: calendar)
        #expect(exhausted.isTrial)
        #expect(exhausted.isExhausted)
        #expect(exhausted.renewsAt == day("2026-10-20"))

        // After the trial: ten for the rest of the month, whatever the trial used.
        let monthly = AssistantAllowance.status(usage, now: day("2026-10-21"), calendar: calendar)
        #expect(monthly == .init(remaining: 10, limit: 10, isTrial: false, renewsAt: calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))))
    }

    @Test func theMonthlyAllowanceRenews() {
        let trialOver = spend(1, from: AssistantUsage(), at: day("2026-09-01"))
        let october = spend(10, from: trialOver, at: day("2026-10-05"))
        #expect(AssistantAllowance.status(october, now: day("2026-10-30"), calendar: calendar).isExhausted)
        #expect(AssistantAllowance.status(october, now: day("2026-11-01", hour: 0), calendar: calendar).remaining == 10)

        let november = spend(3, from: october, at: day("2026-11-02"))
        #expect(november.month == "2026-11")
        #expect(AssistantAllowance.status(november, now: day("2026-11-03"), calendar: calendar).remaining == 7)
    }
}
