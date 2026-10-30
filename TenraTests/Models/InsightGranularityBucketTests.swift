import Testing
import Foundation
@testable import Tenra

@Suite("InsightGranularity — current/previous bucket")
struct InsightGranularityBucketTests {

    private let calendar = Calendar.current
    private let now = Date()

    @Test("month — current bucket is start-of-month → start-of-next-month")
    func monthBucket() {
        let (start, end) = InsightGranularity.month.currentBucketRange()
        let comps = calendar.dateComponents([.year, .month, .day], from: start)
        #expect(comps.day == 1)
        let nowComps = calendar.dateComponents([.year, .month], from: now)
        #expect(comps.year == nowComps.year)
        #expect(comps.month == nowComps.month)

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start)!
        #expect(end == nextMonth)
    }

    @Test("month — previous bucket is one month earlier")
    func monthPrevBucket() {
        let (curStart, _) = InsightGranularity.month.currentBucketRange()
        let (prevStart, prevEnd) = InsightGranularity.month.previousBucketRange()
        let expected = calendar.date(byAdding: .month, value: -1, to: curStart)!
        #expect(prevStart == expected)
        #expect(prevEnd == curStart)
    }

    @Test("quarter — current bucket starts on quarter month boundary")
    func quarterBucket() {
        let (start, end) = InsightGranularity.quarter.currentBucketRange()
        let m = calendar.component(.month, from: start)
        #expect([1, 4, 7, 10].contains(m))
        #expect(calendar.component(.day, from: start) == 1)
        #expect(end == calendar.date(byAdding: .month, value: 3, to: start)!)
    }

    @Test("year — current bucket starts on Jan 1")
    func yearBucket() {
        let (start, end) = InsightGranularity.year.currentBucketRange()
        #expect(calendar.component(.month, from: start) == 1)
        #expect(calendar.component(.day, from: start) == 1)
        #expect(end == calendar.date(byAdding: .year, value: 1, to: start)!)
    }

    @Test("week — current bucket is last 7 days")
    func weekBucket() {
        let (start, end) = InsightGranularity.week.currentBucketRange()
        let endOfDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        #expect(end == endOfDay)
        let expectedStart = calendar.date(byAdding: .day, value: -7, to: endOfDay)!
        #expect(start == expectedStart)
    }

    @Test("allTime — current bucket equals the full data window")
    func allTimeBucket() {
        let (cs, ce) = InsightGranularity.allTime.currentBucketRange()
        let (ds, de) = InsightGranularity.allTime.dateRange(firstTransactionDate: nil)
        // `end` is startOfDay-rounded — should match exactly.
        #expect(ce == de)
        // `start` defaults to "now" in both APIs; the two Date() calls are
        // microseconds apart in practice — assert proximity, not equality.
        #expect(abs(cs.timeIntervalSince(ds)) < 1.0)
    }

    @Test("currentBucketLabel — month renders 'MMMM yyyy'")
    func monthLabel() {
        let label = InsightGranularity.month.currentBucketLabel(locale: Locale(identifier: "en_US"))
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "MMMM yyyy"
        #expect(label == df.string(from: now))
    }

    @Test("currentBucketLabel — week renders 'Last 7 days' string")
    func weekLabel() {
        let label = InsightGranularity.week.currentBucketLabel(locale: Locale(identifier: "en_US"))
        #expect(!label.isEmpty)
    }

    @Test("chart point — only the current bucket is unfinished, all time never (chartIsPartial)")
    func currentBucketIsPartial() {
        func point(_ granularity: InsightGranularity, _ range: (start: Date, end: Date)) -> PeriodDataPoint {
            PeriodDataPoint(
                id: "p", granularity: granularity, key: "p",
                periodStart: range.start, periodEnd: range.end, label: "p",
                income: 0, expenses: 0, cumulativeBalance: nil
            )
        }
        for granularity in [InsightGranularity.week, .month, .quarter, .year] {
            #expect(point(granularity, granularity.currentBucketRange()).chartIsPartial)
            #expect(!point(granularity, granularity.previousBucketRange()).chartIsPartial)
        }
        // The all-time window also ends tomorrow, but it is one period: never "so far".
        #expect(!point(.allTime, InsightGranularity.allTime.currentBucketRange()).chartIsPartial)
    }
}
