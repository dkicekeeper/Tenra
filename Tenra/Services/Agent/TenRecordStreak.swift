//
//  TenRecordStreak.swift
//  Tenra
//
//  Ten's record streak (plan-ten-gamification.md §7.1, the owner's R3): days in a row the person
//  added a record of their own (by hand, by voice, from Ten's draft, by Wallet or a bank
//  notification). A statement or a CSV, a series' own payments and deposit interest do not count
//  (TenWardrobeStore.noteRecords). One missed day a week does not break the run: it is a day off,
//  and the count stays honest, the days that have a record. It replaced the streak of app opens.
//

import Foundation

nonisolated struct TenRecordStreak: Codable, Equatable, Sendable {
    /// The last day with a record, `yyyy-MM-dd` (AssistantChatter.dayKey); "" before the first.
    var lastDay = ""
    /// Days with a record in the current run.
    var count = 0
    /// The longest run so far: what opens Ten's accessories.
    var best = 0
    /// The last day off the run took, `yyyy-MM-dd`; "" for none.
    var dayOff = ""

    /// Days between two days off at least: one a week.
    static let dayOffGap = 7

    /// A record on `date`'s day: the day after the last one adds one; with one day missed, a day
    /// off if the week has none yet; otherwise a new run.
    mutating func record(at date: Date, calendar: Calendar = .current) {
        let today = AssistantChatter.dayKey(date, calendar: calendar)
        guard today != lastDay else {
            count = max(count, 1)
            best = max(best, count)
            return
        }
        switch Self.days(from: lastDay, to: date, calendar: calendar) {
        case 1?:
            count += 1
        case 2? where canTakeDayOff(before: date, calendar: calendar):
            count += 1
            dayOff = Self.key(daysBefore: 1, date, calendar: calendar)
        default:
            count = 1
            dayOff = ""
        }
        best = max(best, count)
        lastDay = today
    }

    /// The run as it stands on `date`: alive while today's record can still continue it, 0 once
    /// it is broken (two days without a record, or a second day off within a week).
    func current(at date: Date, calendar: Calendar = .current) -> Int {
        switch Self.days(from: lastDay, to: date, calendar: calendar) {
        case 0?, 1?: count
        case 2? where canTakeDayOff(before: date, calendar: calendar): count
        default: 0
        }
    }

    /// Whether the day before `date` may be a day off: none taken in the week before it.
    private func canTakeDayOff(before date: Date, calendar: Calendar) -> Bool {
        guard !dayOff.isEmpty, let missed = calendar.date(byAdding: .day, value: -1, to: date) else { return true }
        guard let gap = Self.days(from: dayOff, to: missed, calendar: calendar) else { return true }
        return gap >= Self.dayOffGap
    }

    /// Whole days from a `yyyy-MM-dd` day to `date`'s day; nil for an empty or broken key.
    static func days(from key: String, to date: Date, calendar: Calendar = .current) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return nil
        }
        return calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day
    }

    private static func key(daysBefore days: Int, _ date: Date, calendar: Calendar) -> String {
        AssistantChatter.dayKey(calendar.date(byAdding: .day, value: -days, to: date) ?? date, calendar: calendar)
    }
}
