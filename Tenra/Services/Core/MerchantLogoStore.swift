//
//  MerchantLogoStore.swift
//  Tenra
//
//  Which merchants have a real logo, and under which key LogoService draws it
//  (docs/plan-auto-capture.md §5). A transaction row shows the merchant's logo
//  instead of its category icon only once MerchantLogoResolver found one: the
//  provider chain always ends in a lettermark, which would be worse than the
//  category icon, so a merchant without a logo keeps its category icon.
//
//  Keyed by `CategorySuggestionService.normalizedMerchant`, like the merchant
//  memory, so every description of one merchant ("MAGNUM CASH&CARRY 123",
//  "... 456") gets the same logo, whatever recorded it.
//
//  "No logo" is checked again after 30 days: tenra-assets and logo.dev grow.
//  Storage: a single Codable blob in `UserDefaults`.
//

import Foundation
import Observation

@MainActor
@Observable
final class MerchantLogoStore {

    enum State: Codable, Equatable {
        /// The key LogoService draws: a registry domain, a tenra-assets name, or
        /// `LogoDevNameProvider.scheme` + the merchant's name.
        case found(String)
        case missing
    }

    struct Entry: Codable, Equatable {
        var state: State
        var checkedAt: Date
    }

    static let shared = MerchantLogoStore()

    private static let storageKey = "merchantLogo.v1"
    /// The Settings switch (on by default): `@AppStorage` in the views that read it.
    static let enabledKey = "settings.merchantLogos"
    static let recheckInterval: TimeInterval = 30 * 24 * 60 * 60

    @ObservationIgnored private let defaults: UserDefaults
    /// `[normalized merchant: entry]`
    @ObservationIgnored private var entries: [String: Entry]
    /// Raw description → logo key ("" when none), so a list row normalizes its text once.
    @ObservationIgnored private var keyByDescription: [String: String] = [:]
    /// Bumped on every change: reading it is what re-renders a row when a logo is found.
    private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    /// The merchant's logo for a transaction's description, or nil when none was found.
    func iconSource(forDescription description: String) -> IconSource? {
        _ = version
        if let key = keyByDescription[description] {
            return key.isEmpty ? nil : .brandService(key)
        }
        let merchant = CategorySuggestionService.normalizedMerchant(description)
        var key = ""
        if merchant.count >= CategorySuggestionService.minimumMerchantLength,
           case .found(let found)? = entries[merchant]?.state {
            key = found
        }
        keyByDescription[description] = key
        return key.isEmpty ? nil : .brandService(key)
    }

    /// True when the merchant was never looked up, or had no logo 30 days ago.
    func needsLookup(merchant: String, now: Date = Date()) -> Bool {
        let key = CategorySuggestionService.normalizedMerchant(merchant)
        guard key.count >= CategorySuggestionService.minimumMerchantLength else { return false }
        guard let entry = entries[key] else { return true }
        return entry.state == .missing && now.timeIntervalSince(entry.checkedAt) > Self.recheckInterval
    }

    func record(_ state: State, merchant: String, now: Date = Date()) {
        let key = CategorySuggestionService.normalizedMerchant(merchant)
        guard key.count >= CategorySuggestionService.minimumMerchantLength else { return }
        entries[key] = Entry(state: state, checkedAt: now)
        keyByDescription = [:]
        version += 1
        persist()
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        entries = [:]
        keyByDescription = [:]
        version += 1
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
