//
//  CurrencyRateProvider.swift
//  Tenra
//
//  Provider abstraction for fetching exchange rates from various sources
//  (jsDelivr, Frankfurter, National Bank of Kazakhstan, ...).
//
//  Convention used throughout the currency layer:
//      rates[X] = "how many `pivot` you receive for 1 unit of X"
//  Example: pivot = "KZT", rates["USD"] = 442.5  ⇒  1 USD = 442.5 KZT.
//
//  The pivot key itself is implicit (1.0) and is NOT stored in `rates`.
//

import Foundation

// MARK: - ExchangeRates

/// Normalized exchange-rate snapshot returned by every provider.
struct ExchangeRates: Sendable {
    /// Pivot currency code, e.g. "KZT", "USD".
    let pivot: String
    /// `rates[X] = pivot per 1 X`. Does NOT include the pivot itself.
    let rates: [String: Double]
    /// Date the rates are valid for. May differ from `Date()` for historical fetches.
    let date: Date
    /// Provider identifier (for logging/diagnostics).
    let providerName: String

    /// Re-pivot to a different currency. Returns a new `[code: Double]` dictionary
    /// in the same convention (`new[X] = newPivot per 1 X`).
    ///
    /// Returns `nil` when the new pivot is not present in `rates` and is not the
    /// current pivot — i.e. there is not enough information to do the conversion.
    func normalized(toPivot newPivot: String) -> [String: Double]? {
        if pivot == newPivot { return rates }
        guard let newPivotInOldPivot = rates[newPivot], newPivotInOldPivot > 0 else {
            return nil
        }

        var result: [String: Double] = [:]
        result.reserveCapacity(rates.count)
        // Existing currencies: new[X] = old[X] / old[newPivot]
        for (code, value) in rates where code != newPivot {
            result[code] = value / newPivotInOldPivot
        }
        // Old pivot becomes a regular currency: new[oldPivot] = 1 / old[newPivot]
        result[pivot] = 1.0 / newPivotInOldPivot
        return result
    }
}

// MARK: - Provider Errors

enum CurrencyProviderError: Error, Sendable {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case parseError(String)
    case rateNotFound
    case providerDisabled
    case allProvidersFailed([String])
}

// MARK: - Protocol

/// Protocol every exchange-rate provider conforms to. Implementations MUST be
/// `Sendable` and safe to call from any concurrency context (we route them
/// through `Task.detached`).
protocol CurrencyRateProvider: Sendable {
    /// Identifier for logging (e.g. "jsdelivr", "nbk").
    var name: String { get }
    /// Fetch the snapshot of rates for `date` (nil ⇒ today).
    func fetchRates(on date: Date?) async throws -> ExchangeRates
}

// MARK: - Provider Chain

/// Tries providers in order until one succeeds. Mirrors `LogoProviderChain`
/// (Services/Logo/) — same fallback pattern, different domain.
nonisolated final class CurrencyRateProviderChain: Sendable {
    let providers: [any CurrencyRateProvider]

    init(providers: [any CurrencyRateProvider]) {
        self.providers = providers
    }

    /// Walks through providers in order, returning the first successful result
    /// along with the provider name that produced it. On total failure, throws
    /// `.allProvidersFailed` with diagnostic strings.
    func fetchRates(on date: Date? = nil) async throws -> ExchangeRates {
        var failures: [String] = []
        for provider in providers {
            do {
                return try await provider.fetchRates(on: date)
            } catch {
                failures.append("\(provider.name): \(error)")
                continue
            }
        }
        throw CurrencyProviderError.allProvidersFailed(failures)
    }
}
