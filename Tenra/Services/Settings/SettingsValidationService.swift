//
//  SettingsValidationService.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation
import UIKit

/// Service for validating settings
/// Centralizes all validation rules
final class SettingsValidationService: SettingsValidationServiceProtocol {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - SettingsValidationServiceProtocol

    func validateSettings(_ settings: AppSettings) throws {
        try validateCurrency(settings.baseCurrency)
        try validateWallpaper(settings.wallpaperImageName)
    }

    func validateCurrency(_ currency: String) throws {
        guard AppSettings.availableCurrencies.contains(currency) else {
            throw SettingsValidationError.invalidCurrency(currency)
        }
    }

    func validateWallpaper(_ fileName: String?) throws {
        guard let fileName = fileName, !fileName.isEmpty else {
            // No wallpaper is valid
            return
        }

        let fileURL = getDocumentsURL().appendingPathComponent(fileName)

        // Check file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw SettingsValidationError.wallpaperFileNotFound(fileName)
        }

        // Check file is readable and valid image
        guard let data = try? Data(contentsOf: fileURL),
              UIImage(data: data) != nil else {
            throw SettingsValidationError.wallpaperFileCorrupted(fileName)
        }
    }

    // MARK: - Helper

    private func getDocumentsURL() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
