//
//  LogoService.swift
//  AIFinanceManager
//
//  Central logo service using waterfall provider chain
//

import Foundation
import UIKit

/// Central logo service with waterfall provider chain.
/// Chain: Supabase → LogoDev → GoogleFavicon → Lettermark
final class LogoService {
    static let shared = LogoService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache = LogoDiskCache.shared

    // LogoService is NOT @Observable — no @ObservationIgnored needed
    private let providers: [any LogoProvider] = [
        SupabaseLogoProvider(),
        LogoDevProvider(),
        GoogleFaviconProvider(),
        LettermarkProvider(),
    ]

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.memoryCache.removeAllObjects()
        }
    }

    /// Loads a brand logo through the provider chain.
    /// Resolves brandName to domain before cache/fetch.
    /// Never throws — LettermarkProvider always succeeds.
    @MainActor
    func logoImage(brandName: String) async -> UIImage? {
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }

        let domain = ServiceLogoRegistry.resolveDomain(from: normalizedName)
        let cacheKey = domain as NSString

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = diskCache.load(for: domain) {
            memoryCache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }

        // 3. Provider chain
        if let result = await LogoProviderChain.fetch(
            domain: domain,
            size: 128,
            providers: providers
        ) {
            memoryCache.setObject(result.image, forKey: cacheKey)
            // Only cache real logos to disk, NOT lettermarks.
            // Lettermarks are generated fallbacks — if a real logo becomes
            // available later (uploaded to Supabase), we want to find it.
            if result.shouldCacheToDisk {
                diskCache.save(result.image, for: domain)
            }
            return result.image
        }

        return nil
    }

    /// Prefetch logos for a list of brand names.
    nonisolated func prefetch(brandNames: [String]) {
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for brandName in brandNames {
                    group.addTask { @MainActor in
                        _ = await LogoService.shared.logoImage(brandName: brandName)
                    }
                }
            }
        }
    }

    /// Check if a logo is cached (memory or disk).
    @MainActor
    func isCached(brandName: String) -> Bool {
        let normalizedName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = ServiceLogoRegistry.resolveDomain(from: normalizedName)

        if memoryCache.object(forKey: domain as NSString) != nil {
            return true
        }

        return diskCache.exists(for: domain)
    }
}
