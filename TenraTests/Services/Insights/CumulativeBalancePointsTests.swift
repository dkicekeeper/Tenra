//
//  CumulativeBalancePointsTests.swift
//  TenraTests
//
//  Pins `InsightsService.cumulativeBalancePoints` — THE running-wealth derivation.
//  The wealth insight's chart and the Insights balance stat card's sparkline both go
//  through it, so a second copy of this walk would silently draw two different lines.
//

import Testing
import Foundation
@testable import Tenra

@Suite("InsightsService.cumulativeBalancePoints")
struct CumulativeBalancePointsTests {

    private func point(_ key: String, income: Double, expenses: Double) -> PeriodDataPoint {
        PeriodDataPoint(
            id: key,
            granularity: .month,
            key: key,
            periodStart: Date(timeIntervalSince1970: 0),
            periodEnd: Date(timeIntervalSince1970: 86_400),
            label: key,
            income: income,
            expenses: expenses,
            cumulativeBalance: nil
        )
    }

    /// Jan +30k, Feb −10k, Mar +5k → net flows 30 000, −10 000, 5 000.
    private var points: [PeriodDataPoint] {
        [
            point("2026-01", income: 50_000, expenses: 20_000),
            point("2026-02", income: 10_000, expenses: 20_000),
            point("2026-03", income: 25_000, expenses: 20_000)
        ]
    }

    @Test("Series ends exactly at the known balance")
    func endsAtCurrentBalance() {
        let result = InsightsService.cumulativeBalancePoints(points, endingBalance: 100_000)
        #expect(result.last?.cumulativeBalance == 100_000)
    }

    @Test("Each step moves by that period's net flow")
    func stepsByNetFlow() {
        let result = InsightsService.cumulativeBalancePoints(points, endingBalance: 100_000)
        // Balance before the window: 100 000 − (30 000 − 10 000 + 5 000) = 75 000.
        #expect(result[0].cumulativeBalance == 105_000)   // 75 000 + 30 000
        #expect(result[1].cumulativeBalance == 95_000)    // 105 000 − 10 000
        #expect(result[2].cumulativeBalance == 100_000)   // 95 000 + 5 000
    }

    @Test("Income and expenses ride along untouched")
    func preservesSourceFields() {
        let result = InsightsService.cumulativeBalancePoints(points, endingBalance: 100_000)
        #expect(result.count == points.count)
        #expect(result[0].income == 50_000)
        #expect(result[0].expenses == 20_000)
        #expect(result[0].key == "2026-01")
    }

    @Test("Empty input yields an empty series")
    func emptyInput() {
        #expect(InsightsService.cumulativeBalancePoints([], endingBalance: 100_000).isEmpty)
    }
}
