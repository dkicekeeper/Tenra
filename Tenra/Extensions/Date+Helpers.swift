//
//  Date+Helpers.swift
//  AIFinanceManager
//
//  Created on 2026-02-15
//
//  Date manipulation utilities

import Foundation

extension Date {

    // MARK: - Calendar Helpers

    /// Get start of day for this date
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Get end of day for this date
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    /// Get start of month for this date
    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? self
    }

    /// Get end of month for this date
    var endOfMonth: Date {
        var components = DateComponents()
        components.month = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfMonth) ?? self
    }

    /// Get start of year for this date
    var startOfYear: Date {
        let components = Calendar.current.dateComponents([.year], from: self)
        return Calendar.current.date(from: components) ?? self
    }

    /// Get end of year for this date
    var endOfYear: Date {
        var components = DateComponents()
        components.year = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfYear) ?? self
    }

    // MARK: - Component Access

    /// Get year component
    var year: Int {
        Calendar.current.component(.year, from: self)
    }

    /// Get month component (1-12)
    var month: Int {
        Calendar.current.component(.month, from: self)
    }

    /// Get day component
    var day: Int {
        Calendar.current.component(.day, from: self)
    }

    // MARK: - Comparisons

    /// Check if date is in the same day as another date
    func isSameDay(as date: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: date)
    }

    /// Check if date is in the same month as another date
    func isSameMonth(as date: Date) -> Bool {
        let components1 = Calendar.current.dateComponents([.year, .month], from: self)
        let components2 = Calendar.current.dateComponents([.year, .month], from: date)
        return components1.year == components2.year && components1.month == components2.month
    }

    /// Check if date is in the same year as another date
    func isSameYear(as date: Date) -> Bool {
        Calendar.current.component(.year, from: self) == Calendar.current.component(.year, from: date)
    }

    /// Check if date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Check if date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Check if date is in current month
    var isInCurrentMonth: Bool {
        isSameMonth(as: Date())
    }

    // MARK: - Date Arithmetic

    /// Add days to date
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Add months to date
    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    /// Add years to date
    func adding(years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: years, to: self) ?? self
    }

    /// Days between this date and another date
    func daysBetween(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: startOfDay, to: date.startOfDay)
        return abs(components.day ?? 0)
    }

    /// Months between this date and another date
    func monthsBetween(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: startOfMonth, to: date.startOfMonth)
        return abs(components.month ?? 0)
    }
}
