//
//  InsightSignalServiceTests.swift
//  TenraTests
//
//  Tests for the pure selection core of InsightSignalService (audit 2026-07):
//  severity gating, kind mapping, per-signal 7-day dedup, and the 5/week cap.
//

import Testing
import Foundation
@testable import Tenra

struct InsightSignalServiceTests {

    private func makeInsight(
        id: String,
        type: InsightType,
        severity: InsightSeverity,
        subtitle: String = "Подписка",
        changePercent: Double? = nil
    ) -> Insight {
        Insight(
            id: id,
            type: type,
            title: "Title",
            subtitle: subtitle,
            metric: InsightMetric(value: 100, formattedValue: "100 ₸", currency: "KZT", unit: nil),
            trend: changePercent.map {
                InsightTrend(direction: .up, changePercent: $0, changeAbsolute: 10, comparisonPeriod: "prev")
            },
            severity: severity,
            category: .recurring,
            detailData: nil
        )
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let allKinds = Set(InsightSignalKind.allCases)

    // MARK: - Kind mapping / severity gate

    @Test("neutral and positive insights are never push-worthy")
    func severityGate() {
        #expect(InsightSignalKind.from(makeInsight(id: "a", type: .budgetOverspend, severity: .neutral)) == nil)
        #expect(InsightSignalKind.from(makeInsight(id: "a", type: .budgetOverspend, severity: .positive)) == nil)
        #expect(InsightSignalKind.from(makeInsight(id: "a", type: .budgetOverspend, severity: .critical)) == .budgetOverspend)
        #expect(InsightSignalKind.from(makeInsight(id: "a", type: .subscriptionPriceIncrease, severity: .warning)) == .priceIncrease)
        #expect(InsightSignalKind.from(makeInsight(id: "a", type: .projectedBalance, severity: .critical)) == .lowProjectedBalance)
        // Non-signal types stay in-feed even when critical
        #expect(InsightSignalKind.from(makeInsight(id: "a", type: .netCashFlow, severity: .critical)) == nil)
    }

    // MARK: - Selection

    @Test("fresh critical signal is selected; disabled kind is not")
    func selectionRespectsEnabledKinds() {
        let insight = makeInsight(id: "budget_over", type: .budgetOverspend, severity: .critical)
        let selected = InsightSignalService.selectSignals(
            from: [insight], enabledKinds: allKinds, history: [], now: now
        )
        #expect(selected.map(\.id) == ["budget_over"])

        let noKind = InsightSignalService.selectSignals(
            from: [insight], enabledKinds: allKinds.subtracting([.budgetOverspend]), history: [], now: now
        )
        #expect(noKind.isEmpty)

        let masterOff = InsightSignalService.selectSignals(
            from: [insight], enabledKinds: [], history: [], now: now
        )
        #expect(masterOff.isEmpty)
    }

    @Test("a signal fired within the 7-day window is deduplicated")
    func dedupWindow() {
        let insight = makeInsight(id: "price_increase_s1", type: .subscriptionPriceIncrease, severity: .warning)
        let recent = [InsightSignalService.FiredRecord(id: "price_increase_s1", date: now.addingTimeInterval(-3 * 24 * 3600))]
        let selected = InsightSignalService.selectSignals(
            from: [insight], enabledKinds: allKinds, history: recent, now: now
        )
        #expect(selected.isEmpty)

        // Expired record (8 days ago) no longer blocks.
        let old = [InsightSignalService.FiredRecord(id: "price_increase_s1", date: now.addingTimeInterval(-8 * 24 * 3600))]
        let reselected = InsightSignalService.selectSignals(
            from: [insight], enabledKinds: allKinds, history: old, now: now
        )
        #expect(reselected.count == 1)
    }

    @Test("per-run cap limits a single recompute to 2 signals, critical first")
    func perRunCap() {
        let insights = [
            makeInsight(id: "w1", type: .subscriptionPriceIncrease, severity: .warning),
            makeInsight(id: "c1", type: .projectedBalance, severity: .critical),
            makeInsight(id: "w2", type: .spendingSpike, severity: .warning),
            makeInsight(id: "c2", type: .budgetOverspend, severity: .critical)
        ]
        // Empty history = full weekly budget of 5, but one run may only take 2.
        let selected = InsightSignalService.selectSignals(
            from: insights, enabledKinds: allKinds, history: [], now: now
        )
        #expect(selected.map(\.id) == ["c1", "c2"])
    }

    @Test("weekly cap of 5 limits output, critical signals win the budget")
    func weeklyCap() {
        // 4 already fired this week → budget of 1 left.
        let history = (0..<4).map {
            InsightSignalService.FiredRecord(id: "old_\($0)", date: now.addingTimeInterval(-Double($0 + 1) * 3600))
        }
        let warning  = makeInsight(id: "w1", type: .subscriptionPriceIncrease, severity: .warning)
        let critical = makeInsight(id: "c1", type: .projectedBalance, severity: .critical)
        let selected = InsightSignalService.selectSignals(
            from: [warning, critical], enabledKinds: allKinds, history: history, now: now
        )
        #expect(selected.map(\.id) == ["c1"]) // budget 1, critical sorted first

        // 5 already fired → nothing passes.
        let full = (0..<5).map {
            InsightSignalService.FiredRecord(id: "old_\($0)", date: now.addingTimeInterval(-Double($0 + 1) * 3600))
        }
        let none = InsightSignalService.selectSignals(
            from: [warning, critical], enabledKinds: allKinds, history: full, now: now
        )
        #expect(none.isEmpty)
    }

    // MARK: - Notification body

    @Test("notification body composes subtitle, metric and percent")
    func notificationBody() {
        let insight = makeInsight(id: "a", type: .subscriptionPriceIncrease, severity: .warning, subtitle: "Netflix", changePercent: 20)
        #expect(InsightSignalService.notificationBody(for: insight) == "Netflix · 100 ₸ (+20%)")

        let noTrend = makeInsight(id: "b", type: .budgetOverspend, severity: .critical, subtitle: "2 категории")
        #expect(InsightSignalService.notificationBody(for: noTrend) == "2 категории · 100 ₸")
    }

    // MARK: - Delivery window scheduling

    /// Deterministic RNG for delivery-date tests (SplitMix64).
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test("first delivery is immediate when now is inside the 09:00-21:00 window")
    func deliveryFirstInsideWindow() {
        var rng = SeededRNG(state: 1)
        let now = date(2026, 8, 25, 14, 0)
        let dates = InsightSignalService.deliveryDates(count: 1, now: now, rng: &rng)
        #expect(dates == [now])
    }

    @Test("night-time delivery moves to next morning 09:00-10:30")
    func deliveryNightMovesToMorning() {
        var rng = SeededRNG(state: 2)
        let now = date(2026, 8, 25, 23, 30)
        let dates = InsightSignalService.deliveryDates(count: 1, now: now, rng: &rng)
        let cal = Calendar.current
        #expect(dates.count == 1)
        #expect(cal.component(.day, from: dates[0]) == 26)
        let minutes = cal.component(.hour, from: dates[0]) * 60 + cal.component(.minute, from: dates[0])
        #expect(minutes >= 9 * 60 && minutes <= 10 * 60 + 30)
    }

    @Test("early morning (05:00) uses the SAME day's morning slot")
    func deliveryEarlyMorningSameDay() {
        var rng = SeededRNG(state: 3)
        let now = date(2026, 8, 25, 5, 0)
        let dates = InsightSignalService.deliveryDates(count: 1, now: now, rng: &rng)
        #expect(Calendar.current.component(.day, from: dates[0]) == 25)
        #expect(Calendar.current.component(.hour, from: dates[0]) >= 9)
    }

    @Test("subsequent deliveries are spaced 2-4h and never leave the window")
    func deliverySpacingAndWindow() {
        var rng = SeededRNG(state: 4)
        let now = date(2026, 8, 25, 20, 30) // near window end -> overflow to next morning
        let dates = InsightSignalService.deliveryDates(count: 3, now: now, rng: &rng)
        #expect(dates.count == 3)
        #expect(dates[0] == now)
        let cal = Calendar.current
        for d in dates {
            let hour = cal.component(.hour, from: d)
            #expect(hour >= 9 && hour < 21)
        }
        for i in 1..<dates.count {
            #expect(dates[i] > dates[i - 1])
        }
    }

    @Test("deliveryDates is deterministic under a seeded RNG and empty for count 0")
    func deliveryDeterminismAndZero() {
        let now = date(2026, 8, 25, 22, 0)
        var rng1 = SeededRNG(state: 42)
        var rng2 = SeededRNG(state: 42)
        #expect(InsightSignalService.deliveryDates(count: 2, now: now, rng: &rng1)
             == InsightSignalService.deliveryDates(count: 2, now: now, rng: &rng2))
        var rng3 = SeededRNG(state: 42)
        #expect(InsightSignalService.deliveryDates(count: 0, now: now, rng: &rng3).isEmpty)
    }
}
