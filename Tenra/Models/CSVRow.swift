//
//  CSVRow.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Represents a validated CSV row with all parsed fields
/// Provides type-safe access to row data and computed effective values based on transaction type
struct CSVRow {
    // MARK: - Row Metadata

    /// Original row index in CSV file (for error reporting)
    let rowIndex: Int

    // MARK: - Required Fields

    /// Parsed transaction date
    let date: Date

    /// Transaction type (expense, income, transfer, etc.)
    let type: TransactionType

    /// Transaction amount
    let amount: Double

    /// Transaction currency
    let currency: String

    // MARK: - Account Fields

    /// Raw account value from CSV (before type-based rules)
    let rawAccountValue: String

    /// Raw target account value from CSV (before type-based rules)
    let rawTargetAccountValue: String?

    /// Target currency for multi-currency transfers
    let targetCurrency: String?

    /// Target amount for multi-currency transfers
    let targetAmount: Double?

    // MARK: - Category Fields

    /// Raw category value from CSV (before type-based rules)
    let rawCategoryValue: String

    /// Array of subcategory names
    let subcategoryNames: [String]

    // MARK: - Optional Fields

    /// Transaction note/description
    let note: String?

    // MARK: - Computed Effective Values

    /// Effective account value after applying type-based parsing rules
    /// - Expense: uses rawAccountValue
    /// - Income: uses rawTargetAccountValue (or rawCategoryValue as fallback)
    /// - Transfer: uses rawAccountValue
    var effectiveAccountValue: String {
        switch type {
        case .expense, .depositTopUp, .depositWithdrawal, .depositInterestAccrual,
             .loanPayment, .loanEarlyRepayment:
            return rawAccountValue

        case .income:
            // New format: account = rawTargetAccountValue
            // Old format fallback: account = rawCategoryValue
            if let target = rawTargetAccountValue, !target.isEmpty {
                return target
            } else {
                return rawCategoryValue
            }

        case .internalTransfer:
            return rawAccountValue
        }
    }

    /// Effective category value after applying type-based parsing rules
    /// - Expense: uses rawCategoryValue
    /// - Income: uses rawAccountValue (category = income source)
    /// - Transfer: empty (will use default localized "Transfer")
    var effectiveCategoryValue: String {
        switch type {
        case .expense, .depositTopUp, .depositWithdrawal, .depositInterestAccrual,
             .loanPayment, .loanEarlyRepayment:
            return rawCategoryValue

        case .income:
            // Category for income = income source (rawAccountValue)
            return rawAccountValue

        case .internalTransfer:
            // Transfer category is always default
            return ""
        }
    }
}
