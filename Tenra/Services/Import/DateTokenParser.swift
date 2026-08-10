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
    /// Assumes day-first ordering. Callers that know the column's ordering
    /// should use `parse(_:order:)` instead.
    static func parse(_ token: String) -> String? {
        parse(token, order: .dayFirst)
    }

    /// Parses using a known column ordering, falling back to the opposite
    /// ordering when the given one yields no valid calendar date. The fallback
    /// is safe here in a way it is not for a lone token: the order came from
    /// evidence across the whole column, so the fallback only fires on the
    /// outliers that contradict it.
    static func parse(_ token: String, order: DateOrder) -> String? {
        if let match = token.firstMatch(of: isoPattern) {
            return canonical(year: Int(match.1) ?? 0,
                             month: Int(match.2) ?? 0,
                             day: Int(match.3) ?? 0)
        }

        guard let match = token.firstMatch(of: dayFirstPattern) else { return nil }
        let first = Int(match.1) ?? 0
        let second = Int(match.2) ?? 0
        let year = normalizeYear(Int(match.3) ?? 0)

        switch order {
        case .dayFirst:
            return canonical(year: year, month: second, day: first)
                ?? canonical(year: year, month: first, day: second)
        case .monthFirst:
            return canonical(year: year, month: first, day: second)
                ?? canonical(year: year, month: second, day: first)
        }
    }

    /// True when `token` is a valid date under EITHER ordering.
    ///
    /// Order-agnostic on purpose: ColumnRoleResolver uses this to score which
    /// column holds dates, and that scoring happens before any ordering is
    /// known. A day-first-only check would score a US date column below the
    /// detection threshold and the column would never be found.
    static func looksLikeDate(_ token: String) -> Bool {
        parse(token, order: .dayFirst) != nil || parse(token, order: .monthFirst) != nil
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
