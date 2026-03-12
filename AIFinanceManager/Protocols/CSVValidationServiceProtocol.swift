//
//  CSVValidationServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Protocol for CSV row validation operations
/// Separates validation logic from import orchestration
nonisolated protocol CSVValidationServiceProtocol {
    /// Validates a single CSV row and converts it to a structured DTO
    /// - Parameters:
    ///   - row: Array of string values from CSV
    ///   - index: Row index for error reporting
    ///   - mapping: Column mapping configuration
    /// - Returns: Result containing either validated CSVRow or ValidationError
    func validateRow(
        _ row: [String],
        at index: Int,
        mapping: CSVColumnMapping
    ) -> Result<CSVRow, CSVValidationError>

    /// Validates an entire CSV file sequentially
    /// - Parameters:
    ///   - csvFile: Parsed CSV file
    ///   - mapping: Column mapping configuration
    /// - Returns: Array of validation results for all rows
    func validateFile(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping
    ) async -> [Result<CSVRow, CSVValidationError>]

    /// Validates CSV file rows in parallel batches for improved performance (Phase 5 optimization)
    /// Uses Task groups to validate multiple batches concurrently
    /// - Parameters:
    ///   - csvFile: Parsed CSV file
    ///   - mapping: Column mapping configuration
    ///   - batchSize: Number of rows per batch (default: 500)
    /// - Returns: Array of validation results for all rows
    func validateFileParallel(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping,
        batchSize: Int
    ) async -> [Result<CSVRow, CSVValidationError>]
}
