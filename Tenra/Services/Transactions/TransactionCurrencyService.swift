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
//      • NEVER returns raw `convertedAmount` as a base-currency proxy — that field
//        is denominated in the *account*'s currency, not the base currency.
//      • Used by: TransactionQueryService, InsightsService, DateSectionExpensesCache.
//      • Stateless: `CurrencyConverter.convertSync` already reads an in-memory rate
//        cache, so a per-transaction memo here added nothing (it was never populated)
//        and is intentionally absent — there is no conversion result to go stale.
//
//  CurrencyConverter  (Services/Currency/CurrencyConverter.swift)
//      • Fetches live / historical exchange rates from the National Bank of Kazakhstan API.
//      • Async network calls, XML parsing, 24-hour cache.
//      • `convertSync` reads the same in-memory rate cache used here.
//  ─────────────────────────────────────────────────────────────────────

import Foundation

/// Stateless converter for per-transaction amounts into a target base currency.
/// Uses `CurrencyConverter.convertSync` (cache-only, no network) so summation across
/// multi-currency transactions is correct without async hops.
@MainActor
class TransactionCurrencyService {

    /// Converts `transaction.amount` from its currency to `baseCurrency`.
    /// O(1) on the synchronous path (rates are cached inside `CurrencyConverter`).
    func getConvertedAmountOrCompute(transaction: Transaction, to baseCurrency: String) -> Double {
        convertedValue(for: transaction, to: baseCurrency)
    }

    // MARK: - Private

    /// Single source of truth for `tx.amount` → `baseCurrency` conversion.
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
