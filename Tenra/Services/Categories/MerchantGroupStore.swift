//
//  MerchantGroupStore.swift
//  Tenra
//
//  What the person told Tenra about their merchants beyond the bank's text (the owner's
//  requests, 2026-10-30):
//
//  - **Brands.** Points of one brand the bank names apart ("ZARA MEGA" and "ZARA DOSTYK
//    PLAZA") merged into one merchant: its screen (MerchantDetailView) shows every point's
//    operations and figures, and filters by point.
//  - **Linked operations.** An operation entered by hand ("Куртка") linked to a merchant: it
//    counts as that merchant's wherever its description points.
//
//  Points are keyed by `CategorySuggestionService.normalizedMerchant`, like the merchant
//  memory and the logos, so the store numbers the bank adds never split a point. A brand's
//  name is the one the person typed, else the words its points start with ("Zara").
//
//  Storage: one Codable blob in `UserDefaults`, like MerchantCategoryMemory. The screen's
//  history sweep runs off the main actor with a `Selection` (Sendable) taken from it.
//

import Foundation
import Observation

@MainActor
@Observable
final class MerchantGroupStore {

    /// Points of one brand.
    struct Group: Codable, Equatable, Identifiable {
        let id: String
        /// The points' normalized merchants, in the order they joined.
        var members: [String]
        /// Each point as the bank last wrote it, for its chip.
        var memberNames: [String: String]
        /// The name the person typed; nil: the words the points share.
        var name: String?
    }

    /// What one merchant's screen reads, taken on the main actor for the sweep off it.
    nonisolated struct Selection: Sendable, Equatable {
        /// The normalized merchants whose operations count.
        let merchants: Set<String>
        /// Operations linked by hand: transaction id → normalized merchant.
        let links: [String: String]

        /// The merchant an operation belongs to: its link, else its description's.
        func merchant(of transaction: Transaction) -> String {
            links[transaction.id] ?? CategorySuggestionService.normalizedMerchant(transaction.description)
        }

        func contains(_ transaction: Transaction) -> Bool {
            merchants.contains(merchant(of: transaction))
        }
    }

    private struct Stored: Codable {
        var groups: [Group]
        /// Transaction id → the merchant as the bank wrote it (normalized on read).
        var links: [String: String]
    }

    static let shared = MerchantGroupStore()

    private static let storageKey = "merchant.groups.v1"

