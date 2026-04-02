//
//  WallpaperManagementService.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import UIKit

/// Service for managing wallpaper images
/// Handles saving, loading, caching with LRU eviction
final class WallpaperManagementService: WallpaperManagementServiceProtocol {
    private let fileManager: FileManager
    private let cache: LRUCache<String, UIImage>
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB

    private static let wallpaperHistoryKey = "wallpaperHistory"

    init(
        fileManager: FileManager = .default,
        cacheCapacity: Int = 10
    ) {
        self.fileManager = fileManager
        self.cache = LRUCache(capacity: cacheCapacity)
    }

    // MARK: - WallpaperManagementServiceProtocol

    func saveWallpaper(_ image: UIImage) async throws -> String {

        // Compress image
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw WallpaperError.compressionFailed
        }

        // Validate size
        let dataSize = Int64(data.count)
        guard dataSize < maxFileSize else {
            throw WallpaperError.fileTooLarge(dataSize, maxFileSize)
        }

        // Check disk space
        let freeSpace = try getFreeSpace()
        let requiredSpace = dataSize * 2 // Safety margin
        guard freeSpace > requiredSpace else {
            throw WallpaperError.insufficientSpace(requiredSpace, freeSpace)
        }

        // Generate unique filename
        let fileName = "wallpaper_\(UUID().uuidString).jpg"
        let fileURL = getDocumentsURL().appendingPathComponent(fileName)

        // Save to disk
        do {
            try data.write(to: fileURL, options: .atomic)

        } catch {
            throw WallpaperError.saveFailed(underlying: error)
        }

        // Add to cache
        cache.set(fileName, value: image)

        // Add to history
        await addToHistory(fileName: fileName, fileSize: dataSize)

        return fileName
    }

    func loadWallpaper(named fileName: String) async throws -> UIImage {

        // Check cache first (O(1))
        if let cached = cache.get(fileName) {
            return cached
        }

        // Load from disk
        let fileURL = getDocumentsURL().appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw WallpaperError.fileNotFound(fileName)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard let image = UIImage(data: data) else {
                throw WallpaperError.corruptedFile(fileName)
            }

            // Add to cache for future access
            cache.set(fileName, value: image)


            return image
        } catch {
            if let wallpaperError = error as? WallpaperError {
                throw wallpaperError
            } else {
                throw WallpaperError.loadFailed(underlying: error)
            }
        }
    }

    func removeWallpaper(named fileName: String) async throws {

        // Remove from cache
        cache.remove(fileName)

        // Remove from disk
        let fileURL = getDocumentsURL().appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                // Continue anyway - file might already be deleted
            }
        }

        // Remove from history
        await removeFromHistory(fileName: fileName)
    }

    func getWallpaperHistory() async -> [WallpaperHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.wallpaperHistoryKey),
              let history = try? JSONDecoder().decode([WallpaperHistoryItem].self, from: data) else {
            return []
        }

        // Filter out non-existent files
        let validHistory = history.filter { item in
            let fileURL = getDocumentsURL().appendingPathComponent(item.fileName)
            return fileManager.fileExists(atPath: fileURL.path)
        }

        // Update history if items were removed
        if validHistory.count != history.count {
            await saveHistory(validHistory)
        }

        return validHistory.sorted { $0.createdAt > $1.createdAt } // Most recent first
    }

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - History Management

    private func addToHistory(fileName: String, fileSize: Int64) async {
        var history = await getWallpaperHistory()

        let newItem = WallpaperHistoryItem(
            fileName: fileName,
            createdAt: Date(),
            fileSize: fileSize
        )

        history.insert(newItem, at: 0)

        // Keep only last 10
        if history.count > 10 {
            history = Array(history.prefix(10))
        }

        await saveHistory(history)
    }

    private func removeFromHistory(fileName: String) async {
        var history = await getWallpaperHistory()
        history.removeAll { $0.fileName == fileName }
        await saveHistory(history)
    }

    private func saveHistory(_ history: [WallpaperHistoryItem]) async {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.wallpaperHistoryKey)
        }
    }

    // MARK: - Helpers

    private func getDocumentsURL() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func getFreeSpace() throws -> Int64 {
        let documentsURL = getDocumentsURL()
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: documentsURL.path),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            throw WallpaperError.insufficientSpace(0, 0)
        }
        return freeSize
    }
}
