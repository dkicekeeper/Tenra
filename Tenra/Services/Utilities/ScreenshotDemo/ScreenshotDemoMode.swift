//
//  ScreenshotDemoMode.swift
//  Tenra
//
//  DEBUG-only launch mode for automated App Store screenshot capture.
//
//  Activation: launch the app with the `-ScreenshotDemo` argument. The demo
//  currency comes from the `SCREENSHOT_DEMO_CURRENCY` launch environment
//  variable (defaults to USD). The UI-test runner passes both together with
//  `-AppleLanguages` / `-AppleLocale`, so one binary produces localized
//  screenshots for every storefront.
//
//  Responsibilities are split across the launch sequence:
//  - `applyEarlyOverridesIfNeeded()` — called first thing in
//    `AppDelegate.didFinishLaunching`, BEFORE `PremiumManager.configure()` and
//    before `CurrencyRateStore.shared` is first touched. Writes UserDefaults:
//    onboarding-completed, Founding-User (forces Pro so Voice/OCR/deposit/loan
//    screens are unlocked), base-currency settings and a fresh offline FX-rate
//    cache so no network fetch happens during capture.
//  - `ScreenshotDemoSeeder.seed()` — called from `TenraApp.task` after the
//    CoreData store is ready and before `AppCoordinator` is constructed.
//

import Foundation

#if DEBUG

enum ScreenshotDemoMode {

    static let launchArgument = "-ScreenshotDemo"
    static let currencyEnvironmentKey = "SCREENSHOT_DEMO_CURRENCY"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Storefront currency for the seeded dataset (accounts, amounts, budgets).
    static var currencyCode: String {
        ProcessInfo.processInfo.environment[currencyEnvironmentKey] ?? "USD"
    }

    // MARK: - Early launch overrides

    /// Must run before `PremiumManager.configure()` (founder flag is evaluated
    /// once there) and before anything touches `CurrencyRateStore.shared`
    /// (its init restores the FX cache from UserDefaults synchronously).
    static func applyEarlyOverridesIfNeeded() {
        guard isActive else { return }

        let defaults = UserDefaults.standard

        // Skip onboarding entirely — the seeded dataset IS the "onboarded" state.
        defaults.set(true, forKey: "hasCompletedOnboarding")

        // Force Pro via the Founding User flag so Voice / OCR tabs, deposits and
        // loans are unlocked without RevenueCat network access.
        defaults.set(true, forKey: "tenra.premium.isFounder.v1")

        // Home budgets/summary read best with a month window (budget rings show
        // progress); .allTime is the migration default otherwise.
        defaults.set(true, forKey: "timeFilterMigrationV1")
        if let filterData = try? JSONEncoder().encode(TimeFilter(preset: .thisMonth)) {
            defaults.set(filterData, forKey: "timeFilter")
        }

        writeBaseCurrencySettings(to: defaults)
        writeOfflineRates(to: defaults)
    }

    /// Persists `AppSettings` JSON with the demo base currency under the same
    /// key `SettingsStorageService` reads ("appSettings").
    private static func writeBaseCurrencySettings(to defaults: UserDefaults) {
        let payload: [String: Any] = [
            "baseCurrency": currencyCode,
            "homeBackgroundMode": "none",
            "blurWallpaper": false,
            "homeBackgroundOpacity": 0.35,
            "quickAccessCurrencies": ["USD", "EUR"]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            defaults.set(data, forKey: "appSettings")
        }
    }

    /// Seeds the KZT-pivot FX cache (`currency.rates.cache.v1`) with a fresh
    /// timestamp so `CurrencyConverter.prewarm()` short-circuits and no
    /// provider is contacted during capture. Shape mirrors the private
    /// `PersistedRates` DTO in CurrencyRateStore (default JSONEncoder coding).
    private static func writeOfflineRates(to defaults: UserDefaults) {
        struct PersistedRatesPayload: Codable {
            let pivot: String
            let rates: [String: Double]
            let fetchedAt: Date
            let providerName: String
        }
        var rates: [String: Double] = [:]
        for (code, profile) in ScreenshotDemoCurrency.profiles where code != "KZT" {
            // profile.perEUR = units of `code` per 1 EUR; KZT per 1 unit of code:
            rates[code] = ScreenshotDemoCurrency.kztPerEUR / profile.perEUR
        }
        let payload = PersistedRatesPayload(
            pivot: "KZT",
            rates: rates,
            fetchedAt: Date(),
            providerName: "ScreenshotDemo"
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: "currency.rates.cache.v1")
        }
    }
}

