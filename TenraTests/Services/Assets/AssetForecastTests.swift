//
//  AssetForecastTests.swift
//  TenraTests
//
//  The wear ahead (plan-assets-roadmap 2.9, docs/domains/assets.md §Depreciation): a held asset
//  that depreciates is worth, in three years, its latest dated point worn at its rate; nothing
//  without a rate, once sold, or without a dated point.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssetForecastTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func car(rate: Double? = 0.15) -> Asset {
        Asset(
            name: "Car",
            kind: .vehicle,
            currency: "KZT",
            purchaseDate: Self.day(2024, 1, 1),
            purchasePrice: 10_000_000,
            valuations: [AssetValuation(date: Self.day(2025, 6, 1), value: 8_500_000, source: .manual)],
            depreciationPerYear: rate
        )
    }

    @Test("Three years ahead: the latest valuation worn at the rate, below today's estimate")
    func threeYears() throws {
        let today = Self.day(2026, 1, 1)
        let forecast = try #require(AssetValuationMath.forecast(of: car(), today: today, calendar: Self.calendar))
        #expect(forecast.date == Self.day(2029, 1, 1))
        let timeline = AssetValuationMath.timeline(of: car(), calendar: Self.calendar)
        let expected = try #require(AssetValuationMath.estimate(timeline, on: Self.day(2029, 1, 1), calendar: Self.calendar))
        #expect(forecast.value == expected.value)
        let now = try #require(AssetValuationMath.estimate(timeline, on: today, calendar: Self.calendar))
        #expect(forecast.value < now.value)
        // 3.6 years of 15% from 8.5M: about 4.6M.
        #expect(abs(forecast.value - 8_500_000 * pow(0.85, 3.585)) < 20_000)
    }

    @Test("No forecast without a rate, once sold, or without a dated point")
    func none() {
        let today = Self.day(2026, 1, 1)
        #expect(AssetValuationMath.forecast(of: car(rate: nil), today: today, calendar: Self.calendar) == nil)
        var sold = car()
        sold.valuations.append(AssetValuation(date: Self.day(2025, 12, 1), value: 7_000_000, source: .sale))
        sold.soldAt = Self.day(2025, 12, 1)
        #expect(AssetValuationMath.forecast(of: sold, today: today, calendar: Self.calendar) == nil)
        var undated = car()
        undated.purchaseDate = nil
        undated.valuations = []
        #expect(AssetValuationMath.forecast(of: undated, today: today, calendar: Self.calendar) == nil)
    }
}
