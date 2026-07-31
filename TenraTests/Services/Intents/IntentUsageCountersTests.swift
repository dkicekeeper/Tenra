//
//  IntentUsageCountersTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

struct IntentUsageCountersTests {

    private func makeCounters(_ suite: String) -> IntentUsageCounters {
        UserDefaults().removePersistentDomain(forName: suite)
        return IntentUsageCounters(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test("A fresh store reports zeros")
    func startsAtZero() {
        let counters = makeCounters("intent.counters.1")
        let snapshot = counters.snapshot()
        #expect(snapshot.intentAdds == 0)
        #expect(snapshot.manualAdds == 0)
        #expect(snapshot.fallbacks == 0)
    }

    @Test("Each event increments only its own counter")
    func incrementsIndependently() {
        let counters = makeCounters("intent.counters.2")
        counters.record(.intentAdd)
        counters.record(.intentAdd)
        counters.record(.manualAdd)
        counters.record(.intentFallbackToApp)

        let snapshot = counters.snapshot()
        #expect(snapshot.intentAdds == 2)
        #expect(snapshot.manualAdds == 1)
        #expect(snapshot.fallbacks == 1)
    }

    @Test("Counts survive a new instance over the same defaults")
    func persists() {
        let suite = "intent.counters.3"
        let first = makeCounters(suite)
        first.record(.intentAdd)

        let second = IntentUsageCounters(defaults: UserDefaults(suiteName: suite)!)
        #expect(second.snapshot().intentAdds == 1)
    }

    @Test("Reset clears every counter")
    func resetClears() {
        let counters = makeCounters("intent.counters.4")
        counters.record(.intentAdd)
        counters.record(.manualAdd)
        counters.record(.intentFallbackToApp)

        counters.reset()

        let snapshot = counters.snapshot()
        #expect(snapshot.intentAdds == 0)
        #expect(snapshot.manualAdds == 0)
        #expect(snapshot.fallbacks == 0)
    }
}
