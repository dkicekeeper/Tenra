//
//  CurrencyConverter.swift
//  Tenra
//
//  Static facade over `CurrencyRateStore` + `CurrencyRateProviderChain`.
//
//  RESPONSIBILITY SPLIT (three currency utilities — do NOT confuse them):
//  ─────────────────────────────────────────────────────────────────────
//  CurrencyConverter (THIS FILE) — public API used everywhere
//      • Static helpers: `convertSync`, `getExchangeRate`, `convert`,
//        `getAllRates`, plus the new `prewarm` entry-point.
//      • No state of its own — delegates to `CurrencyRateStore.shared`.
//      • Backwards-compatible call sites: zero changes to existing callers.
//
//  CurrencyRateStore (Services/Currency/CurrencyRateStore.swift)
//      • Lock-protected rate cache + UserDefaults persistence.
//      • Survives app restarts so `convertSync` works at T=0 on warm launch.
//      • Bumps `CurrencyRatesNotifier` (Observable) on every update so
//        SwiftUI views re-render once rates arrive.
//
//  TransactionCurrencyService (Services/Transactions/)
//      • NO network calls. Reads `Transaction.convertedAmount` already
//        persisted on the entity. Used by display layer.
//  ─────────────────────────────────────────────────────────────────────
//
//  Provider chain order (fastest+widest first):
//      1. JsDelivr (200+ currencies, public CDN, no auth, USD-pivot)
//      2. NationalBankKZ (legacy, KZT-resident fallback, 8 currencies)
//
//  Public API contract unchanged:
//      `convertSync(amount:from:to:)`        — cache-only sync conversion
//      `getExchangeRate(for:on:)`            — async fetch with caching
//      `convert(amount:from:to:on:)`         — async conversion
//      `getAllRates()`                       — async snapshot
//
//  New API:
//      `prewarm()`                            — fetch+populate on app start
//      `currentRatesAreFresh`                 — read-only freshness flag
//

import Foundation
import os

