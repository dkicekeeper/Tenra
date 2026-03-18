//
//  GoogleFaviconProvider.swift
//  AIFinanceManager
//
//  Fetches favicons from Google's favicon service
//

import UIKit

/// Fetches brand favicons from Google's public favicon API.
/// Returns nil if response is too small (<1KB) or image is ≤16x16.
nonisolated final class GoogleFaviconProvider: LogoProvider {
    let name = "googleFavicon"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")!
        components.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "sz", value: "128"),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Filter out tiny/default responses
            guard data.count >= 1024 else { return nil }

            guard let image = UIImage(data: data) else { return nil }

            // Google returns 16x16 for unknown domains even with sz=128
            guard image.size.width > 16 && image.size.height > 16 else {
                return nil
            }

            return image
        } catch {
            return nil
        }
    }
}
