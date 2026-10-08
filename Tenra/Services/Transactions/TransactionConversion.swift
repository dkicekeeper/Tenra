//
//  TransactionConversion.swift
//  Tenra
//
//  The three stored conversion fields of a transaction, worked out by one rule for the
//  paths that write them (add, edit, recurring occurrences, subscription edits). Each
//  path used to carry its own copy and they disagreed: the add screen stored a
//  base-currency `convertedAmount`, recurring occurrences a base-currency `targetAmount`
//  that the balance engine reads in the account's currency, and the edit screen dropped
//  `targetCurrency` / `targetAmount` on every save.
//
//  What the fields mean (BalanceCalculationEngine's contract, docs/domains/currency.md):
//  - `convertedAmount`: the amount in the ACCOUNT's currency (a transfer's source
//    account), nil when the transaction is already in it. Never a base-currency figure
//    (CLAUDE.md red flag 6).
//  - `targetCurrency` / `targetAmount`: for a transfer, what the target account receives,
//    in its currency. For any other type, the equivalent the transaction row shows under
//    the amount: the value in the account's currency, or in the base currency when the
//    transaction is already in its account's (foreign) currency.
//

import Foundation

nonisolated struct TransactionConversion: Equatable, Sendable {
    var convertedAmount: Double? = nil
    var targetCurrency: String? = nil
    var targetAmount: Double? = nil

    /// `(amount, from, to)` → the amount in `to`, nil when no rate is known.
    typealias Converter = (Double, String, String) -> Double?

    /// Fields of a transaction that moves one account: income, expense, loan payment,
    /// deposit operations.
    ///
    /// Nil when the amount must be converted into the account's currency and `convert`
    /// has no rate. Saved anyway, the transaction would move the balance by the raw
    /// foreign amount (10 USD taken off a KZT account as 10 ₸), so callers refuse the
    /// save instead.
    static func singleAccount(
        amount: Double,
        currency: String,
        accountCurrency: String,
        baseCurrency: String,
        convert: Converter
    ) -> TransactionConversion? {
        if currency != accountCurrency {
            guard let inAccount = convert(amount, currency, accountCurrency) else { return nil }
            return TransactionConversion(
                convertedAmount: inAccount,
                targetCurrency: accountCurrency,
                targetAmount: inAccount
            )
        }
        // Already in the account's currency: the balance needs nothing. The base-currency
        // equivalent is for display only, so a missing rate just leaves it out.
        if currency != baseCurrency, let inBase = convert(amount, currency, baseCurrency) {
            return TransactionConversion(targetCurrency: baseCurrency, targetAmount: inBase)
        }
        return TransactionConversion()
    }

    /// Fields of a transfer: `convertedAmount` is what leaves the source account (in its
    /// currency, nil when the transfer is entered in it), `targetAmount` what the target
    /// account receives, in `targetCurrency`. Nil when either leg needs a missing rate.
    static func transfer(
        amount: Double,
        currency: String,
        sourceCurrency: String,
        targetCurrency: String,
        convert: Converter
    ) -> TransactionConversion? {
        var fields = TransactionConversion(targetCurrency: targetCurrency, targetAmount: amount)
        if currency != sourceCurrency {
            guard let inSource = convert(amount, currency, sourceCurrency) else { return nil }
            fields.convertedAmount = inSource
        }
        if currency != targetCurrency {
            guard let inTarget = convert(amount, currency, targetCurrency) else { return nil }
            fields.targetAmount = inTarget
        }
        return fields
    }

    /// The rate `transaction` was saved with from `from` to `to`, nil when it holds none.
    ///
    /// An edit that keeps a currency pair reuses it, so the converted value follows the
    /// new amount at the rate the transaction was recorded with (or the bank's own figure
    /// an import stored) instead of being re-priced at today's rate. Editing only the
    /// description therefore leaves the balance untouched.
    ///
    /// - Parameter accountCurrency: currency of the account (a transfer's source account)
    ///   the transaction was saved on, the one `convertedAmount` is denominated in.
    static func storedRate(
        in transaction: Transaction,
        from: String,
        to: String,
        accountCurrency: String?
    ) -> Double? {
        guard from == transaction.currency, from != to, transaction.amount > 0 else { return nil }
        if transaction.targetCurrency == to, let target = transaction.targetAmount, target > 0 {
            return target / transaction.amount
        }
        if accountCurrency == to, let converted = transaction.convertedAmount, converted > 0 {
            return converted / transaction.amount
        }
        return nil
    }

    /// Whether `fields` miss the base-currency equivalent of a transaction in a foreign
    /// currency. It is display only, so `singleAccount` doesn't fail without it, but a
    /// cold rate cache (first launch, offline start) saved the row without its "≈" line:
    /// callers load the rates once more when this is true.
    static func lacksEquivalent(_ fields: TransactionConversion, currency: String, baseCurrency: String) -> Bool {
        currency != baseCurrency && fields.targetAmount == nil
    }

    /// `CurrencyConverter.convertSync` as a `Converter`: cached rates only, no network.
    static func cachedRate(_ amount: Double, _ from: String, _ to: String) -> Double? {
        CurrencyConverter.convertSync(amount: amount, from: from, to: to)
    }

    /// The converter for rewriting `transaction`: a pair it already holds a conversion
    /// for keeps that rate (`storedRate`), anything else uses `cachedRate`.
    static func keepingRates(of transaction: Transaction, accountCurrency: String?) -> Converter {
        { amount, from, to in
            if let rate = TransactionConversion.storedRate(
                in: transaction, from: from, to: to, accountCurrency: accountCurrency
            ) {
                return amount * rate
            }
            return TransactionConversion.cachedRate(amount, from, to)
        }
    }

    /// Loads the rates of `currencies` into the cache (from the network on a miss), so
    /// `cachedRate` can convert them. Callers try the cache first and come here only when
    /// a rate is missing: a stale but present rate is better than waiting on the network.
    static func loadRates(_ currencies: Set<String>) async {
        for currency in currencies {
            _ = await CurrencyConverter.getExchangeRate(for: currency)
        }
    }

    // MARK: - Reading the fields

    /// The equivalent a transaction row shows under its amount, nil when there is none.
    ///
    /// `targetAmount` in `targetCurrency` when it is another currency than the
    /// transaction's. A row that stores only `convertedAmount` (voice, Siri and App
    /// Intents, deposit top-ups, statement and CSV imports, edits saved before the edit
    /// screen kept the equivalent) shows that value in its account's currency: what the
    /// balance moved by. Transfers show both legs instead (`TransactionCardView`).
    ///
    /// - Parameter accountCurrency: currency of the transaction's account, nil when the
    ///   account is unknown (deleted): `convertedAmount` carries no currency of its own.
    static func displayedEquivalent(
        of transaction: Transaction,
        accountCurrency: String?
    ) -> (amount: Double, currency: String)? {
        guard transaction.type != .internalTransfer else { return nil }
        if let currency = transaction.targetCurrency,
           let amount = transaction.targetAmount,
           currency != transaction.currency {
            return (amount, currency)
        }
        if transaction.targetAmount == nil,
           let converted = transaction.convertedAmount,
           let accountCurrency,
           accountCurrency != transaction.currency {
            return (converted, accountCurrency)
        }
        return nil
    }

    /// What `transaction` moved its account (a transfer's source account) by, in that
    /// account's currency, as recorded when it was saved: the amount itself when it is in
    /// `accountCurrency`, else the conversion stored with it. Nil when it holds none, so
    /// the caller converts at today's rate.
    ///
    /// A stored conversion counts only when nothing says it is in another currency:
    /// `targetAmount` labelled with the account's currency first, then `convertedAmount`
    /// (unlabelled, the account's by contract) unless `targetCurrency` names a third
    /// currency, the trace of an account whose currency changed after the save. A loan
    /// payment's `targetCurrency` is the loan's, the transaction's own currency, and does
    /// not count against it. For a transfer the target fields are the other leg, so only
    /// `convertedAmount` is the source leg.
    static func recordedAmount(of transaction: Transaction, inAccountCurrency accountCurrency: String) -> Double? {
        if transaction.currency == accountCurrency { return transaction.amount }
        if transaction.type == .internalTransfer { return transaction.convertedAmount }
        if transaction.targetCurrency == accountCurrency, let target = transaction.targetAmount {
            return target
        }
        guard let converted = transaction.convertedAmount else { return nil }
        if let label = transaction.targetCurrency, label != accountCurrency, label != transaction.currency {
            return nil
        }
        return converted
    }

    /// What `transaction` (any type but a transfer) moves its account by, in that account's
    /// currency: the reading of `BalanceCalculationEngine.getTransactionAmount`, which takes
    /// `targetAmount`, then `convertedAmount`, whatever their label. For code that must keep
    /// a balance exactly where the engine put it, and can't call the MainActor engine.
    static func balanceAmount(of transaction: Transaction, inAccountCurrency accountCurrency: String) -> Double {
        guard transaction.currency != accountCurrency else { return transaction.amount }
        return transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount
    }
}
