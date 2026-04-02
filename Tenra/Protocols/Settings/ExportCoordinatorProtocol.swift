//
//  ExportCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation

/// Protocol for coordinating data export operations
/// Handles CSV export with progress tracking and async operations
protocol ExportCoordinatorProtocol {
    /// Export all transactions to CSV file
    /// - Returns: URL of exported file in temporary directory
    /// - Throws: ExportError if export fails
    func exportAllData() async throws -> URL

    /// Current export progress (0.0 to 1.0)
    var exportProgress: Double { get }
}

/// Errors that can occur during export operations
enum ExportError: LocalizedError {
    case noDataToExport
    case exportFailed(underlying: Error)
    case fileWriteFailed(underlying: Error)
    case insufficientSpace

    var errorDescription: String? {
        switch self {
        case .noDataToExport:
            return String(localized: "error.export.noData", defaultValue: "No data to export")
        case .exportFailed(let error):
            return String(localized: "error.export.failed", defaultValue: "Failed to export data: \(error.localizedDescription)")
        case .fileWriteFailed(let error):
            return String(localized: "error.export.fileWriteFailed", defaultValue: "Failed to write export file: \(error.localizedDescription)")
        case .insufficientSpace:
            return String(localized: "error.export.insufficientSpace", defaultValue: "Insufficient disk space for export")
        }
    }
}
