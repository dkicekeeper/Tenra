//
//  SubscriptionTransactionMatcherTests.swift
//  TenraTests
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct SubscriptionTransactionMatcherTests {

    init() {
        // General hygiene: `CurrencyRateStore` persists rates to UserDefaults
        // and is a process-wide singleton, so a previous run (or another
        // suite) may have populated it. Clearing here keeps the same-/different-
        // currency tests deterministic. NOTE: this is NOT sufficient on its own
        // for `findCandidates_matchesCrossCurrencyViaConvertedAmount` — see the
        // clear inside that test body for why.
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Helpers

    private func makeSubscription(
        amount: Decimal = 9.99,
        startDate: String = "2024-01-01",
        currency: String = "USD"
    ) -> RecurringSeries {
        RecurringSeries(
            id: "sub-1",
            amount: amount,
            currency: currency,
            category: "Entertainment",
            description: "Netflix",
            frequency: .monthly,
            startDate: startDate,
            kind: .subscription,
            status: .active
        )
    }

    private func makeTransaction(
        id: String = UUID().uuidString,
        date: String,
        amount: Double,
        type: TransactionType = .expense,
        currency: String = "USD",
        recurringSeriesId: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "Payment",
            amount: amount,
            currency: currency,
            type: type,
            category: "Entertainment",
            recurringSeriesId: recurringSeriesId
        )
    }

    // MARK: - findCandidates

    @Test func findCandidates_matchesExpensesWithinTolerance() {
        let sub = makeSubscription(amount: 9.99, startDate: "2024-01-01")
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99),
            makeTransaction(date: "2024-03-01", amount: 9.50),  // within 10%
            makeTransaction(date: "2024-04-01", amount: 5.00),  // outside 10%
            makeTransaction(date: "2024-05-01", amount: 15.00), // outside 10%
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(
            for: sub,
            in: transactions
        )

        #expect(candidates.count == 2)
        #expect(candidates[0].amount == 9.99)
        #expect(candidates[1].amount == 9.50)
    }

    @Test func findCandidates_excludesNonExpenses() {
        let sub = makeSubscription()
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99, type: .income),
            makeTransaction(date: "2024-02-02", amount: 9.99, type: .internalTransfer),
            makeTransaction(date: "2024-02-03", amount: 9.99, type: .expense),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].type == .expense)
    }

    @Test func findCandidates_includesTransactionsBeforeStartDate() {
        let sub = makeSubscription(startDate: "2024-06-01")
        let transactions = [
            makeTransaction(date: "2024-05-01", amount: 9.99),
            makeTransaction(date: "2024-07-01", amount: 9.99),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        // No date filter — retroactive linking finds old transactions too
        #expect(candidates.count == 2)
        #expect(candidates[0].date == "2024-05-01")
        #expect(candidates[1].date == "2024-07-01")
    }

    @Test func findCandidates_excludesDifferentCurrency() {
        let sub = makeSubscription(currency: "USD")
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99, currency: "USD"),
            makeTransaction(date: "2024-02-02", amount: 9.99, currency: "KZT"),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].currency == "USD")
    }

    @Test func findCandidates_excludesAlreadyLinked() {
        let sub = makeSubscription()
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99, recurringSeriesId: nil),
            makeTransaction(date: "2024-03-01", amount: 9.99, recurringSeriesId: "other-series"),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].recurringSeriesId == nil)
    }

    @Test func findCandidates_sortsByDate() {
        let sub = makeSubscription()
        let transactions = [
            makeTransaction(date: "2024-04-01", amount: 9.99),
            makeTransaction(date: "2024-02-01", amount: 9.99),
            makeTransaction(date: "2024-03-01", amount: 9.99),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates[0].date == "2024-02-01")
        #expect(candidates[1].date == "2024-03-01")
        #expect(candidates[2].date == "2024-04-01")
    }

    @Test func findCandidates_exactMatchOnlyMatchesExactAmount() {
        let sub = makeSubscription(amount: 9.99)
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99),
            makeTransaction(date: "2024-03-01", amount: 9.50),  // within 10% but not exact
            makeTransaction(date: "2024-04-01", amount: 10.49), // within 10% but not exact
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(
            for: sub,
            in: transactions,
            mode: .exact
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].amount == 9.99)
    }

    @Test func findCandidates_matchesCrossCurrencyViaConvertedAmount() {
        // This test exercises the `convertedAmount` fallback, which only fires
        // when `convertSync(USD→KZT)` returns nil — i.e. when NO USD↔KZT rate is
        // cached. The suite `init()` clears the singleton, but Swift Testing can
        // run a sibling @MainActor suite (e.g. CurrencyRateStorePersistenceTests)
        // that re-populates `CurrencyRateStore.shared` AFTER this init() and
        // BEFORE the matcher call below. Clear again right before the assertion so
        // the miss path is guaranteed regardless of inter-suite ordering.
        CurrencyRateStore.shared.clearAll()

        // Subscription is $100 USD, transaction is in KZT with convertedAmount = 100
        let sub = makeSubscription(amount: 100, currency: "USD")
        let kztTransaction = Transaction(
            id: "cross-1",
            date: "2024-02-01",
            description: "Payment",
            amount: 50_000,
            currency: "KZT",
            convertedAmount: 100,
            type: .expense,
            category: "Entertainment"
        )
        let usdTransaction = makeTransaction(date: "2024-03-01", amount: 100, currency: "USD")
        let unrelatedKzt = Transaction(
            id: "cross-2",
            date: "2024-04-01",
            description: "Other",
            amount: 50_000,
            currency: "KZT",
            convertedAmount: 200, // doesn't match
            type: .expense,
            category: "Entertainment"
        )

        let candidates = SubscriptionTransactionMatcher.findCandidates(
            for: sub,
            in: [kztTransaction, usdTransaction, unrelatedKzt]
        )

        #expect(candidates.count == 2)
        // USD direct match + KZT via convertedAmount
        #expect(candidates.contains(where: { $0.id == "cross-1" }))
        #expect(candidates.contains(where: { $0.currency == "USD" }))
    }
}
