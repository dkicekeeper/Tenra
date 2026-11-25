//
//  JanuaryPlanTests.swift
//  TenraTests
//
//  Pins the plan for January (JanuaryPlan, docs/plan-release-1.9.md §4): the year a plan is for,
//  the days Ten's message posts and stays, the expenses it needs, the message's block for the
//  model, and the year review's button counting as the message. All data invented.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct JanuaryPlanTests {

    private let calendar = FastDateParser.calendar

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func expense(_ date: String, type: TransactionType = .expense) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: date, description: "", amount: 1_000,
            currency: "KZT", type: type, category: "Food", accountId: "a1"
        )
    }

    private func inbox() -> AssistantInbox {
        AssistantInbox(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
    }

    @Test("A plan is for this January in January, for the next one the rest of the year")
    func planYear() {
        #expect(JanuaryPlan.year(on: date(2026, 12, 20), calendar: calendar) == 2027)
        #expect(JanuaryPlan.year(on: date(2027, 1, 3), calendar: calendar) == 2027)
        #expect(JanuaryPlan.year(on: date(2027, 1, 31), calendar: calendar) == 2027)
        #expect(JanuaryPlan.year(on: date(2026, 11, 25), calendar: calendar) == 2027)
    }

    @Test("The message posts on 1 to 5 January and stays through January")
    func window() {
        #expect(JanuaryPlan.postingYear(on: date(2026, 12, 31), calendar: calendar) == nil)
        #expect(JanuaryPlan.postingYear(on: date(2027, 1, 1), calendar: calendar) == 2027)
        #expect(JanuaryPlan.postingYear(on: date(2027, 1, 5), calendar: calendar) == 2027)
        #expect(JanuaryPlan.postingYear(on: date(2027, 1, 6), calendar: calendar) == nil)
        #expect(JanuaryPlan.shownYear(on: date(2027, 1, 31), calendar: calendar) == 2027)
        #expect(JanuaryPlan.shownYear(on: date(2027, 2, 1), calendar: calendar) == nil)
        #expect(JanuaryPlan.shownYear(on: date(2026, 12, 31), calendar: calendar) == nil)
    }

    @Test("It needs 30 expenses in October to December; income, transfers and other months do not count")
    func threshold() {
        let enough = (1...30).map { expense(String(format: "2026-%02d-%02d", 10 + $0 % 3, 1 + $0 % 28)) }
        #expect(JanuaryPlan.isEligible(year: 2027, transactions: enough))
        #expect(!JanuaryPlan.isEligible(year: 2027, transactions: Array(enough.dropFirst())))
        var others = Array(enough.dropFirst())
        others.append(expense("2026-12-15", type: .income))
        others.append(expense("2026-11-15", type: .internalTransfer))
        others.append(expense("2026-09-30"))
        others.append(expense("2027-01-01"))
        #expect(!JanuaryPlan.isEligible(year: 2027, transactions: others))
        others.append(expense("2026-10-01"))
        #expect(JanuaryPlan.isEligible(year: 2027, transactions: others))
    }

    @Test("The message: once a year, its year in the model's block, kept only through its January")
    func notice() {
        let notice = AssistantNotices.januaryPlan(year: 2027, now: date(2027, 1, 1))
        #expect(notice.id == "januaryPlan:2027")
        #expect(notice.kind == .januaryPlan)
        #expect(notice.subjectId == "2027")
        #expect(!notice.question.isEmpty)
        #expect(notice.modelText.contains("\"kind\":\"januaryPlan\""))
        #expect(notice.modelText.contains("\"year\":\"2027\""))
        var subjects = AssistantNotices.Subjects(subscriptions: [], debts: [], goals: [])
        subjects.planYear = 2027
        #expect(subjects.contains(notice))
        subjects.planYear = nil
        #expect(!subjects.contains(notice))
    }

    @Test("Started from the year review, the key counts as posted and the message never shows")
    func startedFromTheReview() {
        let inbox = inbox()
        let notice = AssistantNotices.januaryPlan(year: 2027, now: date(2027, 1, 2))
        inbox.markPosted(notice.id, now: date(2026, 12, 20))
        #expect(inbox.hasPosted(notice.id))
        inbox.post([notice], now: date(2027, 1, 2))
        #expect(inbox.notices.isEmpty)
    }
}
