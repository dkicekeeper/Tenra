//
//  DateFormatters.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

/// Cached DateFormatter instances — MainActor-isolated because DateFormatter
/// is NOT thread-safe. Never access these from background threads/tasks.
/// For background date formatting, use Calendar component extraction
/// (see TransactionSectionKeyFormatter for the pattern).
@MainActor
enum DateFormatters {
    /// Форматтер для дат в формате "yyyy-MM-dd"
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /// Форматтер для времени в формате "HH:mm"
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    /// Форматтер для отображения даты в формате "d MMMM" (локаль устройства)
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = .current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Форматтер для отображения даты с годом в формате "d MMMM yyyy" (локаль устройства)
    static let displayDateWithYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        formatter.locale = .current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Convert "yyyy-MM-dd" string to display format "d MMMM".
    /// Returns the original string if parsing fails.
    static func displayString(from isoDateString: String) -> String {
        if let date = dateFormatter.date(from: isoDateString) {
            return displayDateFormatter.string(from: date)
        }
        return isoDateString
    }
}
