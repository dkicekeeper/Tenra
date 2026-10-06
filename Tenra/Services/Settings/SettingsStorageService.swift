//
//  SettingsStorageService.swift
//  Tenra
//
//  Created on 2026-02-04
//

import Foundation

/// Service for loading and saving settings
/// Handles UserDefaults persistence with validation
@MainActor
final class SettingsStorageService: SettingsStorageServiceProtocol {
    private let userDefaults: UserDefaults
    private let validator: SettingsValidationServiceProtocol

    static let userDefaultsKey = "appSettings"

    init(
        userDefaults: UserDefaults = .standard,
        validator: SettingsValidationServiceProtocol
    ) {
        self.userDefaults = userDefaults
        self.validator = validator
    }

    convenience init(userDefaults: UserDefaults = .standard) {
        self.init(userDefaults: userDefaults, validator: SettingsValidationService())
    }

    // MARK: - SettingsStorageServiceProtocol

    func loadSettings() async throws -> AppSettings {

        // Try to load from UserDefaults
        if let data = userDefaults.data(forKey: Self.userDefaultsKey) {
            let settings: AppSettings
            do {
                settings = try JSONDecoder().decode(AppSettings.self, from: data)
            } catch {
                // Undecodable blob: nothing to repair.
                return AppSettings.makeDefault()
            }
            // Repair the invalid field, never reset everything: a missing wallpaper file
            // (not restored on a new device, or a replace that failed after the old file
            // was deleted) used to fail validation and return the defaults, silently
            // switching the base currency to KZT (USD totals then read as tenge) and
            // dropping hidden amounts and every other preference.
            do {
                try validator.validateWallpaper(settings.wallpaperImageName)
            } catch {
                settings.wallpaperImageName = nil
            }
            do {
                try validator.validateCurrency(settings.baseCurrency)
            } catch {
                settings.baseCurrency = AppSettings.defaultCurrency
            }
            return settings
        }


        return AppSettings.makeDefault()
    }

    func saveSettings(_ settings: AppSettings) async throws {

        // Validate before save
        do {
            try validator.validateSettings(settings)
        } catch {
            throw error
        }

        // Encode and save
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: Self.userDefaultsKey)

        } catch {
            throw SettingsStorageError.saveFailed(underlying: error)
        }
    }

    func validateSettings(_ settings: AppSettings) throws {
        try validator.validateSettings(settings)
    }
}
