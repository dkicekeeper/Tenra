//
//  LogoProvider.swift
//  Tenra
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
        // A merchant's name or a tenra-assets file name ("magnum") is not a domain: logo.dev
        // would answer a monogram for it, which would be kept on disk as the logo.
        guard !domain.hasPrefix(LogoDevNameProvider.scheme), domain.contains("."),
              let url = LogoDevConfig.logoURL(for: domain) else {
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

/// A merchant's logo found by its name on logo.dev (`LogoDevConfig.nameLogoURL`), for
/// the keys MerchantLogoResolver stores as `scheme` + name. Answers nil for any other key
/// and for an unknown name (`fallback=404`), so the chain moves on.
nonisolated final class LogoDevNameProvider: LogoProvider {
    static let scheme = "name:"

    let name = "logoDevName"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard domain.hasPrefix(Self.scheme) else { return nil }
        return await Self.fetch(name: String(domain.dropFirst(Self.scheme.count)))
    }

    static func fetch(name: String) async -> UIImage? {
        guard case .found(let image) = await lookUp(name: name) else { return nil }
        return image
    }

    nonisolated enum NameLookup {
        case found(UIImage)
        /// logo.dev answered that it has none (`fallback=404`), or there is no API key.
        case notFound
        /// No answer: no network, a timeout, a server error. Ask again later.
        case failed
    }

    static func lookUp(name: String) async -> NameLookup {
        guard let url = LogoDevConfig.nameLogoURL(for: name) else { return .notFound }
        guard let result = try? await session.data(from: url),
              let status = (result.1 as? HTTPURLResponse)?.statusCode else {
            return .failed
        }
        switch status {
        case 200: return UIImage(data: result.0).map(NameLookup.found) ?? .notFound
        case 404: return .notFound
        default: return .failed
        }
    }
}
