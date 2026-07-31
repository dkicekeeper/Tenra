//
//  InsightsFXStaleResolverTests.swift
//  TenraTests
//
//  H-7 residual: the Insights cold-FX-cache fallback must NOT blend mismatched
//  units into a base-currency total. `Transaction.convertedAmount` is in the
//  *account* currency (CLAUDE.md ⚠️ #6) — summing it as base currency yields a
//  wrong-unit total (e.g. $20 + $100 = "120 KZT"). On a `convertSync` miss the
//  resolver must skip the tx (contribute 0) AND flag the result FX-stale so it
//  is recomputed on the next FX-version bump (M-9 unified that trigger).
//

import Testing
import Foundation
@testable import Tenra

// @MainActor so these synchronous tests serialize on the main actor with the other
// suites that mutate the process-wide `CurrencyRateStore.shared` (the persistence and
// matcher suites are already @MainActor) — otherwise a concurrent write/clear here
// races their assertions.
@Suite("Insights FX-stale resolver (H-7 residual)", .serialized, .sharedProcessState)
@MainActor
struct InsightsFXStaleResolverTests {

    private let base = "KZT"

    private func makeTx(
        amount: Double,
        currency: String,
        convertedAmount: Double?,
        type: TransactionType = .expense,
        date: String,
        category: String = "Food"
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString,
            date: date,
            description: "Test",
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: type,
            category: category,
            subcategory: nil,
            accountId: "acc-1",
            accountName: "Acc",
            createdAt: 1_700_000_000
        )
    }

    private func pastDateString() -> String {
        let d = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        return DateFormatters.dateFormatter.string(from: d)
    }

    // MARK: - Cold cache must not blend account-currency convertedAmount as base

    @Test("cold cache: cross-currency resolver returns 0, never convertedAmount-as-base")
    func coldCacheStaticDoesNotBlend() {
        CurrencyRateStore.shared.clearAll()
        // 100 USD with a stale convertedAmount of 200 (in account currency, e.g. EUR).
        // If we blended, the base-currency total would wrongly become 200 KZT.
        let tx = makeTx(amount: 100, currency: "USD", convertedAmount: 200, date: pastDateString())

        let result = InsightsService.resolveAmountToBase(tx, baseCurrency: base)
        #expect(result.usedStaleFallback == true)
        #expect(result.amount == 0, "Cross-currency miss must contribute 0, not the account-currency convertedAmount")
    }

    @Test("same-currency tx never flagged stale and keeps its amount")
    func sameCurrencyNotStale() {
        CurrencyRateStore.shared.clearAll()
        let tx = makeTx(amount: 500, currency: base, convertedAmount: nil, date: pastDateString())
        let result = InsightsService.resolveAmountToBase(tx, baseCurrency: base)
        #expect(result.usedStaleFallback == false)
        #expect(result.amount == 500)
    }

    @Test("warm cache: cross-currency converts via convertSync, not stale")
    func warmCacheConverts() {
        let store = CurrencyRateStore.shared
        defer { store.clearAll() }

        let tx = makeTx(amount: 100, currency: "USD", convertedAmount: 999, date: pastDateString())

        // `CurrencyRateStore.shared` is a global singleton; a parallel currency suite can
        // call clearAll() between our rate-set and our read (CLAUDE.md documents this
        // shared-state hazard). Re-establish the rate until the conversion sees it, so the
        // test is deterministic without serializing across suites.
        var result = InsightsService.resolveAmountToBase(tx, baseCurrency: base)
        for _ in 0..<100 where result.usedStaleFallback {
            store.updateCurrentRates(ExchangeRates(
                pivot: "KZT",
                rates: ["USD": 442.5],
                date: Date(),
                providerName: "test"
            ))
            result = InsightsService.resolveAmountToBase(tx, baseCurrency: base)
        }

        #expect(result.usedStaleFallback == false)
        #expect(abs(result.amount - 100 * 442.5) < 0.001)
    }

    // MARK: - PreAggregatedData marks fxStale on a cold cross-currency miss

    @Test("PreAggregatedData flags fxStale and excludes the wrong-unit tx on cold cache")
    func preAggregatedFlagsStaleAndSkips() {
        CurrencyRateStore.shared.clearAll()
        let date = pastDateString()
        // One same-currency expense (300 KZT) and one cross-currency expense
        // (100 USD, stale convertedAmount 5000). On cold cache the USD tx must
        // be skipped (not summed as 5000 KZT) and the result flagged stale.
        let txs = [
            makeTx(amount: 300, currency: base, convertedAmount: nil, date: date),
            makeTx(amount: 100, currency: "USD", convertedAmount: 5000, date: date),
        ]
        let pre = InsightsService.PreAggregatedData.build(from: txs, baseCurrency: base)
        let totalExpenses = pre.monthlyTotals.values.reduce(0) { $0 + $1.expenses }
        #expect(pre.fxStale == true, "Cold cross-currency miss must flag the snapshot FX-stale")
        #expect(abs(totalExpenses - 300) < 0.001, "Wrong-unit USD tx must be skipped, not blended (would be 5300)")
    }
}
