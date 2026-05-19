//
//  Date+Helpers.swift
//  Tenra
//
//  Date manipulation utilities — only the helpers actually used in the codebase.
//

import Foundation

extension Date {
    /// Get start of day for this date
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Get start of month for this date
    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? self
    }
}
