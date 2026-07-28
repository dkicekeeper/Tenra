//
//  CategoryBudgetCurrency.swift
//  Tenra
//
//  One-shot FX conversion for aggregate maintenance.
//
//  Why a dedicated helper:
//  • CategoryAggregate totals are stored in `baseCurrency` (KZT). They MUST NOT
//    use `Transaction.convertedAmount` as a base-currency proxy — that field is
//    denominated in the account's currency, see CLAUDE.md ⚠️ #6.
//  • The aggregate maintenance funnel runs inside `TransactionStore.updateState`
//    on every transaction event; the function is hot and synchronous.
//  • If the FX cache is cold (app just launched, prewarm not finished), we must
//    NOT silently store the wrong unit. We return the raw `amount` as a stand-in
//    and signal staleness so the index can be rebuilt once rates arrive.
//

import Foundation

enum CategoryBudgetCurrency {

    /// Result of a one-shot conversion attempt.
    struct ConversionResult {
        /// Amount in `baseCurrency`, or `amount` if the rate cache is cold AND a
        /// fallback was applied (then `usedStaleFallback` is true).
        let amount: Double

        /// True when the rate cache lacked at least one of the source/target rates
        /// and we returned `amount` unconverted. Aggregates accumulated while this
        /// flag was true should be rebuilt on the next `bumpCurrencyRatesVersion()`.
        let usedStaleFallback: Bool
    }

    /// Convert `amount` from `from` currency to `base` currency.
    /// - If `from == base`: no work, no staleness.
    /// - If rates are available: O(1) hashmap lookup via `CurrencyConverter.convertSync`.
    /// - If rates are cold: return `amount` and flag staleness (caller marks the
    ///   index for FX reconciliation).
    nonisolated static func toBase(amount: Double, from: String, base: String) -> ConversionResult {
        if from == base {
            return ConversionResult(amount: amount, usedStaleFallback: false)
        }
        if let converted = CurrencyConverter.convertSync(amount: amount, from: from, to: base) {
            return ConversionResult(amount: converted, usedStaleFallback: false)
        }
        // Cold cache. Mark stale and accept the raw amount as a stand-in so totals
        // are at least proportional; reconciliation will replace them once rates land.
        return ConversionResult(amount: amount, usedStaleFallback: true)
    }

    /// Bulk-loop variant: identical semantics to `toBase(amount:from:base:)` but reads a
    /// frozen `RateSnapshot` instead of the live store.
    ///
    /// Use this inside any walk over the transaction set. It removes two NSLock
    /// acquisitions per conversion and — more importantly — guarantees every transaction
    /// in the walk is converted against the same rate table, so a prewarm landing
    /// mid-loop cannot produce a total that mixes two different rate generations.
    nonisolated static func toBase(
        amount: Double,
        from: String,
        base: String,
        rates: RateSnapshot
    ) -> ConversionResult {
        if from == base {
            return ConversionResult(amount: amount, usedStaleFallback: false)
        }
        if let converted = rates.convert(amount, from: from, to: base) {
            return ConversionResult(amount: converted, usedStaleFallback: false)
        }
        return ConversionResult(amount: amount, usedStaleFallback: true)
    }
}
