# iCloud Sync & Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add iCloud sync via NSPersistentCloudKitContainer, manual backups to private iCloud storage, and settings sync via NSUbiquitousKeyValueStore.

**Architecture:** Replace NSPersistentContainer with conditional NSPersistentCloudKitContainer inside the existing NSLock pattern. New services (CloudSyncService, CloudSyncSettingsService, CloudBackupService) are coordinated by CloudSyncViewModel. Backups use safe store swap (detach → copy → reattach) instead of resetAllData().

**Tech Stack:** SwiftUI, CoreData, CloudKit (NSPersistentCloudKitContainer), NSUbiquitousKeyValueStore, FileManager ubiquity container

**Spec:** `docs/superpowers/specs/2026-04-02-icloud-sync-design.md`

---

## File Map

### New Files

| File | Path | Responsibility |
|------|------|----------------|
| `BackupMetadata.swift` | `Tenra/Models/` | Codable metadata for backup snapshots |
| `CloudSyncService.swift` | `Tenra/Services/Core/` | Listens to NSPersistentStoreRemoteChange, counts changes via persistent history, reports SyncState |
| `CloudSyncSettingsService.swift` | `Tenra/Services/Settings/` | NSUbiquitousKeyValueStore wrapper with loop prevention |
| `CloudBackupService.swift` | `Tenra/Services/Utilities/` | WAL checkpoint, SQLite copy to ubiquity container, restore via swapStore |
| `CloudSyncViewModel.swift` | `Tenra/ViewModels/` | @Observable @MainActor — owns SyncState, backup list, toggle, coordinates services |
| `SettingsCloudSection.swift` | `Tenra/Views/Settings/` | iCloud section in SettingsView (toggle, status, backups nav, storage) |
| `CloudBackupsView.swift` | `Tenra/Views/Settings/` | Backup list screen with create/restore/delete |
| `BackupRowView.swift` | `Tenra/Views/Settings/` | Single backup row with metadata and swipe actions |
| `Tenra.entitlements` | `Tenra/` | iCloud + Push Notifications entitlements |
| `BackupMetadataTests.swift` | `TenraTests/Models/` | BackupMetadata encoding/decoding tests |
| `CloudSyncSettingsServiceTests.swift` | `TenraTests/Services/` | Settings sync + loop prevention tests |

### Modified Files

| File | Changes |
|------|---------|
| `Tenra/CoreData/CoreDataStack.swift` | Conditional CloudKit container, reloadContainer(), swapStore(), file protection change, schema init |
| `Tenra/ViewModels/AppCoordinator.swift` | Register CloudSyncService, CloudSyncSettingsService, CloudBackupService, CloudSyncViewModel |
| `Tenra/Views/Settings/SettingsView.swift` | Add cloudSection computed property and wire into settingsList |
| `Tenra/en.lproj/Localizable.strings` | Add settings.cloud.* and alert.restore.* / alert.disableSync.* keys |
| `Tenra/ru.lproj/Localizable.strings` | Add corresponding Russian translations |
| `Tenra.xcodeproj/project.pbxproj` | New files, CloudKit + Push capabilities |

---

## Task 1: Project Configuration — Entitlements & Capabilities

**Files:**
- Create: `Tenra/Tenra.entitlements`
- Modify: `Tenra/Info.plist`

- [ ] **Step 1: Create entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.dakacom.Tenra</string>
    </array>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

- [ ] **Step 2: Add entitlements reference to pbxproj**

Open Xcode → Tenra target → Signing & Capabilities → add:
1. **iCloud** capability → check **CloudKit** → add container `iCloud.dakacom.Tenra`
2. **Push Notifications** capability
3. **Background Modes** → check **Remote notifications**

Xcode will auto-update `project.pbxproj` with `CODE_SIGN_ENTITLEMENTS = Tenra/Tenra.entitlements` and the capability sections.

- [ ] **Step 3: Verify build succeeds**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors (CloudKit entitlements are accepted in Simulator builds)

- [ ] **Step 4: Commit**

```bash
git add Tenra/Tenra.entitlements Tenra.xcodeproj/project.pbxproj
git commit -m "feat: add iCloud and Push Notifications entitlements for CloudKit sync"
```

---

## Task 2: CoreDataStack — Conditional CloudKit Container

**Files:**
- Modify: `Tenra/CoreData/CoreDataStack.swift`

This is the most critical change — must preserve the existing NSLock one-time-init pattern.

- [ ] **Step 1: Add `import CloudKit` at the top of CoreDataStack.swift**

Add after line 10 (`import CoreData`):
```swift
import CloudKit
```

- [ ] **Step 2: Extract container creation into a private method**

Replace the inline `NSPersistentContainer(name: "Tenra")` creation at line 113 inside `persistentContainer` with a call to a new private method. Replace:

```swift
let container = NSPersistentContainer(name: "Tenra")
```

with:

```swift
let container = createContainer()
```

Add a new private method after the `persistentContainer` computed property:

```swift
/// Creates either NSPersistentCloudKitContainer or NSPersistentContainer
/// based on user's iCloud sync preference.
private func createContainer() -> NSPersistentContainer {
    if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
        return NSPersistentCloudKitContainer(name: "Tenra")
    } else {
        return NSPersistentContainer(name: "Tenra")
    }
}
```

- [ ] **Step 3: Change file protection from .complete to .completeUntilFirstUserAuthentication**

Replace at line 121:
```swift
description?.setOption(FileProtectionType.complete as NSObject,
                        forKey: NSPersistentStoreFileProtectionKey)
```
with:
```swift
// .completeUntilFirstUserAuthentication allows CloudKit background sync
// while device is locked (after first unlock per boot).
// .complete would block background sync entirely.
description?.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                        forKey: NSPersistentStoreFileProtectionKey)
```

- [ ] **Step 4: Update file protection in resetAllData() to match**

In `resetAllData()`, update the `storeOptions` dictionary at line 278:
```swift
NSPersistentStoreFileProtectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
```

- [ ] **Step 5: Extract container setup into `createAndLoadContainer()` private method**

The `persistentContainer` computed property currently does both locking AND container setup inline. Extract the setup logic into a private method so `reloadContainer()` can reuse it without deadlocking:

