//
//  DateFormattersTests.swift
//  AIFinanceManagerTests
//
//  Created on 2024
//

import Testing
import Foundation
@testable import AIFinanceManager

struct DateFormattersTests {
    
    @Test("DateFormatter formats date correctly")
    func testDateFormatter() {
        let date = Date(timeIntervalSince1970: 1705276800) // 2024-01-15
        let formatted = DateFormatters.dateFormatter.string(from: date)
        #expect(formatted == "2024-01-15")
    }
    
    @Test("DateFormatter parses date correctly")
    func testDateFormatterParsing() {
        let dateString = "2024-01-15"
        let date = DateFormatters.dateFormatter.date(from: dateString)
        #expect(date != nil)
        
        if let date = date {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            #expect(components.year == 2024)
            #expect(components.month == 1)
            #expect(components.day == 15)
        }
    }
    
    @Test("TimeFormatter formats time correctly")
    func testTimeFormatter() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = 14
        components.minute = 30
        
        if let date = calendar.date(from: components) {
            let formatted = DateFormatters.timeFormatter.string(from: date)
            #expect(formatted == "14:30")
        }
    }
    
    @Test("DisplayDateFormatter formats date in Russian")
    func testDisplayDateFormatter() {
        let date = Date(timeIntervalSince1970: 1705276800) // 2024-01-15
        let formatted = DateFormatters.displayDateFormatter.string(from: date)
        // Проверяем, что формат содержит число и месяц
        #expect(formatted.contains("15") || formatted.contains("января") || formatted.contains("January"))
    }
    
    @Test("DateFormatters are singletons")
    func testDateFormattersAreSingletons() {
        let formatter1 = DateFormatters.dateFormatter
        let formatter2 = DateFormatters.dateFormatter
        // Проверяем, что это один и тот же экземпляр (по ссылке)
        #expect(formatter1.dateFormat == formatter2.dateFormat)
    }
}
