//
//  TenMomentsTests.swift
//  TenraTests
//
//  Pins Ten's moments (TenMoments, docs/plan-ten-gamification.md §6): each event's key once, the
//  person's own action always, at most two noticed moments a day, nothing when Ten is not on the
//  device or the switch is off; last month inside the budgets by the budgets' own spending rule;
//  the first capture only while it is recent. Amounts in one currency with no base currency, so
//  no global rate state is touched. All data invented.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TenMomentsTests {

    private let calendar = FastDateParser.calendar

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeMoments(available: Bool = true, presented: @escaping (TenMoment) -> Void = { _ in }) -> (TenMoments, UserDefaults) {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let moments = TenMoments(defaults: defaults, available: { available }) { moment, _ in
            presented(moment)
            return true
        }
        return (moments, defaults)
    }

    private func expense(_ date: String, _ amount: Double, category: String = "Food") -> Transaction {
        Transaction(
            id: UUID().uuidString, date: date, description: "", amount: amount,
            currency: "KZT", type: .expense, category: category, accountId: "a1"
        )
    }

    private func budget(_ name: String, _ amount: Double, resetDay: Int = 1, startedOn: Date? = nil) -> CustomCategory {
        var category = CustomCategory(name: name, colorHex: "#22c55e", type: .expense, budgetAmount: amount, budgetPeriod: .monthly, budgetResetDay: resetDay)
        category.budgetStartDate = startedOn
        return category
    }

    @Test("An event's key shows once; the person's own action always shows")
    func keysOnce() {
        let (moments, _) = makeMoments()
        #expect(moments.celebrate(.goalReached(name: "Bike"), key: "goal:g1"))
        #expect(!moments.celebrate(.goalReached(name: "Bike"), key: "goal:g1"))
        #expect(moments.celebrate(.debtSettled(name: "Aidana"), key: "debt:d1"))
        #expect(moments.celebrate(.loanPaidOff(name: "Car"), key: "loan:l1"))
        #expect(moments.celebrate(.assetSold(name: "Flat"), key: "asset:a1"))
        #expect(moments.unsolicitedToday() == 0)
    }

    @Test("At most two noticed moments a day")
    func dailyLimit() {
        let (moments, _) = makeMoments()
        let now = date(2027, 1, 2)
        #expect(moments.celebrate(.firstCapture, key: "firstCapture", now: now))
        #expect(moments.celebrate(.budgetMonth, key: "budgetMonth:2026-12", now: now))
        #expect(!moments.celebrate(.budgetMonth, key: "budgetMonth:other", now: now))
        // The person's own action is not counted against it.
        #expect(moments.celebrate(.goalReached(name: "Bike"), key: "goal:g2", now: now))
        #expect(moments.unsolicitedToday(now: now) == 2)
    }

    @Test("Nothing without Ten on the device or with the switch off: the screens keep their confetti")
    func offMeansConfetti() {
        let (noTen, _) = makeMoments(available: false)
        #expect(!noTen.celebrate(.goalReached(name: "Bike"), key: "goal:g1"))
        let (switchedOff, defaults) = makeMoments()
        defaults.set(false, forKey: TenMoments.enabledKey)
        #expect(!switchedOff.celebrate(.goalReached(name: "Bike"), key: "goal:g1"))
    }

    @Test("Each event has its words, its face and the confetti only for a celebration")
    func catalog() {
        let goal = TenMoment.make(.goalReached(name: "Bike"), key: "k")
        #expect(goal.message.contains("Bike"))
        #expect(goal.celebrates)
        #expect(goal.mood == .celebrating)
        let asset = TenMoment.make(.assetSold(name: "Flat"), key: "k")
        #expect(!asset.celebrates)
        #expect(asset.mood == .proud)
        for event in [TenMomentEvent.goalReached(name: "x"), .debtSettled(name: "x"), .loanPaidOff(name: "x"), .assetSold(name: "x"), .budgetMonth, .firstCapture] {
            let moment = TenMoment.make(event, key: "k")
            #expect(!moment.title.isEmpty && !moment.line.isEmpty)
        }
    }

    @Test("Last month's budgets are celebrated in the first week of the next one")
    func budgetMonthWindow() {
        #expect(TenMomentRules.budgetMonthKey(now: date(2027, 1, 1), calendar: calendar) == "budgetMonth:2026-12")
        #expect(TenMomentRules.budgetMonthKey(now: date(2027, 1, 7), calendar: calendar) == "budgetMonth:2026-12")
        #expect(TenMomentRules.budgetMonthKey(now: date(2027, 1, 8), calendar: calendar) == nil)
    }

    @Test("Every monthly budget kept, in a month of use: yes; one over, too few records, or none ran the month: no")
    func budgetMonthKept() {
        let now = date(2026, 12, 2)
        var month = (1...12).map { expense(String(format: "2026-11-%02d", $0), 1_000) }
        month.append(expense("2026-11-20", 5_000, category: "Taxi"))
        let budgets = [budget("Food", 20_000), budget("Taxi", 6_000)]
        #expect(TenMomentRules.budgetMonthKept(categories: budgets, transactions: month, baseCurrency: nil, now: now, calendar: calendar))
        // Taxi over its limit.
        let over = month + [expense("2026-11-25", 2_000, category: "Taxi")]
        #expect(!TenMomentRules.budgetMonthKept(categories: budgets, transactions: over, baseCurrency: nil, now: now, calendar: calendar))
        // Spending this month does not count against last month.
        let thisMonth = month + [expense("2026-12-01", 50_000, category: "Taxi")]
        #expect(TenMomentRules.budgetMonthKept(categories: budgets, transactions: thisMonth, baseCurrency: nil, now: now, calendar: calendar))
        // Too few records last month.
        #expect(!TenMomentRules.budgetMonthKept(categories: budgets, transactions: Array(month.prefix(5)), baseCurrency: nil, now: now, calendar: calendar))
        // A budget set mid-month or reset on another day did not run the month: none left.
        let late = [budget("Food", 20_000, startedOn: date(2026, 11, 15)), budget("Taxi", 6_000, resetDay: 10)]
        #expect(!TenMomentRules.budgetMonthKept(categories: late, transactions: month, baseCurrency: nil, now: now, calendar: calendar))
    }

    @Test("The first capture is celebrated only while it is recent")
    func firstCapture() {
        let now = date(2026, 12, 2)
        #expect(TenMomentRules.firstCaptureIsNew(date(2026, 11, 30), now: now))
        #expect(!TenMomentRules.firstCaptureIsNew(date(2026, 11, 1), now: now))
        #expect(!TenMomentRules.firstCaptureIsNew(nil, now: now))
    }
}
