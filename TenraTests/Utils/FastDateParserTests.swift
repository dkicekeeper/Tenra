//
//  FastDateParserTests.swift
//  TenraTests
//
//  Pins FastDateParser to DateFormatter behaviour.
//
//  FastDateParser replaces DateFormatter.date(from:) on every hot path that walks the
//  full transaction set (~254 ms → ~4.8 ms per 19k pass). That replacement is only safe
//  if the two produce identical results, so this suite diffs them directly rather than
//  asserting against hand-written expectations — the reference formatter IS the spec.
//
//  If this suite ever fails, do NOT relax the assertions: the hot-path call sites assume
//  exact equivalence, and a divergence means transaction dates are being misread.
//
//  Created 2026-07-28
//

import Testing
import Foundation
@testable import Tenra

@Suite("FastDateParser ↔ DateFormatter equivalence")
struct FastDateParserTests {

    /// The spec. Identical configuration to `DateFormatters.dateFormatter`.
    private static let reference: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return f
    }()

    // MARK: - Round-trip across two decades

    @Test("parses every day from 2015 through 2035 identically to DateFormatter")
    func matchesDateFormatterAcrossTwoDecades() throws {
        let start = try #require(Self.reference.date(from: "2015-01-01"))
        let end = try #require(Self.reference.date(from: "2035-12-31"))

        var cursor = start
        var checked = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        while cursor <= end {
            let iso = Self.reference.string(from: cursor)

            #expect(
                FastDateParser.date(from: iso) == Self.reference.date(from: iso),
                "parse diverged on \(iso)"
            )
            #expect(
                FastDateParser.string(from: cursor) == iso,
                "format diverged on \(iso)"
            )

            checked += 1
            cursor = try #require(calendar.date(byAdding: .day, value: 1, to: cursor))
        }

        // Sanity: the loop actually ran (a broken cursor would silently pass everything).
        #expect(checked > 7_600, "expected ~7670 days, walked \(checked)")
    }

    // MARK: - Malformed input

    @Test("returns nil for every malformed shape")
    func rejectsMalformedInput() {
        let malformed = [
            "",                       // empty
            "2026-7-28",              // unpadded month
            "2026-07-2",              // unpadded day / too short
            "2026/07/28",             // wrong separator
            "2026-07-28T10:00:00",    // trailing time
            "2026-07-28 ",            // trailing space
            " 2026-07-28",            // leading space
            "26-07-28",               // 2-digit year
            "abcd-ef-gh",             // non-digits
            "2026-ab-28",             // non-digit month
            "20260728",               // no separators
            "2026-07-28-01"           // too long
        ]

        for input in malformed {
            #expect(FastDateParser.date(from: input) == nil, "should be nil: '\(input)'")
        }
    }

    /// Exhaustive sweep of the out-of-range / overflow space.
    ///
    /// DateFormatter's rule here is subtle and was NOT what it looked like: it rejects a
    /// field outside its own range (month 13, day 32 → nil) but rolls over an in-range
    /// day that overflows the month ("2026-02-30" → 2026-03-02, "2025-02-29" → 2025-03-01).
    /// Sampling a handful of inputs hid that. Sweeping every month 0…13 against every day
    /// 0…32 across leap, non-leap and century years pins the real behaviour.
    @Test("matches DateFormatter across every month/day combination, valid or not")
    func matchesAcrossEntireMonthDaySpace() {
        // 2024 leap, 2025 non-leap, 2000 leap century, 1900 non-leap century.
        for year in [2024, 2025, 2000, 1900] {
            for month in 0...13 {
                for day in 0...32 {
                    let iso = String(format: "%04d-%02d-%02d", year, month, day)
                    #expect(
                        FastDateParser.date(from: iso) == Self.reference.date(from: iso),
                        "diverged on \(iso)"
                    )
                }
            }
        }
    }

    // MARK: - Leap years

    @Test("handles leap day exactly as DateFormatter does")
    func handlesLeapDay() {
        // Valid leap days resolve; invalid ones roll over rather than returning nil —
        // whatever DateFormatter does, FastDateParser must do too.
        for iso in ["2024-02-29", "2000-02-29", "2025-02-29", "1900-02-29"] {
            #expect(FastDateParser.date(from: iso) == Self.reference.date(from: iso),
                    "diverged on \(iso)")
        }
        #expect(FastDateParser.date(from: "2024-02-29") != nil, "2024 is a leap year")
    }

    // MARK: - Boundaries

    @Test("matches on month and year boundaries")
    func matchesOnBoundaries() {
        for iso in ["2026-01-01", "2026-01-31", "2026-02-01", "2026-12-31",
                    "2027-01-01", "2026-04-30", "2026-06-30", "2026-11-30"] {
            #expect(FastDateParser.date(from: iso) == Self.reference.date(from: iso),
                    "diverged on boundary \(iso)")
        }
    }

    @Test("zero-pads years below 1000 the way the yyyy specifier does")
    func padsShortYears() {
        guard let d = Self.reference.date(from: "0999-01-05") else {
            Issue.record("reference formatter could not build 0999-01-05")
            return
        }
        #expect(FastDateParser.string(from: d) == Self.reference.string(from: d))
    }
}
