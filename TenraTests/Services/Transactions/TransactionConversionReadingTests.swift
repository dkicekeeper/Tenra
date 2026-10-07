//
//  TransactionConversionReadingTests.swift
//  TenraTests
//
//  The read side of a transaction's conversion fields (TransactionConversion):
//  - `displayedEquivalent`: the "≈" line under a row's amount, now also for rows that
//    store only `convertedAmount` (voice, Siri, imports, older edits), in the account's
//    currency (owner's decision, 2026-10);
//  - `recordedAmount`: what a transaction moved its account by, as recorded, which the
//    account-detail totals count instead of today's rate;
//  - `balanceAmount`: the balance engine's reading, kept by the statement-import merge.
//
//  Pure: no rate cache, no store.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionConversionReadingTests {

    private func tx(
        _ amount: Double, _ currency: String, type: TransactionType = .expense,
        convertedAmount: Double? = nil, targetCurrency: String? = nil, targetAmount: Double? = nil
    ) -> Transaction {
        Transaction(
            id: UUID().uuidString, date: "2026-09-01", description: "x",
            amount: amount, currency: currency, convertedAmount: convertedAmount,
            type: type, category: "Food", accountId: "a1",
            targetAccountId: type == .internalTransfer || type == .loanPayment ? "a2" : nil,
            targetCurrency: targetCurrency, targetAmount: targetAmount
        )
    }

    // MARK: - displayedEquivalent

    @Test("the stored equivalent shows as before")
    func storedEquivalent() throws {
        let equivalent = try #require(TransactionConversion.displayedEquivalent(
            of: tx(10, "USD", convertedAmount: 5_000, targetCurrency: "KZT", targetAmount: 5_000),
            accountCurrency: "KZT"
        ))
        #expect(equivalent.amount == 5_000 && equivalent.currency == "KZT")

        let base = try #require(TransactionConversion.displayedEquivalent(
            of: tx(10, "USD", targetCurrency: "KZT", targetAmount: 5_000), accountCurrency: "USD"
        ))
        #expect(base.currency == "KZT", "a transaction in its account's currency shows the base equivalent")
    }

    @Test("a row with only convertedAmount shows it in the account's currency")
    func convertedOnlyShowsInAccountCurrency() throws {
        let equivalent = try #require(TransactionConversion.displayedEquivalent(
            of: tx(10, "USD", convertedAmount: 4_500), accountCurrency: "KZT"
        ))
        #expect(equivalent.amount == 4_500)
        #expect(equivalent.currency == "KZT")
    }

    @Test("no equivalent without an account currency, in the account's currency, or for transfers")
    func noEquivalent() {
        #expect(TransactionConversion.displayedEquivalent(
            of: tx(10, "USD", convertedAmount: 4_500), accountCurrency: nil) == nil)
        #expect(TransactionConversion.displayedEquivalent(
            of: tx(10, "USD", convertedAmount: 4_500), accountCurrency: "USD") == nil)
        #expect(TransactionConversion.displayedEquivalent(
            of: tx(10, "KZT"), accountCurrency: "KZT") == nil)
        #expect(TransactionConversion.displayedEquivalent(
            of: tx(10, "USD", type: .internalTransfer, convertedAmount: 5_000, targetCurrency: "EUR", targetAmount: 9),
            accountCurrency: "KZT") == nil, "transfers show both legs in TransferAmountView")
    }

    @Test("a loan payment from a card in another currency shows what left the card")
    func loanPaymentShowsSourceLeg() throws {
        // CoreData fills a loan payment's targetCurrency with the loan's, its own currency.
        let payment = tx(500, "USD", type: .loanPayment, convertedAmount: 250_000, targetCurrency: "USD")
        let equivalent = try #require(TransactionConversion.displayedEquivalent(of: payment, accountCurrency: "KZT"))
        #expect(equivalent.amount == 250_000 && equivalent.currency == "KZT")
    }

    // MARK: - recordedAmount

    @Test("recordedAmount: the amount itself, the labelled equivalent, then convertedAmount")
    func recordedAmountOrder() {
        #expect(TransactionConversion.recordedAmount(of: tx(10, "KZT"), inAccountCurrency: "KZT") == 10)
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", convertedAmount: 4_500, targetCurrency: "KZT", targetAmount: 4_500),
            inAccountCurrency: "KZT") == 4_500)
        // The add screen used to store the BASE value as convertedAmount next to the
        // labelled account value: the label wins.
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", convertedAmount: 4_500, targetCurrency: "EUR", targetAmount: 8),
            inAccountCurrency: "EUR") == 8)
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", convertedAmount: 4_500), inAccountCurrency: "KZT") == 4_500)
    }

    @Test("recordedAmount: nothing when the stored conversion is known to be in another currency")
    func recordedAmountRefusesOtherCurrencies() {
        // The account's currency changed after the save: the label names the old one.
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", convertedAmount: 4_500, targetCurrency: "KZT", targetAmount: 4_500),
            inAccountCurrency: "EUR") == nil)
        // Older recurring occurrences stored only a base-currency targetAmount.
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", targetCurrency: "KZT", targetAmount: 5_000), inAccountCurrency: "EUR") == nil)
        #expect(TransactionConversion.recordedAmount(of: tx(10, "USD"), inAccountCurrency: "KZT") == nil)
    }

    @Test("recordedAmount: a loan payment's own-currency label doesn't hide convertedAmount")
    func recordedAmountLoanPayment() {
        let payment = tx(500, "USD", type: .loanPayment, convertedAmount: 250_000, targetCurrency: "USD")
        #expect(TransactionConversion.recordedAmount(of: payment, inAccountCurrency: "KZT") == 250_000)
    }

    @Test("recordedAmount: a transfer's source leg is convertedAmount, never the target leg")
    func recordedAmountTransfer() {
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", type: .internalTransfer, convertedAmount: 5_000, targetCurrency: "KZT", targetAmount: 5_100),
            inAccountCurrency: "KZT") == 5_000)
        #expect(TransactionConversion.recordedAmount(
            of: tx(10, "USD", type: .internalTransfer, targetCurrency: "KZT", targetAmount: 5_100),
            inAccountCurrency: "KZT") == nil)
    }

    // MARK: - balanceAmount

    @Test("balanceAmount reads like the balance engine")
    func balanceAmountMatchesEngine() {
        let account = AccountBalance(accountId: "a1", currentBalance: 0, currency: "KZT")
        let engine = BalanceCalculationEngine()
        let samples = [
            tx(10, "USD", convertedAmount: 4_500, targetCurrency: "KZT", targetAmount: 4_600),
            tx(10, "USD", convertedAmount: 4_500),
            tx(10, "USD"),
            tx(10, "KZT", convertedAmount: 99, targetCurrency: "USD", targetAmount: 0.02),
            tx(10, "USD", type: .income, convertedAmount: 4_500)
        ]
        for sample in samples {
            let fromEngine = abs(engine.contribution(of: sample, to: account, policy: .allTime))
            #expect(TransactionConversion.balanceAmount(of: sample, inAccountCurrency: "KZT") == fromEngine)
        }
    }
}
