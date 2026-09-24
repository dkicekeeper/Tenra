//
//  AutomaticBackupPolicyTests.swift
//  TenraTests
//
//  Backups used to exist only if the user tapped "Create backup". Pins when the
//  weekly automatic backup runs.
//

import Testing
import Foundation
@testable import Tenra

struct AutomaticBackupPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let week = CloudSyncViewModel.automaticBackupInterval

    private func due(last: Date?, enabled: Bool = true, count: Int = 10) -> Bool {
        CloudSyncViewModel.isAutomaticBackupDue(lastBackup: last, now: now, enabled: enabled, transactionCount: count)
    }

    @Test func neverBackedUpIsDue() {
        #expect(due(last: nil))
    }

    @Test func weekOldBackupIsDue() {
        #expect(due(last: now.addingTimeInterval(-week)))
    }

    @Test func recentBackupIsNotDue() {
        #expect(!due(last: now.addingTimeInterval(-week + 3600)))
    }

    @Test func disabledIsNeverDue() {
        #expect(!due(last: nil, enabled: false))
    }

    @Test func emptyDataIsNotBackedUp() {
        #expect(!due(last: nil, count: 0))
    }
}
