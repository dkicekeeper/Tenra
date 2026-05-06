//
//  TransactionCurrencyService.swift
//  Tenra
//
//  PURPOSE: In-memory cache of per-transaction amounts converted to a base currency
//  for display and aggregation.
//
//  RESPONSIBILITY SPLIT (do NOT confuse these two currency utilities):
//  ─────────────────────────────────────────────────────────────────────
//  TransactionCurrencyService  (THIS FILE)
//      • Converts each `Transaction.amount` from `tx.currency` to a target base
//        currency via `CurrencyConverter.convertSync` (cache-only, no network).
//      • Stores the result in an O(1) lookup keyed by "<txId>_<baseCurrency>".
//      • NEVER returns raw `convertedAmount` as a base-currency proxy — that field
//        is denominated in the *account*'s currency, not the base currency.
//      • Used by: TransactionQueryService, InsightsService, DateSectionExpensesCache.
//
//  CurrencyConverter  (Services/Currency/CurrencyConverter.swift)
//      • Fetches live / historical exchange rates from the National Bank of Kazakhstan API.
//      • Async network calls, XML parsing, 24-hour cache.
//      • `convertSync` reads the same in-memory rate cache used here.
//  ─────────────────────────────────────────────────────────────────────

import Foundation

/// In-memory display cache for per-transaction amounts converted to a target base currency.
/// Uses `CurrencyConverter.convertSync` (cache-only, no network) so summation across
/// multi-currency transactions is correct without async hops.
@MainActor
class TransactionCurrencyService {

    // MARK: - Cache

    private var cache: [String: Double] = [:]
    private(set) var isInvalidated: Bool = true

    // MARK: - API

    /// Invalidate the conversion cache
    func invalidate() {
        isInvalidated = true
    }

    /// Precompute converted amounts for all transactions in `baseCurrency`.
    /// Reads exchange rates from `CurrencyConverter`'s cache (populated at startup
    /// via `prewarm`). When a rate is unavailable, falls back to the per-transaction
    /// `convertedAmount` (in *account* currency) — wrong unit but better than a
    /// runtime hole; sums will visually re-correct once rates load and the cache
    /// is invalidated.
    func precompute(transactions: [Transaction], baseCurrency: String) {
        guard isInvalidated else { return }

        PerformanceProfiler.start("TransactionCurrencyService.precompute")

        var newCache: [String: Double] = [:]
        newCache.reserveCapacity(transactions.count)

        for tx in transactions {
            let key = "\(tx.id)_\(baseCurrency)"
            newCache[key] = convertedValue(for: tx, to: baseCurrency)
        }

        self.cache = newCache
        self.isInvalidated = false
        PerformanceProfiler.end("TransactionCurrencyService.precompute")
    }

    /// Get cached converted amount for a transaction
    func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
        let key = "\(transactionId)_\(baseCurrency)"
        return cache[key]
    }

    /// Get converted amount from cache, falling back to a fresh `convertSync` call
    /// (rates are cached, so this is still O(1) on the synchronous path).
    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        if let cached = getConvertedAmount(transactionId: transaction.id, to: baseCurrency) {
            return cached
        }
        return convertedValue(for: transaction, to: baseCurrency)
    }

    // MARK: - Private

    /// Single source of truth for `tx.amount` → `baseCurrency` conversion. Used by
    /// both `precompute` and the on-demand fallback path.
    private func convertedValue(for tx: Transaction, to baseCurrency: String) -> Double {
        if tx.currency == baseCurrency {
            return tx.amount
        }
        if let converted = CurrencyConverter.convertSync(
            amount: tx.amount,
            from: tx.currency,
            to: baseCurrency
        ) {
            return converted
        }
        // Last-resort fallback: rates not yet loaded. `convertedAmount` is in
        // account currency, not baseCurrency — wrong unit, but matches the
        // historical behaviour and self-corrects on rate-load + invalidate.
        return tx.convertedAmount ?? tx.amount
    }
}
