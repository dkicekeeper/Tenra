//
//  AppStreak.swift
//  Tenra
//
//  Days in a row the person opened Tenra (the owner's choice for unlocking Ten's accessories,
//  AssistantWardrobe): counted when the app comes to the foreground, from the first launch of the
//  version that added it. Importing a statement does not add to it.
//

import Foundation

enum AppStreak {
    /// The last day counted, `yyyy-MM-dd`; the run's length; the longest run so far.
    static let lastDayKey = "streak.lastDay"
    static let countKey = "streak.count"
    static let bestKey = "streak.best"

    /// Counts `date`'s day: the day after the last one adds one, a gap starts a new run.
    static func record(_ date: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        let today = AssistantChatter.dayKey(date, calendar: calendar)
        let count = next(lastDay: defaults.string(forKey: lastDayKey) ?? "",
                         count: defaults.integer(forKey: countKey),
                         today: date, calendar: calendar)
        defaults.set(today, forKey: lastDayKey)
        defaults.set(count, forKey: countKey)
        defaults.set(max(count, defaults.integer(forKey: bestKey)), forKey: bestKey)
    }

    /// The run's length on `today`, given the last day counted and the run then.
    static func next(lastDay: String, count: Int, today: Date, calendar: Calendar = .current) -> Int {
        let todayKey = AssistantChatter.dayKey(today, calendar: calendar)
        if lastDay == todayKey { return max(count, 1) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           lastDay == AssistantChatter.dayKey(yesterday, calendar: calendar) {
            return count + 1
        }
        return 1
    }
}
