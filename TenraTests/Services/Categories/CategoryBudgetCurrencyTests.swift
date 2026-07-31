//
//  CategoryBudgetCurrencyTests.swift
//  TenraTests
//
//  The aggregate maintenance funnel routes every tx through `toBase` once.
//  These tests guarantee:
//   • Identity case (currency == base) returns amount as-is, no stale flag.
//   • Cold-cache case (rates unavailable) returns `amount` AND flags stale —
//     never silently writes the wrong unit into an aggregate. See CLAUDE.md ⚠️ #6.
//

import Testing
@testable import Tenra

@Suite(.sharedProcessState)
struct CategoryBudgetCurrencyTests {

    @Test("identity conversion: amount preserved, not flagged stale")
    func identityConversion() {
        let result = CategoryBudgetCurrency.toBase(amount: 1234.56, from: "KZT", base: "KZT")
        #expect(result.amount == 1234.56)
        #expect(result.usedStaleFallback == false)
    }

    @Test("cold-cache conversion flags stale fallback and returns raw amount")
    func coldCacheFallback() {
        // Ensure no rates are loaded. The shared store is mutable global state;
        // clear it for the duration of the test.
        CurrencyRateStore.shared.clearAll()
        let result = CategoryBudgetCurrency.toBase(amount: 500.0, from: "USD", base: "KZT")
        #expect(result.amount == 500.0)
        #expect(result.usedStaleFallback == true)
    }
}