// MARK: - Currency profiles

/// Per-currency scaling used both for seeding realistic local amounts and for
/// the deterministic offline FX table (both derive from `perEUR`, so converted
/// totals stay consistent).
struct ScreenshotDemoCurrencyProfile {
    /// Units of this currency per 1 EUR (approximate market rate).
    let perEUR: Double
    /// Display/rounding decimals for seeded amounts.
    let decimals: Int
    /// Plausible local annual deposit rate, percent.
    let depositRatePercent: Double
    /// Plausible local annual loan rate, percent.
    let loanRatePercent: Double
}

enum ScreenshotDemoCurrency {

    static let kztPerEUR: Double = 590

    static let profiles: [String: ScreenshotDemoCurrencyProfile] = [
        "EUR": .init(perEUR: 1.0,   decimals: 2, depositRatePercent: 3.5,  loanRatePercent: 6.0),
        "USD": .init(perEUR: 1.1,   decimals: 2, depositRatePercent: 4.0,  loanRatePercent: 7.0),
        "CAD": .init(perEUR: 1.5,   decimals: 2, depositRatePercent: 3.8,  loanRatePercent: 6.5),
        "CHF": .init(perEUR: 0.95,  decimals: 2, depositRatePercent: 1.2,  loanRatePercent: 3.0),
        "GBP": .init(perEUR: 0.85,  decimals: 2, depositRatePercent: 4.0,  loanRatePercent: 6.5),
        "MXN": .init(perEUR: 21.0,  decimals: 2, depositRatePercent: 9.5,  loanRatePercent: 15.0),
        "TRY": .init(perEUR: 38.0,  decimals: 2, depositRatePercent: 42.0, loanRatePercent: 48.0),
        "BRL": .init(perEUR: 6.2,   decimals: 2, depositRatePercent: 11.0, loanRatePercent: 22.0),
        "UAH": .init(perEUR: 46.0,  decimals: 0, depositRatePercent: 13.5, loanRatePercent: 20.0),
        "JPY": .init(perEUR: 172.0, decimals: 0, depositRatePercent: 0.5,  loanRatePercent: 2.0),
        "KRW": .init(perEUR: 1560.0, decimals: 0, depositRatePercent: 3.2, loanRatePercent: 5.0),
        "KZT": .init(perEUR: 590.0, decimals: 0, depositRatePercent: 14.5, loanRatePercent: 19.0),
        "RUB": .init(perEUR: 95.0,  decimals: 0, depositRatePercent: 16.0, loanRatePercent: 22.0)
    ]

    static func profile(for code: String) -> ScreenshotDemoCurrencyProfile {
        profiles[code] ?? profiles["USD"]!
    }

    /// Scales a EUR-reference amount into the demo currency and rounds it to a
    /// "hand-entered" looking value.
    static func amount(_ eurBase: Double, in code: String) -> Double {
        let profile = profile(for: code)
        let raw = eurBase * profile.perEUR
        return niceRound(raw, decimals: profile.decimals)
    }

    static func niceRound(_ value: Double, decimals: Int) -> Double {
        let magnitude = abs(value)
        let rounded: Double
        switch magnitude {
        case ..<10:
            rounded = decimals > 0 ? (value * 10).rounded() / 10 : value.rounded()
        case ..<100:
            rounded = value.rounded()
        case ..<1_000:
            rounded = (value / 10).rounded() * 10
        case ..<100_000:
            rounded = (value / 100).rounded() * 100
        default:
            rounded = (value / 1_000).rounded() * 1_000
        }
        return rounded
    }
}

#endif
