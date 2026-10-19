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
//  app, when it comes to the front, for the merchants Apple Pay payments came from
//  (remembered or captured), a few per pass: an intent never makes this request.
//

import Foundation

@MainActor
enum MerchantLogoResolver {

    /// Lookups per pass, so a long list of new merchants spreads over a few launches.
    private static let lookupsPerPass = 12

    private static var isRunning = false

    /// Looks up the merchants that were never looked up, or had no logo a month ago.
    static func resolvePending(store: MerchantLogoStore = .shared) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var seen = Set<String>()
        let merchants = (MerchantCategoryMemory.shared.merchants.map(\.displayName) + WalletCaptureStore.shared.merchants)
            .filter { seen.insert(CategorySuggestionService.normalizedMerchant($0)).inserted }
            .filter { store.needsLookup(merchant: $0) }
            .prefix(lookupsPerPass)

        for merchant in merchants {
            store.record(await lookUp(merchant), merchant: merchant)
        }
    }

    static func lookUp(_ merchant: String) async -> MerchantLogoStore.State {
        let name = MerchantName.displayName(merchant)

        if let domain = registryDomain(forMerchant: name) {
            return .found(domain)
        }
        if let indexName = await JsDelivrLogoProvider.indexName(forMerchant: name) {
            return .found(indexName)
        }
        // A sole proprietor's name is a person's: it stays on the device.
        if !MerchantName.isSoleProprietor(merchant), let image = await LogoDevNameProvider.fetch(name: name) {
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
