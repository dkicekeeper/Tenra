//
//  LogoProvider.swift
//  AIFinanceManager
//
//  Waterfall chain protocol for logo fetching
//

import UIKit

/// Protocol for logo providers in the waterfall chain.
/// All conformances must be nonisolated (opt out of implicit MainActor).
nonisolated protocol LogoProvider {
    var name: String { get }
    func fetchLogo(domain: String, size: CGFloat) async -> UIImage?
}

/// Result from the provider chain, includes which provider succeeded.
struct LogoProviderResult {
    let image: UIImage
    let providerName: String
    /// Whether this result should be cached to disk (lettermark should NOT be cached)
    var shouldCacheToDisk: Bool { providerName != "lettermark" }
}

/// Runs providers in order, returns first non-nil result with provider info.
nonisolated enum LogoProviderChain {
    static func fetch(
        domain: String,
        size: CGFloat,
        providers: [any LogoProvider]
    ) async -> LogoProviderResult? {
        for provider in providers {
            if let image = await provider.fetchLogo(domain: domain, size: size) {
                return LogoProviderResult(image: image, providerName: provider.name)
            }
        }
        return nil
    }
}

/// Fetches logos from logo.dev API. Returns nil if API key is unavailable.
nonisolated final class LogoDevProvider: LogoProvider {
    let name = "logoDev"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard let url = LogoDevConfig.logoURL(for: domain) else {
            return nil
        }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                return nil
            }

            return image
        } catch {
            return nil
        }
    }
}
