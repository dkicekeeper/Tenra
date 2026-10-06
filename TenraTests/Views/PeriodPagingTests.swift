//
//  PeriodPagingTests.swift
//  TenraTests
//
//  Pins the index arithmetic behind the Insights period pagers (the paged category
//  breakdown and the category drill-down): where a pager opens, how far the chevrons
//  step, and that stepping never leaves the pages.
//
//  Pure tests — no views, no store, no async.
//

import Testing
@testable import Tenra

@Suite("PeriodPaging")
struct PeriodPagingTests {

    private let keys = ["2026-01", "2026-02", "2026-03", "2026-04"]

    // MARK: - Opening page

    @Test("Opens on the period the user drilled in from")
    func opensOnDrilledPeriod() {
        #expect(PeriodPaging.index(of: "2026-02", in: keys, fallbackKey: "2026-04") == 1)
    }

    @Test("Without a period of its own the pager opens on the current period")
    func opensOnCurrentPeriodWithoutKey() {
        #expect(PeriodPaging.index(of: nil, in: keys, fallbackKey: "2026-03") == 2)
    }

    @Test("A period the pager doesn't have falls back to the current one")
    func unknownKeyFallsBackToCurrent() {
        #expect(PeriodPaging.index(of: "2025-W12", in: keys, fallbackKey: "2026-04") == 3)
    }

    @Test("Neither key present: the newest page; no pages: index 0")
    func lastResortIndex() {
        #expect(PeriodPaging.index(of: "2024-01", in: keys, fallbackKey: "2027-01") == keys.count - 1)
        #expect(PeriodPaging.index(of: "2024-01", in: [], fallbackKey: "2027-01") == 0)
    }

    // MARK: - Stepping

    @Test("Steps one period back and forward")
    func stepsWithinBounds() {
        #expect(PeriodPaging.stepped(2, by: -1, count: keys.count) == 1)
        #expect(PeriodPaging.stepped(2, by: 1, count: keys.count) == 3)
    }

    @Test("No step past the first or the last period")
    func stopsAtBothEnds() {
        #expect(PeriodPaging.stepped(0, by: -1, count: keys.count) == nil)
        #expect(PeriodPaging.stepped(keys.count - 1, by: 1, count: keys.count) == nil)
        #expect(PeriodPaging.stepped(0, by: 1, count: 1) == nil)
        #expect(PeriodPaging.stepped(0, by: -1, count: 0) == nil)
    }

    @Test("Stepping back from the current period visits every period once, in order")
    func walksEveryPeriod() {
        var index = PeriodPaging.index(of: nil, in: keys, fallbackKey: "2026-04")
        var visited = [keys[index]]
        while let previous = PeriodPaging.stepped(index, by: -1, count: keys.count) {
            index = previous
            visited.append(keys[index])
        }
        #expect(visited == Array(keys.reversed()))
    }

    // MARK: - Clamping

    @Test("Initial index is clamped into the pages")
    func clampsIntoPages() {
        #expect(PeriodPaging.clamped(-3, count: 4) == 0)
        #expect(PeriodPaging.clamped(2, count: 4) == 2)
        #expect(PeriodPaging.clamped(9, count: 4) == 3)
        #expect(PeriodPaging.clamped(3, count: 0) == 0)
    }
}
