//
//  SettingsStorageServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation

/// Protocol for settings storage operations
/// Abstracts persistence layer for testability and flexibility
protocol SettingsStorageServiceProtocol {
    /// Load settings from persistent storage
    /// - Returns: AppSettings instance
    /// - Throws: SettingsStorageError if loading fails
    func loadSettings() async throws -> AppSettings

    /// Save settings to persistent storage
    /// - Parameter settings: Settings to save
    /// - Throws: SettingsStorageError if saving fails
    func saveSettings(_ settings: AppSettings) async throws

    /// Validate settings before operations
    /// - Parameter settings: Settings to validate
    /// - Throws: SettingsValidationError if validation fails
    func validateSettings(_ settings: AppSettings) throws
}

/// Errors that can occur during settings storage operations
enum SettingsStorageError: LocalizedError {
    case loadFailed(underlying: Error)
    case saveFailed(underlying: Error)
    case corruptedData
    case migrationFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed(let error):
            return String(localized: "error.settings.loadFailed", defaultValue: "Failed to load settings: \(error.localizedDescription)")
        case .saveFailed(let error):
            return String(localized: "error.settings.saveFailed", defaultValue: "Failed to save settings: \(error.localizedDescription)")
        case .corruptedData:
            return String(localized: "error.settings.corruptedData", defaultValue: "Settings data is corrupted")
        case .migrationFailed:
            return String(localized: "error.settings.migrationFailed", defaultValue: "Failed to migrate settings")
        }
    }
}
