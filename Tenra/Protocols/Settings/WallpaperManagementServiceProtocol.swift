//
//  WallpaperManagementServiceProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import UIKit

/// Protocol for wallpaper file management
/// Handles saving, loading, caching, and removal of wallpaper images
protocol WallpaperManagementServiceProtocol {
    /// Save wallpaper image to disk
    /// - Parameter image: UIImage to save
    /// - Returns: Filename of saved wallpaper
    /// - Throws: WallpaperError if save fails
    func saveWallpaper(_ image: UIImage) async throws -> String

    /// Load wallpaper image from disk or cache
    /// - Parameter fileName: Name of wallpaper file
    /// - Returns: UIImage instance
    /// - Throws: WallpaperError if load fails
    func loadWallpaper(named fileName: String) async throws -> UIImage

    /// Remove wallpaper file from disk and cache
    /// - Parameter fileName: Name of wallpaper file to remove
    /// - Throws: WallpaperError if removal fails
    func removeWallpaper(named fileName: String) async throws

    /// Get history of wallpapers
    /// - Returns: Array of wallpaper history items
    func getWallpaperHistory() async -> [WallpaperHistoryItem]

    /// Clear wallpaper cache
    func clearCache()
}

/// Wallpaper history item for quick restore
struct WallpaperHistoryItem: Identifiable, Codable {
    let id: String
    let fileName: String
    let createdAt: Date
    let fileSize: Int64

    init(fileName: String, createdAt: Date = Date(), fileSize: Int64) {
        self.id = UUID().uuidString
        self.fileName = fileName
        self.createdAt = createdAt
        self.fileSize = fileSize
    }
}

/// Errors that can occur during wallpaper operations
enum WallpaperError: LocalizedError {
    case compressionFailed
    case fileTooLarge(Int64, Int64) // actual, max
    case insufficientSpace(Int64, Int64) // required, available
    case fileNotFound(String)
    case corruptedFile(String)
    case invalidFormat
    case saveFailed(underlying: Error)
    case loadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return String(localized: "error.wallpaper.compressionFailed", defaultValue: "Failed to compress wallpaper image")
        case .fileTooLarge(let actual, let max):
            let maxMB = Double(max) / (1024 * 1024)
            let actualMB = Double(actual) / (1024 * 1024)
            return String(localized: "error.wallpaper.fileTooLarge", defaultValue: "Wallpaper file is too large (\(String(format: "%.1f", actualMB)) MB, max \(String(format: "%.1f", maxMB)) MB)")
        case .insufficientSpace(let required, let available):
            let requiredMB = Double(required) / (1024 * 1024)
            let availableMB = Double(available) / (1024 * 1024)
            return String(localized: "error.wallpaper.insufficientSpace", defaultValue: "Insufficient disk space (need \(String(format: "%.1f", requiredMB)) MB, have \(String(format: "%.1f", availableMB)) MB)")
        case .fileNotFound(let fileName):
            return String(localized: "error.wallpaper.fileNotFound", defaultValue: "Wallpaper file not found: \(fileName)")
        case .corruptedFile(let fileName):
            return String(localized: "error.wallpaper.corruptedFile", defaultValue: "Wallpaper file is corrupted: \(fileName)")
        case .invalidFormat:
            return String(localized: "error.wallpaper.invalidFormat", defaultValue: "Invalid image format")
        case .saveFailed(let error):
            return String(localized: "error.wallpaper.saveFailed", defaultValue: "Failed to save wallpaper: \(error.localizedDescription)")
        case .loadFailed(let error):
            return String(localized: "error.wallpaper.loadFailed", defaultValue: "Failed to load wallpaper: \(error.localizedDescription)")
        }
    }
}
