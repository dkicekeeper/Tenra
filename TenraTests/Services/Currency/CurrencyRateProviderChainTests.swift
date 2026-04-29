//
//  CurrencyRateProviderChainTests.swift
//  TenraTests
//
//  Verifies that `CurrencyRateProviderChain` falls through to the next provider
//  on failure and preserves first-success semantics.
//

import Testing
import Foundation
@testable import Tenra

struct CurrencyRateProviderChainTests {

    // MARK: - Helpers

    private struct StubProvider: CurrencyRateProvider {
        let name: String
        let result: Result<ExchangeRates, Error>

        func fetchRates(on date: Date?) async throws -> ExchangeRates {
            switch result {
            case .success(let rates): return rates
            case .failure(let err):  throw err
            }
        }
    }

    private static func makeRates(pivot: String, providerName: String) -> ExchangeRates {
        ExchangeRates(
            pivot: pivot,
            rates: ["USD": 442.5],
            date: Date(),
            providerName: providerName
        )
    }

    // MARK: - First success short-circuits the chain

    @Test("Chain returns first successful provider's result")
    func firstSuccessShortCircuits() async throws {
        let chain = CurrencyRateProviderChain(providers: [
            StubProvider(name: "primary",   result: .success(Self.makeRates(pivot: "KZT", providerName: "primary"))),
            StubProvider(name: "secondary", result: .success(Self.makeRates(pivot: "KZT", providerName: "secondary")))
        ])

        let result = try await chain.fetchRates(on: nil)
        #expect(result.providerName == "primary")
    }

    // MARK: - Falls through on failure

    @Test("Chain falls through to next provider on failure")
    func fallsThroughOnFailure() async throws {
        let chain = CurrencyRateProviderChain(providers: [
            StubProvider(name: "broken",   result: .failure(CurrencyProviderError.networkError(NSError(domain: "test", code: 1)))),
            StubProvider(name: "fallback", result: .success(Self.makeRates(pivot: "KZT", providerName: "fallback")))
        ])

        let result = try await chain.fetchRates(on: nil)
        #expect(result.providerName == "fallback")
    }

    // MARK: - All-fail throws aggregate error

    @Test("All providers failing raises allProvidersFailed")
    func allProvidersFailing() async {
        let chain = CurrencyRateProviderChain(providers: [
            StubProvider(name: "a", result: .failure(CurrencyProviderError.invalidResponse)),
            StubProvider(name: "b", result: .failure(CurrencyProviderError.parseError("bad")))
        ])

        do {
            _ = try await chain.fetchRates(on: nil)
            Issue.record("Expected throw, got success")
        } catch CurrencyProviderError.allProvidersFailed(let failures) {
            #expect(failures.count == 2)
            #expect(failures.contains(where: { $0.contains("a") }))
            #expect(failures.contains(where: { $0.contains("b") }))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Empty chain throws

    @Test("Empty chain throws allProvidersFailed with empty failures list")
    func emptyChainThrows() async {
        let chain = CurrencyRateProviderChain(providers: [])
        do {
            _ = try await chain.fetchRates(on: nil)
            Issue.record("Expected throw, got success")
        } catch CurrencyProviderError.allProvidersFailed(let failures) {
            #expect(failures.isEmpty)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
