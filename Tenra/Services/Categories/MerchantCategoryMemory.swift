//
//  MerchantCategoryMemory.swift
//  Tenra
//
//  Remembers which expense category the user chose for a merchant, so the
//  Shortcuts "Wallet" automation (Apple Pay → AddExpenseIntent with the
//  merchant as the note) asks for a category once per merchant instead of on
//  every payment.
//
//  One explicit choice is enough: unlike VoiceLearningStore there is no
//  confidence threshold, because nothing here is ever inferred. Entries are
//  written only when the user picked the category (in the intent, or by
//  passing it from the automation), and corrected when the user later changes
//  the category of such a transaction in the app.
//
//  Keyed by `CategorySuggestionService.normalizedMerchant`, so the store
//  numbers and punctuation Wallet appends ("MAGNUM CASH&CARRY 123") do not
//  split one merchant into many. Stores the category ID, not its name, so a
//  rename keeps working; a deleted category simply reads as unknown again.
//
//  Storage: a single Codable blob in `UserDefaults`, like VoiceLearningStore.
//  The natural ceiling is the number of distinct merchants the user pays with
//  Apple Pay, which stays small.
//

import Foundation

@MainActor
final class MerchantCategoryMemory {

    static let shared = MerchantCategoryMemory()

    private static let storageKey = "intent.merchantCategory.v1"

    private let defaults: UserDefaults
    /// `[normalized merchant: category id]`
    private var entries: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    /// The normalized key for a merchant, or nil when the text carries too
    /// little signal to remember anything by (empty, digits only, two letters).
    static func key(forMerchant merchant: String) -> String? {
        let key = CategorySuggestionService.normalizedMerchant(merchant)
        guard key.count >= CategorySuggestionService.minimumMerchantLength else { return nil }
        return key
    }

    /// The expense category last chosen for this merchant, if it still exists.
    func category(forMerchant merchant: String, in categories: [CustomCategory]) -> CustomCategory? {
        guard let key = Self.key(forMerchant: merchant),
              let id = entries[key] else { return nil }
        return categories.first { $0.id == id && $0.type == .expense }
    }

    /// Records the user's choice. The latest choice wins.
    func remember(categoryId: String, forMerchant merchant: String) {
        guard !categoryId.isEmpty,
              let key = Self.key(forMerchant: merchant),
              entries[key] != categoryId else { return }
        entries[key] = categoryId
        persist()
    }

    /// Follows a category change the user made in the app, but only for a
    /// merchant that is already remembered: every in-app edit is not a reason
    /// to start remembering a merchant the automation never sees.
    func correct(categoryId: String, forMerchant merchant: String) {
        guard let key = Self.key(forMerchant: merchant), entries[key] != nil else { return }
        remember(categoryId: categoryId, forMerchant: merchant)
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        entries = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
