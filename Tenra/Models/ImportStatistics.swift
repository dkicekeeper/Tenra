//
//  ImportStatistics.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Comprehensive import statistics with performance metrics
/// Provides detailed breakdown of import results and timing information
struct ImportStatistics {
    // MARK: - Row Counts

    /// Total number of rows processed
    let totalRows: Int

    /// Number of transactions successfully imported
    let importedCount: Int

    /// Number of rows skipped (validation failures + duplicates)
    let skippedCount: Int

    /// Number of duplicate transactions skipped
    let duplicatesSkipped: Int

    // MARK: - Entity Creation Counts

    /// Number of accounts created during import
    let createdAccounts: Int

    /// Number of categories created during import
    let createdCategories: Int

    /// Number of subcategories created during import
    let createdSubcategories: Int

    // MARK: - Performance Metrics

    /// Total duration of import operation in seconds
    let duration: TimeInterval

    /// Processing speed in rows per second
    let rowsPerSecond: Double

    // MARK: - Errors

    /// Array of validation errors encountered during import
    let errors: [CSVValidationError]

    /// Non-nil when CoreData persistence failed at the end of import.
    /// The user must be informed — imported data may not be saved.
    let persistenceError: String?

    // MARK: - Computed Properties

    /// Success rate as a fraction from 0.0 to 1.0
    var successRate: Double {
        guard totalRows > 0 else { return 0.0 }
        return Double(importedCount) / Double(totalRows)
    }

    /// Success rate as a percentage (0-100)
    var successPercentage: Int {
        Int(successRate * 100)
    }

    /// Flag indicating if import had errors
    var hasErrors: Bool {
        !errors.isEmpty
    }

    /// Number of validation errors (excluding duplicates)
    var validationErrorCount: Int {
        errors.count
    }
}
