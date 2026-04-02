//
//  TransactionFormService.swift
//  AIFinanceManager
//
//  Service for transaction form validation and processing.
//  Extracted from AddTransactionModal to follow Single Responsibility Principle.
//

import Foundation

@MainActor
final class TransactionFormService: TransactionFormServiceProtocol {

    // MARK: - Validation

    func validate(_ formData: TransactionFormData, accounts: [Account]) -> ValidationResult {
        var errors: [ValidationError] = []

        // Validate amount
        guard let decimalAmount = formData.parsedAmount else {
            errors.append(.invalidAmount)
            return .invalid(errors)
        }

        guard decimalAmount > 0 else {
            errors.append(.amountMustBePositive)
            return .invalid(errors)
        }

        // Validate account selection
        guard let accountId = formData.accountId else {
            errors.append(.accountNotSelected)
            return .invalid(errors)
        }

        // Validate account exists
        guard accounts.contains(where: { $0.id == accountId }) else {
            errors.append(.accountNotFound)
            return .invalid(errors)
        }

        return .valid
    }

    // MARK: - Currency Conversion

    func convertCurrency(
        amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String,
        baseCurrency: String
    ) async -> CurrencyConversionResult {
        // No conversion needed if currencies match
        guard sourceCurrency != targetCurrency else {
            return CurrencyConversionResult(convertedAmount: nil, exchangeRate: nil)
        }

        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue

        // Pre-fetch exchange rates
        _ = await CurrencyConverter.getExchangeRate(for: sourceCurrency)
        _ = await CurrencyConverter.getExchangeRate(for: targetCurrency)

        // Try sync conversion first (uses cache)
        if let convertedAmount = CurrencyConverter.convertSync(
            amount: amountDouble,
            from: sourceCurrency,
            to: targetCurrency
        ) {
            let rate = convertedAmount / amountDouble
            return CurrencyConversionResult(
                convertedAmount: convertedAmount,
                exchangeRate: rate
            )
        }

        // Fallback to async conversion
        if let convertedAmount = await CurrencyConverter.convert(
            amount: amountDouble,
            from: sourceCurrency,
            to: targetCurrency
        ) {
            let rate = convertedAmount / amountDouble
            return CurrencyConversionResult(
                convertedAmount: convertedAmount,
                exchangeRate: rate
            )
        }

        return CurrencyConversionResult(convertedAmount: nil, exchangeRate: nil)
    }

    // MARK: - Target Amounts Calculation

    func calculateTargetAmounts(
        amount: Decimal,
        currency: String,
        account: Account,
        baseCurrency: String
    ) async -> TargetAmounts {
        let accountCurrency = account.currency

        // Case 1: Transaction currency differs from account currency
        // Need to convert to account currency for correct balance update
        if currency != accountCurrency {
            let conversionResult = await convertCurrency(
                amount: amount,
                from: currency,
                to: accountCurrency,
                baseCurrency: baseCurrency
            )

            return TargetAmounts(
                targetCurrency: accountCurrency,
                targetAmount: conversionResult.convertedAmount
            )
        }

        // Case 2: Transaction currency == Account currency, but differs from base currency
        // Show equivalent in base currency for UI display
        if currency == accountCurrency && currency != baseCurrency {
            let conversionResult = await convertCurrency(
                amount: amount,
                from: currency,
                to: baseCurrency,
                baseCurrency: baseCurrency
            )

            if conversionResult.convertedAmount != nil {
                return TargetAmounts(
                    targetCurrency: baseCurrency,
                    targetAmount: conversionResult.convertedAmount
                )
            }
        }

        // Case 3: All currencies match or no conversion available
        return .none
    }

    // MARK: - Date Utilities

    func isFutureDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let transactionDate = calendar.startOfDay(for: date)
        return transactionDate > today
    }
}
