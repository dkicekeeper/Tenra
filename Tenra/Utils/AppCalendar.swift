//
//  AppCalendar.swift
//  Tenra
//
//  The calendar for week and month boundaries: the system's, with the first weekday the person
//  chose in Settings → Formats (or the region's).
//

import Foundation

nonisolated enum AppCalendar {
    static var current: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = FormatSettings.snapshot.firstWeekday
        return calendar
    }
}
