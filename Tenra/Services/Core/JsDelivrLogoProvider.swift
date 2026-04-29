//
//  JsDelivrLogoProvider.swift
//  Tenra
//
//  Fetches logos from jsDelivr CDN backed by the public GitHub repo
//  `dkicekeeper/tenra-assets` (logos/<filename>.png).
//
//  On first request, indexes the repo via the jsDelivr packages API.
//  Builds a normalized lookup: strips spaces/underscores/hyphens, lowercases.
//  Matches domain, displayName, or aliases against the index.
//  Index is cached to disk and refreshed once per day.
//

import UIKit
import os

nonisolated final class JsDelivrLogoProvider: LogoProvider {
    let name = "jsdelivr"

    private static let logger = Logger(subsystem: "Tenra", category: "JsDelivrLogoProvider")

    // MARK: - Endpoints

    /// jsDelivr packages API — returns flat file list for the repo at given ref.
    private static let packageAPI = "https://data.jsdelivr.com/v1/packages/gh/dkicekeeper/tenra-assets@main?structure=flat"

    /// CDN base URL for actual logo downloads.
    private static let cdnBase = "https://cdn.jsdelivr.net/gh/dkicekeeper/tenra-assets@main/logos"

    /// Path prefix in the API response that flags entries as logos.
    private static let logosPrefix = "/logos/"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    // MARK: - Index (normalized name → actual filename with extension)

    private static let indexActor = IndexActor()

    actor IndexActor {
        private var index: [String: String]? // normalized → "actual_filename.png"
        private var lastFetch: Date?
        private var inFlightFetch: Task<[String: String], Never>?

        /// Get the index, fetching if needed (max once per day for non-empty, retry every 60s for empty)
        func getIndex() async -> [String: String] {
            if let index, !index.isEmpty, let lastFetch, Date().timeIntervalSince(lastFetch) < 86400 {
                return index
            }

            // Empty index? Retry after 60s (not 24h) — likely a transient failure.
            if let index, index.isEmpty, let lastFetch, Date().timeIntervalSince(lastFetch) < 60 {
                return index
            }

            if index == nil, let diskIndex = loadFromDisk(), !diskIndex.index.isEmpty {
                self.index = diskIndex.index
                self.lastFetch = diskIndex.date
                if Date().timeIntervalSince(diskIndex.date) < 86400 {
                    return diskIndex.index
                }
            }

            // Coalesce concurrent fetches: parallel callers await the same Task.
            if let inFlightFetch {
                return await inFlightFetch.value
            }

            let fetchTask = Task<[String: String], Never> { [weak self] in
                let fetched = await self?.fetchPackageIndex() ?? nil
                let result = fetched ?? [:]
                await self?.storeFetchResult(result)
                return result
            }
            inFlightFetch = fetchTask
            let result = await fetchTask.value
            inFlightFetch = nil
            return result
        }

        private func storeFetchResult(_ result: [String: String]) {
            if !result.isEmpty {
                self.index = result
                self.lastFetch = Date()
                saveToDisk(result)
            } else {
                self.lastFetch = Date()
                if self.index == nil { self.index = [:] }
            }
        }

        func refresh() async {
            if let inFlightFetch {
                _ = await inFlightFetch.value
                return
            }
            let fetchTask = Task<[String: String], Never> { [weak self] in
                let fetched = await self?.fetchPackageIndex() ?? nil
                let result = fetched ?? [:]
                await self?.storeFetchResult(result)
                return result
            }
            inFlightFetch = fetchTask
            _ = await fetchTask.value
            inFlightFetch = nil
        }

        // MARK: - jsDelivr Packages API

        private func fetchPackageIndex() async -> [String: String]? {
            guard let url = URL(string: JsDelivrLogoProvider.packageAPI) else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await JsDelivrLogoProvider.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    JsDelivrLogoProvider.logger.error("Package list failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return nil
                }

                // Response shape: { "files": [ { "name": "/logos/kaspi.png", ... }, ... ] }
                guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let files = payload["files"] as? [[String: Any]] else {
                    return nil
                }

                var index: [String: String] = [:]
                for file in files {
                    guard let path = file["name"] as? String,
                          path.hasPrefix(JsDelivrLogoProvider.logosPrefix) else { continue }

                    let filename = String(path.dropFirst(JsDelivrLogoProvider.logosPrefix.count))
                    let lower = filename.lowercased()
                    guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") else { continue }

                    let nameWithoutExt = (filename as NSString).deletingPathExtension
                    let normalized = Self.normalize(nameWithoutExt)
                    if normalized.isEmpty { continue }

                    // First match wins — keeps deterministic behavior when duplicates differ
                    // only by extension.
                    if index[normalized] == nil {
                        index[normalized] = filename
                    }
                }

                JsDelivrLogoProvider.logger.info("Indexed \(index.count) logos from jsDelivr")
                return index
            } catch {
                JsDelivrLogoProvider.logger.error("Package list error: \(error.localizedDescription)")
                return nil
            }
        }

        // MARK: - Disk Cache

        private static let cacheURL: URL = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("jsdelivr_logo_index.json")
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
        let index = await Self.indexActor.getIndex()
        guard !index.isEmpty else { return nil }

        let entry = ServiceLogoRegistry.domainMap[domain.lowercased()]
        var candidates: [String] = []

        // 1. displayName ("Kaspi", "Yandex Go")
        if let displayName = entry?.displayName {
            let normalized = IndexActor.normalize(displayName)
            candidates.append(normalized)

            // 2. displayName without common suffixes ("Eurasian Bank" → "eurasian")
            let stripped = Self.stripCommonSuffixes(normalized)
            if stripped != normalized {
                candidates.append(stripped)
            }
        }

        // 3. Domain base ("kaspi" from "kaspi.kz")
        let domainBase = domain.split(separator: ".").first.map(String.init) ?? domain
        let normalizedBase = IndexActor.normalize(domainBase)
        candidates.append(normalizedBase)

        // 4. Domain base without suffixes ("bereke" from "berekebank")
        let strippedBase = Self.stripCommonSuffixes(normalizedBase)
        if strippedBase != normalizedBase {
            candidates.append(strippedBase)
        }

        // 5. Full domain normalized ("kaspikz")
        candidates.append(IndexActor.normalize(domain))

        // 6. Aliases
        if let aliases = entry?.aliases {
            for alias in aliases {
                candidates.append(IndexActor.normalize(alias))
            }
        }

        var seen = Set<String>()
        let uniqueCandidates = candidates.filter { seen.insert($0).inserted }

        for candidate in uniqueCandidates {
            if let actualFilename = index[candidate] {
                return await downloadLogo(filename: actualFilename)
            }
        }

        return nil
    }

    // MARK: - Helpers

    /// Strip common prefixes/suffixes from normalized names to improve matching.
    /// "eurasianbank" → "eurasian", "bankcentercredit" → "centercredit"
    /// Works on already-normalized (lowercased, no separators) strings.
    private static let commonAffixes = ["bank", "kz", "ru", "com"]

    private static func stripCommonSuffixes(_ normalized: String) -> String {
        var result = normalized
        for affix in commonAffixes {
            if result.hasSuffix(affix) && result.count > affix.count {
                result = String(result.dropLast(affix.count))
            }
            if result.hasPrefix(affix) && result.count > affix.count {
                result = String(result.dropFirst(affix.count))
            }
        }
        return result
    }

    // MARK: - Download

    private func downloadLogo(filename: String) async -> UIImage? {
        guard let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let urlString = "\(Self.cdnBase)/\(encoded)"
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
