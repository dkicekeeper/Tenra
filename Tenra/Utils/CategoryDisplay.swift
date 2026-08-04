//
//  CategoryDisplay.swift
//  Tenra
//
//  UI-side resolver for `Transaction.category`. The model stores raw, locale-independent
//  values (`"Loan Payment"`, `"Transfer"`, etc.) so the data survives locale changes;
//  this resolver maps them to localized strings at render time.
//
//  Usage:
//  ```swift
//  Text(CategoryDisplay.displayName(for: tx.category, type: tx.type))
//  ```
//

import Foundation

enum CategoryDisplay {

    /// Returns a user-facing label for a transaction's `category` field.
    ///
    /// - Locale-independent technical constants (`"Loan Payment"`, `"Transfer"`) are
    ///   replaced with localized strings keyed off `TransactionType` so users see
    ///   "Платёж по кредиту" / "Перевод" instead of raw English.
    /// - User-defined categories pass through unchanged.
    /// - Empty categories fall back to a generic "Without category" label rather than
    ///   rendering an empty UI region.
    /// `nonisolated`: also called off MainActor by `InsightsService` when it labels a
    /// breakdown item built on the background insights thread.
    nonisolated static func displayName(for category: String, type: TransactionType) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return fallbackLabel(for: type)
        }

        if trimmed == TransactionType.loanPaymentCategoryName {
            switch type {
            case .loanEarlyRepayment:
                return String(localized: "transaction.type.loanEarlyRepayment", defaultValue: "Досрочное погашение")
            default:
                return String(localized: "transaction.type.loanPayment", defaultValue: "Платёж по кредиту")
            }
        }

        if trimmed == TransactionType.depositInterestCategoryName {
            return String(localized: "transaction.type.depositInterestAccrual", defaultValue: "Начисление процентов")
        }

        if trimmed == TransactionType.transferCategoryName {
            return String(localized: "transaction.type.internalTransfer", defaultValue: "Перевод")
        }

        return trimmed
    }

    nonisolated private static func fallbackLabel(for type: TransactionType) -> String {
        switch type {
        case .loanPayment:
            return String(localized: "transaction.type.loanPayment", defaultValue: "Платёж по кредиту")
        case .loanEarlyRepayment:
            return String(localized: "transaction.type.loanEarlyRepayment", defaultValue: "Досрочное погашение")
        case .internalTransfer:
            return String(localized: "transaction.type.internalTransfer", defaultValue: "Перевод")
        case .depositTopUp:
            return String(localized: "transaction.type.depositTopUp", defaultValue: "Пополнение депозита")
        case .depositWithdrawal:
            return String(localized: "transaction.type.depositWithdrawal", defaultValue: "Снятие с депозита")
        case .depositInterestAccrual:
            return String(localized: "transaction.type.depositInterestAccrual", defaultValue: "Начисление процентов")
        case .income, .expense:
            return String(localized: "category.uncategorized", defaultValue: "Без категории")
        }
    }
}
