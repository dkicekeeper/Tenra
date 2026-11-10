//
//  SpendingReminderPlanTests.swift
//  TenraTests
//
//  Pins Ten's evening spending reminder (docs/plan-spending-reminder.md §3): the days after the
//  last reaction (0, 1, 2, 3, 5, 7 and the goodbye on 10), none on a day something was recorded
//  or once the time has passed, yesterday's category on the next day only, a phrase per day that
//  differs from its neighbours, and what counts as the person recording today.
//

import Testing
import Foundation
@testable import Tenra

struct SpendingReminderPlanTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 10, _ minute: Int = 0, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func reminders(
        reaction: Date,
        recorded: Date? = nil,
        hook: SpendingReminderPlan.Hook? = nil,
        now: Date,
        hour: Int = 20,
        minute: Int = 0
    ) -> [SpendingReminderPlan.Reminder] {
        SpendingReminderPlan.reminders(
            lastReaction: reaction, lastRecorded: recorded, hook: hook, now: now,
            hour: hour, minute: minute, calendar: calendar
        )
    }

    private func transaction(
        type: TransactionType = .expense,
        category: String = "Кафе",
        date: String = "2026-11-05",
        createdAt: Date,
        series: String? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: date, description: "", amount: 1500, currency: "KZT",
            type: type, category: category, recurringSeriesId: series,
            createdAt: createdAt.timeIntervalSince1970
        )
    }

    private func isFarewell(_ reminder: SpendingReminderPlan.Reminder) -> Bool {
        if case .farewell = reminder.phrase { return true }
        return false
    }

    private func isHook(_ reminder: SpendingReminderPlan.Reminder) -> Bool {
        if case .hook = reminder.phrase { return true }
        return false
    }

    @Test("A fresh reaction gives the whole series: days 0-3, 5, 7 and the goodbye on 10")
    func freshReactionGivesFullSeries() {
        let result = reminders(reaction: date(5), now: date(5))
        #expect(result.map(\.date) == [5, 6, 7, 8, 10, 12, 15].map { date($0, 20) })
        #expect(result.last.map(isFarewell) == true)
        #expect(result.dropLast().allSatisfy { !isFarewell($0) })
    }

    @Test("Something recorded today: no reminder tonight")
    func recordedTodaySkipsTonight() {
        let result = reminders(reaction: date(5), recorded: date(5, 12), now: date(5, 13))
        #expect(result.first?.date == date(6, 20))
        #expect(result.count == 6)
    }

    @Test("Past the reminder's time today: the series starts tomorrow")
    func pastTimeSkipsTonight() {
        #expect(reminders(reaction: date(5), now: date(5, 20, 30)).first?.date == date(6, 20))
    }

    @Test("An old reaction keeps only what is still ahead")
    func oldReactionKeepsOnlyTheTail() {
        let result = reminders(reaction: date(1), now: date(5))
        #expect(result.map(\.date) == [date(6, 20), date(8, 20), date(11, 20)])
        #expect(result.last.map(isFarewell) == true)
    }

    @Test("After the goodbye Ten is silent until the person comes back")
    func silentAfterFarewell() {
        #expect(reminders(reaction: date(1), now: date(12)).isEmpty)
    }

    @Test("Yesterday's category only on the day after it was recorded")
    func hookOnlyTheNextDay() {
        let hook = SpendingReminderPlan.Hook(category: "Кафе", day: "2026-11-05")
        let result = reminders(reaction: date(5), recorded: date(5, 12), hook: hook, now: date(5, 13))
        #expect(result.first?.date == date(6, 20))
        #expect(result.first?.phrase == .hook("Кафе"))
        #expect(result.dropFirst().allSatisfy { !isHook($0) })
    }

    @Test("The hook's day is the calendar day it was recorded on, whatever the time zone later")
    func hookDayIsACalendarDay() {
        let recorded = SpendingReminderPlan.hook(
            from: [transaction(createdAt: date(5, 23, 30))], now: date(5, 23, 30), calendar: calendar
        )
        #expect(recorded?.day == "2026-11-05")
        // The phone moves three hours west (Almaty to Moscow): the 6th's reminder still names the
        // 5th's expense, and the 7th's does not.
        var west = Calendar(identifier: .gregorian)
        west.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let sixth = west.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 13))!
        let result = SpendingReminderPlan.reminders(
            lastReaction: sixth, lastRecorded: nil, hook: recorded, now: sixth,
            hour: 20, minute: 0, calendar: west
        )
        #expect(result.first?.phrase == .hook("Кафе"))
        #expect(result.dropFirst().allSatisfy { !isHook($0) })
    }

    @Test("The time chosen in Settings is kept")
    func customTimeRespected() {
        let result = reminders(reaction: date(5), now: date(5), hour: 21, minute: 30)
        #expect(!result.isEmpty)
        #expect(result.allSatisfy {
            calendar.component(.hour, from: $0.date) == 21 && calendar.component(.minute, from: $0.date) == 30
        })
    }

    @Test("Eight days in a row get eight different phrases")
    func phrasesDifferOnNeighbourDays() {
        let indices = (1...8).map { SpendingReminderPlan.phraseIndex(for: date($0), count: 8, calendar: calendar) }
        #expect(Set(indices).count == 8)
        #expect(indices.allSatisfy { (1...8).contains($0) })
    }

    @Test("Recorded today means created today by the person, whatever its date")
    func userRecordExcludesRecurringAndOldCreation() {
        let now = date(5, 18)
        #expect(SpendingReminderPlan.isUserRecord(transaction(createdAt: date(5, 9)), now: now, calendar: calendar))
        #expect(!SpendingReminderPlan.isUserRecord(transaction(createdAt: date(5, 9), series: "s1"), now: now, calendar: calendar))
        #expect(!SpendingReminderPlan.isUserRecord(transaction(createdAt: date(4, 9)), now: now, calendar: calendar))
        #expect(SpendingReminderPlan.isUserRecord(transaction(date: "2026-10-03", createdAt: date(5, 9)), now: now, calendar: calendar))
    }

    @Test("Deposit interest Tenra posts is not the person recording")
    func depositInterestIsNotARecord() {
        let now = date(5, 18)
        #expect(!SpendingReminderPlan.isUserRecord(
            transaction(type: .depositInterestAccrual, createdAt: date(5, 9)), now: now, calendar: calendar
        ))
        #expect(SpendingReminderPlan.isUserRecord(transaction(type: .income, createdAt: date(5, 9)), now: now, calendar: calendar))
    }

    @Test("The hook is the latest expense's category; incomes alone give none")
    func hookTakesLatestExpense() {
        let now = date(5, 18)
        let transactions = [
            transaction(category: "Продукты", createdAt: date(5, 9)),
            transaction(type: .income, category: "Зарплата", createdAt: date(5, 12)),
            transaction(category: "Кафе", createdAt: date(5, 11)),
        ]
        #expect(SpendingReminderPlan.hook(from: transactions, now: now, calendar: calendar)?.category == "Кафе")
        let incomes = [transaction(type: .income, category: "Зарплата", createdAt: date(5, 12))]
        #expect(SpendingReminderPlan.hook(from: incomes, now: now, calendar: calendar) == nil)
    }
}
