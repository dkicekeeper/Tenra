//
//  SpendingReminderPlan.swift
//  Tenra
//
//  Which evening reminders Ten sends and with which words (docs/plan-spending-reminder.md §3):
//  counted from the person's last reaction (Tenra opened), on days 0, 1, 2, 3, then 5 and 7, a
//  goodbye on day 10 and nothing after; none on a day something was recorded or once the time
//  has passed. The first reminder after a day with entries names that day's category, never an
//  amount (it shows on the lock screen). Pure: SpendingReminder schedules what this returns.
//

import Foundation

nonisolated enum SpendingReminderPlan {

    /// Days after the last reaction an ordinary reminder may come on.
    static let regularDayOffsets = [0, 1, 2, 3, 5, 7]
    /// The day of the goodbye; nothing after it until the person comes back.
    static let farewellDayOffset = 10
    /// Ordinary phrases per language: `spendingReminder.phrase.1` … `.8`.
    static let regularPhraseCount = 8
    /// Goodbyes per language: `spendingReminder.farewell.1`, `.2`.
    static let farewellPhraseCount = 2

    /// The category of an expense recorded on `day`, for the next day's reminder.
    struct Hook: Equatable, Sendable {
        let category: String
        let day: Date
    }

    /// What a reminder says; the numbers count from 1, as the string keys do.
    enum Phrase: Equatable, Sendable {
        case regular(Int)
        case hook(String)
        case farewell(Int)
    }

    struct Reminder: Equatable, Sendable {
        let date: Date
        let phrase: Phrase
    }

    /// The reminders after the last reaction that are still ahead of `now`, at `hour`:`minute`,
    /// skipping the day of `lastRecorded`.
    static func reminders(
        lastReaction: Date,
        lastRecorded: Date?,
        hook: Hook?,
        now: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar = .current
    ) -> [Reminder] {
        let startDay = calendar.startOfDay(for: lastReaction)
        let offsets = regularDayOffsets.map { ($0, false) } + [(farewellDayOffset, true)]
        return offsets.compactMap { offset, isFarewell in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date > now else { return nil }
            if let lastRecorded, calendar.isDate(lastRecorded, inSameDayAs: day) { return nil }
            if isFarewell {
                return Reminder(date: date, phrase: .farewell(phraseIndex(for: day, count: farewellPhraseCount, calendar: calendar)))
            }
            if let hook, let dayBefore = calendar.date(byAdding: .day, value: -1, to: day),
               calendar.isDate(hook.day, inSameDayAs: dayBefore) {
                return Reminder(date: date, phrase: .hook(hook.category))
            }
            return Reminder(date: date, phrase: .regular(phraseIndex(for: day, count: regularPhraseCount, calendar: calendar)))
        }
    }

    /// The phrase of `day`, 1…`count`: neighbouring days differ, and one repeats only after
    /// `count` days. Fixed by the date, so rescheduling never changes a day's words.
    static func phraseIndex(for day: Date, count: Int, calendar: Calendar = .current) -> Int {
        guard count > 0 else { return 1 }
        let origin = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let dayNumber = calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: day)).day ?? 0
        return ((dayNumber % count) + count) % count + 1
    }

    /// The person recorded it today: created today, whatever its date, and not an occurrence
    /// Tenra made for a recurring series.
    static func isUserRecord(_ transaction: Transaction, now: Date, calendar: Calendar = .current) -> Bool {
        transaction.recurringSeriesId == nil
            && calendar.isDate(Date(timeIntervalSince1970: transaction.createdAt), inSameDayAs: now)
    }

    /// Today's hook from what was just recorded: the category of the latest expense, if any.
    static func hook(from transactions: [Transaction], now: Date, calendar: Calendar = .current) -> Hook? {
        transactions
            .filter { $0.type == .expense && isUserRecord($0, now: now, calendar: calendar) }
            .max { $0.createdAt < $1.createdAt }
            .map { Hook(category: $0.category, day: calendar.startOfDay(for: now)) }
    }
}
