//
//  DateFormatters.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

/// Cached DateFormatter instances. These formatters are configured once at
/// startup and never mutated. @MainActor removed because DateFormatter is
/// Sendable in iOS 26+ SDK — plain static let properties are accessible from
/// any isolation domain. For older-style formatting patterns see
/// TransactionSectionKeyFormatter.
enum DateFormatters {
    /// Форматтер для дат в формате "yyyy-MM-dd"
    nonisolated static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Форматтер для времени в формате "HH:mm"
    nonisolated static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Форматтер для отображения даты в формате "d MMMM" (локаль устройства)
    nonisolated static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.locale = .current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Форматтер для отображения даты с годом в формате "d MMMM yyyy" (локаль устройства)
    nonisolated static let displayDateWithYearFormatter: DateFormatter = {
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
