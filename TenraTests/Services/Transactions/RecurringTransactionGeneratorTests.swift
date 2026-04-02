//
//  RecurringTransactionGeneratorTests.swift
//  AIFinanceManagerTests
//
//  Tests for RecurringTransactionGenerator edge cases:
//  - Month-end date clamping (Jan 31 → Feb 28/29)
//  - Leap-year Feb 29 start date for yearly frequency
//  - Horizon boundary inclusion
//  - Existing occurrence key deduplication
//  - DST-boundary generation (no duplicates/gaps on spring-forward)
//
//  TEST-03
//

import Testing
import Foundation
@testable import AIFinanceManager

@Suite("RecurringTransactionGenerator Edge Cases")
struct RecurringTransactionGeneratorTests {

    // MARK: - Shared helpers

    /// Standard formatter matching DateFormatters.dateFormatter
    private func makeFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }

    /// Build a minimal RecurringSeries for generator tests
    private func makeSeries(
        id: String = "series-test",
        startDate: String,
        frequency: RecurringFrequency,
        isActive: Bool = true
    ) -> RecurringSeries {
        RecurringSeries(
            id: id,
            isActive: isActive,
            amount: Decimal(10),
            currency: "USD",
            category: "Test",
            description: "Test series",
            frequency: frequency,
            startDate: startDate
        )
    }

    // MARK: - Test A: Jan 31 monthly → Feb 28 (non-leap 2025)

    /// Monthly series starting 2025-01-31 must produce a 2025-02-28 occurrence.
    /// 2025 is NOT a leap year, so calendar clamps Jan 31 + 1 month to Feb 28.
    @Test("Jan 31 monthly produces Feb 28 on non-leap year 2025")
    func testJan31MonthlyProducesFeb28NonLeap() {
        let formatter = makeFormatter()
        let generator = RecurringTransactionGenerator(dateFormatter: formatter)
        let series = makeSeries(startDate: "2025-01-31", frequency: .monthly)

        // horizonMonths = 3 — runs in 2026, so all 2025 dates are within window
        let result = generator.generateTransactions(
            series: [series],
            existingOccurrences: [],
            existingTransactionIds: [],
            accounts: [],
            baseCurrency: "USD",
            horizonMonths: 3
        )

        let dates = result.occurrences.map { $0.occurrenceDate }
        #expect(dates.contains("2025-02-28"), "Expected Feb 28 occurrence for non-leap 2025; got: \(dates)")
        #expect(!dates.contains("2025-02-29"), "Should NOT contain Feb 29 on non-leap year")
    }

    // MARK: - Test B: Jan 31 monthly → Feb 29 (leap year 2024)

    /// Monthly series starting 2024-01-31 must produce a 2024-02-29 occurrence.
    /// 2024 IS a leap year, so Jan 31 + 1 month = Feb 29 (valid date).
    @Test("Jan 31 monthly produces Feb 29 on leap year 2024")
    func testJan31MonthlyProducesFeb29LeapYear() {
        let formatter = makeFormatter()
        let generator = RecurringTransactionGenerator(dateFormatter: formatter)
        let series = makeSeries(startDate: "2024-01-31", frequency: .monthly)

        let result = generator.generateTransactions(
            series: [series],
            existingOccurrences: [],
            existingTransactionIds: [],
            accounts: [],
            baseCurrency: "USD",
            horizonMonths: 3
        )

        let dates = result.occurrences.map { $0.occurrenceDate }
        #expect(dates.contains("2024-02-29"), "Expected Feb 29 occurrence for leap year 2024; got: \(dates)")
    }

    // MARK: - Test C: Feb 29 yearly → Feb 28 on non-leap year

    /// Yearly series starting 2024-02-29 must produce 2025-02-28.
    /// 2025 is NOT a leap year; Calendar clamps Feb 29 + 1 year to Feb 28.
    @Test("Feb 29 yearly series produces Feb 28 on non-leap next year")
    func testFeb29YearlyProducesFeb28NonLeapNextYear() {
        let formatter = makeFormatter()
        let generator = RecurringTransactionGenerator(dateFormatter: formatter)
        let series = makeSeries(startDate: "2024-02-29", frequency: .yearly)

        // horizonMonths = 3 (runs in 2026) — covers 2024, 2025, and current 2026 occurrences
        let result = generator.generateTransactions(
            series: [series],
            existingOccurrences: [],
            existingTransactionIds: [],
            accounts: [],
            baseCurrency: "USD",
            horizonMonths: 3
        )

        let dates = result.occurrences.map { $0.occurrenceDate }
        #expect(dates.contains("2025-02-28"), "Expected 2025-02-28 for yearly series starting 2024-02-29; got: \(dates)")
        #expect(!dates.contains("2025-02-29"), "Should NOT contain 2025-02-29 on non-leap year")
    }

    // MARK: - Test D: Horizon boundary — second occurrence at exactly horizon date is included

    /// A monthly series whose second occurrence falls exactly at today + 1 month
    /// must be included. The generator uses `currentDate <= horizonDate`.
    @Test("Occurrence at exactly the horizon date is included")
    func testHorizonBoundaryInclusion() {
        let formatter = makeFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let generator = RecurringTransactionGenerator(dateFormatter: formatter, calendar: calendar)

        // Use a date far in the past so ALL occurrences up to today+1 month are generated.
        // With horizonMonths=1, the horizon is startOfDay(today) + 1 month.
        // We start from 2024-01-01; the generator will produce many occurrences.
        // The last one should be <= today+1month (i.e., the occurrence AT the boundary is included).
        let series = makeSeries(startDate: "2024-01-01", frequency: .monthly)

        let result = generator.generateTransactions(
            series: [series],
            existingOccurrences: [],
            existingTransactionIds: [],
            accounts: [],
            baseCurrency: "USD",
            horizonMonths: 1
        )

        // Compute today + 1 month for boundary verification
        let today = calendar.startOfDay(for: Date())
        guard let horizonDate = calendar.date(byAdding: .month, value: 1, to: today) else {
            Issue.record("Could not compute horizon date")
            return
        }

        // All produced occurrences must be <= horizonDate
        for occ in result.occurrences {
            guard let occDate = formatter.date(from: occ.occurrenceDate) else {
                Issue.record("Could not parse occurrence date: \(occ.occurrenceDate)")
                continue
            }
            #expect(occDate <= horizonDate, "Occurrence \(occ.occurrenceDate) is past the horizon \(horizonDate)")
        }

        // There should be at least one occurrence (series starts in the past)
        #expect(!result.occurrences.isEmpty, "Expected at least one occurrence for past-starting series")
    }

    // MARK: - Test E: Existing occurrence key deduplication

    /// If an occurrence for the series' startDate already exists, the generator
    /// must skip it and NOT produce a duplicate transaction or occurrence.
    @Test("Existing occurrence key prevents duplicate generation")
    func testExistingOccurrenceKeyDeduplication() {
        let formatter = makeFormatter()
        let generator = RecurringTransactionGenerator(dateFormatter: formatter)

        let seriesId = "series-dedup"
        let firstOccurrenceDate = "2025-01-01"

        let series = makeSeries(id: seriesId, startDate: firstOccurrenceDate, frequency: .monthly)

        // Pre-seed the first occurrence
        let existingOccurrence = RecurringOccurrence(
            id: "occ-existing",
            seriesId: seriesId,
            occurrenceDate: firstOccurrenceDate,
            transactionId: "tx-existing"
        )

        let result = generator.generateTransactions(
            series: [series],
            existingOccurrences: [existingOccurrence],
            existingTransactionIds: [],
            accounts: [],
            baseCurrency: "USD",
            horizonMonths: 3
        )

        // The pre-seeded occurrence date must NOT appear in newly generated occurrences
        let newDates = result.occurrences.map { $0.occurrenceDate }
        #expect(!newDates.contains(firstOccurrenceDate),
                "Pre-seeded occurrence for \(firstOccurrenceDate) must not be regenerated; got: \(newDates)")

        // But subsequent occurrences (Feb, Mar, etc.) should still be generated
        #expect(newDates.contains("2025-02-01"),
                "Subsequent occurrences after the pre-seeded date should still be generated; got: \(newDates)")
    }

    // MARK: - Test F: DST-boundary daily generation (America/New_York spring-forward)

    /// A daily series spanning 2025-03-08 (US Eastern spring-forward: clocks jump 2 AM → 3 AM)
    /// must produce exactly consecutive dates with no duplicates or gaps.
    /// Calendar.date(byAdding: .day, value: 1) is DST-aware and always produces the next calendar date.
    @Test("DST spring-forward boundary produces consecutive daily occurrences with no duplicates")
    func testDSTBoundaryDailyGenerationNoGapsOrDuplicates() {
        let formatter = makeFormatter()
        // Use America/New_York timezone — 2025-03-09 is the spring-forward day (02:00→03:00)
        guard let nyTimeZone = TimeZone(identifier: "America/New_York") else {
            Issue.record("Could not create America/New_York timezone")
            return
        }

        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = nyTimeZone

        let dstFormatter = DateFormatter()
        dstFormatter.dateFormat = "yyyy-MM-dd"
        dstFormatter.locale = Locale(identifier: "en_US_POSIX")
        dstFormatter.timeZone = nyTimeZone

        let dstGenerator = RecurringTransactionGenerator(dateFormatter: dstFormatter, calendar: dstCalendar)

        // Start the day before DST spring-forward; running in 2026 means all 2025 dates are in the past
        let series = makeSeries(startDate: "2025-03-08", frequency: .daily)

        let result = dstGenerator.generateTransactions(
            series: [series],
            existingOccurrences: [],
            existingTransactionIds: [],
            accounts: [],
            baseCurrency: "USD",
            horizonMonths: 3
        )

        let occurrenceDates = result.occurrences.map { $0.occurrenceDate }

        // 1. Must contain both days around the DST transition (no skip)
        #expect(occurrenceDates.contains("2025-03-08"),
                "Must contain 2025-03-08 (day before DST spring-forward)")
        #expect(occurrenceDates.contains("2025-03-09"),
                "Must contain 2025-03-09 (DST spring-forward day)")

        // 2. No duplicate dates
        let uniqueDates = Set(occurrenceDates)
        #expect(uniqueDates.count == occurrenceDates.count,
                "Duplicate occurrence dates found: \(occurrenceDates.filter { d in occurrenceDates.filter { $0 == d }.count > 1 })")

        // 3. Verify dates are strictly consecutive (sorted order matches sequential dates)
        let sortedDates = occurrenceDates.sorted()
        for i in 1..<sortedDates.count {
            guard let prev = dstFormatter.date(from: sortedDates[i - 1]),
                  let curr = dstFormatter.date(from: sortedDates[i]) else {
                Issue.record("Could not parse consecutive dates at index \(i)")
                continue
            }
            // The next date should be exactly 1 calendar day after the previous
            guard let expectedNext = dstCalendar.date(byAdding: .day, value: 1, to: prev) else {
                Issue.record("Could not compute expected next date from \(sortedDates[i - 1])")
                continue
            }
            let expectedNextStr = dstFormatter.string(from: expectedNext)
            #expect(sortedDates[i] == expectedNextStr,
                    "Gap between \(sortedDates[i - 1]) and \(sortedDates[i]): expected \(expectedNextStr)")
        }

        // 4. Must have at least the 10 days covering March 8–17 (spanning the DST boundary)
        let dstSpan = ["2025-03-08","2025-03-09","2025-03-10","2025-03-11",
                       "2025-03-12","2025-03-13","2025-03-14","2025-03-15",
                       "2025-03-16","2025-03-17"]
        for d in dstSpan {
            #expect(occurrenceDates.contains(d), "Missing expected occurrence: \(d)")
        }
    }
}
