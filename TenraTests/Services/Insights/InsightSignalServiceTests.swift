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
}
