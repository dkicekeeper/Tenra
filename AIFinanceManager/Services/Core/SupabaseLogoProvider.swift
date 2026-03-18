//
//  SupabaseLogoProvider.swift
//  AIFinanceManager
//
//  Fetches logos from Supabase Storage public bucket
//

import UIKit

/// Fetches brand logos from Supabase Storage.
/// Tries multiple filename variants (logoFilename, displayName, domain) with URL encoding.
/// Handles Cyrillic, spaces, mixed case automatically.
nonisolated final class SupabaseLogoProvider: LogoProvider {
    let name = "supabase"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    /// Base URL read once from Info.plist at init time
    private static let baseURL: String? = {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let url = plist["SUPABASE_LOGOS_BASE_URL"] as? String,
              !url.isEmpty else {
            return nil
        }
        return url
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard Self.baseURL != nil else { return nil }

        let entry = ServiceLogoRegistry.domainMap[domain.lowercased()]

        // Build candidate filenames in priority order (max ~3 unique attempts)
        var candidates: [String] = []

        // 1. Exact logoFilename if set
        if let filename = entry?.logoFilename {
            candidates.append(filename)
        }

        // 2. Display name (e.g. "Yandex Go", "Kaspi")
        if let displayName = entry?.displayName {
            candidates.append(displayName)
        }

        // 3. Domain without TLD (e.g. "kaspi" from "kaspi.kz")
        let domainBase = domain.split(separator: ".").first.map(String.init) ?? domain
        candidates.append(domainBase)

        // Deduplicate while preserving order
        var seen = Set<String>()
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }

        // Try each candidate
        for candidate in uniqueCandidates {
            if let image = await tryFetch(filename: candidate) {
                return image
            }
        }

        return nil
    }

    /// Try to fetch a logo with the given filename (without extension).
    /// Handles URL encoding for Cyrillic, spaces, etc.
    private func tryFetch(filename: String) async -> UIImage? {
        guard let baseURL = Self.baseURL else { return nil }

        // Percent-encode filename for URL safety (Cyrillic, spaces, etc.)
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let urlString = "\(baseURL)/\(encoded).png"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard data.count > 100 else { return nil }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