    @ObservationIgnored private let defaults: UserDefaults
    /// After every change: Insights' top merchant counts brands (AppCoordinator).
    @ObservationIgnored var didChange: () -> Void = {}
    private(set) var groups: [Group]
    /// Transaction id → the merchant it is linked to, as the bank wrote it.
    private(set) var links: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load(from: defaults)
        self.groups = stored?.groups ?? []
        self.links = stored?.links ?? [:]
    }

    // MARK: - Reading

    /// The brand a point belongs to.
    func group(forMerchant merchant: String) -> Group? {
        guard let key = MerchantCategoryMemory.key(forMerchant: merchant) else { return nil }
        return group(forKey: key)
    }

    func group(forKey key: String) -> Group? {
        groups.first { $0.members.contains(key) }
    }

    /// The operations of a merchant's screen: its brand's points, or only `point` of them
    /// (a normalized merchant), with the operations linked to them.
    func selection(forMerchant merchant: String, point: String? = nil) -> Selection {
        let key = CategorySuggestionService.normalizedMerchant(merchant)
        let members: Set<String>
        if let point {
            members = [point]
        } else {
            members = Set(group(forKey: key)?.members ?? [key])
        }
        var normalized: [String: String] = [:]
        for (id, name) in links {
            let linked = CategorySuggestionService.normalizedMerchant(name)
            if members.contains(linked) { normalized[id] = linked }
        }
        return Selection(merchants: members, links: normalized)
    }

    /// The brands and links for a sweep off the main actor (Insights' top merchant).
    var brands: MerchantBrands {
        var brandOfPoint: [String: String] = [:]
        var names: [String: String] = [:]
        for group in groups {
            for member in group.members { brandOfPoint[member] = group.id }
            names[group.id] = displayName(of: group)
        }
        var normalized: [String: String] = [:]
        for (id, name) in links {
            normalized[id] = CategorySuggestionService.normalizedMerchant(name)
        }
        return MerchantBrands(brandOfPoint: brandOfPoint, names: names, links: normalized)
    }

    /// The merchant an operation was linked to by hand, as the bank wrote it.
    func linkedMerchant(forTransactionId id: String) -> String? {
        links[id]
    }

    /// The brand's name: the person's, else the words every point starts with, else the
    /// first point's name.
    func displayName(of group: Group) -> String {
        if let name = group.name, !name.isEmpty { return name }
        let names = group.members.compactMap { group.memberNames[$0] }
        if let shared = Self.sharedLeadingWords(of: names) { return MerchantName.displayName(shared) }
        return names.first.map(MerchantName.displayName) ?? ""
    }

    /// The words every name starts with ("ZARA MEGA", "ZARA DOSTYK PLAZA" → "ZARA"), compared
    /// as normalized merchants; nil when they share none long enough to name a brand.
    nonisolated static func sharedLeadingWords(of names: [String]) -> String? {
        guard let first = names.first, names.count > 1 else { return nil }
        let words = names.map { CategorySuggestionService.normalizedMerchant($0).split(separator: " ") }
        var count = 0
        while let word = words[0].dropFirst(count).first,
              words.allSatisfy({ $0.count > count && $0[count] == word }) {
            count += 1
        }
        guard count > 0 else { return nil }
        let shared = words[0].prefix(count).joined(separator: " ")
        guard shared.count >= CategorySuggestionService.minimumMerchantLength else { return nil }
        // The person's spelling of those words, from the first name.
        let originals = first.split(whereSeparator: \.isWhitespace)
        var taken: [Substring] = []
        for word in originals {
            let joined = CategorySuggestionService.normalizedMerchant((taken + [word]).joined(separator: " "))
            if joined.count > shared.count { break }
            taken.append(word)
            if joined == shared { break }
        }
        let original = taken.joined(separator: " ")
        return CategorySuggestionService.normalizedMerchant(original) == shared ? original : shared
    }

    // MARK: - Brands

    /// Merges points (as the bank wrote them) into one brand with `merchant`, the screen's.
    /// Brands any of them already belong to merge whole.
    func merge(_ others: [String], into merchant: String) {
        let named = ([merchant] + others).compactMap { name -> (key: String, name: String)? in
            guard let key = MerchantCategoryMemory.key(forMerchant: name) else { return nil }
            return (key, name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let anchor = named.first else { return }
        var members: [String] = []
        var memberNames: [String: String] = [:]
        var name: String?
        var absorbed = Set<String>()
        for point in named {
            if let existing = group(forKey: point.key) {
                guard !absorbed.contains(existing.id) else { continue }
                absorbed.insert(existing.id)
                name = name ?? existing.name
                for member in existing.members where !members.contains(member) {
                    members.append(member)
                    memberNames[member] = existing.memberNames[member]
                }
            } else if !members.contains(point.key) {
                members.append(point.key)
                memberNames[point.key] = point.name
            }
        }
        guard members.count > 1 else { return }
        let id = group(forKey: anchor.key)?.id ?? UUID().uuidString
        groups.removeAll { absorbed.contains($0.id) }
        groups.append(Group(id: id, members: members, memberNames: memberNames, name: name))
        persist()
    }

    /// Takes a point out of its brand; a brand left with one point is no brand.
    func remove(point key: String) {
        guard let index = groups.firstIndex(where: { $0.members.contains(key) }) else { return }
        groups[index].members.removeAll { $0 == key }
        groups[index].memberNames[key] = nil
        if groups[index].members.count < 2 { groups.remove(at: index) }
        persist()
    }

    /// The brand's points go back to being merchants of their own.
    func dissolve(groupId: String) {
        guard groups.contains(where: { $0.id == groupId }) else { return }
        groups.removeAll { $0.id == groupId }
        persist()
    }

    /// The name the person gave the brand; empty or nil: the shared words again.
    func rename(groupId: String, to name: String?) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard groups[index].name != value else { return }
        groups[index].name = value
        persist()
    }

    // MARK: - Linked operations

    /// Links operations to a merchant (as the bank wrote it): they count as its whatever
    /// their description says.
    func link(transactionIds: [String], toMerchant merchant: String) {
        guard MerchantCategoryMemory.key(forMerchant: merchant) != nil, !transactionIds.isEmpty else { return }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in transactionIds { links[id] = name }
        persist()
    }

    func unlink(transactionId id: String) {
        guard links.removeValue(forKey: id) != nil else { return }
        persist()
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        groups = []
        links = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults) -> Stored? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Stored(groups: groups, links: links)) {
            defaults.set(data, forKey: Self.storageKey)
        }
        didChange()
    }
}

