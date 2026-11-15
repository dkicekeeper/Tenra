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
//  A merchant may charge for several subscriptions: a biller such as "APPLE.COM/BILL" charges
//  for iCloud, a game and an app alike, so every subscription linked to it is kept, and the
//  amount tells them apart (SubscriptionChargeMatcher).
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
        /// `[normalized merchant: the series last linked]`, kept for snapshots saved before
        /// `seriesSetByMerchant`.
        var seriesByMerchant: [String: String]
        /// `[normalized merchant: every series linked to it]`. nil in snapshots saved before it.
        var seriesSetByMerchant: [String: [String]]?
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
            snapshot = Snapshot(seriesByMerchant: [:], seriesSetByMerchant: [:], dismissed: [:])
        }
    }

    /// The subscription the person linked this merchant to last.
    func seriesId(forMerchant merchant: String) -> String? {
        MerchantCategoryMemory.key(forMerchant: merchant).flatMap { snapshot.seriesByMerchant[$0] }
    }

    /// Every subscription the person linked this merchant to.
    func seriesIds(forMerchant merchant: String) -> Set<String> {
        guard let key = MerchantCategoryMemory.key(forMerchant: merchant) else { return [] }
        var ids = Set(snapshot.seriesSetByMerchant?[key] ?? [])
        if let last = snapshot.seriesByMerchant[key] { ids.insert(last) }
        return ids
    }

    func remember(seriesId: String, forMerchant merchant: String) {
        guard let key = MerchantCategoryMemory.key(forMerchant: merchant) else { return }
        var set = snapshot.seriesSetByMerchant ?? [:]
        var ids = set[key] ?? snapshot.seriesByMerchant[key].map { [$0] } ?? []
        if !ids.contains(seriesId) { ids.append(seriesId) }
        set[key] = ids
        snapshot.seriesSetByMerchant = set
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
        snapshot = Snapshot(seriesByMerchant: [:], seriesSetByMerchant: [:], dismissed: [:])
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
