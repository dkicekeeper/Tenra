//
//  SettingsStorageService.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import Foundation

/// Service for loading and saving settings
/// Handles UserDefaults persistence with validation
@MainActor
final class SettingsStorageService: SettingsStorageServiceProtocol {
    private let userDefaults: UserDefaults
    private let validator: SettingsValidationServiceProtocol

    private static let userDefaultsKey = "appSettings"

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
            do {
                let settings = try JSONDecoder().decode(AppSettings.self, from: data)

                // Validate loaded settings
                try validator.validateSettings(settings)


                return settings
            } catch {

                // Return default on decode/validation failure
                return AppSettings.makeDefault()
            }
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