/// The person's brands and linked operations as plain values, for a sweep off the main actor.
nonisolated struct MerchantBrands: Sendable {
    /// A point (normalized merchant) → its brand's id.
    let brandOfPoint: [String: String]
    /// A brand's id → its name.
    let names: [String: String]
    /// Transaction id → the normalized merchant it is linked to.
    let links: [String: String]

    static let none = MerchantBrands(brandOfPoint: [:], names: [:], links: [:])

    var isEmpty: Bool { brandOfPoint.isEmpty && links.isEmpty }

    /// The merchant an operation counts for: its link, else `described` (its description's,
    /// normalized by the caller), and the brand that merchant belongs to.
    func merchant(of transaction: Transaction, described: String) -> String {
        let point = links[transaction.id] ?? described
        return brandOfPoint[point].map { Self.brandPrefix + $0 } ?? point
    }

    /// The name of a brand `merchant(of:described:)` returned; nil for a single point.
    func brandName(_ merchant: String) -> String? {
        guard merchant.hasPrefix(Self.brandPrefix) else { return nil }
        return names[String(merchant.dropFirst(Self.brandPrefix.count))]
    }

    /// Normalized merchants are letters and spaces: a brand's key never collides with one.
    private static let brandPrefix = "#brand:"
}

/// The merchants of a history, to pick the points of a brand from (MerchantMergeView). Pure
/// and `nonisolated`: the sweep runs off the main actor (red flag #9).
nonisolated enum MerchantDirectory {

    /// A merchant of the history: its normalized key, its latest description, how often.
    struct Entry: Identifiable, Sendable, Equatable {
        let id: String
        let name: String
        let count: Int
        /// Starts with the same word as the merchant it is offered to.
        let isSuggested: Bool
    }

    /// The expenses and income a merchant's screen does not count yet, to link to it by hand.
    static func linkCandidates(in transactions: [Transaction], excluding selection: MerchantGroupStore.Selection) -> [Transaction] {
        transactions.filter { tx in
            (tx.type == .expense || tx.type == .income) && !selection.contains(tx)
        }
    }

    /// Every merchant of the history's expenses and income but `excluded`: those that share the
    /// first word of `key` first, then the most frequent.
    static func entries(in transactions: [Transaction], excluding excluded: Set<String>, like key: String) -> [Entry] {
        var counts: [String: (name: String, date: String, count: Int)] = [:]
        for tx in transactions where tx.type == .expense || tx.type == .income {
            let merchant = CategorySuggestionService.normalizedMerchant(tx.description)
            guard merchant.count >= CategorySuggestionService.minimumMerchantLength,
                  !excluded.contains(merchant) else { continue }
            var entry = counts[merchant] ?? (name: tx.description, date: tx.date, count: 0)
            entry.count += 1
            // The latest description names it: the bank's current spelling.
            if tx.date > entry.date {
                entry.name = tx.description
                entry.date = tx.date
            }
            counts[merchant] = entry
        }
        let firstWord = key.split(separator: " ").first.map(String.init) ?? ""
        return counts
            .map { merchant, entry in
                Entry(
                    id: merchant,
                    name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    count: entry.count,
                    isSuggested: !firstWord.isEmpty
                        && merchant.split(separator: " ").first.map(String.init) == firstWord
                )
            }
            .sorted { lhs, rhs in
                if lhs.isSuggested != rhs.isSuggested { return lhs.isSuggested }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.id < rhs.id
            }
    }
}