```swift
/// Creates, configures, and loads a persistent container.
/// Does NOT acquire containerLock — caller is responsible.
private func createAndLoadContainer() -> NSPersistentContainer {
    let container = createContainer()

    let description = container.persistentStoreDescriptions.first
    description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    description?.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                            forKey: NSPersistentStoreFileProtectionKey)
    description?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
    description?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

    if container is NSPersistentCloudKitContainer {
        description?.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.dakacom.Tenra"
        )
    }

    container.loadPersistentStores { [self] storeDescription, error in
        if let error = error as NSError? {
            CoreDataStack.logger.critical("Persistent store failed to load: \(error), \(error.userInfo)")
            self.isCoreDataAvailable = false
            if error.code == NSPersistentStoreIncompatibleVersionHashError ||
               error.code == NSMigrationMissingSourceModelError {
                self.initializationError = String(localized: "error.coredata.migrationFailed")
            } else {
                self.initializationError = String(localized: "error.coredata.initializationFailed")
            }
        } else {
            CoreDataStack.logger.info("✅ [CoreDataStack] Persistent store loaded: \(storeDescription.url?.lastPathComponent ?? "unknown", privacy: .public)")
        }
    }

    // CloudKit schema init (DEBUG only, gated by UserDefaults flag)
    if let cloudContainer = container as? NSPersistentCloudKitContainer {
        let hasInitialized = UserDefaults.standard.bool(forKey: "CloudKitSchemaInitialized")
        if !hasInitialized {
            do {
                #if DEBUG
                try cloudContainer.initializeCloudKitSchema(options: [])
                UserDefaults.standard.set(true, forKey: "CloudKitSchemaInitialized")
                CoreDataStack.logger.info("CloudKit schema initialized (development)")
                #else
                try cloudContainer.initializeCloudKitSchema(options: [.dryRun])
                CoreDataStack.logger.info("CloudKit schema validated (production)")
                #endif
            } catch {
                CoreDataStack.logger.error("CloudKit schema initialization failed: \(error.localizedDescription)")
            }
        }
    }

    container.viewContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    container.viewContext.undoManager = nil

    return container
}
```

Then update the `persistentContainer` computed property to call it:

```swift
nonisolated var persistentContainer: NSPersistentContainer {
    containerLock.lock()
    defer { containerLock.unlock() }

    if let existing = _persistentContainer {
        return existing
    }

    let container = createAndLoadContainer()
    _persistentContainer = container
    return container
}
```

- [ ] **Step 6: Add `reloadContainer()` method**

Add in the `// MARK: - Reset` section, before `resetAllData()`:

```swift
/// Tears down and recreates the persistent container.
/// Used when toggling iCloud sync on/off — the container type changes
/// between NSPersistentContainer and NSPersistentCloudKitContainer.
func reloadContainer() {
    containerLock.lock()

    // 1. Remove existing store from coordinator
    if let container = _persistentContainer {
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }

    // 2. Clear cached container and recreate — all inside the lock
    let newContainer = createAndLoadContainer()
    _persistentContainer = newContainer

    containerLock.unlock()

    // 3. Notify all FRC holders to tear down and re-fetch
    NotificationCenter.default.post(name: Self.storeDidResetNotification, object: self)
}
```

- [ ] **Step 7: Add `swapStore(from:)` method for backup restore**

Add after `reloadContainer()`:

```swift
/// Error types for backup operations
enum CloudBackupError: Error, LocalizedError {
    case noActiveStore
    case copyFailed(Error)
    case incompatibleVersion(String)

    var errorDescription: String? {
        switch self {
        case .noActiveStore: return "No active persistent store"
        case .copyFailed(let error): return "Failed to copy backup: \(error.localizedDescription)"
        case .incompatibleVersion(let version): return "Backup model version \(version) is incompatible"
        }
    }
}

/// Replaces the current persistent store with a backup file.
/// Safe sequence: detach store → replace file → reattach with original options.
/// Does NOT use resetAllData() which would create an empty store first.
func swapStore(from backupURL: URL) throws {
    containerLock.lock()
    defer { containerLock.unlock() }

    guard let container = _persistentContainer,
          let store = container.persistentStoreCoordinator.persistentStores.first,
          let storeURL = store.url else {
        throw CloudBackupError.noActiveStore
    }

    // 1. Capture current store options before removal — cast to [String: Any]
    let options = store.options as? [String: Any]

    // 2. Remove store from coordinator (NOT resetAllData — that recreates it)
    try container.persistentStoreCoordinator.remove(store)

    // 3. Replace SQLite file
    let fm = FileManager.default
    if fm.fileExists(atPath: storeURL.path) {
        try fm.removeItem(at: storeURL)
    }
    // Also remove WAL/SHM if present
    let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
    let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
    try? fm.removeItem(at: walURL)
    try? fm.removeItem(at: shmURL)

    do {
        try fm.copyItem(at: backupURL, to: storeURL)
    } catch {
        // Restore failed — attempt to re-add empty store so app doesn't crash
        try? container.persistentStoreCoordinator.addPersistentStore(
            type: .sqlite, at: storeURL, options: options
        )
        throw CloudBackupError.copyFailed(error)
    }

    // 4. Re-add store with ALL original options (history tracking, file protection, etc.)
    try container.persistentStoreCoordinator.addPersistentStore(
        type: .sqlite, at: storeURL, options: options
    )

    // 5. Reset viewContext to evict stale objects
    container.viewContext.reset()

    // 6. Notify FRC holders to recreate
    NotificationCenter.default.post(name: Self.storeDidResetNotification, object: self)
}
```

- [ ] **Step 8: Add `persistentStoreURL` computed property**

Add in the `// MARK: - Performance Monitoring` section:

```swift
/// URL of the active persistent store SQLite file
nonisolated var persistentStoreURL: URL? {
    persistentContainer.persistentStoreDescriptions.first?.url
}
```

- [ ] **Step 9: Verify build succeeds**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 10: Commit**

```bash
git add Tenra/CoreData/CoreDataStack.swift
git commit -m "feat: add conditional CloudKit container, reloadContainer(), swapStore(), and schema init

CoreDataStack now creates NSPersistentCloudKitContainer when iCloud sync
is enabled. File protection changed to .completeUntilFirstUserAuthentication
for background sync. Safe store swap for backup restore."
```

