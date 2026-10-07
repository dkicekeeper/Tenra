//
//  CSVConversionColumnsTests.swift
//  TenraTests
//
//  The conversion columns of the CSV contract (CSVConversionColumns), without a store:
//  - export labelled the non-transfer column with the transaction's currency although the
//    value was in the account's, and dropped a transfer's source leg;
//  - import never converted a row in another currency than its account, so the balance
//    moved by the raw foreign amount. Old files must still read exactly as before.
//
//  Rates are a fixed closure: 1 USD = 500 ₸, 1 EUR = 550 ₸.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct CSVConversionColumnsTests {

    private nonisolated static func rates(_ amount: Double, _ from: String, _ to: String) -> Double? {
        let kztPerUnit: [String: Double] = ["KZT": 1, "USD": 500, "EUR": 550]
        guard let fromRate = kztPerUnit[from], let toRate = kztPerUnit[to] else { return nil }
        return amount * fromRate / toRate
    }

    private nonisolated static func noRates(_ amount: Double, _ from: String, _ to: String) -> Double? { nil }

    private func imported(
        _ amount: Double, _ currency: String, type: TransactionType = .expense,
        account: String?, targetAccount: String? = nil,
        convertedAmount: Double? = nil, targetCurrency: String? = nil, targetAmount: Double? = nil,
        convert: TransactionConversion.Converter = CSVConversionColumnsTests.rates
    ) -> TransactionConversion? {
        CSVConversionColumns.importedFields(
            type: type, amount: amount, currency: currency,
            accountCurrency: account, targetAccountCurrency: targetAccount,
            convertedAmount: convertedAmount, targetCurrency: targetCurrency, targetAmount: targetAmount,
            convert: convert
        )
    }

    // MARK: - Export

    @Test("export labels the account-currency value with the account's currency")
    func exportLabelsAccountCurrency() throws {
        let voice = Transaction(id: "v", date: "2026-09-01", description: "x", amount: 10, currency: "USD",
                                convertedAmount: 4_500, type: .expense, category: "Food", accountId: "kzt")
        let column = try #require(CSVConversionColumns.exportedEquivalent(of: voice, accountCurrency: "KZT"))
        #expect(column.currency == "KZT", "was the transaction's currency (USD)")
        #expect(column.amount == 4_500)
    }

    @Test("export keeps a base-currency equivalent of a transaction in its account's currency")
    func exportBaseEquivalent() throws {
        let tx = Transaction(id: "b", date: "2026-09-01", description: "x", amount: 5, currency: "USD",
                             type: .expense, category: "Food", accountId: "usd",
                             targetCurrency: "KZT", targetAmount: 2_300)
        let column = try #require(CSVConversionColumns.exportedEquivalent(of: tx, accountCurrency: "USD"))
        #expect(column.currency == "KZT" && column.amount == 2_300)
    }

    // MARK: - Import, one account

    @Test("old files read as before: the value labelled with the transaction's currency is convertedAmount")
    func oldLabelReadsAsBefore() {
        #expect(imported(10, "USD", account: "KZT", targetCurrency: "USD", targetAmount: 4_500)
                == TransactionConversion(convertedAmount: 4_500))
        #expect(imported(10, "USD", account: "KZT", targetAmount: 4_500)
                == TransactionConversion(convertedAmount: 4_500))
        #expect(imported(10, "USD", account: nil, targetAmount: 7)
                == TransactionConversion(convertedAmount: 7), "no account: as before")
        #expect(imported(10, "KZT", account: "KZT") == TransactionConversion())
    }

    @Test("a row in another currency without a value is converted at the cached rate")
    func missingValueIsConverted() {
        #expect(imported(10, "USD", account: "KZT") == TransactionConversion(convertedAmount: 5_000))
        #expect(imported(10, "USD", account: "KZT", convert: Self.noRates) == nil,
                "without a rate the row is refused, not saved with the raw 10")
    }

    @Test("an equivalent in a third currency never becomes the balance's amount")
    func thirdCurrencyEquivalent() throws {
        // The engine reads targetAmount first: a base-currency figure must not land there.
        let fields = try #require(imported(10, "USD", account: "EUR", targetCurrency: "KZT", targetAmount: 5_000))
        #expect(fields.targetAmount == nil)
        let inEuro: Double = 10.0 * 500.0 / 550.0
        let converted = try #require(fields.convertedAmount)
        #expect(abs(converted - inEuro) < 0.0001)
        // In the account's own currency it is the display-only equivalent.
        #expect(imported(10, "USD", account: "USD", targetCurrency: "KZT", targetAmount: 5_000)
                == TransactionConversion(targetCurrency: "KZT", targetAmount: 5_000))
    }

    // MARK: - Import, transfers

    @Test("a same-currency transfer from an old file keeps empty fields")
    func sameCurrencyTransferAsBefore() {
        #expect(imported(100, "KZT", type: .internalTransfer, account: "KZT", targetAccount: "KZT")
                == TransactionConversion())
        #expect(imported(200_000, "KZT", type: .internalTransfer, account: "KZT", targetAccount: "USD",
                         targetCurrency: "USD", targetAmount: 450.25)
                == TransactionConversion(targetCurrency: "USD", targetAmount: 450.25))
    }

    @Test("a transfer's source leg comes from the new column, else the cached rate")
    func transferSourceLeg() {
        #expect(imported(10, "USD", type: .internalTransfer, account: "KZT", targetAccount: "USD",
                         convertedAmount: 4_600, targetCurrency: "USD", targetAmount: 10)
                == TransactionConversion(convertedAmount: 4_600, targetCurrency: "USD", targetAmount: 10))
        #expect(imported(10, "USD", type: .internalTransfer, account: "KZT", targetAccount: "USD",
                         targetCurrency: "USD", targetAmount: 10)
                == TransactionConversion(convertedAmount: 5_000, targetCurrency: "USD", targetAmount: 10))
        #expect(imported(10, "USD", type: .internalTransfer, account: "KZT", targetAccount: "USD",
                         targetCurrency: "USD", targetAmount: 10, convert: Self.noRates) == nil)
    }

    @Test("a transfer's target leg is spelled out whenever the balance could misread it")
    func transferTargetLeg() throws {
        // Source converted, no target columns: without targetAmount the engine would
        // credit the target with the source leg (5 000 as dollars).
        #expect(imported(10, "USD", type: .internalTransfer, account: "KZT", targetAccount: "USD")
                == TransactionConversion(convertedAmount: 5_000, targetCurrency: "USD", targetAmount: 10))
        // Target in another currency than the transfer, no columns: converted.
        let toEuro = try #require(imported(100, "KZT", type: .internalTransfer, account: "KZT", targetAccount: "EUR"))
        #expect(toEuro.targetCurrency == "EUR")
        let inEuro: Double = 100.0 / 550.0
        let received = try #require(toEuro.targetAmount)
        #expect(abs(received - inEuro) < 0.0001)
        // A target figure labelled with another currency than the target account's.
        #expect(imported(100, "KZT", type: .internalTransfer, account: "KZT", targetAccount: "KZT",
                         targetCurrency: "USD", targetAmount: 0.2)
                == TransactionConversion(targetCurrency: "KZT", targetAmount: 100))
        // Unlabelled figure: kept, labelled with the target account's currency.
        #expect(imported(200_000, "KZT", type: .internalTransfer, account: "KZT", targetAccount: "USD",
                         targetAmount: 450.25)
                == TransactionConversion(targetCurrency: "USD", targetAmount: 450.25))
    }
}
