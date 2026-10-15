//
//  AssistantCharacterTests.swift
//  TenraTests
//
//  Ten as a character: the days-in-a-row streak, what opens its accessories and what it
//  daydreams of.
//

import Testing
import Foundation
@testable import Tenra

@Suite("Ten as a character")
struct AssistantCharacterTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: Streak

    @Test("The next day adds one, the same day keeps the run, a gap starts again")
    func streak() {
        let today = day(2026, 10, 15)
        #expect(AppStreak.next(lastDay: "2026-10-14", count: 4, today: today, calendar: calendar) == 5)
        #expect(AppStreak.next(lastDay: "2026-10-15", count: 4, today: today, calendar: calendar) == 4)
        #expect(AppStreak.next(lastDay: "2026-10-12", count: 4, today: today, calendar: calendar) == 1)
        #expect(AppStreak.next(lastDay: "", count: 0, today: today, calendar: calendar) == 1)
    }

    // MARK: Wardrobe

    @Test("Three accessories are open from the start")
    func openFromStart() {
        let open = AssistantWardrobe.unlocked(remembered: [], bestStreak: 1, hasGoal: false, hasReachedGoal: false,
                                              at: day(2026, 10, 15), calendar: calendar)
        #expect(open == ["glasses", "headphones", "beanie"])
    }

    @Test("Streaks, goals and Nauryz open the rest")
    func unlocks() {
        let week = AssistantWardrobe.unlocked(remembered: [], bestStreak: 7, hasGoal: true, hasReachedGoal: false,
                                              at: day(2026, 10, 15), calendar: calendar)
        #expect(week.contains("sunglasses"))
        #expect(week.contains("partyHat"))
        #expect(!week.contains("sleepMask"))
        #expect(!week.contains("crown"))
        let month = AssistantWardrobe.unlocked(remembered: [], bestStreak: 30, hasGoal: true, hasReachedGoal: true,
                                               at: day(2026, 3, 22), calendar: calendar)
        #expect(month == Set(CreatureAccessory.allCases.map(\.rawValue)))
    }

    @Test("What was opened stays open")
    func remembered() {
        let open = AssistantWardrobe.unlocked(remembered: ["crown"], bestStreak: 1, hasGoal: false, hasReachedGoal: false,
                                              at: day(2026, 10, 15), calendar: calendar)
        #expect(open.contains("crown"))
        #expect(AssistantWardrobe.decode(AssistantWardrobe.encode(open)) == open)
    }

    @Test("Holidays dress Ten, then the crown day, then the choice")
    func dressing() {
        #expect(AssistantWardrobe.accessory(choice: "glasses", crownDay: "", at: day(2027, 1, 1), calendar: calendar) == .partyHat)
        #expect(AssistantWardrobe.accessory(choice: "glasses", crownDay: "", at: day(2026, 3, 21), calendar: calendar) == .taqiya)
        #expect(AssistantWardrobe.accessory(choice: "glasses", crownDay: "2026-10-15", at: day(2026, 10, 15), calendar: calendar) == .crown)
        #expect(AssistantWardrobe.accessory(choice: "glasses", crownDay: "", at: day(2026, 10, 15), calendar: calendar) == .glasses)
        #expect(AssistantWardrobe.accessory(choice: "", crownDay: "", at: day(2026, 10, 15), calendar: calendar) == nil)
    }

    // MARK: Daydreams

    @Test("The person's own things come first, the neutral ones after")
    func daydreams() {
        let now = day(2026, 10, 15)
        let symbols = AssistantDaydreams.symbols(
            payments: [
                .init(icon: .sfSymbol("music.note"), date: now.addingTimeInterval(2 * 24 * 3600)),
                .init(icon: .sfSymbol("tv.fill"), date: now.addingTimeInterval(20 * 24 * 3600)),
            ],
            goals: [
                .init(icon: .sfSymbol("car.fill"), progress: 0.8, reachedAt: nil),
                .init(icon: nil, progress: 0.2, reachedAt: nil),
            ],
            spendingRising: true,
            debtDueDates: [now.addingTimeInterval(3 * 24 * 3600)],
            now: now,
            exists: { _ in true }
        )
        #expect(symbols == ["music.note", "car.fill", "chart.line.uptrend.xyaxis", "handshake.fill",
                            "cup.and.saucer.fill", "star.fill", "airplane"])
    }

    @Test("A brand logo is a card, a goal reached this week a trophy, a missing symbol its fallback")
    func daydreamFallbacks() {
        let now = day(2026, 10, 15)
        let symbols = AssistantDaydreams.symbols(
            payments: [.init(icon: .brandService("netflix"), date: now.addingTimeInterval(3600))],
            goals: [.init(icon: .sfSymbol("car.fill"), progress: 1, reachedAt: now.addingTimeInterval(-2 * 24 * 3600))],
            spendingRising: false,
            debtDueDates: [now.addingTimeInterval(-24 * 3600)],
            now: now,
            exists: { $0 != "handshake.fill" }
        )
        #expect(symbols == ["creditcard.fill", "trophy.fill", "banknote.fill", "cup.and.saucer.fill", "star.fill", "airplane"])
    }

    @Test("Nothing on its mind: the neutral pictures only")
    func daydreamsNeutral() {
        let symbols = AssistantDaydreams.symbols(payments: [], goals: [], spendingRising: false, debtDueDates: [],
                                                 now: day(2026, 10, 15), exists: { _ in true })
        #expect(symbols == AssistantDaydreams.neutral)
    }
}