---

## Task 3: BackupMetadata Model

**Files:**
- Create: `Tenra/Models/BackupMetadata.swift`
- Create: `TenraTests/Models/BackupMetadataTests.swift`

- [ ] **Step 1: Write BackupMetadata tests**

Create `TenraTests/Models/BackupMetadataTests.swift`:

```swift
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

        let formatted = metadata.formattedFileSize
        // ByteCountFormatter output varies by locale, just check it's non-empty
        #expect(!formatted.isEmpty)
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/BackupMetadataTests 2>&1 | grep -E "error:|Test Case|failed" | head -20`
Expected: Compilation failure — `BackupMetadata` not found

- [ ] **Step 3: Create BackupMetadata model**

Create `Tenra/Models/BackupMetadata.swift`:

```swift
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

    /// Human-readable file size (e.g. "2.1 MB")
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Formatted date for display
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
```

- [ ] **Step 4: Add file to Xcode project and run tests**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/BackupMetadataTests 2>&1 | grep -E "error:|Test Case|passed|failed" | head -20`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Tenra/Models/BackupMetadata.swift TenraTests/Models/BackupMetadataTests.swift
git commit -m "feat: add BackupMetadata model with encoding/decoding tests"
```

---

## Task 4: CloudSyncService — Sync Monitoring

**Files:**
- Create: `Tenra/Services/Core/CloudSyncService.swift`

- [ ] **Step 1: Create CloudSyncService**

Create `Tenra/Services/Core/CloudSyncService.swift`:

```swift
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
/// Uses block-based NotificationCenter API (no NSObject inheritance needed).
nonisolated final class CloudSyncService: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudSyncService")

    private let coreDataStack: CoreDataStack

    /// Notification observer token for cleanup
    private var remoteChangeObserver: Any?

    /// Last processed history token — persisted to UserDefaults.
    /// nonisolated(unsafe): read/written only from notification callback queue — accepted race
    /// with init-time nil value (harmless: worst case re-processes already-seen transactions).
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
    var onSyncStateChanged: (@Sendable (SyncState) -> Void)?

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

            // Update token to latest
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

    /// Checks if user is signed into iCloud
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
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Core/CloudSyncService.swift
git commit -m "feat: add CloudSyncService for monitoring CloudKit remote changes"
```

---

## Task 5: CloudSyncSettingsService — Settings Sync

**Files:**
- Create: `Tenra/Services/Settings/CloudSyncSettingsService.swift`
- Create: `TenraTests/Services/CloudSyncSettingsServiceTests.swift`

- [ ] **Step 1: Write tests for settings sync and loop prevention**

Create `TenraTests/Services/CloudSyncSettingsServiceTests.swift`:

```swift
//
//  CloudSyncSettingsServiceTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@Suite("CloudSyncSettingsService")
struct CloudSyncSettingsServiceTests {

    @Test("pushToCloud writes to key-value store")
    func pushToCloud() {
        let service = CloudSyncSettingsService()
        service.pushToCloud(key: "baseCurrency", value: "USD")

        let stored = NSUbiquitousKeyValueStore.default.string(forKey: "baseCurrency")
        #expect(stored == "USD")
    }

    @Test("syncedKeys returns expected settings keys")
    func syncedKeys() {
        let keys = CloudSyncSettingsService.syncedKeys
        #expect(keys.contains("baseCurrency"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/CloudSyncSettingsServiceTests 2>&1 | grep -E "error:|failed" | head -10`
Expected: Compilation failure

- [ ] **Step 3: Create CloudSyncSettingsService**

Create `Tenra/Services/Settings/CloudSyncSettingsService.swift`:

```swift
//
//  CloudSyncSettingsService.swift
//  Tenra
//
//  Wraps NSUbiquitousKeyValueStore for syncing user preferences across devices.
//  Loop prevention: applySyncedSettings() writes ONLY to UserDefaults.
//  pushToCloud() is called ONLY from explicit user actions.
//

import Foundation
import os

final class CloudSyncSettingsService: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudSyncSettingsService")

    /// Keys that are synced between devices
    static let syncedKeys: [String] = [
        "baseCurrency",
        "homeBackgroundMode",
        "blurWallpaper"
    ]

    /// Callback for when remote settings change — set by CloudSyncViewModel
    var onRemoteSettingsChanged: (([String: Any]) -> Void)?

    /// Flag to prevent re-entrant pushes during applySyncedSettings
    private var isApplyingRemoteChanges = false

    init() {}

    // MARK: - Outgoing (user action only)

    /// Push a single setting to iCloud. Called ONLY from explicit user actions,
    /// NEVER from applySyncedSettings() to prevent infinite loops.
    func pushToCloud(key: String, value: Any) {
        guard !isApplyingRemoteChanges else {
            CloudSyncSettingsService.logger.debug("Skipping pushToCloud during remote apply for key: \(key)")
            return
        }
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Push all synced settings to iCloud
    func pushAllToCloud() {
        for key in Self.syncedKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                NSUbiquitousKeyValueStore.default.set(value, forKey: key)
            }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: - Incoming (remote changes)

    /// Start listening for remote settings changes
    func startListening() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        // Trigger initial sync
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func stopListening() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil
        )
    }

    @objc private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRaw = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }

        let reason = reasonRaw
        guard reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange else {
            return
        }

        // Collect changed values
        var changedSettings: [String: Any] = [:]
        for key in Self.syncedKeys {
            if let value = NSUbiquitousKeyValueStore.default.object(forKey: key) {
                changedSettings[key] = value
            }
        }

        guard !changedSettings.isEmpty else { return }

        CloudSyncSettingsService.logger.info("Received \(changedSettings.count) remote settings changes")

        // Apply to UserDefaults ONLY (loop prevention)
        isApplyingRemoteChanges = true
        for (key, value) in changedSettings {
            UserDefaults.standard.set(value, forKey: key)
        }
        isApplyingRemoteChanges = false

        // Notify ViewModel to update UI
        onRemoteSettingsChanged?(changedSettings)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/CloudSyncSettingsServiceTests 2>&1 | grep -E "error:|passed|failed" | head -10`
