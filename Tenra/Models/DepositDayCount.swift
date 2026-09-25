//
//  DepositDayCount.swift
//  Tenra
//
//  How a bank turns an annual rate into interest for one day: the day-count
//  convention. Research (2026-09-25): Kazakh banks mostly count 30 days a month and
//  360 a year (Kaspi, Alatau City Bank; the National Bank's own deposits count
//  actual days / 360), Russian banks count actual days / 365 or 366. Tenra used to
//  divide by 365 for everyone, so a Kaspi deposit showed ~1.9% more than the bank in
//  31-day months, ~8% less in February, and a little more over a leap year.
//
//  The interest walk accrues day by day; each day earns
//  `principal × rate × dailyFraction(on:)`.
//

import Foundation

nonisolated enum DepositDayCount: String, Codable, CaseIterable, Sendable {
    /// Every month counts 30 days, the year 360: a full month always earns rate / 12.
    case thirty360 = "30/360"
    /// Actual days over a fixed 365-day year (Tenra's behavior before 2026-09-25).
    case actual365 = "actual/365"
    /// Actual days over the days of that year: 365, or 366 in a leap year.
    case actualActual = "actual/actual"
    /// Actual days over a 360-day year.
    case actual360 = "actual/360"

    /// New deposits: the convention most banks in the app's main market use.
    static let defaultForNewDeposits: DepositDayCount = .thirty360
    /// Deposits saved before the setting existed keep the arithmetic they were
    /// created with, so their history does not change.
    static let legacy: DepositDayCount = .actual365

    /// The share of a year the given calendar day earns interest for.
    ///
    /// 30/360 walks the calendar but weights days so each month sums to 30: the 31st
    /// counts 0, the last day of February counts the missing days (3, or 2 in a leap
    /// year), every other day counts 1. A period starting on the 15th therefore earns
    /// 30 − 15 + 1 = 16 days, as the convention requires.
    func dailyFraction(on date: Date, calendar: Calendar) -> Decimal {
        switch self {
        case .actual365:
            return 1 / Decimal(365)
        case .actual360:
            return 1 / Decimal(360)
        case .actualActual:
            let days = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
            return 1 / Decimal(days)
        case .thirty360:
            let day = calendar.component(.day, from: date)
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            let weight: Int
            if day > 30 {
                weight = 0
            } else if daysInMonth < 30 && day == daysInMonth {
                weight = 30 - daysInMonth + 1
            } else {
                weight = 1
            }
            return Decimal(weight) / Decimal(360)
        }
    }

    var localizedTitle: String {
        switch self {
        case .thirty360: return String(localized: "deposit.dayCount.thirty360")
        case .actual365: return String(localized: "deposit.dayCount.actual365")
        case .actualActual: return String(localized: "deposit.dayCount.actualActual")
        case .actual360: return String(localized: "deposit.dayCount.actual360")
        }
    }
}
