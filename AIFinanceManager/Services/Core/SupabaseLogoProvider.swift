//
//  SupabaseLogoProvider.swift
//  AIFinanceManager
//
//  Fetches logos from Supabase Storage with auto-indexing.
//  Lists bucket contents once, builds fuzzy index, matches by normalized name.
//

import UIKit
import os

/// Fetches brand logos from Supabase Storage public bucket.
///
/// On first request, indexes the entire bucket via Supabase Storage API.
/// Builds a normalized lookup: strips spaces/underscores/hyphens, lowercases.
/// Matches domain, displayName, or aliases against the index.
/// Index is cached to disk and refreshed once per day.
nonisolated final class SupabaseLogoProvider: LogoProvider {
    let name = "supabase"

    private static let logger = Logger(subsystem: "AIFinanceManager", category: "SupabaseLogoProvider")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    // MARK: - Config from Info.plist

    private static let config: (baseURL: String, projectURL: String, anonKey: String)? = {
        guard let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let baseURL = plist["SUPABASE_LOGOS_BASE_URL"] as? String, !baseURL.isEmpty,
              let anonKey = plist["SUPABASE_ANON_KEY"] as? String, !anonKey.isEmpty else {
            return nil
        }
        // Extract project URL from base URL: https://xxx.supabase.co/storage/v1/object/public/logos → https://xxx.supabase.co
        let projectURL: String
        if let range = baseURL.range(of: "/storage/") {
            projectURL = String(baseURL[baseURL.startIndex..<range.lowerBound])
        } else {
            // Fallback: assume base URL IS the project URL
            projectURL = baseURL
        }
        return (baseURL: baseURL, projectURL: projectURL, anonKey: anonKey)
    }()

    // MARK: - Index (normalized name → actual filename with extension)

    /// Actor to protect mutable index state
    private static let indexActor = IndexActor()

    actor IndexActor {
        private var index: [String: String]? // normalized → "actual_filename.png"
        private var lastFetch: Date?
        private var isFetching = false

        /// Get the index, fetching if needed (max once per day for non-empty, retry every 60s for empty)
        func getIndex() async -> [String: String] {
            // Return cached if fresh and non-empty
            if let index, !index.isEmpty, let lastFetch, Date().timeIntervalSince(lastFetch) < 86400 {
                return index
            }

            // Empty index? Retry after 60s (not 24h) — likely a transient failure
            if let index, index.isEmpty, let lastFetch, Date().timeIntervalSince(lastFetch) < 60 {
                return index
            }

            // Try disk cache first (only if non-empty)
            if index == nil, let diskIndex = loadFromDisk(), !diskIndex.index.isEmpty {
                self.index = diskIndex.index
                self.lastFetch = diskIndex.date
                if Date().timeIntervalSince(diskIndex.date) < 86400 {
                    return diskIndex.index
                }
            }

            // Fetch from Supabase (prevent concurrent fetches)
            guard !isFetching else {
                return index ?? [:]
            }
            isFetching = true
            defer { isFetching = false }

            if let freshIndex = await fetchBucketIndex() {
                self.index = freshIndex
                self.lastFetch = Date()
                // Only cache non-empty index to disk
                if !freshIndex.isEmpty {
                    saveToDisk(freshIndex)
                }
                return freshIndex
            }

            return index ?? [:]
        }

        /// Force refresh the index
        func refresh() async {
            guard !isFetching else { return }
            isFetching = true
            defer { isFetching = false }

            if let freshIndex = await fetchBucketIndex() {
                self.index = freshIndex
                self.lastFetch = Date()
                saveToDisk(freshIndex)
            }
        }

        // MARK: - Supabase Storage API

        private func fetchBucketIndex() async -> [String: String]? {
            guard let config = SupabaseLogoProvider.config else { return nil }

            let listURL = "\(config.projectURL)/storage/v1/object/list/logos"
            guard let url = URL(string: listURL) else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = #"{"prefix":"","limit":1000,"sortBy":{"column":"name","order":"asc"}}"#.data(using: .utf8)

            do {
                let (data, response) = try await SupabaseLogoProvider.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    SupabaseLogoProvider.logger.error("Bucket list failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return nil
                }

                // Parse JSON array of objects with "name" field
                guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    return nil
                }

                var index: [String: String] = [:]
                for item in items {
                    guard let filename = item["name"] as? String else { continue }

                    // Skip directories and non-png files
                    guard filename.hasSuffix(".png") || filename.hasSuffix(".jpg") || filename.hasSuffix(".jpeg") else { continue }

                    // Normalize: strip extension, lowercase, remove separators
                    let nameWithoutExt = (filename as NSString).deletingPathExtension
                    let normalized = Self.normalize(nameWithoutExt)

                    index[normalized] = filename
                }

                SupabaseLogoProvider.logger.info("Indexed \(index.count) logos from Supabase")
                return index
            } catch {
                SupabaseLogoProvider.logger.error("Bucket list error: \(error.localizedDescription)")
                return nil
            }
        }

        // MARK: - Disk Cache

        private static let cacheURL: URL = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("supabase_logo_index.json")
        }()

        private func saveToDisk(_ index: [String: String]) {
            let payload: [String: Any] = [
                "date": ISO8601DateFormatter().string(from: Date()),
                "index": index,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? data.write(to: Self.cacheURL)
            }
        }

        private func loadFromDisk() -> (index: [String: String], date: Date)? {
            guard let data = try? Data(contentsOf: Self.cacheURL),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dateStr = payload["date"] as? String,
                  let date = ISO8601DateFormatter().date(from: dateStr),
                  let index = payload["index"] as? [String: String] else {
                return nil
            }
            return (index, date)
        }

        // MARK: - Normalization

        /// Normalize a name for fuzzy matching: lowercase, strip separators
        static func normalize(_ name: String) -> String {
            name.lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ".", with: "")
        }
    }

    // MARK: - LogoProvider

    func fetchLogo(domain: String, size: CGFloat) async -> UIImage? {
        guard let config = Self.config else { return nil }

        let index = await Self.indexActor.getIndex()
        guard !index.isEmpty else { return nil }

        // Build search candidates from registry entry
        let entry = ServiceLogoRegistry.domainMap[domain.lowercased()]
        var candidates: [String] = []

        // 1. displayName ("Kaspi", "Yandex Go")
        if let displayName = entry?.displayName {
            candidates.append(IndexActor.normalize(displayName))
        }

        // 3. Domain base ("kaspi" from "kaspi.kz")
        let domainBase = domain.split(separator: ".").first.map(String.init) ?? domain
        candidates.append(IndexActor.normalize(domainBase))

        // 4. Full domain normalized ("kaspikz")
        candidates.append(IndexActor.normalize(domain))

        // Deduplicate
        var seen = Set<String>()
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }

        // Find first match in index
        for candidate in uniqueCandidates {
            if let actualFilename = index[candidate] {
                return await downloadLogo(filename: actualFilename, baseURL: config.baseURL)
            }
        }

        return nil
    }

    // MARK: - Download

    private func downloadLogo(filename: String, baseURL: String) async -> UIImage? {
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let urlString = "\(baseURL)/\(encoded)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await Self.session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  data.count > 100 else {
                return nil
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
