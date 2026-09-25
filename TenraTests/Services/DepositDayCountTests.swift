//
//  DepositDayCountTests.swift
//  TenraTests
//
//  The deposit day-count conventions (DepositDayCount): 30/360 gives every month
//  exactly rate / 12 (Kaspi, most Kazakh banks), actual/actual follows leap years,
//  old deposits keep actual/365, and the interest walk uses the deposit's setting.
//

import Testing
import Foundation
@testable import Tenra

struct DepositDayCountTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Sum of daily fractions from `from` through `through`, inclusive.
    private func fraction(_ method: DepositDayCount, from: Date, through: Date) -> Decimal {
        var total: Decimal = 0
        var day = from
        while day <= through {
            total += method.dailyFraction(on: day, calendar: calendar)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return total
    }

    private func close(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        abs(lhs - rhs) < Decimal(string: "0.0000000001")!
    }

    @Test(arguments: [2026, 2028])
    func thirty360GivesEveryMonthATwelfth(year: Int) {
        for month in 1...12 {
            let first = date(year, month, 1)
            let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first)!
            #expect(close(fraction(.thirty360, from: first, through: last), Decimal(30) / Decimal(360)),
                    "\(year)-\(month)")
        }
    }

    @Test func thirty360PartialMonthCountsThirtyMinusStartPlusOne() {
        // From the 15th: 30 − 15 + 1 = 16 days, whether the month has 31 days or 28.
        #expect(close(fraction(.thirty360, from: date(2026, 1, 15), through: date(2026, 1, 31)), Decimal(16) / Decimal(360)))
        #expect(close(fraction(.thirty360, from: date(2026, 2, 15), through: date(2026, 2, 28)), Decimal(16) / Decimal(360)))
    }

    @Test func actualConventions() {
        #expect(close(DepositDayCount.actualActual.dailyFraction(on: date(2028, 3, 1), calendar: calendar), 1 / Decimal(366)))
        #expect(close(DepositDayCount.actualActual.dailyFraction(on: date(2026, 3, 1), calendar: calendar), 1 / Decimal(365)))
        #expect(close(DepositDayCount.actual365.dailyFraction(on: date(2028, 3, 1), calendar: calendar), 1 / Decimal(365)))
        #expect(close(DepositDayCount.actual360.dailyFraction(on: date(2026, 3, 1), calendar: calendar), 1 / Decimal(360)))
        // A leap year under actual/actual earns exactly the annual rate.
        #expect(close(fraction(.actualActual, from: date(2028, 1, 1), through: date(2028, 12, 31)), 1))
    }

    // MARK: - Persistence

    @Test func depositsSavedBeforeTheSettingKeepActual365() throws {
        let saved = DepositInfo(bankName: "Bank", initialPrincipal: 1000, interestRateAnnual: 12, interestPostingDay: 1)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        json.removeValue(forKey: "dayCount")
        let legacy = try JSONDecoder().decode(DepositInfo.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.dayCount == .actual365)
    }

    @Test func chosenMethodSurvivesSaving() throws {
        let info = DepositInfo(bankName: "Bank", initialPrincipal: 1000, interestRateAnnual: 12,
                               interestPostingDay: 1, dayCount: .thirty360)
        let decoded = try JSONDecoder().decode(DepositInfo.self, from: JSONEncoder().encode(info))
        #expect(decoded.dayCount == .thirty360)
        #expect(DepositDayCount.defaultForNewDeposits == .thirty360)
    }

    // MARK: - Interest walk

    @Test func interestWalkUsesTheDepositsMethod() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastCalc = DateFormatters.dateFormatter.string(
            from: Calendar.current.date(byAdding: .day, value: -5, to: today)!)
        func info(_ method: DepositDayCount) -> DepositInfo {
            DepositInfo(bankName: "Bank", initialPrincipal: 1_200_000, capitalizationEnabled: false,
                        interestRateAnnual: 12,
                        interestRateHistory: [RateChange(effectiveFrom: lastCalc, annualRate: 12)],
                        interestPostingDay: 1, lastInterestCalculationDate: lastCalc,
                        lastInterestPostingMonth: "2020-01-01", dayCount: method)
        }
        let legacy = DepositInterestService.calculateInterestToToday(depositInfo: info(.actual365), accountId: "d", allTransactions: [])
        let thirty = DepositInterestService.calculateInterestToToday(depositInfo: info(.thirty360), accountId: "d", allTransactions: [])

        // Days walked, recovered from the actual/365 result, then weighted the 30/360 way.
        let perDay365: Decimal = 1_200_000 * Decimal(12) / 100 / 365
        let days = Int(NSDecimalNumber(decimal: legacy / perDay365).doubleValue.rounded())
        var expected: Decimal = 0
        for offset in 0..<days {
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            expected += 1_200_000 * Decimal(12) / 100
                * DepositDayCount.thirty360.dailyFraction(on: day, calendar: Calendar.current)
        }
        #expect(days > 0)
        #expect(abs(thirty - expected) < Decimal(string: "0.001")!, "\(thirty) vs \(expected)")
    }
}