nonisolated final class CurrencyConverter: @unchecked Sendable {

    // MARK: - Provider chain (lazy, shared)

    private static let logger = Logger(subsystem: "Tenra", category: "CurrencyConverter")

    /// Default provider chain. jsDelivr first (broadest coverage), NBK as
    /// last-resort fallback. Never call providers directly from outside —
    /// always through this chain so retries and fallbacks fire.
    nonisolated(unsafe) static var providerChain: CurrencyRateProviderChain = {
        CurrencyRateProviderChain(providers: [
            JsDelivrCurrencyProvider(apiBase: "USD"),
            NationalBankKZProvider()
        ])
    }()

    // MARK: - In-flight de-duplication

    /// Coalesces concurrent `getExchangeRate(...)` callers waiting on the same
    /// network fetch (e.g. UI components all asking for "today" at once).
    /// Keyed by `dateKey` ("today" or "yyyy-MM-dd"). Cleared on completion.
    nonisolated(unsafe) private static var inflight: [String: Task<ExchangeRates?, Never>] = [:]
    private static let inflightLock = NSLock()

    // MARK: - Public API (back-compat)

    /// Get the rate for a single currency, KZT-pivot. `nil` on failure.
    /// Caches every successful response in `CurrencyRateStore`.
    static func getExchangeRate(for currency: String, on date: Date? = nil) async -> Double? {
        if currency == "KZT" { return 1.0 }

        let store = CurrencyRateStore.shared
        let isHistorical = !(date == nil || Calendar.current.isDateInToday(date!))

        // Cache hit
        if isHistorical {
            let key = Self.dateKey(for: date!)
            if let cached = store.historicalRate(for: currency, dateKey: key) {
                return cached
            }
        } else {
            if store.hasFreshRates, let cached = store.currentRate(for: currency) {
                return cached
            }
        }

        // Cache miss → fetch through provider chain (de-duped).
        let snapshot = await fetchRatesDeduped(on: date)
        if let snapshot {
            return snapshot.normalized(toPivot: "KZT")?[currency]
        }

        // Provider failed → fall back to whatever is in cache (stale-while-revalidate).
        if isHistorical {
            return store.historicalRate(for: currency, dateKey: Self.dateKey(for: date!))
        } else {
            return store.currentRate(for: currency)
        }
    }

    /// Async conversion. Tries cache-only first, then falls through to
    /// `getExchangeRate(...)` which may hit the network.
    static func convert(amount: Double, from: String, to: String, on date: Date? = nil) async -> Double? {
        if from == to { return amount }

        // Fast path — cache-only.
        if date == nil, let result = convertSync(amount: amount, from: from, to: to) {
            return result
        }

        guard let fromRate = await getExchangeRate(for: from, on: date),
              let toRate   = await getExchangeRate(for: to,   on: date),
              toRate > 0 else {
            return nil
        }
        return amount * fromRate / toRate
    }

    /// Synchronous, cache-only conversion. Returns nil if either currency is
    /// missing from the cache. Safe to call from any actor.
    static func convertSync(amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        let store = CurrencyRateStore.shared
        guard let fromRate = store.currentRate(for: from),
              let toRate   = store.currentRate(for: to),
              toRate > 0 else {
            return nil
        }
        return amount * fromRate / toRate
    }

    /// Snapshot of every cached rate (KZT-pivot). Triggers a fetch if cache is empty/stale.
    static func getAllRates() async -> [String: Double] {
        if !CurrencyRateStore.shared.hasFreshRates {
            _ = await fetchRatesDeduped(on: nil)
        }
        return CurrencyRateStore.shared.cachedRates
    }

    // MARK: - New: Pre-warm

    /// Pre-populate the rate cache. Call once during app startup (after the
    /// fast-path UI is visible, in parallel with the heavy data load).
    /// Idempotent: if cache is already fresh, returns immediately without
    /// hitting the network. If cache is empty but a previous fetched-rate
    /// snapshot was restored from disk, this does a background refresh.
    static func prewarm() async {
        let store = CurrencyRateStore.shared
        if store.hasFreshRates {
            logger.debug("prewarm skipped — cache fresh (provider=\(store.lastProviderName ?? "?", privacy: .public))")
            return
        }
        await MainActor.run { CurrencyRatesNotifier.shared.setFetching(true) }
        let result = await fetchRatesDeduped(on: nil)
        await MainActor.run { CurrencyRatesNotifier.shared.setFetching(false) }

        if let result {
            logger.info("prewarm fetched \(result.rates.count, privacy: .public) rates from \(result.providerName, privacy: .public)")
        } else if !store.cachedRates.isEmpty {
            logger.debug("prewarm failed but disk cache present — using stale rates")
        } else {
            logger.error("prewarm failed and disk cache empty — convertSync will return nil")
        }
    }

    /// Whether the in-memory rate cache is non-empty AND <24h old.
    static var currentRatesAreFresh: Bool {
        CurrencyRateStore.shared.hasFreshRates
    }

    // MARK: - Internal helpers

    /// Coalesces concurrent fetches for the same date. Stores both the
    /// snapshot (current rates → store, historical → store) on success.
    @discardableResult
    private static func fetchRatesDeduped(on date: Date?) async -> ExchangeRates? {
        let isHistorical = !(date == nil || Calendar.current.isDateInToday(date!))
        let key = isHistorical ? Self.dateKey(for: date!) : "__today__"

        inflightLock.lock()
        if let existing = inflight[key] {
            inflightLock.unlock()
            return await existing.value
        }

        let task = Task<ExchangeRates?, Never> { @Sendable in
            let snapshot: ExchangeRates?
            do {
                snapshot = try await providerChain.fetchRates(on: date)
            } catch {
                logger.error("provider chain failed: \(String(describing: error), privacy: .public)")
                snapshot = nil
            }

            if let snapshot {
                if isHistorical {
                    CurrencyRateStore.shared.updateHistoricalRates(snapshot, dateKey: key)
                } else {
                    CurrencyRateStore.shared.updateCurrentRates(snapshot)
                }
            }
            return snapshot
        }
        inflight[key] = task
        inflightLock.unlock()

        let result = await task.value
        inflightLock.lock()
        inflight.removeValue(forKey: key)
        inflightLock.unlock()
        return result
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
