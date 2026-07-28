//
//  RateSnapshot.swift
//  Tenra
//
//  Immutable, point-in-time copy of the FX rate table for bulk conversion loops.
//
//  Two reasons this exists — the second matters more than the first.
//
//  1. Lock traffic. `CurrencyConverter.convertSync` calls
//     `CurrencyRateStore.currentRate(for:)` twice, and each of those takes the store's
//     NSLock. In a walk over 19k transactions that is 38 000 lock acquisitions per pass,
//     plus memory barriers that block the optimiser from hoisting anything out of the
//     loop. Several of these walks run concurrently on detached tasks during launch, so
//     the lock is genuinely contended, not just uncontended-cheap.
//
//  2. Consistency. `convertSync` reads live state. If a prewarm response lands halfway
//     through an aggregate walk, the first half of the set is converted at the old rates
//     and the second half at the new ones, and the resulting total corresponds to no
//     actual point in time. `aggregatesAreFXStale` catches a cold cache, not this. A
//     snapshot pins one rate table for the whole computation.
//
//  Scope: bulk loops only. Single conversions should keep calling
//  `CurrencyConverter.convertSync` — there are hundreds of those and they gain nothing.
//

import Foundation

/// A frozen copy of the KZT-pivot rate table. Take one before a bulk loop, use it for
/// every conversion inside, discard it after.
struct RateSnapshot: Sendable {

    private let rates: [String: Double]

    /// Copies the current rate table. Safe from any actor — `cachedRates` takes the
    /// store's lock once and returns a value-type dictionary.
    nonisolated init() {
        self.rates = CurrencyRateStore.shared.cachedRates
    }

    /// Testing seam: build a snapshot from an explicit table.
    nonisolated init(rates: [String: Double]) {
        self.rates = rates
    }

    /// True when the snapshot was taken against a cold cache. Callers that maintain
    /// `aggregatesAreFXStale` can check this once instead of per transaction.
    nonisolated var isEmpty: Bool { rates.isEmpty }

    /// Same semantics as `CurrencyConverter.convertSync`: nil when either side is missing
    /// from the table, so the caller applies its own documented fallback and flags
    /// FX-staleness. Never silently returns an unconverted amount.
    nonisolated func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let fromRate = rate(for: from),
              let toRate = rate(for: to),
              toRate > 0 else { return nil }
        return amount * fromRate / toRate
    }

    /// KZT is the implicit pivot and is never stored in the table.
    private nonisolated func rate(for currency: String) -> Double? {
        currency == "KZT" ? 1.0 : rates[currency]
    }
}
