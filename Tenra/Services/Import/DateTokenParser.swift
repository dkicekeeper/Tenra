//
//  DateTokenParser.swift
//  Tenra
//
//  Parses a date out of an arbitrary statement cell. Deliberately regex +
//  arithmetic rather than DateFormatter: this runs once per cell over
//  thousands of cells, and DateFormatter.date(from:) costs ~13 µs per call
//  (see CLAUDE.md Red Flag #15 and Tenra/Utils/FastDateParser.swift).
//

import Foundation

nonisolated enum DateTokenParser {

    /// Matches d.m.y, d/m/y, d-m-y with 1-2 digit day and month, 2 or 4 digit year.
    private static let dayFirstPattern = /(\d{1,2})[.\/\-](\d{1,2})[.\/\-](\d{2,4})/

    /// Matches ISO yyyy-mm-dd.
    private static let isoPattern = /(\d{4})-(\d{1,2})-(\d{1,2})/

    /// Parses the first date found in `token`, returning canonical "yyyy-MM-dd".
    /// Returns nil when no valid calendar date is present.
    static func parse(_ token: String) -> String? {
        if let match = token.firstMatch(of: isoPattern) {
            let year = Int(match.1) ?? 0
            let month = Int(match.2) ?? 0
            let day = Int(match.3) ?? 0
            return canonical(year: year, month: month, day: day)
        }

        guard let match = token.firstMatch(of: dayFirstPattern) else { return nil }
        let first = Int(match.1) ?? 0
        let second = Int(match.2) ?? 0
        let year = normalizeYear(Int(match.3) ?? 0)

        // Day-first is the sole convention for the ambiguous separator group
        // (EU, CIS, LATAM statements). We deliberately do NOT fall back to a
        // month-first reading when day-first is invalid (e.g. "08.13.2026"):
        // guessing which side is the month for a token we already failed to
        // parse one way risks silently accepting a wrong date, which is worse
        // than dropping the row. ISO yyyy-mm-dd is handled separately above.
        return canonical(year: year, month: second, day: first)
    }

    /// True when `token` contains a parseable date.
    static func looksLikeDate(_ token: String) -> Bool {
        parse(token) != nil
    }

    private static func normalizeYear(_ raw: Int) -> Int {
        raw < 100 ? 2000 + raw : raw
    }

    private static func canonical(year: Int, month: Int, day: Int) -> String? {
        guard year >= 1900, year <= 2200 else { return nil }
        guard month >= 1, month <= 12 else { return nil }
        guard day >= 1, day <= daysInMonth(month: month, year: year) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
