//
//  VoiceLearningStore.swift
//  Tenra
//
//  Lightweight persistent learning for voice-input account suggestions.
//
//  Records every (category → account) pair the user confirms via the voice
//  flow, keeping a hit count per pair. When the parser needs to pick a
//  default account for a parsed category, it consults this store first —
//  user-confirmed choices override usage-based heuristics.
//
//  Storage: a single Codable blob in `UserDefaults`. Small enough that we
//  don't need CoreData. If the dataset grows past a few hundred categories
//  we should migrate, but the natural ceiling is "number of distinct
//  category names the user actually uses" which stays small.
//

import Foundation

final class VoiceLearningStore: @unchecked Sendable {

    // MARK: - Shared instance

    static let shared = VoiceLearningStore()

    // MARK: - Configuration

    /// Categories below this hit count don't override usage-based defaults.
    /// Prevents one accidental tap from locking in a wrong account forever.
    private static let confidenceThreshold = 2

    private static let storageKey = "voice.learning.preferences.v1"

    // MARK: - State

    private let defaults: UserDefaults
    private var cache: PreferenceBlob

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cache = Self.load(from: defaults) ?? PreferenceBlob()
    }

    // MARK: - Public API

    /// Increment the hit counter for a (category, accountId) pair.
    /// Empty / nil category is stored under the empty-string key so it
    /// participates in the global recall flow.
    func recordSave(category: String?, accountId: String?) {
        guard let accountId, !accountId.isEmpty else { return }
        let key = Self.normalize(category)
        var bucket = cache.preferences[key] ?? [:]
        bucket[accountId, default: 0] += 1
        cache.preferences[key] = bucket
        persist()
    }

    /// Return the user's preferred account ID for this category, or nil if
    /// the store has no confident preference yet.
    /// - Parameter category: Category name; nil falls back to the global
    ///   (empty-key) bucket.
    /// - Parameter filter: Optional closure to exclude inactive / wrong-type
    ///   accounts. The caller passes its live account list and decides what
    ///   counts as "still usable".
    func preferredAccountID(forCategory category: String?, where filter: (String) -> Bool = { _ in true }) -> String? {
        let key = Self.normalize(category)
        guard let bucket = cache.preferences[key] else { return nil }
        let ranked = bucket
            .filter { $0.value >= Self.confidenceThreshold && filter($0.key) }
            .sorted { $0.value > $1.value }
        return ranked.first?.key
    }

    /// Wipe everything — exposed for tests and Settings-level "forget me".
    func reset() {
        cache = PreferenceBlob()
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private struct PreferenceBlob: Codable {
        /// `[category-key: [accountId: hits]]`. The category key is
        /// `normalize(...)` of the user-facing category name.
        var preferences: [String: [String: Int]] = [:]
    }

    private static func load(from defaults: UserDefaults) -> PreferenceBlob? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PreferenceBlob.self, from: data)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func normalize(_ category: String?) -> String {
        guard let category, !category.isEmpty else { return "" }
        return category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
