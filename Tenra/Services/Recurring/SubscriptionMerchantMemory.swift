//
//  SubscriptionMerchantMemory.swift
//  Tenra
//
//  Which subscription a merchant charges for, as the person said it: an expense linked to a
//  subscription by hand ("This is a subscription…", Link payments, "Merge" in To review)
//  teaches its merchant, so the next charge from that merchant merges into the planned one on
//  its own, whatever its name, account or currency (SubscriptionChargeMatcher, tier 1). A
//  suggestion the person turned down is kept too, so it is not asked again.
//
//  Keyed on the normalized merchant (MerchantCategoryMemory.key), one UserDefaults blob. A
//  deleted subscription simply matches nothing. docs/domains/recurring.md §Real charges.
//

import Foundation

@MainActor
final class SubscriptionMerchantMemory {

    static let shared = SubscriptionMerchantMemory()

    private static let storageKey = "subscription.merchants.v1"

    private struct Snapshot: Codable {
        /// `[normalized merchant: series id]`
        var seriesByMerchant: [String: String]
        /// `[normalized merchant: series ids turned down]`
        var dismissed: [String: [String]]
    }

    private let defaults: UserDefaults
    private var snapshot: Snapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = Snapshot(seriesByMerchant: [:], dismissed: [:])
        }
    }

    /// The subscription the person linked this merchant to.
    func seriesId(forMerchant merchant: String) -> String? {
        MerchantCategoryMemory.key(forMerchant: merchant).flatMap { snapshot.seriesByMerchant[$0] }
    }

    func remember(seriesId: String, forMerchant merchant: String) {
        guard let key = MerchantCategoryMemory.key(forMerchant: merchant) else { return }
        snapshot.seriesByMerchant[key] = seriesId
        snapshot.dismissed[key]?.removeAll { $0 == seriesId }
        persist()
    }

    /// The subscriptions the person said this merchant is not.
    func dismissedSeriesIds(forMerchant merchant: String) -> Set<String> {
        MerchantCategoryMemory.key(forMerchant: merchant).map { Set(snapshot.dismissed[$0] ?? []) } ?? []
    }

    func dismiss(seriesId: String, forMerchant merchant: String) {
        guard let key = MerchantCategoryMemory.key(forMerchant: merchant) else { return }
        var ids = snapshot.dismissed[key] ?? []
        guard !ids.contains(seriesId) else { return }
        ids.append(seriesId)
        snapshot.dismissed[key] = ids
        persist()
    }

    /// Wipe everything. Exposed for tests.
    func reset() {
        snapshot = Snapshot(seriesByMerchant: [:], dismissed: [:])
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
