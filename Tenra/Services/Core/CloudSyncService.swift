//
//  CloudSyncService.swift
//  Tenra
//
//  Monitors CloudKit sync status via persistent history transactions
//

import Foundation
import CoreData
import CloudKit
import os

/// Sync state reported to UI via CloudSyncViewModel
enum SyncState: Sendable {
    case idle
    case syncing
    case synced(lastSync: Date, sentCount: Int, receivedCount: Int)
    case error(String)
    case disabled
    case noAccount
    case initialSync
}

/// Monitors NSPersistentStoreRemoteChange notifications and tracks sync status
/// via NSPersistentHistoryTransaction.
nonisolated final class CloudSyncService: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudSyncService")

    private let coreDataStack: CoreDataStack

    /// Notification observer token for cleanup
    private var remoteChangeObserver: Any?

    /// Last processed history token — persisted to UserDefaults.
    /// nonisolated(unsafe): read/written only from notification callback queue — accepted race.
    private var lastHistoryToken: NSPersistentHistoryToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "CloudSyncLastHistoryToken") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "CloudSyncLastHistoryToken")
            }
        }
    }

    /// Callback to update SyncState on MainActor.
    /// nonisolated(unsafe): written once at init time by CloudSyncViewModel, then only read — accepted race.
    nonisolated(unsafe) var onSyncStateChanged: (@Sendable (SyncState) -> Void)?

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Start/Stop

    func startMonitoring() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: coreDataStack.persistentContainer.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] notification in
            self?.handleRemoteChange(notification)
        }
        CloudSyncService.logger.info("Started monitoring remote changes")
    }

    func stopMonitoring() {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            remoteChangeObserver = nil
        }
        CloudSyncService.logger.info("Stopped monitoring remote changes")
    }

    // MARK: - Remote Change Handling

    private func handleRemoteChange(_ notification: Notification) {
        let context = coreDataStack.newBackgroundContext()

        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastHistoryToken)
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                return
            }

            guard !transactions.isEmpty else { return }

            var receivedCount = 0
            for transaction in transactions {
                if let changes = transaction.changes {
                    receivedCount += changes.count
                }
            }

            lastHistoryToken = transactions.last?.token

            let state = SyncState.synced(
                lastSync: Date(),
                sentCount: 0,
                receivedCount: receivedCount
            )
            onSyncStateChanged?(state)

            CloudSyncService.logger.info("Processed \(transactions.count) remote transactions (\(receivedCount) changes)")
        }
    }

    // MARK: - iCloud Account Check

    func checkiCloudAccountStatus() async -> Bool {
        do {
            let status = try await CKContainer(identifier: "iCloud.dakacom.Tenra").accountStatus()
            return status == .available
        } catch {
            CloudSyncService.logger.error("iCloud account check failed: \(error.localizedDescription)")
            return false
        }
    }
}
