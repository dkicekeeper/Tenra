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
//
//  Also what the user chose for a merchant in its edit sheet (MerchantCategoryEditView):
//  an icon or logo of their own or no logo at all, which a lookup never replaces, and a
//  name, which the merchant's transaction rows show instead of the bank's text.
//
//  Storage: two Codable blobs in `UserDefaults`, the logos and the names.
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
        /// Picked by the user: never looked up again.
        case custom(IconSource)
        /// "No logo", the user's choice: the category icon stays and no lookup runs.
        case hidden
    }

    struct Entry: Codable, Equatable {
        var state: State
        var checkedAt: Date
        /// Whether logo.dev was asked too. nil in entries saved before history merchants
        /// were looked up on device only, all of which were asked.
        var lookedUpOnline: Bool?
    }

    static let shared = MerchantLogoStore()

    private static let storageKey = "merchantLogo.v1"
    private static let namesKey = "merchantName.v1"
    /// The Settings switch (on by default): `@AppStorage` in the views that read it.
    static let enabledKey = "settings.merchantLogos"
    static let recheckInterval: TimeInterval = 30 * 24 * 60 * 60

    @ObservationIgnored private let defaults: UserDefaults
    /// `[normalized merchant: entry]`
    @ObservationIgnored private var entries: [String: Entry]
    /// `[normalized merchant: the name the user gave it]`
    @ObservationIgnored private var names: [String: String]
    /// Raw description → normalized merchant ("" when too short), so a list row normalizes
    /// its text once.
    @ObservationIgnored private var merchantByDescription: [String: String] = [:]
    /// Bumped on every change: reading it is what re-renders a row when a logo is found.
    private(set) var version = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load([String: Entry].self, key: Self.storageKey, from: defaults) ?? [:]
        self.names = Self.load([String: String].self, key: Self.namesKey, from: defaults) ?? [:]
    }

    /// The merchant's logo (found or picked) for a transaction's description, or nil.
    func iconSource(forDescription description: String) -> IconSource? {
        _ = version
        guard let merchant = merchantKey(forDescription: description) else { return nil }
        switch entries[merchant]?.state {
        case .found(let key)?: return .brandService(key)
        case .custom(let icon)?: return icon
        case .missing?, .hidden?, nil: return nil
        }
    }

    /// The name the user gave this transaction's merchant, or nil.
    func customName(forDescription description: String) -> String? {
        _ = version
        return merchantKey(forDescription: description).flatMap { names[$0] }
    }

    private func merchantKey(forDescription description: String) -> String? {
        if let cached = merchantByDescription[description] {
            return cached.isEmpty ? nil : cached
        }
        let merchant = CategorySuggestionService.normalizedMerchant(description)
        let key = merchant.count >= CategorySuggestionService.minimumMerchantLength ? merchant : ""
        merchantByDescription[description] = key
        return key.isEmpty ? nil : key
    }

    /// The merchant's lookup state or the icon the user picked; nil when never looked up.
    func state(forMerchant merchant: String) -> State? {
        Self.key(merchant).flatMap { entries[$0]?.state }
    }

    // MARK: - The user's choices

    /// An icon or logo the user picked for the merchant; nil goes back to the lookup.
    func setCustomIcon(_ icon: IconSource?, forMerchant merchant: String) {
        guard let key = Self.key(merchant) else { return }
        if let icon {
            entries[key] = Entry(state: .custom(icon), checkedAt: Date(), lookedUpOnline: nil)
        } else {
            guard entries.removeValue(forKey: key) != nil else { return }
        }
        version += 1
        persist()
    }

    /// A name the user gave the merchant; nil or empty goes back to the bank's text.
    func setCustomName(_ name: String?, forMerchant merchant: String) {
        guard let key = Self.key(merchant) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard names[key] != (trimmed.isEmpty ? nil : trimmed) else { return }
        names[key] = trimmed.isEmpty ? nil : trimmed
        version += 1
        persistNames()
    }

    /// "No logo" for the merchant, so its rows keep the category icon; false goes back to
    /// the lookup.
    func setHidden(_ hidden: Bool, forMerchant merchant: String) {
        guard let key = Self.key(merchant) else { return }
        if hidden {
            entries[key] = Entry(state: .hidden, checkedAt: Date(), lookedUpOnline: nil)
        } else {
            guard entries[key]?.state == .hidden else { return }
            entries.removeValue(forKey: key)
        }
        version += 1
        persist()
    }

    private static func key(_ merchant: String) -> String? {
        let key = CategorySuggestionService.normalizedMerchant(merchant)
        return key.count >= CategorySuggestionService.minimumMerchantLength ? key : nil
    }

    /// True when the merchant was never looked up, had no logo 30 days ago, or was looked up
    /// on device only and may now be asked online (it turned up in an Apple Pay payment).
    func needsLookup(merchant: String, online: Bool = true, now: Date = Date()) -> Bool {
        let key = CategorySuggestionService.normalizedMerchant(merchant)
        guard key.count >= CategorySuggestionService.minimumMerchantLength else { return false }
        guard let entry = entries[key] else { return true }
        // Found or picked: never looked up again.
        guard entry.state == .missing else { return false }
        return now.timeIntervalSince(entry.checkedAt) > Self.recheckInterval
            || (online && entry.lookedUpOnline == false)
    }

    /// A lookup's result. Never replaces what the user chose meanwhile: an icon or no logo.
    func record(_ state: State, merchant: String, online: Bool = true, now: Date = Date()) {
        guard let key = Self.key(merchant) else { return }
        switch entries[key]?.state {
        case .custom?, .hidden?: return
        default: break
        }
        entries[key] = Entry(state: state, checkedAt: now, lookedUpOnline: online)
        version += 1
        persist()
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        entries = [:]
        names = [:]
        version += 1
        defaults.removeObject(forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.namesKey)
    }

    // MARK: - Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func persistNames() {
        guard let data = try? JSONEncoder().encode(names) else { return }
        defaults.set(data, forKey: Self.namesKey)
    }
}
