//
//  RecurringOccurrenceCurrencyTests.swift
//  TenraTests
//
//  Recurring occurrences stored only a BASE-currency targetAmount, which the balance
//  engine reads in the ACCOUNT's currency: a USD subscription paid from a EUR card took
//  its tenge value (5 000) off the card in euros. They now carry the account-currency
//  conversion (TransactionConversion), like a hand-entered expense.
//
//  @MainActor + .sharedProcessState: the generator converts through the process-global
//  CurrencyRateStore.shared, seeded per test and cleared in init (CLAUDE.md "Testing").
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct RecurringOccurrenceCurrencyTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    /// 1 USD = 500 KZT, 1 EUR = 550 KZT.
    private func seedCache() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 500, "EUR": 550],
            date: Date(),
            providerName: "test"
        ))
    }

    private func close(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.0001
    }

    private func firstOccurrence(of series: RecurringSeries, accounts: [Account]) -> Transaction? {
        RecurringTransactionGenerator(dateFormatter: DateFormatters.dateFormatter)
            .generateUpToNextFuture(
                series: series,
                existingOccurrences: [],
                existingTransactionIds: [],
                accounts: accounts,
                baseCurrency: "KZT"
            )
            .transactions.first
    }

    private func series(currency: String, accountId: String) -> RecurringSeries {
        RecurringSeries(
            amount: 10, currency: currency, category: "Subscriptions", description: "Service",
            accountId: accountId, frequency: .monthly,
            startDate: DateFormatters.dateFormatter.string(from: Date())
        )
    }

    @Test("an occurrence on a card in another currency converts into the card's currency")
    func occurrenceUsesAccountCurrency() throws {
        seedCache()
        let card = Account(id: "eur", name: "Euro card", currency: "EUR", initialBalance: 0)
        let occurrence = try #require(firstOccurrence(of: series(currency: "USD", accountId: "eur"), accounts: [card]))

        // Used to be convertedAmount nil + targetAmount 5 000 "KZT", read as 5 000 EUR.
        #expect(close(occurrence.convertedAmount, 5_000.0 / 550.0))
        #expect(occurrence.targetCurrency == "EUR")
        #expect(close(occurrence.targetAmount, 5_000.0 / 550.0))

        let delta = BalanceCalculationEngine().contribution(
            of: occurrence,
            to: AccountBalance(accountId: "eur", currentBalance: 0, currency: "EUR"),
            policy: .allTime
        )
        #expect(close(delta, -5_000.0 / 550.0))
    }

    @Test("an occurrence in the card's own foreign currency keeps only the base equivalent")
    func occurrenceInAccountCurrency() throws {
        seedCache()
        let card = Account(id: "usd", name: "Dollar card", currency: "USD", initialBalance: 0)
        let occurrence = try #require(firstOccurrence(of: series(currency: "USD", accountId: "usd"), accounts: [card]))

        #expect(occurrence.convertedAmount == nil)
        #expect(occurrence.targetCurrency == "KZT")
        #expect(occurrence.targetAmount == 5_000)
    }
}
