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

    /// "yyyy-MM-dd" in UTC, Gregorian, POSIX: the keys of historical FX rates and the date in
    /// the rate APIs' URLs and responses. Without the POSIX locale a device whose region uses
    /// another calendar (Buddhist, Japanese) writes another year into the key.
    nonisolated static let rateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
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
    private nonisolated static let displayFormatterLock = NSLock()
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

    // MARK: - Day dates in the chosen style

    private nonisolated(unsafe) static var dayFormatterCache: [String: DateFormatter] = [:]

    /// The pattern of one day date. `words` takes only the ORDER from the locale's `dMMMM`
    /// template (day first or month first), so Russian stays "3 ноября 2026" without "г.".
    private nonisolated static func dayPattern(style: DateStyle, includeYear: Bool, locale: Locale) -> String {
        switch style {
        case .iso: return "yyyy-MM-dd"
        case .dots: return includeYear ? "dd.MM.yyyy" : "dd.MM"
        case .slash: return includeYear ? "MM/dd/yyyy" : "MM/dd"
        case .words:
            let template = DateFormatter.dateFormat(fromTemplate: "dMMMM", options: 0, locale: locale) ?? "d MMMM"
            let dayFirst = (template.firstIndex(of: "d") ?? template.endIndex) < (template.firstIndex(of: "M") ?? template.endIndex)
            if dayFirst { return includeYear ? "d MMMM yyyy" : "d MMMM" }
            return includeYear ? "MMMM d, yyyy" : "MMMM d"
        }
    }

    /// A day date in the chosen style: "3 ноября" / "November 3" (words), "03.11", "11/03" or
    /// "2026-11-03" (always with the year). Formatters are cached by style, year and locale.
    nonisolated static func day(
        _ date: Date,
        includeYear: Bool,
        style: DateStyle = FormatSettings.snapshot.dateStyle,
        locale: Locale = .current
    ) -> String {
        let withYear = includeYear || style == .iso
        let key = "\(style.rawValue)|\(withYear)|\(locale.identifier)|\(TimeZone.current.identifier)"
        displayFormatterLock.lock()
        defer { displayFormatterLock.unlock() }
        if let cached = dayFormatterCache[key] { return cached.string(from: date) }
        let formatter = DateFormatter()
        // POSIX for the numeric styles: digits and separators must not follow the region.
        formatter.locale = style == .words ? locale : Locale(identifier: "en_US_POSIX")
        formatter.calendar = style == .words ? locale.calendar : Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = dayPattern(style: style, includeYear: withYear, locale: locale)
        dayFormatterCache[key] = formatter
        return formatter.string(from: date)
    }

    /// Display a date as a day date, appending the year only when it falls outside the
    /// current calendar year. Keeps same-year dates uncluttered while disambiguating
    /// future/past dates (e.g. a next-charge date in 2027).
    nonisolated static func displayDateOmittingCurrentYear(_ date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return day(date, includeYear: !sameYear)
    }

    /// Convert "yyyy-MM-dd" string to a day date (no year; "iso" always has it).
    /// Returns the original string if parsing fails.
    nonisolated static func displayString(from isoDateString: String) -> String {
        if let date = FastDateParser.date(from: isoDateString) {
            return day(date, includeYear: false)
        }
        return isoDateString
    }
}
