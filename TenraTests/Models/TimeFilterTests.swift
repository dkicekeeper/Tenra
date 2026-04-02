//
//  TimeFilterTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026
//

import Testing
import Foundation
@testable import AIFinanceManager

struct TimeFilterTests {

    @Test("Today filter includes today's date")
    func testTodayFilter() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let filter = TimeFilter(preset: .today)
        #expect(filter.contains(date: today))

        // Yesterday should not be included
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            #expect(!filter.contains(date: yesterday))
        }
    }

    @Test("This month filter includes current month dates")
    func testThisMonthFilter() {
        let calendar = Calendar.current
        let today = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!

        let filter = TimeFilter(preset: .thisMonth)

        #expect(filter.contains(date: today))
        #expect(filter.contains(date: startOfMonth))

        // Last month should not be included
        if let lastMonth = calendar.date(byAdding: .month, value: -1, to: startOfMonth) {
            #expect(!filter.contains(date: lastMonth))
        }
    }

    @Test("Last 30 days filter")
    func testLast30DaysFilter() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let filter = TimeFilter(preset: .last30Days)

        #expect(filter.contains(date: today))

        // 29 days ago should be included
        if let day29 = calendar.date(byAdding: .day, value: -29, to: today) {
            #expect(filter.contains(date: day29))
        }

        // 31 days ago should not be included
        if let day31 = calendar.date(byAdding: .day, value: -31, to: today) {
            #expect(!filter.contains(date: day31))
        }
    }

    @Test("All time filter includes any date")
    func testAllTimeFilter() {
        let calendar = Calendar.current
        let today = Date()

        let filter = TimeFilter(preset: .allTime)

        #expect(filter.contains(date: today))

        // Very old date should be included
        if let oldDate = calendar.date(byAdding: .year, value: -10, to: today) {
            #expect(filter.contains(date: oldDate))
        }

        // Future date should be included
        if let futureDate = calendar.date(byAdding: .year, value: 10, to: today) {
            #expect(filter.contains(date: futureDate))
        }
    }

    @Test("Custom date range filter")
    func testCustomDateRangeFilter() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let start = calendar.date(byAdding: .day, value: -7, to: today),
              let end = calendar.date(byAdding: .day, value: 7, to: today) else {
            Issue.record("Failed to create dates for custom range test")
            return
        }

        let filter = TimeFilter(preset: .custom, startDate: start, endDate: end)

        #expect(filter.contains(date: today))
        #expect(filter.contains(date: start))

        // Day before start should not be included
        if let beforeStart = calendar.date(byAdding: .day, value: -1, to: start) {
            #expect(!filter.contains(date: beforeStart))
        }

        // Day after end should not be included
        if let afterEnd = calendar.date(byAdding: .day, value: 1, to: end) {
            #expect(!filter.contains(date: afterEnd))
        }
    }

    @Test("Date string filtering")
    func testDateStringFiltering() {
        let filter = TimeFilter(preset: .today)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let todayString = dateFormatter.string(from: Date())
        #expect(filter.contains(dateString: todayString))

        // Invalid date string should return false
        #expect(!filter.contains(dateString: "invalid-date"))
    }
}
