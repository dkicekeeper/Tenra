//
//  AppSettings.swift
//  AIFinanceManager
//
//  Created on 2024
//  Enhanced: 2026-02-04 (Settings Refactoring Phase 1)
//

import Foundation
import SwiftUI
import Observation

// MARK: - HomeBackgroundMode

/// Режим фона главного экрана.
/// - `none` — стандартный системный фон (по умолчанию)
/// - `gradient` — цветные орбы на основе топ-категорий расходов
/// - `wallpaper` — пользовательское фото
enum HomeBackgroundMode: String, Codable, CaseIterable, Sendable {
    case none
    case gradient
    case wallpaper
}

/// Application settings model
/// Enhanced with validation, defaults, and factory methods
/// ✅ MIGRATED 2026-02-12: Now using @Observable instead of ObservableObject
@Observable
@MainActor
class AppSettings: Codable {
    // MARK: - Observable Properties

    var baseCurrency: String
    var wallpaperImageName: String?
    /// Активный режим фона главного экрана.
    var homeBackgroundMode: HomeBackgroundMode
    /// Размыть фото-обои на главном экране.
    var blurWallpaper: Bool

    // MARK: - Constants

    nonisolated static let defaultCurrency = "KZT"
    nonisolated static let availableCurrencies = ["KZT", "USD", "EUR", "RUB", "GBP", "CNY", "JPY"]

    // MARK: - Computed Properties

    /// Validate if current settings are valid
    var isValid: Bool {
        Self.availableCurrencies.contains(baseCurrency)
    }

    // MARK: - Initialization

    init(
        baseCurrency: String = defaultCurrency,
        wallpaperImageName: String? = nil,
        homeBackgroundMode: HomeBackgroundMode = .none,
        blurWallpaper: Bool = false
    ) {
        self.baseCurrency = baseCurrency
        self.wallpaperImageName = wallpaperImageName
        self.homeBackgroundMode = homeBackgroundMode
        self.blurWallpaper = blurWallpaper
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case baseCurrency
        case wallpaperImageName
        case homeBackgroundMode
        case blurWallpaper
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseCurrency = try container.decode(String.self, forKey: .baseCurrency)
        wallpaperImageName = try container.decodeIfPresent(String.self, forKey: .wallpaperImageName)
        // Backward-compatible: old saves without these keys use defaults
        homeBackgroundMode = (try? container.decodeIfPresent(HomeBackgroundMode.self, forKey: .homeBackgroundMode)) ?? .none
        blurWallpaper = (try? container.decodeIfPresent(Bool.self, forKey: .blurWallpaper)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseCurrency, forKey: .baseCurrency)
        try container.encodeIfPresent(wallpaperImageName, forKey: .wallpaperImageName)
        try container.encode(homeBackgroundMode, forKey: .homeBackgroundMode)
        try container.encode(blurWallpaper, forKey: .blurWallpaper)
    }

    // MARK: - In-place Update

    /// Copy all persisted values from `other` into this instance.
    ///
    /// Used by `SettingsViewModel.loadSettings()` so that the shared `AppSettings`
    /// reference held by `TransactionsViewModel` (and observed by `ContentView`) is
    /// mutated in-place rather than replaced — preserving the @Observable subscription chain.
    func update(from other: AppSettings) {
        baseCurrency = other.baseCurrency
        wallpaperImageName = other.wallpaperImageName
        homeBackgroundMode = other.homeBackgroundMode
        blurWallpaper = other.blurWallpaper
    }

    // MARK: - Factory Methods

    /// Create default settings instance
    static func makeDefault() -> AppSettings {
        AppSettings(
            baseCurrency: defaultCurrency,
            wallpaperImageName: nil
        )
    }

    // MARK: - Legacy Persistence (Deprecated)
    // NOTE: These methods are kept for backward compatibility
    // New code should use SettingsStorageService instead

    private static let userDefaultsKey = "appSettings"

    /// Legacy save method
    /// - Note: Prefer using SettingsStorageService for new code
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: AppSettings.userDefaultsKey)
        }
    }

    /// Legacy load method
    /// - Note: Prefer using SettingsStorageService for new code
    /// - Returns: AppSettings instance (default if load fails)
    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return makeDefault()
    }
}
