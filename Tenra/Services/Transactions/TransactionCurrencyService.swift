//
//  TransactionCurrencyService.swift
//  AIFinanceManager
//
//  PURPOSE: In-memory cache of pre-computed currency amounts for display.
//
//  RESPONSIBILITY SPLIT (do NOT confuse these two currency utilities):
//  ─────────────────────────────────────────────────────────────────────
//  TransactionCurrencyService  (THIS FILE)
//      • Reads the `convertedAmount` field already stored on each Transaction.
//      • NO network calls, NO exchange-rate fetching.
//      • Provides O(1) lookup after a single O(N) precompute pass.
//      • Used by: TransactionQueryService, InsightsService (display layer).
//
//  CurrencyConverter  (Services/Utilities/CurrencyConverter.swift)
//      • Fetches live / historical exchange rates from the National Bank of Kazakhstan API.
//      • Async network calls, XML parsing, 24-hour cache.
//      • Used by: BalanceCalculationEngine for cross-currency balance recalculation.
//  ─────────────────────────────────────────────────────────────────────

import Foundation

/// In-memory display cache for pre-computed transaction amounts in base currency.
/// Reads only from `Transaction.convertedAmount` (set at import/creation time).
/// For live exchange-rate conversion use `CurrencyConverter`.
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
    /// Uses only pre-stored `convertedAmount` — no network requests.
    func precompute(transactions: [Transaction], baseCurrency: String) {
        guard isInvalidated else { return }

        PerformanceProfiler.start("TransactionCurrencyService.precompute")

        var newCache: [String: Double] = [:]
        newCache.reserveCapacity(transactions.count)

        for tx in transactions {
            let key = "\(tx.id)_\(baseCurrency)"
            if tx.currency == baseCurrency {
                newCache[key] = tx.amount
            } else {
                newCache[key] = tx.convertedAmount ?? tx.amount
            }
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

    /// Get converted amount from cache, falling back to transaction data
    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        if let cached = getConvertedAmount(transactionId: transaction.id, to: baseCurrency) {
            return cached
        }
        if transaction.currency == baseCurrency {
            return transaction.amount
        }
        return transaction.convertedAmount ?? transaction.amount
    }
}
