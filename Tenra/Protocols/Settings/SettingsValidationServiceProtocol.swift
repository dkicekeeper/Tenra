//
//  SettingsValidationServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation

/// Protocol for settings validation
/// Centralizes all validation rules for settings
protocol SettingsValidationServiceProtocol {
    /// Validate all settings
    /// - Parameter settings: Settings to validate
    /// - Throws: SettingsValidationError if validation fails
    func validateSettings(_ settings: AppSettings) throws

    /// Validate currency code
    /// - Parameter currency: Currency code to validate
    /// - Throws: SettingsValidationError if invalid
    func validateCurrency(_ currency: String) throws

    /// Validate wallpaper file reference
    /// - Parameter fileName: Wallpaper file name to validate
    /// - Throws: SettingsValidationError if file doesn't exist or is corrupted
    func validateWallpaper(_ fileName: String?) throws
}

/// Validation errors for settings
enum SettingsValidationError: LocalizedError {
    case invalidCurrency(String)
    case wallpaperFileNotFound(String)
    case wallpaperFileCorrupted(String)
    case invalidLanguage(String)

    var errorDescription: String? {
        switch self {
        case .invalidCurrency(let currency):
            return String(localized: "error.settings.invalidCurrency", defaultValue: "Invalid currency: \(currency)")
        case .wallpaperFileNotFound(let fileName):
            return String(localized: "error.settings.wallpaperNotFound", defaultValue: "Wallpaper file not found: \(fileName)")
        case .wallpaperFileCorrupted(let fileName):
            return String(localized: "error.settings.wallpaperCorrupted", defaultValue: "Wallpaper file is corrupted: \(fileName)")
        case .invalidLanguage(let language):
            return String(localized: "error.settings.invalidLanguage", defaultValue: "Invalid language: \(language)")
        }
    }
}
