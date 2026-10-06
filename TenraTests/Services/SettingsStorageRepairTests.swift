//
//  SettingsStorageRepairTests.swift
//  TenraTests
//
//  A stored setting that fails validation is repaired on its own. Before, a missing
//  wallpaper file (not restored on a new device, or a failed replace) made
//  loadSettings return the defaults: the base currency silently became KZT and every
//  other preference was lost.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct SettingsStorageRepairTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "settings.repair.\(UUID().uuidString)")!
    }

    private func store(_ settings: AppSettings, in defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: SettingsStorageService.userDefaultsKey)
    }

    @Test("A missing wallpaper file drops the wallpaper only; the base currency stays")
    func missingWallpaperKeepsTheRest() async throws {
        let defaults = makeDefaults()
        try store(
            AppSettings(baseCurrency: "USD", wallpaperImageName: "gone-\(UUID().uuidString).jpg", hidesAmounts: true),
            in: defaults
        )

        let loaded = try await SettingsStorageService(userDefaults: defaults).loadSettings()

        #expect(loaded.baseCurrency == "USD")
        #expect(loaded.wallpaperImageName == nil)
        #expect(loaded.hidesAmounts)
    }

    @Test("An unknown currency falls back to the default; the rest stays")
    func invalidCurrencyFallsBackAlone() async throws {
        let defaults = makeDefaults()
        try store(AppSettings(baseCurrency: "NOT-A-CURRENCY", hidesAmounts: true), in: defaults)

        let loaded = try await SettingsStorageService(userDefaults: defaults).loadSettings()

        #expect(loaded.baseCurrency == AppSettings.defaultCurrency)
        #expect(loaded.hidesAmounts)
    }

    @Test("Nothing stored gives the defaults")
    func nothingStored() async throws {
        let loaded = try await SettingsStorageService(userDefaults: makeDefaults()).loadSettings()
        #expect(loaded.baseCurrency == AppSettings.defaultCurrency)
        #expect(loaded.wallpaperImageName == nil)
    }
}
