//
//  BackupRetentionTests.swift
//  TenraTests
//
//  One shared limit of 5 backups let the weekly automatic backup push the user's own
//  backups out within five weeks. Pins the separate limits: each kind evicts only its
//  own kind, and backups from before the kind was recorded count as manual.
//

import Testing
import Foundation
@testable import Tenra

struct BackupRetentionTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func backup(daysAgo: Double, automatic: Bool?) -> BackupMetadata {
        BackupMetadata(
            id: UUID().uuidString,
            date: now.addingTimeInterval(-daysAgo * 86_400),
            transactionCount: 1,
            accountCount: 1,
            categoryCount: 1,
            modelVersion: "v12",
            fileSize: 1,
            appVersion: "1.4",
            isAutomatic: automatic
        )
    }

    private func evicted(_ backups: [BackupMetadata], after created: BackupMetadata) -> [String] {
        CloudBackupService.backupsToEvict(from: backups + [created], after: created).map(\.id)
    }

    @Test func automaticBackupEvictsOnlyTheOldestAutomaticOne() {
        let manual = (1...5).map { backup(daysAgo: Double($0 * 7), automatic: false) }
        let legacy = (1...3).map { backup(daysAgo: Double(100 + $0), automatic: nil) }
        let automatic = (1...CloudBackupService.maxAutomaticBackups).map {
            backup(daysAgo: Double($0 * 7 + 1), automatic: true)
        }
        let created = backup(daysAgo: 0, automatic: true)

        #expect(evicted(manual + legacy + automatic, after: created) == [automatic.last!.id])
    }

    @Test func manualBackupNeverEvictsAutomaticOnes() {
        let automatic = (1...6).map { backup(daysAgo: Double($0), automatic: true) }
        let manual = (1...CloudBackupService.maxManualBackups).map {
            backup(daysAgo: Double($0 * 10), automatic: false)
        }
        let created = backup(daysAgo: 0, automatic: false)

        #expect(evicted(automatic + manual, after: created) == [manual.last!.id])
    }

    @Test func backupsWithoutAKindCountAsManual() {
        let legacy = (1...CloudBackupService.maxManualBackups).map {
            backup(daysAgo: Double($0), automatic: nil)
        }

        #expect(evicted(legacy, after: backup(daysAgo: 0, automatic: true)).isEmpty)
        #expect(evicted(legacy, after: backup(daysAgo: 0, automatic: false)) == [legacy.last!.id])
    }

    @Test func belowTheLimitNothingIsEvicted() {
        let automatic = (1..<CloudBackupService.maxAutomaticBackups).map {
            backup(daysAgo: Double($0), automatic: true)
        }
        #expect(evicted(automatic, after: backup(daysAgo: 0, automatic: true)).isEmpty)
    }

    @Test func theNewBackupIsNeverEvicted() {
        // Another device's automatic backups can be dated after this one (clock skew).
        let newer = (1...6).map { _ in backup(daysAgo: -1, automatic: true) }
        let created = backup(daysAgo: 0, automatic: true)

        let ids = evicted(newer, after: created)
        #expect(!ids.contains(created.id))
        #expect(ids.count == newer.count - (CloudBackupService.maxAutomaticBackups - 1))
    }

    @Test func metadataWithoutTheKindDecodesAsLegacy() throws {
        let json = #"{"id":"A","date":0,"transactionCount":1,"accountCount":1,"categoryCount":1,"modelVersion":"v7","fileSize":10,"appVersion":"1.2"}"#
        let legacy = try JSONDecoder().decode(BackupMetadata.self, from: Data(json.utf8))
        #expect(legacy.isAutomatic == nil)

        let encoded = try JSONEncoder().encode(backup(daysAgo: 0, automatic: true))
        #expect(try JSONDecoder().decode(BackupMetadata.self, from: encoded).isAutomatic == true)
    }
}
