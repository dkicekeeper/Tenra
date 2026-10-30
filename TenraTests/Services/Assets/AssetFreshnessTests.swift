//
//  AssetFreshnessTests.swift
//  TenraTests
//
//  Phase 3 of the assets plan (docs/domains/assets.md): with a depreciation rule the value is
//  the latest valuation less the depreciation for the years since (an estimate), a new valuation
//  is the new base, a sold asset keeps its sale; a valuation older than six months (homes and
//  cars) or a year (the rest) is out of date; the total over time ends on today's estimate; and
//  Ten writes once a half-year about an out-of-date asset, its message gone once it is valued.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized)
struct AssetFreshnessTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 10M in 2024, valued 9M on 1 Jan 2025, losing 15% a year.
    private static var car: Asset {
        Asset(
            id: "car", name: "Car", kind: .vehicle, currency: "KZT",
            purchaseDate: day(2024, 1, 1), purchasePrice: 10_000_000,
            valuations: [AssetValuation(id: "v", date: day(2025, 1, 1), value: 9_000_000)],
            depreciationPerYear: 0.15
        )
    }

    // MARK: - Depreciation

    @Test func aRuleCountsTheValueDownFromTheLatestValuation() {
        let summary = AssetValuationMath.summary(of: Self.car, today: Self.day(2026, 1, 1), calendar: Self.calendar)
        let expected = 9_000_000 * pow(0.85, 365 / AssetValuationMath.daysPerYear)
        #expect(abs(summary.value - expected) < 1)
        #expect(summary.value == summary.value.rounded())
        #expect(summary.isEstimate)
        #expect(summary.valuedOn == Self.day(2025, 1, 1))
        #expect(abs((summary.gain ?? 0) - (expected - 10_000_000)) < 1)
    }

    @Test func aNewValuationIsTheNewBase() {
        var car = Self.car
        car.valuations.append(AssetValuation(date: Self.day(2026, 1, 1), value: 8_000_000))
        let summary = AssetValuationMath.summary(of: car, today: Self.day(2026, 1, 1), calendar: Self.calendar)
        #expect(summary.value == 8_000_000)
        #expect(!summary.isEstimate)
    }

    @Test func withoutARuleOrOnceSoldThereIsNoEstimate() {
        var kept = Self.car
        kept.depreciationPerYear = nil
        #expect(AssetValuationMath.summary(of: kept, today: Self.day(2026, 1, 1), calendar: Self.calendar).value == 9_000_000)

        var sold = Self.car
        sold.valuations.append(AssetValuation(date: Self.day(2025, 6, 1), value: 8_500_000, source: .sale))
        sold.soldAt = Self.day(2025, 6, 1)
        let summary = AssetValuationMath.summary(of: sold, today: Self.day(2026, 1, 1), calendar: Self.calendar)
        #expect(summary.value == 8_500_000)
        #expect(!summary.isEstimate)
    }

    @Test func aTimelineIsEmptyBeforeThePurchaseAndAfterTheSale() {
        var car = Self.car
        car.depreciationPerYear = nil
        car.soldAt = Self.day(2026, 3, 1)
        let timeline = AssetValuationMath.timeline(of: car, calendar: Self.calendar)
        #expect(AssetValuationMath.estimate(timeline, on: Self.day(2023, 12, 31), calendar: Self.calendar) == nil)
        #expect(AssetValuationMath.estimate(timeline, on: Self.day(2024, 6, 1), calendar: Self.calendar)?.value == 10_000_000)
        #expect(AssetValuationMath.estimate(timeline, on: Self.day(2025, 6, 1), calendar: Self.calendar)?.value == 9_000_000)
        #expect(AssetValuationMath.estimate(timeline, on: Self.day(2026, 3, 1), calendar: Self.calendar) == nil)
    }

    @Test func theTotalOverTimeEndsOnTodaysEstimate() {
        let today = Self.day(2026, 1, 1)
        let points = AssetValuationMath.totalHistory(of: [Self.car], today: today, calendar: Self.calendar) { amount, _ in amount }
        #expect(points.map(\.date) == [Self.day(2024, 1, 1), Self.day(2025, 1, 1), today])
        #expect(abs((points.last?.value ?? 0) - 9_000_000 * pow(0.85, 365 / AssetValuationMath.daysPerYear)) < 1)
    }

    // MARK: - Out of date

    @Test func homesAndCarsGoOutOfDateAfterSixMonthsTheRestAfterAYear() {
        let today = Self.day(2026, 10, 29)
        func asset(_ kind: AssetKind, valuedOn date: Date) -> Asset {
            Asset(name: "A", kind: kind, currency: "KZT", valuations: [AssetValuation(date: date, value: 1)])
        }
        #expect(AssetValuationMath.isStale(asset(.apartment, valuedOn: Self.day(2026, 4, 1)), today: today, calendar: Self.calendar))
        #expect(!AssetValuationMath.isStale(asset(.apartment, valuedOn: Self.day(2026, 5, 1)), today: today, calendar: Self.calendar))
        #expect(AssetValuationMath.isStale(asset(.vehicle, valuedOn: Self.day(2026, 4, 1)), today: today, calendar: Self.calendar))
        #expect(!AssetValuationMath.isStale(asset(.other, valuedOn: Self.day(2025, 12, 1)), today: today, calendar: Self.calendar))
        #expect(AssetValuationMath.isStale(asset(.other, valuedOn: Self.day(2025, 10, 1)), today: today, calendar: Self.calendar))
    }

    @Test func withoutAValuationThePurchaseDayCountsAndASoldAssetIsNeverOutOfDate() {
        let today = Self.day(2026, 10, 29)
        let bought = Asset(name: "Flat", kind: .apartment, currency: "KZT", purchaseDate: Self.day(2018, 10, 29), purchasePrice: 24_000_000)
        #expect(AssetValuationMath.isStale(bought, today: today, calendar: Self.calendar))
        var sold = bought
        sold.soldAt = Self.day(2019, 1, 1)
        #expect(!AssetValuationMath.isStale(sold, today: today, calendar: Self.calendar))
    }

    // MARK: - Ten writes

    @Test func anOutOfDateAssetIsWrittenAboutOnceAHalfYear() {
        let bought = Asset(id: "flat", name: "Flat", kind: .apartment, currency: "KZT", purchaseDate: Self.day(2018, 10, 29), purchasePrice: 24_000_000)
        let fresh = Asset(id: "car", name: "Car", kind: .vehicle, currency: "KZT", valuations: [AssetValuation(date: Self.day(2026, 10, 1), value: 1)])
        let notices = AssistantNotices.staleAssets(
            [bought, fresh],
            summary: { AssetValuationMath.summary(of: $0, today: Self.day(2026, 10, 29), calendar: Self.calendar) },
            now: Self.day(2026, 10, 29),
            calendar: Self.calendar
        )
        #expect(notices.map(\.id) == ["asset:flat:2026-H2"])
        #expect(notices.first?.kind == .asset)
        #expect(notices.first?.subjectId == "flat")
        let spring = AssistantNotices.staleAssets(
            [bought],
            summary: { AssetValuationMath.summary(of: $0) },
            now: Self.day(2027, 3, 1),
            calendar: Self.calendar
        )
        #expect(spring.map(\.id) == ["asset:flat:2027-H1"])
    }

    @Test func theMessageLeavesOnceTheAssetIsValued() {
        let notice = AssistantNotice(
            id: "asset:flat:2026-H2", kind: .asset, title: "Flat", body: "", mood: .idle,
            question: "", insightId: nil, subjectId: "flat", createdAt: Self.day(2026, 10, 29)
        )
        let stale = AssistantNotices.Subjects(subscriptions: [], debts: [], goals: [], staleAssets: ["flat"])
        let valued = AssistantNotices.Subjects(subscriptions: [], debts: [], goals: [], staleAssets: [])
        #expect(stale.contains(notice))
        #expect(!valued.contains(notice))
    }
}
