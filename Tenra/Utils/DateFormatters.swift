//
//  DateFormatters.swift
//  Tenra
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

    // Display formatters depend on the device locale (localised month names). A static
    // `let` captured `Locale.current` once, so a mid-session language change showed stale
    // month names until the process was killed (cache audit #19). These are cached by
    // locale identifier and rebuilt only when it changes — per-call cost stays ~0 without
    // going stale.
    private static let displayFormatterLock = NSLock()
    nonisolated(unsafe) private static var displayFormatterCache: [String: (locale: String, formatter: DateFormatter)] = [:]

    private nonisolated static func localizedDisplayFormatter(format: String) -> DateFormatter {
        let localeId = Locale.current.identifier
        displayFormatterLock.lock()
        defer { displayFormatterLock.unlock() }
        if let cached = displayFormatterCache[format], cached.locale == localeId {
            return cached.formatter
        }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = .current
        formatter.timeZone = TimeZone.current
        displayFormatterCache[format] = (localeId, formatter)
        return formatter
    }

    /// Форматтер для отображения даты в формате "d MMMM" (локаль устройства)
    nonisolated static var displayDateFormatter: DateFormatter { localizedDisplayFormatter(format: "d MMMM") }

    /// Форматтер для отображения даты с годом в формате "d MMMM yyyy" (локаль устройства)
    nonisolated static var displayDateWithYearFormatter: DateFormatter { localizedDisplayFormatter(format: "d MMMM yyyy") }

    /// Display a date as "d MMMM", appending the year ("d MMMM yyyy") only when it
    /// falls outside the current calendar year. Keeps same-year dates uncluttered
    /// while disambiguating future/past dates (e.g. a next-charge date in 2027).
    static func displayDateOmittingCurrentYear(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return displayDateFormatter.string(from: date)
        }
        return displayDateWithYearFormatter.string(from: date)
    }

    /// Convert "yyyy-MM-dd" string to display format "d MMMM".
    /// Returns the original string if parsing fails.
    static func displayString(from isoDateString: String) -> String {
        if let date = dateFormatter.date(from: isoDateString) {
            return displayDateFormatter.string(from: date)
        }
        return isoDateString
    }
}