Expected: Tests PASS

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Settings/CloudSyncSettingsService.swift TenraTests/Services/CloudSyncSettingsServiceTests.swift
git commit -m "feat: add CloudSyncSettingsService with NSUbiquitousKeyValueStore and loop prevention"
```

---

## Task 6: CloudBackupService — Backup Create/Restore/Delete

**Files:**
- Create: `Tenra/Services/Utilities/CloudBackupService.swift`

- [ ] **Step 1: Create CloudBackupService**

Create `Tenra/Services/Utilities/CloudBackupService.swift`:

```swift
//
//  CloudBackupService.swift
//  Tenra
//
//  Creates, lists, restores, and deletes SQLite backups in iCloud ubiquity container.
//  Uses WAL checkpoint before copying for consistency.
//  Uses CoreDataStack.swapStore() for safe restore.
//

import Foundation
import CoreData
import os

final class CloudBackupService: @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudBackupService")

    private let coreDataStack: CoreDataStack
    private let maxBackups = 5

    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }

    // MARK: - Ubiquity Container

    /// Returns the Backups directory in the iCloud ubiquity container, or nil if iCloud is unavailable.
    private func backupsDirectoryURL() -> URL? {
        guard let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.dakacom.Tenra") else {
            CloudBackupService.logger.warning("iCloud ubiquity container not available")
            return nil
        }
        let backupsDir = ubiquityURL.appendingPathComponent("Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: backupsDir.path) {
            try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        }
        return backupsDir
    }

    // MARK: - Create Backup

    /// Creates a backup of the current SQLite store in the iCloud ubiquity container.
    /// Performs WAL checkpoint before copying for consistency.
    func createBackup(
        transactionCount: Int,
        accountCount: Int,
        categoryCount: Int
    ) async throws -> BackupMetadata {
        guard let backupsDir = backupsDirectoryURL() else {
            throw CloudBackupError.noActiveStore
        }

        guard let storeURL = coreDataStack.persistentStoreURL else {
            throw CloudBackupError.noActiveStore
        }

        // Flush pending changes to SQLite and checkpoint WAL.
        // Saving the viewContext first ensures all in-memory changes are written.
        // Then we copy .sqlite + .sqlite-wal + .sqlite-shm as a consistent set.
        let viewContext = coreDataStack.viewContext
        try viewContext.performAndWait {
            if viewContext.hasChanges {
                try viewContext.save()
            }
        }

        // Create backup directory with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = backupsDir.appendingPathComponent(timestamp, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Copy SQLite file
        let backupStoreURL = backupDir.appendingPathComponent("Tenra.sqlite")
        try FileManager.default.copyItem(at: storeURL, to: backupStoreURL)

        // Also copy WAL and SHM if they exist (belt and suspenders)
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let backupWalURL = backupDir.appendingPathComponent("Tenra.sqlite-wal")
        let backupShmURL = backupDir.appendingPathComponent("Tenra.sqlite-shm")
        if FileManager.default.fileExists(atPath: walURL.path) {
            try? FileManager.default.copyItem(at: walURL, to: backupWalURL)
        }
        if FileManager.default.fileExists(atPath: shmURL.path) {
            try? FileManager.default.copyItem(at: shmURL, to: backupShmURL)
        }

        // Calculate file size
        let attributes = try FileManager.default.attributesOfItem(atPath: backupStoreURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Create and save metadata
        let metadata = BackupMetadata(
            id: UUID().uuidString,
            date: Date(),
            transactionCount: transactionCount,
            accountCount: accountCount,
            categoryCount: categoryCount,
            modelVersion: "v6",
            fileSize: fileSize,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )

        let metadataURL = backupDir.appendingPathComponent("metadata.json")
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL)

        // Enforce max backups limit
        try enforceMaxBackups()

        CloudBackupService.logger.info("Backup created: \(timestamp), size: \(fileSize) bytes")

        return metadata
    }

    // MARK: - List Backups

    /// Returns all available backups sorted by date (newest first)
    func listBackups() -> [BackupMetadata] {
        guard let backupsDir = backupsDirectoryURL() else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var backups: [BackupMetadata] = []
        for dirURL in contents {
            let metadataURL = dirURL.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(BackupMetadata.self, from: data) else {
                continue
            }
            backups.append(metadata)
        }

        return backups.sorted { $0.date > $1.date }
    }

    // MARK: - Restore Backup

    /// Current model version — must match backup to allow restore
    private static let currentModelVersion = "v6"

    /// Restores a backup by swapping the persistent store.
    /// Rejects backups with incompatible model versions.
    /// - Parameter metadata: The backup to restore
    func restoreBackup(_ metadata: BackupMetadata) async throws {
        // Reject incompatible model versions
        guard metadata.modelVersion == Self.currentModelVersion else {
            throw CloudBackupError.incompatibleVersion(metadata.modelVersion)
        }

        guard let backupsDir = backupsDirectoryURL() else {
            throw CloudBackupError.noActiveStore
        }

        // Find the backup directory matching this metadata
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            throw CloudBackupError.noActiveStore
        }

        var backupStoreURL: URL?
        for dirURL in contents {
            let metadataURL = dirURL.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let m = try? JSONDecoder().decode(BackupMetadata.self, from: data),
               m.id == metadata.id {
                backupStoreURL = dirURL.appendingPathComponent("Tenra.sqlite")
                break
            }
        }

        guard let sourceURL = backupStoreURL,
              fm.fileExists(atPath: sourceURL.path) else {
            throw CloudBackupError.noActiveStore
        }

        // Ensure file is downloaded from iCloud
        if !fm.isUbiquitousItem(at: sourceURL) || !FileManager.default.fileExists(atPath: sourceURL.path) {
            try fm.startDownloadingUbiquitousItem(at: sourceURL)
            // Wait for download — simple polling with timeout
            let deadline = Date().addingTimeInterval(60)
            while !fm.fileExists(atPath: sourceURL.path) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        // Swap the store
        try coreDataStack.swapStore(from: sourceURL)

        CloudBackupService.logger.info("Backup restored: \(metadata.id)")
    }

    // MARK: - Delete Backup

    /// Deletes a specific backup
    func deleteBackup(_ metadata: BackupMetadata) throws {
        guard let backupsDir = backupsDirectoryURL() else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for dirURL in contents {
            let metadataURL = dirURL.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let m = try? JSONDecoder().decode(BackupMetadata.self, from: data),
               m.id == metadata.id {
                try fm.removeItem(at: dirURL)
                CloudBackupService.logger.info("Backup deleted: \(metadata.id)")
                return
            }
        }
    }

    // MARK: - Storage

    /// Estimated iCloud storage used by backups
    func estimateStorageUsed() -> Int64 {
        let backups = listBackups()
        return backups.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Private

    private func enforceMaxBackups() throws {
        var backups = listBackups()
        while backups.count > maxBackups {
            if let oldest = backups.last {
                try deleteBackup(oldest)
                backups.removeLast()
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Utilities/CloudBackupService.swift
git commit -m "feat: add CloudBackupService for iCloud backup create/restore/delete

Uses WAL checkpoint before copy, CoreDataStack.swapStore() for safe restore,
enforces max 5 backups with auto-cleanup."
```

---

## Task 7: CloudSyncViewModel

**Files:**
- Create: `Tenra/ViewModels/CloudSyncViewModel.swift`

- [ ] **Step 1: Create CloudSyncViewModel**

Create `Tenra/ViewModels/CloudSyncViewModel.swift`:

```swift
//
//  CloudSyncViewModel.swift
//  Tenra
//
//  UI state for iCloud sync settings.
//  Coordinates CloudSyncService, CloudSyncSettingsService, and CloudBackupService.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class CloudSyncViewModel {

    private static let logger = Logger(subsystem: "Tenra", category: "CloudSyncViewModel")

    // MARK: - Observable State

    var syncState: SyncState = .disabled
    var backups: [BackupMetadata] = []
    var isCreatingBackup = false
    var isRestoringBackup = false
    var storageUsed: Int64 = 0
    var successMessage: String?
    var errorMessage: String?

    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "iCloudSyncEnabled")
        }
    }

    // MARK: - Dependencies

    @ObservationIgnored private let syncService: CloudSyncService
    @ObservationIgnored private let settingsService: CloudSyncSettingsService
    @ObservationIgnored private let backupService: CloudBackupService
    @ObservationIgnored private let coreDataStack: CoreDataStack

    /// Set by AppCoordinator after init — used for full re-initialization after restore
    @ObservationIgnored weak var appCoordinator: AppCoordinator?

    // MARK: - Init

    init(
        syncService: CloudSyncService,
        settingsService: CloudSyncSettingsService,
        backupService: CloudBackupService,
        coreDataStack: CoreDataStack = .shared
    ) {
        self.syncService = syncService
        self.settingsService = settingsService
        self.backupService = backupService
        self.coreDataStack = coreDataStack

        // Setup callbacks
        syncService.onSyncStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.syncState = state
            }
        }

        settingsService.onRemoteSettingsChanged = { [weak self] changes in
            Task { @MainActor in
                self?.handleRemoteSettingsChanged(changes)
            }
        }
    }

    // MARK: - Sync Toggle

    func toggleSync() async {
        if isSyncEnabled {
            // Turning OFF — confirm first (handled by view alert)
            disableSync()
        } else {
            await enableSync()
        }
    }

    func enableSync() async {
        let hasAccount = await syncService.checkiCloudAccountStatus()
        guard hasAccount else {
            syncState = .noAccount
            return
        }

        isSyncEnabled = true
        syncState = .initialSync
        coreDataStack.reloadContainer()
        syncService.startMonitoring()
        settingsService.startListening()
        settingsService.pushAllToCloud()

        CloudSyncViewModel.logger.info("iCloud sync enabled")
    }

    func disableSync() {
        isSyncEnabled = false
        syncState = .disabled
        syncService.stopMonitoring()
        settingsService.stopListening()
        coreDataStack.reloadContainer()

        CloudSyncViewModel.logger.info("iCloud sync disabled")
    }

    // MARK: - Backups

    func loadBackups() {
        backups = backupService.listBackups()
        storageUsed = backupService.estimateStorageUsed()
    }

    func createBackup(transactionCount: Int, accountCount: Int, categoryCount: Int) async {
        isCreatingBackup = true
        do {
            let metadata = try await backupService.createBackup(
                transactionCount: transactionCount,
                accountCount: accountCount,
                categoryCount: categoryCount
            )
            backups.insert(metadata, at: 0)
            storageUsed = backupService.estimateStorageUsed()
            await showSuccess(String(localized: "settings.cloud.backupCreated"))
        } catch {
            await showError(error.localizedDescription)
        }
        isCreatingBackup = false
    }

    func restoreBackup(_ metadata: BackupMetadata) async {
        isRestoringBackup = true
        do {
            try await backupService.restoreBackup(metadata)
            await showSuccess(String(localized: "settings.cloud.restoreSuccess"))
            // AppCoordinator will handle re-initialization via storeDidResetNotification
        } catch {
            await showError(error.localizedDescription)
        }
        isRestoringBackup = false
    }

    func deleteBackup(_ metadata: BackupMetadata) {
        do {
            try backupService.deleteBackup(metadata)
            backups.removeAll { $0.id == metadata.id }
            storageUsed = backupService.estimateStorageUsed()
        } catch {
            Task { await showError(error.localizedDescription) }
        }
    }

    // MARK: - Settings Sync

    /// Push a setting change to iCloud (called from SettingsViewModel on user action)
    func pushSettingToCloud(key: String, value: Any) {
        guard isSyncEnabled else { return }
        settingsService.pushToCloud(key: key, value: value)
    }

    private func handleRemoteSettingsChanged(_ changes: [String: Any]) {
        CloudSyncViewModel.logger.info("Applied \(changes.count) remote settings")
        // SettingsService reads from UserDefaults, which was already updated
        // by CloudSyncSettingsService. UI will update via @Observable.
    }

    // MARK: - Initialize on App Start

    func initializeIfNeeded() async {
        guard isSyncEnabled else {
            syncState = .disabled
            return
        }

        let hasAccount = await syncService.checkiCloudAccountStatus()
        guard hasAccount else {
            syncState = .noAccount
            return
        }

        syncState = .idle
        syncService.startMonitoring()
        settingsService.startListening()
        loadBackups()
    }

    // MARK: - Messages

    private func showSuccess(_ message: String) async {
        successMessage = message
        try? await Task.sleep(for: .seconds(3))
        successMessage = nil
    }

    private func showError(_ message: String) async {
        errorMessage = message
        try? await Task.sleep(for: .seconds(5))
        errorMessage = nil
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add Tenra/ViewModels/CloudSyncViewModel.swift
git commit -m "feat: add CloudSyncViewModel coordinating sync, settings, and backup services"
```

---

## Task 8: Wire Up in AppCoordinator

**Files:**
- Modify: `Tenra/ViewModels/AppCoordinator.swift`

- [ ] **Step 1: Add CloudSyncViewModel property**

In `AppCoordinator.swift`, add after the `insightsViewModel` declaration (around line 33):

```swift
@ObservationIgnored let cloudSyncViewModel: CloudSyncViewModel
```

- [ ] **Step 2: Initialize services and CloudSyncViewModel in init()**

At the end of the `init()` method (after the `insightsViewModel` initialization, around line 182), add:

```swift
// iCloud Sync services
let cloudSyncService = CloudSyncService()
let cloudSyncSettingsService = CloudSyncSettingsService()
let cloudBackupService = CloudBackupService()

self.cloudSyncViewModel = CloudSyncViewModel(
    syncService: cloudSyncService,
    settingsService: cloudSyncSettingsService,
    backupService: cloudBackupService
)
self.cloudSyncViewModel.appCoordinator = self
```

- [ ] **Step 3: Add cloud sync initialization to `initialize()` method**

Find the `initialize()` method in AppCoordinator. At the end of the method, add:

```swift
// Initialize iCloud sync if enabled
await cloudSyncViewModel.initializeIfNeeded()
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add Tenra/ViewModels/AppCoordinator.swift
git commit -m "feat: wire CloudSyncViewModel into AppCoordinator with service dependencies"
```

---

## Task 9: Localization — Add Cloud Sync Strings

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 1: Add English localization strings**

Append to the end of `Tenra/en.lproj/Localizable.strings`:

```
// MARK: - iCloud Sync
"settings.cloud" = "iCloud";
"settings.cloud.sync" = "iCloud Sync";
"settings.cloud.status.synced" = "Synced";
"settings.cloud.status.syncing" = "Syncing...";
"settings.cloud.status.initialSync" = "Initial Sync";
"settings.cloud.status.initialSyncMessage" = "This may take several minutes";
"settings.cloud.status.error" = "Sync Error";
"settings.cloud.status.disabled" = "Disabled";
"settings.cloud.status.noAccount" = "Sign in to iCloud in Settings";
"settings.cloud.lastSync" = "Last sync: %@";
"settings.cloud.changes" = "%d sent · %d received";
"settings.cloud.backups" = "Backups";
"settings.cloud.createBackup" = "Create Backup";
"settings.cloud.backupCreated" = "Backup created successfully";
"settings.cloud.restore" = "Restore";
"settings.cloud.restoreSuccess" = "Data restored successfully";
"settings.cloud.delete" = "Delete";
"settings.cloud.storage" = "Storage";
"settings.cloud.storageUsed" = "%@ of %@";
"settings.cloud.backupMetadata" = "%d accounts · %d transactions · %@";
"alert.restore.title" = "Restore Backup?";
"alert.restore.message" = "All current data will be replaced with the backup from %@.";
"alert.restore.confirm" = "Restore";
"alert.disableSync.title" = "Disable iCloud Sync?";
"alert.disableSync.message" = "Data will only be stored locally on this device.";
"alert.disableSync.confirm" = "Disable";
```

- [ ] **Step 2: Add Russian localization strings**

Append to the end of `Tenra/ru.lproj/Localizable.strings`:

```
// MARK: - iCloud Sync
"settings.cloud" = "iCloud";
"settings.cloud.sync" = "Синхронизация iCloud";
"settings.cloud.status.synced" = "Синхронизировано";
"settings.cloud.status.syncing" = "Синхронизация...";
"settings.cloud.status.initialSync" = "Первая синхронизация";
"settings.cloud.status.initialSyncMessage" = "Это может занять несколько минут";
"settings.cloud.status.error" = "Ошибка синхронизации";
"settings.cloud.status.disabled" = "Отключено";
"settings.cloud.status.noAccount" = "Войдите в iCloud в Настройках";
"settings.cloud.lastSync" = "Последняя: %@";
"settings.cloud.changes" = "%d отправлено · %d получено";
"settings.cloud.backups" = "Резервные копии";
"settings.cloud.createBackup" = "Создать резервную копию";
"settings.cloud.backupCreated" = "Резервная копия создана";
"settings.cloud.restore" = "Восстановить";
"settings.cloud.restoreSuccess" = "Данные восстановлены";
"settings.cloud.delete" = "Удалить";
"settings.cloud.storage" = "Хранилище";
"settings.cloud.storageUsed" = "%@ из %@";
"settings.cloud.backupMetadata" = "%d счетов · %d транзакций · %@";
"alert.restore.title" = "Восстановить данные?";
"alert.restore.message" = "Все текущие данные будут заменены копией от %@.";
"alert.restore.confirm" = "Восстановить";
"alert.disableSync.title" = "Отключить синхронизацию?";
"alert.disableSync.message" = "Данные будут храниться только на этом устройстве.";
"alert.disableSync.confirm" = "Отключить";
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat: add iCloud sync localization strings (English + Russian)"
```

---

## Task 10: UI — SettingsCloudSection

**Files:**
- Create: `Tenra/Views/Settings/SettingsCloudSection.swift`

- [ ] **Step 1: Create SettingsCloudSection**

Create `Tenra/Views/Settings/SettingsCloudSection.swift`:

```swift
//
//  SettingsCloudSection.swift
//  Tenra
//
//  iCloud section in Settings — toggle, status, backups navigation, storage.
//  Follows existing SettingsGeneralSection props pattern.
//

import SwiftUI

struct SettingsCloudSection: View {

    let isSyncEnabled: Bool
    let syncState: SyncState
    let storageUsed: Int64
    let onToggleSync: (Bool) -> Void
    let backupsDestination: CloudBackupsView

    var body: some View {
        Section(header: SettingsSectionHeaderView(title: String(localized: "settings.cloud"))) {
            // Sync toggle
            UniversalRow(
                config: .settings,
                leadingIcon: .sfSymbol("icloud", color: AppColors.accent, size: AppIconSize.md)
            ) {
                Text(String(localized: "settings.cloud.sync"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                Toggle("", isOn: Binding(
                    get: { isSyncEnabled },
                    set: { onToggleSync($0) }
                ))
                .labelsHidden()
            }

            // Status row (hidden when disabled)
            if isSyncEnabled {
                syncStatusRow
            }

            // Backups navigation
            NavigationSettingsRow(
                icon: "externaldrive.badge.icloud",
                title: String(localized: "settings.cloud.backups")
            ) {
                backupsDestination
            }

            // Storage usage
            UniversalRow(
                config: .settings,
                leadingIcon: .sfSymbol("internaldrive", color: AppColors.accent, size: AppIconSize.md)
            ) {
                Text(String(localized: "settings.cloud.storage"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                Text(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var syncStatusRow: some View {
        UniversalRow(
            config: .settings,
            leadingIcon: .sfSymbol(statusIcon, color: statusColor, size: AppIconSize.md)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(statusText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } trailing: {
            EmptyView()
        }
        .animation(AppAnimation.gentleSpring, value: statusText)
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        switch syncState {
        case .synced: return "checkmark.icloud"
        case .syncing, .initialSync: return "arrow.triangle.2.circlepath.icloud"
        case .error: return "exclamationmark.icloud"
        case .noAccount: return "person.crop.circle.badge.exclamationmark"
        default: return "icloud"
        }
    }

    private var statusColor: Color {
        switch syncState {
        case .synced: return AppColors.success
        case .syncing, .initialSync: return AppColors.accent
        case .error: return AppColors.destructive
        case .noAccount: return AppColors.warning
        default: return AppColors.textSecondary
        }
    }

    private var statusText: String {
        switch syncState {
        case .synced: return String(localized: "settings.cloud.status.synced")
        case .syncing: return String(localized: "settings.cloud.status.syncing")
        case .initialSync: return String(localized: "settings.cloud.status.initialSync")
        case .error(let message): return "\(String(localized: "settings.cloud.status.error")): \(message)"
        case .noAccount: return String(localized: "settings.cloud.status.noAccount")
        default: return String(localized: "settings.cloud.status.disabled")
        }
    }

    private var statusSubtitle: String? {
        switch syncState {
        case .synced(let lastSync, let sent, let received):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let timeAgo = formatter.localizedString(for: lastSync, relativeTo: Date())
            var subtitle = String(format: String(localized: "settings.cloud.lastSync"), timeAgo)
            if sent > 0 || received > 0 {
                subtitle += "\n" + String(format: String(localized: "settings.cloud.changes"), sent, received)
            }
            return subtitle
        case .initialSync:
            return String(localized: "settings.cloud.status.initialSyncMessage")
        default:
            return nil
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Settings/SettingsCloudSection.swift
git commit -m "feat: add SettingsCloudSection with sync toggle, status, and storage display"
```

---

## Task 11: UI — BackupRowView & CloudBackupsView

**Files:**
- Create: `Tenra/Views/Settings/BackupRowView.swift`
- Create: `Tenra/Views/Settings/CloudBackupsView.swift`

- [ ] **Step 1: Create BackupRowView**

Create `Tenra/Views/Settings/BackupRowView.swift`:

```swift
//
//  BackupRowView.swift
//  Tenra
//
//  Single backup row with metadata and swipe actions.
//

import SwiftUI

struct BackupRowView: View {
    let metadata: BackupMetadata
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(metadata.formattedDate)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

            Text(metadataLine)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "settings.cloud.delete"), systemImage: "trash")
            }

            Button {
                onRestore()
            } label: {
                Label(String(localized: "settings.cloud.restore"), systemImage: "arrow.counterclockwise")
            }
            .tint(AppColors.accent)
        }
    }

    private var metadataLine: String {
        String(format: String(localized: "settings.cloud.backupMetadata"),
               metadata.accountCount, metadata.transactionCount, metadata.formattedFileSize)
    }
}
```

- [ ] **Step 2: Create CloudBackupsView**

Create `Tenra/Views/Settings/CloudBackupsView.swift`:

```swift
//
//  CloudBackupsView.swift
//  Tenra
//
//  Backup list screen with create, restore, and delete.
//

import SwiftUI

struct CloudBackupsView: View {

    let cloudSyncViewModel: CloudSyncViewModel

    /// Counts needed for backup metadata — passed from SettingsView
    let transactionCount: Int
    let accountCount: Int
    let categoryCount: Int

    @State private var showingRestoreAlert = false
    @State private var backupToRestore: BackupMetadata?
    @State private var showingDeleteAlert = false
    @State private var backupToDelete: BackupMetadata?

    var body: some View {
        List {
            // Create backup button
            Section {
                Button {
                    Task {
                        await cloudSyncViewModel.createBackup(
                            transactionCount: transactionCount,
                            accountCount: accountCount,
                            categoryCount: categoryCount
                        )
                    }
                } label: {
                    HStack {
                        Spacer()
                        if cloudSyncViewModel.isCreatingBackup {
                            ProgressView()
                                .padding(.trailing, AppSpacing.sm)
                        }
                        Text(String(localized: "settings.cloud.createBackup"))
                            .font(AppTypography.body)
                        Spacer()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(cloudSyncViewModel.isCreatingBackup)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            // Backup list
            if !cloudSyncViewModel.backups.isEmpty {
                Section(header: SettingsSectionHeaderView(title: String(localized: "settings.cloud.backups"))) {
                    ForEach(cloudSyncViewModel.backups) { backup in
                        BackupRowView(
                            metadata: backup,
                            onRestore: {
                                backupToRestore = backup
                                showingRestoreAlert = true
                            },
                            onDelete: {
                                backupToDelete = backup
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.cloud.backups"))
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            // Toast messages
            VStack {
                if let successMessage = cloudSyncViewModel.successMessage {
                    MessageBanner.success(successMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                if let errorMessage = cloudSyncViewModel.errorMessage {
                    MessageBanner.error(errorMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
                Spacer()
            }
        }
        .alert(
            String(localized: "alert.restore.title"),
            isPresented: $showingRestoreAlert
        ) {
            Button(String(localized: "alert.restore.confirm"), role: .destructive) {
                if let backup = backupToRestore {
                    Task { await cloudSyncViewModel.restoreBackup(backup) }
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            if let backup = backupToRestore {
                Text(String(format: String(localized: "alert.restore.message"), backup.formattedDate))
            }
        }
        .alert(
            String(localized: "settings.cloud.delete"),
            isPresented: $showingDeleteAlert
        ) {
            Button(String(localized: "settings.cloud.delete"), role: .destructive) {
                if let backup = backupToDelete {
                    cloudSyncViewModel.deleteBackup(backup)
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        }
        .task {
            cloudSyncViewModel.loadBackups()
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add Tenra/Views/Settings/BackupRowView.swift Tenra/Views/Settings/CloudBackupsView.swift
git commit -m "feat: add CloudBackupsView and BackupRowView for backup management UI"
```

---

## Task 12: Wire SettingsCloudSection into SettingsView

**Files:**
- Modify: `Tenra/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Add cloudSyncViewModel dependency to SettingsView**

Add after the `loansViewModel` declaration (line 27):

```swift
let cloudSyncViewModel: CloudSyncViewModel
```

- [ ] **Step 2: Add cloudSection computed property**

Add after the `dangerZoneSection` computed property (around line 223):

```swift
private var cloudSection: some View {
    SettingsCloudSection(
        isSyncEnabled: cloudSyncViewModel.isSyncEnabled,
        syncState: cloudSyncViewModel.syncState,
        storageUsed: cloudSyncViewModel.storageUsed,
        onToggleSync: { enabled in
            if enabled {
                Task { await cloudSyncViewModel.enableSync() }
            } else {
                showingDisableSyncConfirmation = true
            }
        },
        backupsDestination: CloudBackupsView(
            cloudSyncViewModel: cloudSyncViewModel,
            transactionCount: transactionsViewModel.allTransactions.count,
            accountCount: accountsViewModel.accounts.count,
            categoryCount: 0 // will be set from categoriesViewModel
        )
    )
}
```

- [ ] **Step 3: Add showingDisableSyncConfirmation state**

Add after the existing `@State` declarations (around line 33):

```swift
@State private var showingDisableSyncConfirmation = false
```

- [ ] **Step 4: Insert cloudSection into settingsList**

In the `settingsList` `List`, add `cloudSection` after `generalSection`:

```swift
List {
    generalSection
    cloudSection       // ← NEW
    dataManagementSection
    exportImportSection
    experimentsSection
    aboutSection
    dangerZoneSection
}
```

- [ ] **Step 5: Add disable sync confirmation alert**

After the existing `showingResetConfirmation` alert (around line 101), add:

```swift
.alert(
    String(localized: "alert.disableSync.title"),
    isPresented: $showingDisableSyncConfirmation
) {
    Button(String(localized: "alert.disableSync.confirm"), role: .destructive) {
        cloudSyncViewModel.disableSync()
    }
    Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
} message: {
    Text(String(localized: "alert.disableSync.message"))
}
```

- [ ] **Step 6: Update SettingsView Preview and all call sites**

Update the Preview at the bottom and any other places where `SettingsView` is instantiated to pass `cloudSyncViewModel`. Search for `SettingsView(` across the project to find all call sites.

In Preview:
```swift
#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        SettingsView(
            settingsViewModel: coordinator.settingsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionStore: coordinator.transactionStore,
            depositsViewModel: coordinator.depositsViewModel,
            loansViewModel: coordinator.loansViewModel,
            cloudSyncViewModel: coordinator.cloudSyncViewModel
        )
    }
}
```

Find and update all other `SettingsView(` call sites (likely in `ContentView.swift` or similar navigation container).

- [ ] **Step 7: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 8: Commit**

```bash
git add Tenra/Views/Settings/SettingsView.swift
git commit -m "feat: wire SettingsCloudSection into SettingsView with disable sync alert"
```

---

## Task 13: Update All SettingsView Call Sites

**Files:**
- Modify: Any file that creates `SettingsView` (likely `ContentView.swift` or navigation container)

- [ ] **Step 1: Find all SettingsView instantiation sites**

Run: `grep -rn "SettingsView(" Tenra/ --include="*.swift"` to find all call sites.

- [ ] **Step 2: Add `cloudSyncViewModel` parameter to each call site**

Add `cloudSyncViewModel: coordinator.cloudSyncViewModel` (or equivalent) to every `SettingsView(` initializer.

- [ ] **Step 3: Verify build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: pass cloudSyncViewModel to all SettingsView call sites"
```

---

## Task 14: Full Build & Test Verification

- [ ] **Step 1: Full build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

- [ ] **Step 2: Run all unit tests**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -E "Test Suite|passed|failed|error:" | head -30`
Expected: All tests pass

- [ ] **Step 3: Fix any compilation or test failures**

Address any issues found in steps 1-2.

- [ ] **Step 4: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve build/test issues from iCloud sync integration"
```

---

## Task Summary

| Task | Description | New Files | Modified Files |
|------|-------------|-----------|----------------|
| 1 | Entitlements & capabilities | `Tenra.entitlements` | `project.pbxproj` |
| 2 | CoreDataStack CloudKit changes | — | `CoreDataStack.swift` |
| 3 | BackupMetadata model + tests | `BackupMetadata.swift`, `BackupMetadataTests.swift` | — |
| 4 | CloudSyncService | `CloudSyncService.swift` | — |
| 5 | CloudSyncSettingsService + tests | `CloudSyncSettingsService.swift`, `CloudSyncSettingsServiceTests.swift` | — |
| 6 | CloudBackupService | `CloudBackupService.swift` | — |
| 7 | CloudSyncViewModel | `CloudSyncViewModel.swift` | — |
| 8 | AppCoordinator wiring | — | `AppCoordinator.swift` |
| 9 | Localization strings | — | `Localizable.strings` ×2 |
| 10 | SettingsCloudSection | `SettingsCloudSection.swift` | — |
| 11 | BackupRowView + CloudBackupsView | `BackupRowView.swift`, `CloudBackupsView.swift` | — |
| 12 | Wire into SettingsView | — | `SettingsView.swift` |
| 13 | Update call sites | — | `ContentView.swift` + others |
| 14 | Full build & test verification | — | — |
