//
//  TransactionFormServiceProtocol.swift
//  AIFinanceManager
//
//  Protocol for transaction form validation and processing
//

import Foundation
import Combine

/// Result of form validation
struct ValidationResult {
    let isValid: Bool
    let errors: [ValidationError]

    static var valid: ValidationResult {
        ValidationResult(isValid: true, errors: [])
    }

    static func invalid(_ errors: [ValidationError]) -> ValidationResult {
        ValidationResult(isValid: false, errors: errors)
    }
}

/// Validation errors
enum ValidationError: LocalizedError {
    case invalidAmount
    case amountMustBePositive
    case amountExceedsMaximum
    case accountNotSelected
    case accountNotFound
    case custom(String)  // NEW: For arbitrary error messages (e.g., from TransactionStore)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return String(localized: "error.validation.enterAmount")
        case .amountMustBePositive:
            return String(localized: "error.validation.amountGreaterThanZero")
        case .amountExceedsMaximum:
            return String(
                localized: "error.amount.exceedsMaximum",
                defaultValue: "Amount cannot exceed 999,999,999.99"
            )
        case .accountNotSelected:
            return String(localized: "error.validation.selectAccount")
        case .accountNotFound:
            return String(localized: "error.validation.accountNotFound")
        case .custom(let message):
            return message
        }
    }
}

/// Result of currency conversion
struct CurrencyConversionResult {
    let convertedAmount: Double?
    let exchangeRate: Double?
}

/// Target amounts for transaction (when currency differs from account currency)
struct TargetAmounts {
    let targetCurrency: String?
    let targetAmount: Double?

    static var none: TargetAmounts {
        TargetAmounts(targetCurrency: nil, targetAmount: nil)
    }
}

/// Protocol for transaction form validation and processing
@MainActor
protocol TransactionFormServiceProtocol {
    /// Validate transaction form data
    func validate(_ formData: TransactionFormData, accounts: [Account]) -> ValidationResult

    /// Convert currency to base currency
    func convertCurrency(
        amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String,
        baseCurrency: String
    ) async -> CurrencyConversionResult

    /// Calculate target amounts when transaction currency differs from account currency
    func calculateTargetAmounts(
        amount: Decimal,
        currency: String,
        account: Account,
        baseCurrency: String
    ) async -> TargetAmounts

    /// Check if date is in the future
    func isFutureDate(_ date: Date) -> Bool
}
