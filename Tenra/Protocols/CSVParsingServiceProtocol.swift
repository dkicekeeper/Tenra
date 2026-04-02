//
//  CSVParsingServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-03
//  CSV Import Refactoring Phase 1
//

import Foundation

/// Protocol for CSV file parsing operations
/// Separates parsing logic from business logic for better testability
@MainActor
protocol CSVParsingServiceProtocol {
    /// Parses a CSV file from a URL
    /// - Parameter url: File URL to parse
    /// - Returns: Parsed CSV file structure
    /// - Throws: CSVImportError if parsing fails
    func parseFile(from url: URL) async throws -> CSVFile

    /// Parses CSV content from a string
    /// - Parameter content: CSV content as string
    /// - Returns: Parsed CSV file structure
    /// - Throws: CSVImportError if parsing fails
    func parseContent(_ content: String) async throws -> CSVFile
}
