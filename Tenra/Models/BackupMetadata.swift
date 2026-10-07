//
//  BackupMetadata.swift
//  Tenra
//
//  Metadata for iCloud backup snapshots
//

import Foundation

nonisolated struct BackupMetadata: Codable, Sendable, Identifiable {
    let id: String
    let date: Date
    let transactionCount: Int
    let accountCount: Int
    let categoryCount: Int
    let modelVersion: String
    let fileSize: Int64
    let appVersion: String
    /// Made by the weekly automatic backup rather than by the user. `nil` for backups made
    /// before 2026-10, which didn't record it: they count as manual, so an automatic
    /// backup never evicts them (`CloudBackupService.backupsToEvict`). Optional so older
    /// metadata decodes; older app versions ignore the key.
    var isAutomatic: Bool? = nil

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    private nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
