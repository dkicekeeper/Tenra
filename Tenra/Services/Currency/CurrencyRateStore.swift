//
//  CurrencyRateStore.swift
//  Tenra
//
//  Single source of truth for exchange-rate data. Two halves:
//
//  1. `nonisolated CurrencyRateStore` — thread-safe rate cache used by sync
//     helpers (`CurrencyConverter.convertSync`). Lock-protected dictionary;
//     reads are cheap and lock-free in practice (small critical sections).
//
//  2. `@Observable @MainActor CurrencyRatesNotifier` — UI-side mirror that
//     bumps a `version: Int` whenever rates land. SwiftUI views observing it
//     re-render so currency equivalents update automatically once the
//     pre-warm fetch finishes.
//
//  Convention: rates are stored in KZT-pivot form for backwards compatibility
//  with the existing `convertSync` formula:
//      cachedRates[X] = "how many KZT per 1 X"
//      conversion: amount * fromRate / toRate
//  KZT is implicit (1.0) and is never stored as a key.
//
//  Persistence: UserDefaults key `currency.rates.cache.v1`. Survives restarts;
//  loaded synchronously on first access so `convertSync` works immediately
//  after a warm-launch.
//

import Foundation
import Observation

// MARK: - Persistence DTO

private struct PersistedRates: Codable {
    let pivot: String
    let rates: [String: Double]
    let fetchedAt: Date
    let providerName: String
}

// MARK: - Rate Store (nonisolated, lock-protected)

