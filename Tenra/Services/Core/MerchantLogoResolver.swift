//
//  MerchantLogoResolver.swift
//  Tenra
//
//  Finds a merchant's logo once and records it in MerchantLogoStore
//  (docs/plan-auto-capture.md §5), most private source first:
//
//  1. ServiceLogoRegistry by the merchant's clean name or its first words: on device;
//  2. the tenra-assets index (JsDelivrLogoProvider.indexName): matched on device;
//  3. logo.dev by name (LogoDevNameProvider, owner's decision 2026-10-19): the clean
//     name, and nothing else about the payment, leaves the device; never for a sole
//     proprietor (ИП), whose name is a person's.
//
//  Nothing found → `.missing`, and the row keeps its category icon. Runs only in the
//  app, when it comes to the front: an intent never makes these requests.
//
//  Two kinds of merchants:
//  • the ones Apple Pay payments came from (remembered or captured): all three sources,
//    a few per pass. Apple Pay only pays shops, never people;
//  • the frequent ones in the history (statement imports, hand entries): sources 1 and 2
//    only. A statement's rows include transfers to people ("Асель К."), and a person's
//    name must never leave the device.
//

import Foundation

@MainActor
enum MerchantLogoResolver {

    /// Online lookups per pass, so a long list of new merchants spreads over a few launches.
    private static let lookupsPerPass = 12
    /// On-device lookups per pass: no request but the daily tenra-assets index.
    private static let localLookupsPerPass = 50
    /// Visits that make a history merchant worth a logo.
    nonisolated static let frequentVisits = 3

    private static var isRunning = false
    /// The history pass runs at most every 12 hours: the counts barely move in between.
    private static var lastHistoryPass: Date?
    private static let historyPassInterval: TimeInterval = 12 * 60 * 60

    /// Looks up the merchants that were never looked up, or had no logo a month ago.
    /// `history`: the loaded transactions (empty before the full load), counted off the
    /// main actor.
    static func resolvePending(history: [Transaction] = [], store: MerchantLogoStore = .shared) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var seen = Set<String>()
        let applePay = (MerchantCategoryMemory.shared.merchants.map(\.displayName) + WalletCaptureStore.shared.merchants)
            .filter { seen.insert(CategorySuggestionService.normalizedMerchant($0)).inserted }
        for merchant in applePay.filter({ store.needsLookup(merchant: $0, online: true) }).prefix(lookupsPerPass) {
            store.record(await lookUp(merchant, online: true), merchant: merchant, online: true)
        }

        let now = Date()
        guard !history.isEmpty,
              lastHistoryPass.map({ now.timeIntervalSince($0) > historyPassInterval }) ?? true else { return }
        lastHistoryPass = now
        let frequent = await Task.detached(priority: .utility) {
            frequentMerchants(in: history, minimumVisits: frequentVisits)
        }.value
        let local = frequent
            .filter { seen.insert(CategorySuggestionService.normalizedMerchant($0)).inserted }
            .filter { store.needsLookup(merchant: $0, online: false) }
            .prefix(localLookupsPerPass)
        for merchant in local {
            store.record(await lookUp(merchant, online: false), merchant: merchant, online: false)
        }
    }

    /// Expense and income descriptions that name the same merchant at least
    /// `minimumVisits` times, most frequent first, each as it was first written.
    nonisolated static func frequentMerchants(in transactions: [Transaction], minimumVisits: Int) -> [String] {
        var visits: [String: (count: Int, sample: String)] = [:]
        for tx in transactions where tx.type == .expense || tx.type == .income {
            let key = CategorySuggestionService.normalizedMerchant(tx.description)
            guard key.count >= CategorySuggestionService.minimumMerchantLength else { continue }
            visits[key, default: (0, tx.description)].count += 1
        }
        return visits
            .filter { $0.value.count >= minimumVisits }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { $0.value.sample }
    }

    /// `online`: whether logo.dev may be asked by name (Apple Pay merchants only).
    static func lookUp(_ merchant: String, online: Bool = true) async -> MerchantLogoStore.State {
        let name = MerchantName.displayName(merchant)

        if let domain = registryDomain(forMerchant: name) {
            return .found(domain)
        }
        if let indexName = await JsDelivrLogoProvider.indexName(forMerchant: name) {
            return .found(indexName)
        }
        // A sole proprietor's name is a person's: it stays on the device.
        if online, !MerchantName.isSoleProprietor(merchant), let image = await LogoDevNameProvider.fetch(name: name) {
            let key = LogoDevNameProvider.scheme + name
            LogoDiskCache.shared.save(image, for: key)
            return .found(key)
        }
        return .missing
    }

    /// The registry's domain for a clean merchant name: the whole name, its first two
    /// words, or its first word ("Netflix", "Yandex Go", "Starbucks Coffee" → Starbucks).
    static func registryDomain(forMerchant name: String) -> String? {
        let words = CategorySuggestionService.normalizedMerchant(name).split(separator: " ").map(String.init)
        var candidates = [name.lowercased(), words.joined(separator: " ")]
        if words.count > 2 { candidates.append(words.prefix(2).joined(separator: " ")) }
        if let first = words.first, first.count >= CategorySuggestionService.minimumMerchantLength {
            candidates.append(first)
        }
        return candidates.lazy.compactMap { ServiceLogoRegistry.aliasMap[$0]?.domain }.first
    }
}
