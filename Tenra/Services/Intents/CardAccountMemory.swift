//
//  CardAccountMemory.swift
//  Tenra
//
//  Remembers which account a Wallet card pays from, so one Wallet automation
//  on "Any Card" records every card's payments on the right account
//  (LogWalletPaymentIntent). The card arrives as the automation's
//  "Card or Pass" text ("Kaspi Gold").
//
//  Written only from a choice the user made: an account fixed in the
//  automation, a captured payment saved from the edit screen, or "Correct" in
//  the To review list. A guessed account is never remembered, or the first
//  guess would decide every later payment of that card.
//
//  Storage: a single Codable blob in `UserDefaults`, like MerchantCategoryMemory.
//  The natural ceiling is the number of cards in Wallet.
//

import Foundation
import Observation

@MainActor
@Observable
final class CardAccountMemory {

    struct Entry: Codable, Equatable {
        var accountId: String
        /// The card as Wallet last wrote it, for display.
        var displayName: String
    }

    static let shared = CardAccountMemory()

    private static let storageKey = "intent.cardAccount.v1"

    @ObservationIgnored private let defaults: UserDefaults
    /// `[normalized card: entry]`
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    /// The key for a card: lowercased, whitespace collapsed. nil for an empty card,
    /// which is what an automation that does not pass the card sends.
    static func key(forCard card: String) -> String? {
        let key = card
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return key.isEmpty ? nil : key
    }

    /// The account the user chose for this card, if any. The caller checks it still exists.
    func accountId(forCard card: String) -> String? {
        Self.key(forCard: card).flatMap { entries[$0]?.accountId }
    }

    /// Records the user's choice. The latest choice wins.
    func remember(accountId: String, forCard card: String) {
        guard !accountId.isEmpty, let key = Self.key(forCard: card) else { return }
        let entry = Entry(
            accountId: accountId,
            displayName: card.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard entries[key] != entry else { return }
        entries[key] = entry
        persist()
    }

    /// Forgets a card: its next payment goes to the suggested account again.
    func forget(card: String) {
        guard let key = Self.key(forCard: card), entries.removeValue(forKey: key) != nil else { return }
        persist()
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        entries = [:]
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
