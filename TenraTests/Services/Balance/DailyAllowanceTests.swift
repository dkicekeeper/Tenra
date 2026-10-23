//
//  DailyAllowanceTests.swift
//  TenraTests
//
//  Pins the horizon of Home's "For today": the next income of an active income series within
//  45 days, else the first day of next month. The amount itself is forecast_balance's,
//  pinned by AgentForecastTests.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct DailyAllowanceTests {

    private let calendar = FastDateParser.calendar
    private var today: Date { FastDateParser.date(from: "2026-10-22")! }

    private func series(_ category: String, start: String, frequency: RecurringFrequency = .monthly, isActive: Bool = true) -> RecurringSeries {
        RecurringSeries(isActive: isActive, amount: 450_000, currency: "KZT", category: category, description: category, frequency: frequency, startDate: start)
    }

    @Test("The next salary is the horizon")
    func nextIncome() throws {
        let horizon = try #require(DailyAllowance.horizon(
            series: [series("Salary", start: "2026-01-25"), series("Rent", start: "2026-01-01")],
            incomeCategories: ["Salary"],
            today: today,
            calendar: calendar
        ))
        #expect(FastDateParser.string(from: horizon.date) == "2026-10-25")
        #expect(horizon.isIncome)
    }

    @Test("Without an income series, a paused one, or one too far, the month's end")
    func monthEnd() throws {
        for incomes in [
            [RecurringSeries](),
            [series("Salary", start: "2026-01-25", isActive: false)],
            [series("Bonus", start: "2026-03-01", frequency: .yearly)],
        ] {
            let horizon = try #require(DailyAllowance.horizon(series: incomes, incomeCategories: ["Salary", "Bonus"], today: today, calendar: calendar))
            #expect(FastDateParser.string(from: horizon.date) == "2026-11-01")
            #expect(!horizon.isIncome)
        }
    }

    @Test("An income due today counts from its next occurrence")
    func incomeToday() throws {
        let horizon = try #require(DailyAllowance.horizon(
            series: [series("Salary", start: "2026-09-22")],
            incomeCategories: ["Salary"],
            today: today,
            calendar: calendar
        ))
        #expect(FastDateParser.string(from: horizon.date) == "2026-11-22")
    }
}
