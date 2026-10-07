//
//  CSVConversionColumns.swift
//  Tenra
//
//  A transaction's conversion fields (`TransactionConversion`) in the CSV columns, both
//  ways. docs/domains/csv.md has the column contract.
//
//  - `targetCurrency` / `targetAmount`: for a transfer, what the target account
//    received; for any other type, the equivalent the row shows under the amount
//    (`TransactionConversion.displayedEquivalent`), labelled with its currency. Exports
//    before 2026-10 labelled it with the transaction's currency although the value was
//    in the account's.
//  - `convertedAmount` (12th column, 2026-10): what a transfer took out of its source
//    account, in that account's currency. Older exports dropped it.
//
//  Import fills what the balance needs and the file lacks at today's cached rate: a row
//  in another currency than its account used to move the balance by the raw foreign
//  amount (10 USD taken off a tenge account as 10 ₸). Everything an old file says is
//  read as before.
//

import Foundation

nonisolated enum CSVConversionColumns {

    /// Header of the 12th column.
    static let convertedAmountHeader = "convertedAmount"

    // MARK: - Export

    /// `targetCurrency` / `targetAmount` of a row that is not a transfer: the equivalent
    /// the row shows, else a `convertedAmount` with no currency to show it in (the
    /// transaction is already in the account's, or the account is gone), labelled with
    /// the account's currency, empty when unknown.
    static func exportedEquivalent(
        of transaction: Transaction,
        accountCurrency: String?
    ) -> (currency: String, amount: Double)? {
        if let equivalent = TransactionConversion.displayedEquivalent(
            of: transaction, accountCurrency: accountCurrency
        ) {
            return (equivalent.currency, equivalent.amount)
        }
        if let converted = transaction.convertedAmount, converted != 0 {
            return (accountCurrency ?? "", converted)
        }
        return nil
    }

    // MARK: - Import

    /// Conversion fields of an imported row.
    ///
    /// Nil when a balance needs an amount in another currency that neither the file nor
    /// `convert` has: the row is skipped rather than saved with the raw foreign amount.
    ///
    /// - Parameters:
    ///   - accountCurrency: currency of the row's account (a transfer's source account),
    ///     nil when the row has none.
    ///   - targetAccountCurrency: currency of a transfer's target account, nil otherwise.
    ///   - convertedAmount: the `convertedAmount` column, nil when absent or empty.
    ///   - targetCurrency: the `targetCurrency` column, nil when absent or empty.
    ///   - targetAmount: the `targetAmount` column, nil when absent or empty.
    static func importedFields(
        type: TransactionType,
        amount: Double,
        currency: String,
        accountCurrency: String?,
        targetAccountCurrency: String?,
        convertedAmount: Double?,
        targetCurrency: String?,
        targetAmount: Double?,
        convert: TransactionConversion.Converter
    ) -> TransactionConversion? {
        if type == .internalTransfer {
            return transferFields(
                amount: amount, currency: currency,
                sourceCurrency: accountCurrency, targetAccountCurrency: targetAccountCurrency,
                convertedAmount: convertedAmount,
                targetCurrency: targetCurrency, targetAmount: targetAmount,
                convert: convert
            )
        }

        // No account: no balance to move. As before: the column is `convertedAmount`.
        guard let accountCurrency else {
            return TransactionConversion(convertedAmount: targetAmount)
        }

        if currency != accountCurrency {
            // The account-currency value the file carries: the 12th column, else the
            // equivalent unless it names a third currency. Old exports labelled that
            // value with the transaction's currency.
            let labelFits = targetCurrency == nil
                || targetCurrency == accountCurrency
                || targetCurrency == currency
            let fromFile = convertedAmount ?? (labelFits ? targetAmount : nil)
            guard let inAccount = fromFile ?? convert(amount, currency, accountCurrency) else {
                return nil
            }
            // Only `convertedAmount`, like the file always gave: the balance engine reads
            // `targetAmount` first in the account's currency, so an equivalent in a third
            // currency must not land there.
            return TransactionConversion(convertedAmount: inAccount)
        }

        // Already in the account's currency: nothing for the balance. An equivalent in
        // another currency is display only (exports from 2026-10 carry it).
        if let label = targetCurrency, label != currency, let value = targetAmount {
            return TransactionConversion(targetCurrency: label, targetAmount: value)
        }
        return TransactionConversion(convertedAmount: targetAmount)
    }

    private static func transferFields(
        amount: Double,
        currency: String,
        sourceCurrency: String?,
        targetAccountCurrency: String?,
        convertedAmount: Double?,
        targetCurrency: String?,
        targetAmount: Double?,
        convert: TransactionConversion.Converter
    ) -> TransactionConversion? {
        // As before: the target columns as the file has them.
        var fields = TransactionConversion(targetCurrency: targetCurrency, targetAmount: targetAmount)

        // Source leg, in the source account's currency (`TransactionConversion.transfer`).
        if let sourceCurrency, sourceCurrency != currency {
            guard let inSource = convertedAmount ?? convert(amount, currency, sourceCurrency) else {
                return nil
            }
            fields.convertedAmount = inSource
        }

        // Target leg, in the target account's currency.
        guard let targetAccountCurrency else { return fields }
        let fileValueFits = targetAmount != nil
            && (targetCurrency == nil || targetCurrency == targetAccountCurrency)
        if fileValueFits {
            fields.targetCurrency = targetAccountCurrency
        } else if targetAccountCurrency != currency {
            guard let inTarget = convert(amount, currency, targetAccountCurrency) else { return nil }
            fields.targetCurrency = targetAccountCurrency
            fields.targetAmount = inTarget
        } else if fields.convertedAmount != nil || targetAmount != nil {
            // The target receives the amount itself. Spelled out: without it the balance
            // engine would credit the source leg (`convertedAmount`), or a figure the file
            // labelled with another currency.
            fields.targetCurrency = targetAccountCurrency
            fields.targetAmount = amount
        }
        return fields
    }
}
