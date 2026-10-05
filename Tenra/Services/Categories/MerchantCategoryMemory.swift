//
//  MerchantCategoryMemory.swift
//  Tenra
//
//  Remembers which expense category, and which subcategory, the user chose
//  for a merchant, so the Shortcuts "Wallet" automation (Apple Pay →
//  AddExpenseIntent with the merchant as the note) asks once per merchant
//  instead of on every payment.
//
//  One explicit choice is enough: unlike VoiceLearningStore there is no
//  confidence threshold, because nothing here is ever inferred. Entries are
//  written only when the user picked the category (in the intent, or by
//  passing it from the automation), and corrected when the user later changes
//  the category or subcategory of such a transaction in the app.
//
//  Keyed by `CategorySuggestionService.normalizedMerchant`, so the store
//  numbers and punctuation Wallet appends ("MAGNUM CASH&CARRY 123") do not
//  split one merchant into many. Stores ids, not names, so a rename keeps
//  working; a deleted category simply reads as unknown again.
//
//  Storage: a single Codable blob in `UserDefaults`, like VoiceLearningStore.
//  The natural ceiling is the number of distinct merchants the user pays with
//  Apple Pay, which stays small.
//

import Foundation

@MainActor
final class MerchantCategoryMemory {

    struct Entry: Codable, Equatable {
        var categoryId: String
        /// nil: never decided (the category came from the automation, or the
        /// category had no subcategories when asked). Empty: the user chose
        /// "no subcategory".
        var subcategoryIds: [String]?
    }

    static let shared = MerchantCategoryMemory()

    private static let storageKey = "intent.merchantCategory.v1"

    private let defaults: UserDefaults
    /// `[normalized merchant: entry]`
    private var entries: [String: Entry]

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
        guard let entry = entry(forMerchant: merchant) else { return nil }
        return categories.first { $0.id == entry.categoryId && $0.type == .expense }
    }

    /// The subcategory decision for this merchant (see `Entry.subcategoryIds`).
    /// The caller checks the ids against the category's current subcategories.
    func subcategoryIds(forMerchant merchant: String) -> [String]? {
        entry(forMerchant: merchant)?.subcategoryIds
    }

    /// Records the user's choice. The latest choice wins. A nil
    /// `subcategoryIds` keeps the earlier subcategory decision while the
    /// category stays the same, so an automation that passes only a fixed
    /// category does not erase a subcategory fixed in the app.
    func remember(categoryId: String, subcategoryIds: [String]? = nil, forMerchant merchant: String) {
        guard !categoryId.isEmpty, let key = Self.key(forMerchant: merchant) else { return }
        var entry = Entry(categoryId: categoryId, subcategoryIds: subcategoryIds?.sorted())
        if subcategoryIds == nil, let previous = entries[key], previous.categoryId == categoryId {
            entry.subcategoryIds = previous.subcategoryIds
        }
        guard entries[key] != entry else { return }
        entries[key] = entry
        persist()
    }

    /// Follows a category or subcategory change the user made in the app, but
    /// only for a merchant that is already remembered: every in-app edit is not
    /// a reason to start remembering a merchant the automation never sees.
    func correct(categoryId: String, subcategoryIds: [String], forMerchant merchant: String) {
        guard entry(forMerchant: merchant) != nil else { return }
        remember(categoryId: categoryId, subcategoryIds: subcategoryIds, forMerchant: merchant)
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        entries = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func entry(forMerchant merchant: String) -> Entry? {
        Self.key(forMerchant: merchant).flatMap { entries[$0] }
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
