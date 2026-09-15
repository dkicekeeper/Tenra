//
//  SettingsValidationService.swift
//  Tenra
//
//  Created on 2026-02-04
//

import Foundation
import ImageIO

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
        guard CurrencyInfo.find(currency) != nil else {
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

        // Check the file is a readable image — by its header, not by decoding it.
        // `Data(contentsOf:)` + `UIImage(data:)` pulled a multi-megabyte photo into
        // memory and decoded it on the main thread (this type is MainActor-isolated by
        // the project's default isolation) on every settings load AND save, only to
        // answer "is this still a valid image?". `CGImageSource` reads the header alone.
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0 else {
            throw SettingsValidationError.wallpaperFileCorrupted(fileName)
        }
    }

    // MARK: - Helper

    private func getDocumentsURL() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