nonisolated final class CurrencyRateStore: @unchecked Sendable {

    // MARK: Singleton

    /// Shared instance. `nonisolated(unsafe)` because there is exactly one
    /// initializer call (lazy `let`-style init pattern via static dispatch).
    nonisolated(unsafe) static let shared = CurrencyRateStore()

    // MARK: Constants

    private static let userDefaultsKey = "currency.rates.cache.v1"
    /// Stale-but-usable window. Beyond this, `convertSync` still works (fall
    /// back to last-known) but a background refresh is triggered.
    static let cacheValidityHours: TimeInterval = 24 * 60 * 60

    // MARK: State (lock-protected)

    private let lock = NSLock()
    private var _cachedRates: [String: Double] = [:]
    private var _lastUpdated: Date?
    private var _historicalRates: [String: [String: Double]] = [:]
    private var _lastProviderName: String?

    // MARK: Init

    init() {
        loadFromDisk()
    }

    // MARK: Public reads (thread-safe)

    /// Snapshot of current rates in KZT-pivot form. Empty until first fetch
    /// or first successful disk-restore.
    var cachedRates: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return _cachedRates
    }

    var lastUpdated: Date? {
        lock.lock(); defer { lock.unlock() }
        return _lastUpdated
    }

    var lastProviderName: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastProviderName
    }

    /// True if cached rates are present AND fetched within the validity window.
    var hasFreshRates: Bool {
        lock.lock(); defer { lock.unlock() }
        guard !_cachedRates.isEmpty, let updated = _lastUpdated else { return false }
        return Date().timeIntervalSince(updated) < Self.cacheValidityHours
    }

    /// Fast-path lookup. Returns nil if the currency isn't in the cache.
    /// `KZT` returns 1.0 because it is the implicit pivot.
    func currentRate(for currency: String) -> Double? {
        if currency == "KZT" { return 1.0 }
        lock.lock(); defer { lock.unlock() }
        return _cachedRates[currency]
    }

    /// Historical rate for a specific date. Returns nil if not previously fetched.
    func historicalRate(for currency: String, dateKey: String) -> Double? {
        if currency == "KZT" { return 1.0 }
        lock.lock(); defer { lock.unlock() }
        return _historicalRates[dateKey]?[currency]
    }

    /// Snapshot of historical rates for a specific date.
    func historicalRates(forDateKey dateKey: String) -> [String: Double]? {
        lock.lock(); defer { lock.unlock() }
        return _historicalRates[dateKey]
    }

    // MARK: Public writes

    /// Atomically replaces the current rate snapshot. Triggers persistence and
    /// MainActor notifier bump for UI reactivity.
    func updateCurrentRates(_ rates: ExchangeRates) {
        // Re-pivot to KZT — this is the internal storage convention.
        guard let normalized = rates.normalized(toPivot: "KZT") else {
            // Provider couldn't be normalized to KZT (KZT not present in rates
            // and not the source pivot). Don't overwrite a good cache with garbage.
            return
        }

        lock.lock()
        _cachedRates = normalized
        _lastUpdated = Date()
        _lastProviderName = rates.providerName
        let snapshot = (normalized, _lastUpdated!, rates.providerName)
        lock.unlock()

        persistToDisk(rates: snapshot.0, fetchedAt: snapshot.1, providerName: snapshot.2)
        Task { @MainActor in
            CurrencyRatesNotifier.shared.didUpdate(at: snapshot.1, providerName: snapshot.2)
        }
    }

    /// Stores a historical snapshot keyed by date string (yyyy-MM-dd).
    /// Historical rates are NOT persisted to disk in this version (they are
    /// large and rarely re-used between launches).
    func updateHistoricalRates(_ rates: ExchangeRates, dateKey: String) {
        guard let normalized = rates.normalized(toPivot: "KZT") else { return }
        lock.lock()
        _historicalRates[dateKey] = normalized
        lock.unlock()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else {
            return
        }
        guard let decoded = try? JSONDecoder().decode(PersistedRates.self, from: data) else {
            return
        }

        lock.lock()
        _cachedRates = decoded.rates
        _lastUpdated = decoded.fetchedAt
        _lastProviderName = decoded.providerName
        lock.unlock()

        // Mirror the disk-restored snapshot to the UI notifier so views that
        // observe it (and were instantiated before the first fetch) start with
        // a non-zero version.
        let snapshot = (decoded.fetchedAt, decoded.providerName)
        Task { @MainActor in
            CurrencyRatesNotifier.shared.didRestore(at: snapshot.0, providerName: snapshot.1)
        }
    }

    private func persistToDisk(rates: [String: Double], fetchedAt: Date, providerName: String) {
        let payload = PersistedRates(
            pivot: "KZT",
            rates: rates,
            fetchedAt: fetchedAt,
            providerName: providerName
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    /// Wipes both in-memory and on-disk caches. Used by Settings → Reset.
    func clearAll() {
        lock.lock()
        _cachedRates = [:]
        _lastUpdated = nil
        _historicalRates = [:]
        _lastProviderName = nil
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        Task { @MainActor in CurrencyRatesNotifier.shared.didClear() }
    }
}

// MARK: - UI Notifier (Observable)

/// Lightweight `@Observable` mirror of the rate store. Views that need to
/// re-render when rates land observe `version` (or `lastUpdated`) — a single
/// scalar that bumps on every successful fetch / disk restore / clear.
///
/// Why split from `CurrencyRateStore`?
/// - The store is `nonisolated` so `convertSync` callers from background
///   threads (RecurringTransactionGenerator, SubscriptionTransactionMatcher)
///   can read it directly.
/// - The notifier is MainActor-isolated and `@Observable` so SwiftUI views
///   participate in the change-tracking system.
@Observable
@MainActor
final class CurrencyRatesNotifier {
    static let shared = CurrencyRatesNotifier()

    /// Monotonically increasing version. Views observe this for reactivity.
    private(set) var version: Int = 0
    /// Timestamp of the latest update (or restore). Useful for "rates from N
    /// minutes ago" UI in Settings.
    private(set) var lastUpdated: Date?
    /// Provider that produced the most recent successful fetch.
    private(set) var lastProviderName: String?
    /// True while a pre-warm or refresh is in flight. Toggles for spinner UI.
    private(set) var isFetching: Bool = false

    private init() {}

    func setFetching(_ fetching: Bool) {
        isFetching = fetching
    }

    func didUpdate(at date: Date, providerName: String) {
        lastUpdated = date
        lastProviderName = providerName
        version &+= 1
    }

    func didRestore(at date: Date, providerName: String) {
        lastUpdated = date
        lastProviderName = providerName
        version &+= 1
    }

    func didClear() {
        lastUpdated = nil
        lastProviderName = nil
        version &+= 1
    }
}
