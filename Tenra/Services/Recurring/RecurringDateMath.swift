//
//  RecurringDateMath.swift
//  Tenra
//
//  The one place that computes recurring occurrence dates. Occurrence k is
//  `start + k × period`, anchored to the series start, so a series on the
//  29th-31st keeps its day: Jan 31 → Feb 28 → Mar 31 → Apr 30. Stepping from the
//  previous occurrence instead (the old generator) clamped once in February and
//  stayed on the 28th forever, while reminders computed from the start date and
//  fired on a different day.
//
//  Used by RecurringTransactionGenerator and SubscriptionNotificationScheduler.
//  Adding a RecurringFrequency case means updating the switches here too.
//

import Foundation

nonisolated enum RecurringDateMath {

    /// Occurrence `index` (0 = start), anchored to the start date. Month-based
    /// frequencies clamp per occurrence, never cumulatively.
    static func occurrence(_ index: Int, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily:     return calendar.date(byAdding: .day, value: index, to: start)
        case .weekly:    return calendar.date(byAdding: .day, value: 7 * index, to: start)
        case .monthly:   return calendar.date(byAdding: .month, value: index, to: start)
        case .quarterly: return calendar.date(byAdding: .month, value: 3 * index, to: start)
        case .yearly:    return calendar.date(byAdding: .month, value: 12 * index, to: start)
        }
    }

    /// Index of the period that contains `date` (never negative). Month-based
    /// frequencies compare (year, month) only and ignore the day, so an occurrence
    /// that drifted to the 28th under the old stepping still maps to its own period.
    static func periodIndex(of date: Date, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Int {
        let index: Int
        switch frequency {
        case .daily:
            index = days(from: start, to: date, calendar: calendar)
        case .weekly:
            index = floorDiv(days(from: start, to: date, calendar: calendar), 7)
        case .monthly:
            index = months(from: start, to: date, calendar: calendar)
        case .quarterly:
            index = floorDiv(months(from: start, to: date, calendar: calendar), 3)
        case .yearly:
            index = floorDiv(months(from: start, to: date, calendar: calendar), 12)
        }
        return max(0, index)
    }

    /// The occurrence in the period AFTER the one containing `existing`. Resuming
    /// generation from here can never create a second occurrence in a period that
    /// already has one (even if the stored one drifted).
    static func occurrence(afterPeriodOf existing: Date, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Date? {
        occurrence(periodIndex(of: existing, start: start, frequency: frequency, calendar: calendar) + 1,
                   start: start, frequency: frequency, calendar: calendar)
    }

    /// First anchored occurrence strictly after `date` (day granularity).
    static func firstOccurrence(after date: Date, start: Date, frequency: RecurringFrequency, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        var index = periodIndex(of: day, start: start, frequency: frequency, calendar: calendar)
        // The occurrence of the current period may still be ahead (e.g. the 31st when
        // `date` is the 10th); otherwise move on. Two steps always suffice.
        for _ in 0..<3 {
            guard let candidate = occurrence(index, start: start, frequency: frequency, calendar: calendar) else { return nil }
            if calendar.startOfDay(for: candidate) > day { return candidate }
            index += 1
        }
        return occurrence(index, start: start, frequency: frequency, calendar: calendar)
    }

    // MARK: - Private

    private static func days(from start: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
    }

    private static func months(from start: Date, to date: Date, calendar: Calendar) -> Int {
        let s = calendar.dateComponents([.year, .month], from: start)
        let d = calendar.dateComponents([.year, .month], from: date)
        return ((d.year ?? 0) - (s.year ?? 0)) * 12 + ((d.month ?? 0) - (s.month ?? 0))
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        a >= 0 ? a / b : -((-a + b - 1) / b)
    }
}
