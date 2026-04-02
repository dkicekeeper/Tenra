//
//  BackupMetadata.swift
//  Tenra
//
//  Metadata for iCloud backup snapshots
//

import Foundation

struct BackupMetadata: Codable, Sendable, Identifiable {
    let id: String
    let date: Date
    let transactionCount: Int
    let accountCount: Int
    let categoryCount: Int
    let modelVersion: String
    let fileSize: Int64
    let appVersion: String

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
