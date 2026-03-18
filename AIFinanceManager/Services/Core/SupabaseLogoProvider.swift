//
//  SupabaseLogoProvider.swift
//  AIFinanceManager
//
//  Fetches logos from Supabase Storage public bucket
//

import UIKit

/// Fetches brand logos from Supabase Storage.
/// URL: {SUPABASE_LOGOS_BASE_URL}/{domain}.png
/// Returns nil if base URL not configured or logo not found.
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
        guard let baseURL = Self.baseURL else { return nil }

        let urlString = "\(baseURL)/\(domain).png"
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
