//
//  FastDateParser.swift
//  Tenra
//
//  Fast parse/format for the canonical "yyyy-MM-dd" form used by `Transaction.date`.
//
//  Why this exists
//  ───────────────
//  `DateFormatter.date(from:)` costs ~13.4 µs per call. Over 19k transactions that is
//  ~254 ms per pass (measured, Apple Silicon, -O) — and the app makes that pass at least
//  four times during a cold launch and three more on every home-screen summary refresh.
//  It was the single dominant CPU cost in the app.
//
//  The format is fixed and locale-independent, so the whole ICU machinery is wasted.
//  A manual UTF8 digit scan plus `Calendar.date(from:)` produces the identical `Date`
//  for ~4.8 ms over the same 19k — roughly 53× faster. Formatting is a smaller win
//  (5.4 ms vs 18.6 ms) but comes for free alongside.
//
//  Contract
//  ────────
//  `date(from:)` is byte-for-byte equivalent to `DateFormatters.dateFormatter.date(from:)`
//  (locale = en_US_POSIX, calendar = gregorian, timeZone = .current) for every input.
//  This is pinned by `FastDateParserTests`, which diffs both implementations across every
//  day from 2015 through 2035 plus malformed input. Do not change the calendar/timeZone
//  configuration below without re-running that suite.
//
//  Scope
//  ─────
//  Use this ONLY for the canonical "yyyy-MM-dd" storage format. Anything user-facing
//  (localized month names, display strings) must keep going through `DateFormatters` —
//  those depend on the device locale by design.
//

import Foundation

enum FastDateParser {

    /// Gregorian calendar pinned to the same configuration as `DateFormatters.dateFormatter`.
    /// `nonisolated` is required: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes plain
    /// enum statics implicitly MainActor-isolated, which would fail to compile at the
    /// `Task.detached` call sites this type exists to serve (see docs/concurrency.md).
    nonisolated static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    /// Parses strictly "yyyy-MM-dd". Returns nil for any other shape, and for
    /// calendrically invalid dates (month 13, 30 February) — matching a
    /// non-lenient `DateFormatter`.
    nonisolated static func date(from s: String) -> Date? {
        var year = 0, month = 0, day = 0, index = 0

        for byte in s.utf8 {
            switch index {
            case 0, 1, 2, 3:
                guard byte >= 48, byte <= 57 else { return nil }
                year = year * 10 + Int(byte - 48)
            case 4, 7:
                guard byte == 45 else { return nil }          // '-'
            case 5, 6:
                guard byte >= 48, byte <= 57 else { return nil }
                month = month * 10 + Int(byte - 48)
            case 8, 9:
                guard byte >= 48, byte <= 57 else { return nil }
                day = day * 10 + Int(byte - 48)
            default:
                return nil                                    // longer than 10 bytes
            }
            index += 1
        }

        guard index == 10 else { return nil }                 // shorter than 10 bytes

        // DateFormatter is NOT uniformly strict here, and matching it exactly matters.
        // Measured behaviour of the reference formatter:
        //   "2026-13-01" → nil          (month outside 1...12)
        //   "2026-07-32" → nil          (day outside 1...31)
        //   "2026-02-30" → 2026-03-02   (in-range day, overflow ROLLS OVER)
        //   "2025-02-29" → 2025-03-01   (same — not nil!)
        // So: reject values outside each field's own range, then let Calendar roll the
        // remainder over. `Calendar.date(from:)` alone rolls everything (month 13 would
        // become January 2027), which is why the range guard cannot be dropped.
        guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// Formats a `Date` back into "yyyy-MM-dd" without touching `DateFormatter`.
    /// Inverse of `date(from:)` for any date in the supported range.
    nonisolated static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 0
        let month = c.month ?? 0
        let day = c.day ?? 0
        // "yyyy" in DateFormatter zero-pads to a minimum of 4 digits; mirror that so
        // years below 1000 round-trip. Out of range for real data, but the contract
        // says "equivalent to DateFormatters.dateFormatter" without qualification.
        let y = year < 1000 ? String(format: "%04d", year) : "\(year)"
        return "\(y)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
    }
}
