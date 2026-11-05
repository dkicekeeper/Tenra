//
//  BackupMetadataTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@Suite("BackupMetadata")
struct BackupMetadataTests {

    @Test("Encoding and decoding preserves all fields")
    func roundTrip() throws {
        let original = BackupMetadata(
            id: "test-uuid",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            transactionCount: 19234,
            accountCount: 5,
            categoryCount: 12,
            modelVersion: "v6",
            fileSize: 2_100_000,
            appVersion: "1.5.0"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupMetadata.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.date == original.date)
        #expect(decoded.transactionCount == original.transactionCount)
        #expect(decoded.accountCount == original.accountCount)
        #expect(decoded.categoryCount == original.categoryCount)
        #expect(decoded.modelVersion == original.modelVersion)
        #expect(decoded.fileSize == original.fileSize)
        #expect(decoded.appVersion == original.appVersion)
    }

    @Test("formattedFileSize formats bytes correctly")
    func formattedFileSize() {
        let metadata = BackupMetadata(
            id: "test", date: Date(),
            transactionCount: 0, accountCount: 0, categoryCount: 0,
            modelVersion: "v6", fileSize: 2_100_000, appVersion: "1.0"
        )
        #expect(!metadata.formattedFileSize.isEmpty)
    }

    @Test("formattedDate produces non-empty string")
    func formattedDate() {
        let metadata = BackupMetadata(
            id: "test", date: Date(),
            transactionCount: 0, accountCount: 0, categoryCount: 0,
            modelVersion: "v6", fileSize: 0, appVersion: "1.0"
        )
        #expect(!metadata.formattedDate.isEmpty)
    }

    /// The Backups list writes the day in the chosen date style, with its year, then the time.
    @Test(arguments: [DateStyle.dots, .slash, .iso])
    func formattedDateFollowsTheDateStyle(_ style: DateStyle) {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = BackupMetadata(
            id: "test", date: date,
            transactionCount: 0, accountCount: 0, categoryCount: 0,
            modelVersion: "v6", fileSize: 0, appVersion: "1.0"
        )
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let (y, m, d) = (day.year!, day.month!, day.day!)
        let expected: String
        switch style {
        case .dots: expected = String(format: "%02d.%02d.%04d", d, m, y)
        case .slash: expected = String(format: "%02d/%02d/%04d", m, d, y)
        default: expected = String(format: "%04d-%02d-%02d", y, m, d)
        }
        let locale = Locale(identifier: "en_US")
        let text = metadata.formattedDate(style: style, locale: locale)
        #expect(text.hasPrefix(expected), "\(text)")
        #expect(text.hasSuffix(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))), "\(text)")
    }

    @Test func formattedDateInWordsAbbreviatesTheMonth() {
        let metadata = BackupMetadata(
            id: "test", date: Date(timeIntervalSince1970: 1_700_000_000),
            transactionCount: 0, accountCount: 0, categoryCount: 0,
            modelVersion: "v6", fileSize: 0, appVersion: "1.0"
        )
        let text = metadata.formattedDate(style: .words, locale: Locale(identifier: "en_US"))
        #expect(text.contains("Nov"), "\(text)")
        #expect(text.contains("2023"), "\(text)")
    }
}
