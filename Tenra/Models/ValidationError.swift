//
//  ValidationError.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Structured CSV validation error with localization support
/// Provides rich context for debugging and user-friendly error messages
struct CSVValidationError: LocalizedError {
    // MARK: - Properties

    /// Row index where error occurred (0-based)
    let rowIndex: Int

    /// Column name where error occurred (optional)
    let column: String?

    /// Error code for categorization
    let code: CSVValidationErrorCode

    /// Additional context for error (e.g., invalid value)
    let context: [String: String]

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch code {
        case .missingRequiredColumn:
            return String(localized: "csvImport.error.missingRequiredColumn")

        case .invalidDateFormat:
            let value = context["value"] ?? ""
            return String(
                format: String(localized: "csvImport.error.invalidDateFormat"),
                rowIndex + 2, // +2 for header row + 1-based indexing
                value
            )

        case .invalidAmount:
            let value = context["value"] ?? ""
            return String(
                format: String(localized: "csvImport.error.invalidAmount"),
                rowIndex + 2,
                value
            )

        case .invalidType:
            let value = context["value"] ?? ""
            return String(
                format: String(localized: "csvImport.error.invalidType"),
                rowIndex + 2,
                value
            )

        case .emptyValue:
            let columnName = column ?? "unknown"
            return String(
                format: String(localized: "csvImport.error.emptyValue"),
                rowIndex + 2,
                columnName
            )

        case .duplicateTransaction:
            return String(
                format: String(localized: "csvImport.error.duplicateTransaction"),
                rowIndex + 2
            )
        }
    }
}

// MARK: - Validation Error Codes

/// Categorized CSV validation error codes
enum CSVValidationErrorCode: String {
    /// Required column is missing from mapping
    case missingRequiredColumn

    /// Date value cannot be parsed with specified format
    case invalidDateFormat

    /// Amount value cannot be parsed as Double
    case invalidAmount

    /// Transaction type value is not recognized
    case invalidType

    /// Required field has empty value
    case emptyValue

    /// Transaction already exists (duplicate fingerprint)
    case duplicateTransaction
}
