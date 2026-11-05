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
        NumberDisplay.fileSize(fileSize)
    }

    /// "3 нояб. 2026, 14:30": the day in the chosen date style, with its year, then the time.
    var formattedDate: String {
        formattedDate(style: FormatSettings.snapshot.dateStyle, locale: .current)
    }

    func formattedDate(style: DateStyle, locale: Locale) -> String {
        let day = DateFormatters.day(date, includeYear: true, abbreviated: true, style: style, locale: locale)
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        return String(format: String(localized: "settings.cloud.backupDate"), day, time)
    }
}
