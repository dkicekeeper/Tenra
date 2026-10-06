//
//  LinkPaymentsSelectedTotalTests.swift
//  TenraTests
//
//  The link-payments screen's "N selected · total" summed `convertedAmount` as if it
//  were base currency, before trying the rate. That field is in the ACCOUNT's currency
//  (CLAUDE.md red flag 6): a 10 USD payment from a euro card added ~9 "tenge".
//
//  @MainActor + .sharedProcessState: conversion reads the process-global
//  CurrencyRateStore.shared, seeded per test and cleared in init (CLAUDE.md "Testing").
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct LinkPaymentsSelectedTotalTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    private func payment(amount: Double, currency: String, convertedAmount: Double?) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: "2026-09-01", description: "Service",
            amount: amount, currency: currency, convertedAmount: convertedAmount,
            type: .expense, category: "Subscriptions", accountId: "card"
        )
    }

    @Test("a foreign payment is converted to base currency, not summed via convertedAmount")
    func foreignPaymentUsesRate() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500, "EUR": 550],
            date: Date(),
            providerName: "test"
        ))
        // 10 USD paid from a euro card: convertedAmount holds euros.
        let fromEuroCard = payment(amount: 10, currency: "USD", convertedAmount: 5_000.0 / 550.0)
        #expect(LinkPaymentsView.amountInBaseCurrency(fromEuroCard, base: "KZT") == 5_000)

        let local = payment(amount: 700, currency: "KZT", convertedAmount: nil)
        #expect(LinkPaymentsView.amountInBaseCurrency(local, base: "KZT") == 700)
    }

    @Test("without a rate the stored conversion is the last resort")
    func coldCacheFallsBack() {
        // A code no rate provider knows: no cached table can convert it.
        let fromTengeCard = payment(amount: 10, currency: "ZZZ", convertedAmount: 5_000)
        #expect(LinkPaymentsView.amountInBaseCurrency(fromTengeCard, base: "KZT") == 5_000)
    }
}
