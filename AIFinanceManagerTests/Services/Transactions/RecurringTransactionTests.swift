//
//  RecurringTransactionTests.swift
//  AIFinanceManagerTests
//
//  Created on 2024
//

import Testing
import Foundation
@testable import AIFinanceManager

struct RecurringTransactionTests {
    
    @Test("RecurringFrequency has all cases")
    func testRecurringFrequencyCases() {
        let cases = RecurringFrequency.allCases
        #expect(cases.contains(.daily))
        #expect(cases.contains(.weekly))
        #expect(cases.contains(.monthly))
        #expect(cases.contains(.yearly))
    }
    
    @Test("RecurringFrequency display names")
    func testRecurringFrequencyDisplayNames() {
        #expect(RecurringFrequency.daily.displayName.count > 0)
        #expect(RecurringFrequency.weekly.displayName.count > 0)
        #expect(RecurringFrequency.monthly.displayName.count > 0)
        #expect(RecurringFrequency.yearly.displayName.count > 0)
    }
    
    @Test("RecurringSeries initializes correctly")
    func testRecurringSeriesInit() {
        let series = RecurringSeries(
            id: "test-id",
            isActive: true,
            amount: Decimal(100.0),
            currency: "USD",
            category: "Food",
            subcategory: nil,
            description: "Test",
            accountId: "account-1",
            targetAccountId: nil,
            frequency: .monthly,
            startDate: "2024-01-15"
        )

        #expect(series.id == "test-id")
        #expect(series.amount == Decimal(100.0))
        #expect(series.currency == "USD")
        #expect(series.category == "Food")
        #expect(series.frequency == .monthly)
        #expect(series.isActive == true)
    }
    
    @Test("RecurringOccurrence initializes correctly")
    func testRecurringOccurrenceInit() {
        let occurrence = RecurringOccurrence(
            id: "occ-1",
            seriesId: "series-1",
            occurrenceDate: "2024-01-15",
            transactionId: "tx-1"
        )
        
        #expect(occurrence.id == "occ-1")
        #expect(occurrence.seriesId == "series-1")
        #expect(occurrence.occurrenceDate == "2024-01-15")
        #expect(occurrence.transactionId == "tx-1")
    }

    @Test("RecurringSeries occurrences calculation")
    func testOccurrencesInInterval() {
        let series = RecurringSeries(
            amount: Decimal(10.0),
            currency: "USD",
            category: "Entertainment",
            description: "Netflix",
            frequency: .monthly,
            startDate: "2024-01-01"
        )
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let start = dateFormatter.date(from: "2024-01-01"),
              let end = dateFormatter.date(from: "2024-03-31") else {
            #expect(Bool(false), "Failed to create dates")
            return
        }
        
        let interval = DateInterval(start: start, end: end)
        let occurrences = series.occurrences(in: interval)
        
        #expect(occurrences.count == 3)
        #expect(dateFormatter.string(from: occurrences[0]) == "2024-01-01")
        #expect(dateFormatter.string(from: occurrences[1]) == "2024-02-01")
        #expect(dateFormatter.string(from: occurrences[2]) == "2024-03-01")
    }
}
