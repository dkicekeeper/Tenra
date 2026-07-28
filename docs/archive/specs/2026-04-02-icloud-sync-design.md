# iCloud Sync & Backup — Design Spec

**Date:** 2026-04-02
**Status:** Draft
**Scope:** Automatic CloudKit sync between devices + manual iCloud backups + settings sync

---

## 1. Overview

Add iCloud synchronization to Tenra for:
1. **Automatic real-time sync** of CoreData between devices (iPhone ↔ iPad) via CloudKit
2. **Manual backups** — SQLite snapshots stored in private iCloud container
3. **Settings sync** — user preferences via `NSUbiquitousKeyValueStore`

### Approach

Replace `NSPersistentContainer` with `NSPersistentCloudKitContainer`. The project is already prepared:
- Persistent history tracking enabled
- Remote change notifications enabled
- All entities marked `syncable="YES"`
- Unique constraints on all entities
- `automaticallyMergesChangesFromParent = true` on viewContext

Conflict resolution: last write wins (`NSMergeByPropertyObjectTrumpMergePolicy`, already configured).

---

## 2. Architecture

### 2.1 New Services

#### CloudSyncService
- `nonisolated final class` — runs on background thread
- Listens to `NSPersistentStoreRemoteChange` notifications (already enabled)
- Tracks sync status via `NSPersistentHistoryTransaction` change counting
- Exposes sync state to `CloudSyncViewModel`

```swift
enum SyncState: Sendable {
    case idle
    case syncing
    case synced(lastSync: Date, sentCount: Int, receivedCount: Int)
    case error(Error)
    case disabled
    case noAccount       // no iCloud account on device
    case initialSync     // first-time upload (19k+ records, may take minutes)
}
```

#### CloudSyncSettingsService
- Wraps `NSUbiquitousKeyValueStore` for settings sync
- Syncs: base currency, theme, language, other user preferences
- Listens to `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
- Pushes changes to `SettingsService` on receiving remote updates
- **Loop prevention:** `applySyncedSettings()` writes ONLY to `UserDefaults`, never back to `NSUbiquitousKeyValueStore`. Outgoing sync (`pushToCloud()`) is a separate method called only from explicit user actions, not from incoming notification handlers.

#### CloudBackupService
- Location: `Services/Utilities/` (file I/O utility, not core infrastructure)
- Creates SQLite snapshots in `FileManager.default.url(forUbiquityContainerIdentifier:)` → `/Backups/`
- **Safe backup creation:** triggers WAL checkpoint (`PRAGMA wal_checkpoint(TRUNCATE)`) before copying to ensure consistent snapshot of `.sqlite` file only (no `.sqlite-wal`/`.sqlite-shm` needed after checkpoint)
- Stores `BackupMetadata` JSON alongside each backup:
  ```swift
  struct BackupMetadata: Codable, Sendable {
      let id: String           // UUID
      let date: Date
      let transactionCount: Int
      let accountCount: Int
      let categoryCount: Int
      let modelVersion: String // "v6"
      let fileSize: Int64      // bytes
      let appVersion: String
  }
  ```
- Maximum 5 backups — auto-deletes oldest when exceeded
- **Safe restore flow** (see Section 3.5 for details):
  1. Remove store from coordinator (NOT `resetAllData()`)
  2. Copy backup file to persistent store URL
  3. Re-add store with all original options
  4. Post `storeDidResetNotification`
  5. Re-initialize `AppCoordinator`

#### CloudSyncViewModel
- `@Observable @MainActor class` — in `ViewModels/`
- Owns `SyncState` as a published property (no separate `CloudSyncStatus` file)
- Coordinates all three services for UI
- Dependencies: `CloudSyncService`, `CloudSyncSettingsService`, `CloudBackupService`
- Exposes: sync state, backup list, storage usage, toggle state
- Registered in `AppCoordinator`

### 2.2 CoreDataStack Changes

#### Container creation inside existing `NSLock` pattern

The existing `CoreDataStack` uses `containerLock` + `_persistentContainer` for thread-safe lazy initialization. The CloudKit toggle integrates into this pattern:

```swift
// Inside the existing persistentContainer computed property (guarded by containerLock)
private func createContainer() -> NSPersistentContainer {
    if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
        let container = NSPersistentCloudKitContainer(name: "Tenra")
        let description = container.persistentStoreDescriptions.first!
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.dakacom.Tenra"
        )
        return container
    } else {
        return NSPersistentContainer(name: "Tenra")
    }
}
```

#### New `reloadContainer()` method for toggle on/off

```swift
func reloadContainer() {
    containerLock.lock()
    defer { containerLock.unlock() }

    // 1. Remove existing store from coordinator
    if let store = _persistentContainer?.persistentStoreCoordinator.persistentStores.first {
        try? _persistentContainer?.persistentStoreCoordinator.remove(store)
    }

    // 2. Clear cached container — forces re-creation on next access
    _persistentContainer = nil

    // 3. Re-trigger lazy initialization with new container type
    _ = persistentContainer

    // 4. Notify all FRC holders
    NotificationCenter.default.post(name: .storeDidResetNotification, object: nil)
}
```

#### New `swapStore(from backupURL: URL)` method for backup restore

```swift
func swapStore(from backupURL: URL) throws {
    containerLock.lock()
    defer { containerLock.unlock() }

    guard let container = _persistentContainer,
          let store = container.persistentStoreCoordinator.persistentStores.first,
          let storeURL = store.url else {
        throw CloudBackupError.noActiveStore
    }

    // 1. Capture current store options
    let options = store.options

    // 2. Remove store from coordinator (NOT resetAllData — that recreates it)
    try container.persistentStoreCoordinator.remove(store)

    // 3. Replace SQLite file
    let fm = FileManager.default
    try fm.removeItem(at: storeURL)
    try fm.copyItem(at: backupURL, to: storeURL)

    // 4. Re-add store with ALL original options (history tracking, file protection, etc.)
    try container.persistentStoreCoordinator.addPersistentStore(
        type: .sqlite,
        at: storeURL,
        options: options
    )

    // 5. Reset viewContext to pick up new store
    container.viewContext.reset()

    // 6. Notify FRC holders to recreate
    NotificationCenter.default.post(name: .storeDidResetNotification, object: nil)
}
```

#### File protection change for background sync

```swift
// Before: .complete (inaccessible when device locked — blocks background CloudKit sync)
// After: .completeUntilFirstUserAuthentication (accessible after first unlock)
description.setOption(
    FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
    forKey: NSPersistentStoreFileProtectionKey
)
```

**Rationale:** `FileProtectionType.complete` makes the SQLite file inaccessible while the device is locked. CloudKit syncs in background (via background app refresh / push notifications) and needs to read the store. `.completeUntilFirstUserAuthentication` keeps data encrypted at rest but accessible after the user unlocks the device once per boot — standard for apps with background sync.

#### CloudKit schema initialization

```swift
// Called once during development to push CoreData schema to CloudKit
// In production: .dryRun validates schema exists without modifying
#if DEBUG
try container.initializeCloudKitSchema(options: [])
#else
try container.initializeCloudKitSchema(options: [.dryRun])
#endif
```

**Development workflow:** Run the app once in DEBUG with `initializeCloudKitSchema()` to push schema to CloudKit development environment. Then promote to production via CloudKit Dashboard before App Store release.

### 2.3 Project Configuration (Xcode)

- Add **CloudKit** capability → creates `Tenra.entitlements` with `com.apple.developer.icloud-container-identifiers`
- Add **iCloud** entitlement with container `iCloud.dakacom.Tenra`
- Add **Push Notifications** capability (required by CloudKit for remote change notifications)
- Add **Background Modes** → Remote notifications

### 2.4 Dependency Graph

```
AppCoordinator
  ├── CloudSyncService (new) — Services/Core/
  │     └── CoreDataStack (existing)
  ├── CloudSyncSettingsService (new) — Services/Settings/
  │     └── NSUbiquitousKeyValueStore
  ├── CloudBackupService (new) — Services/Utilities/
  │     ├── CoreDataStack (existing)
  │     └── FileManager.ubiquityContainerURL
  └── SettingsViewModel (existing)
        └── CloudSyncViewModel (new) — ViewModels/
              ├── CloudSyncService
              ├── CloudSyncSettingsService
              └── CloudBackupService
```

---

## 3. Data Flow

### 3.1 Auto-Sync (outgoing)

```
ViewModel.save()
  → TransactionStore.apply()
    → CoreData context.save()
      → NSPersistentCloudKitContainer
        → CloudKit private database
```

### 3.2 Auto-Sync (incoming)

```
CloudKit private database
  → NSPersistentStoreRemoteChange notification
    → CloudSyncService.handleRemoteChange()
      → count changes via NSPersistentHistoryTransaction
      → update SyncState on CloudSyncViewModel (MainActor)
    → viewContext.automaticallyMergesChangesFromParent (existing)
      → TransactionStore sees changes automatically
```

### 3.3 Settings Sync

```
Outgoing (user action):
  SettingsService.setCurrency()
    → UserDefaults (local)
    → CloudSyncSettingsService.pushToCloud() → NSUbiquitousKeyValueStore.set()

Incoming (remote change):
  didChangeExternallyNotification
    → CloudSyncSettingsService.handleExternalChange()
      → SettingsService.applySyncedSettings()  // writes ONLY to UserDefaults
        → AppCoordinator updates VMs
```

**Loop prevention contract:** `applySyncedSettings()` never calls `pushToCloud()`. Only explicit user actions trigger outgoing sync.

### 3.4 Backup Create

```
User taps "Create Backup"
  → CloudBackupService.createBackup()
    → PRAGMA wal_checkpoint(TRUNCATE)        // flush WAL to main SQLite
    → CoreDataStack.persistentStoreURL
    → FileManager.copyItem() (.sqlite only)  // consistent after checkpoint
    → BackupMetadata.toJSON()
    → FileManager.ubiquityContainerURL → /Backups/{timestamp}/
    → iCloud Drive uploads automatically
```

### 3.5 Backup Restore

```
User taps "Restore" → Alert confirmation
  → CloudBackupService.restoreBackup(metadata)
    → FileManager.startDownloadingUbiquitousItem() (if not downloaded)
    → CoreDataStack.swapStore(from: backupURL)
      1. Remove store from coordinator
      2. Copy backup .sqlite to persistent store URL
      3. Re-add store with original options (history tracking, file protection, etc.)
      4. Reset viewContext
      5. Post storeDidResetNotification → FRC recreated
    → AppCoordinator.initialize()            // full re-initialization
```

### 3.6 First-Time Sync (19k transactions)

```
Toggle ON (first device with existing data)
  → reloadContainer() → NSPersistentCloudKitContainer
  → CloudKit begins uploading (400 records per batch, auto-managed)
  → SyncState = .initialSync
  → UI shows "Initial sync in progress" with indeterminate progress
  → CloudKit rate-limits internally (~10-30 minutes for 19k records)
  → Completion: SyncState = .synced(...)

Second device (fresh install)
  → SyncState = .initialSync
  → CloudKit downloads records (typically faster than upload)
  → Completion: SyncState = .synced(...)
```

**User-facing messaging:** `.initialSync` state shows distinct UI from `.syncing` — explains that first sync takes time, shows "This may take several minutes" text. No fake progress bar (CloudKit doesn't expose per-record progress).

---

## 4. UI Design

### 4.1 SettingsCloudSection (in SettingsView)

New section following existing patterns: `SettingsSectionHeaderView`, `UniversalRow(.settings)`, `NavigationSettingsRow`.

```
Section(header: SettingsSectionHeaderView("settings.cloud"))
├── UniversalRow(.settings)
│   icon: "icloud" / AppColors.accent / AppIconSize.md
│   title: "settings.cloud.sync"
│   trailing: Toggle (bound to iCloudSyncEnabled)
│
├── UniversalRow(.settings) [hidden if sync disabled]
│   icon: "arrow.triangle.2.circlepath" / dynamic color
│   title: status text ("settings.cloud.status.synced" etc.)
│   subtitle: "settings.cloud.lastSync" + relative time
│   subtitle2: "settings.cloud.changes" + sent/received
│   (for .initialSync: "settings.cloud.status.initialSync" + descriptive text)
│
├── NavigationSettingsRow
│   icon: "externaldrive.badge.icloud"
│   title: "settings.cloud.backups"
│   destination: CloudBackupsView
│
└── UniversalRow(.settings)
    icon: "internaldrive"
    title: "settings.cloud.storage"
    trailing: usage text + progress indicator
```

### 4.2 CloudBackupsView (separate screen)

```
NavigationStack
├── Button("settings.cloud.createBackup") / PrimaryButtonStyle
│   → ProgressView during creation
│   → MessageBanner.success("settings.cloud.backupCreated")
│
└── List of BackupRowView (sorted by date, newest first)
    ├── Date — AppTypography.body / AppColors.textPrimary
    ├── Metadata line — AppTypography.bodySmall / AppColors.textSecondary
    │   "{accountCount} accounts · {txCount} transactions · {fileSize}"
    └── swipeActions:
        ├── Restore (.accent) → Alert confirmation → restore flow
        └── Delete (.destructive) → Alert confirmation → delete
```

### 4.3 Design System Usage

| Element | Token |
|---------|-------|
| Section header | `SettingsSectionHeaderView` |
| Row layout | `UniversalRow(config: .settings)` |
| Navigation | `NavigationSettingsRow` |
| Icons | SF Symbols + `AppColors.accent` + `AppIconSize.md` |
| Typography | `AppTypography.body`, `.bodySmall` |
| Colors | `AppColors.textPrimary`, `.textSecondary`, `.accent`, `.destructive` |
| Animations | `AppAnimation.gentleSpring` for status transitions |
| Feedback | `MessageBanner.success/error/warning` |
| Buttons | `PrimaryButtonStyle` |
| Strings | `String(localized:)` throughout |

### 4.4 Interactions

- **Toggle off** → `alert.disableSync` confirmation alert
- **Toggle on** → checks iCloud account availability first; if none → shows "Sign in to iCloud" message. If first sync → `.initialSync` state with explanatory text
- **Create backup** → shows inline ProgressView, then `MessageBanner.success`
- **Restore** → `alert.restore` confirmation → ProgressView → `swapStore()` → full app re-initialization
- **Sync error** → red status icon + "Retry" button + `MessageBanner.error`
- **Storage full** → `MessageBanner.warning` + suggest deleting old backups

---

## 5. Localization

### en.lproj/Localizable.strings additions

```
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

### ru.lproj/Localizable.strings additions

```
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

---

## 6. Error Handling

| Situation | Behavior |
|-----------|----------|
| No iCloud account | Toggle disabled, show `settings.cloud.status.noAccount` |
| No network | Status "Waiting for network", data queues locally |
| Data conflict | `NSMergeByPropertyObjectTrumpMergePolicy` — last write wins |
| Backup not downloaded | `startDownloadingUbiquitousItem()` + ProgressView |
| CloudKit error | Red status + "Retry" button + `MessageBanner.error` |
| Storage full | `MessageBanner.warning` + suggest deleting old backups |
| Backup restore fails | Keep current data intact (store re-added from original), show `MessageBanner.error` |
| Model version mismatch on restore | Reject restore, show version incompatibility error |
| First-time sync | `.initialSync` state, "This may take several minutes" text |
| CloudKit schema missing | `initializeCloudKitSchema(.dryRun)` validates; logs error if not pushed |

---

## 7. New Files

| File | Location | Purpose |
|------|----------|---------|
| `CloudSyncService.swift` | `Services/Core/` | CloudKit sync monitoring, change counting |
| `CloudSyncSettingsService.swift` | `Services/Settings/` | `NSUbiquitousKeyValueStore` wrapper |
| `CloudBackupService.swift` | `Services/Utilities/` | Backup create/restore/delete/list |
| `BackupMetadata.swift` | `Models/` | Backup metadata model |
| `CloudSyncViewModel.swift` | `ViewModels/` | UI state for cloud settings (owns `SyncState`) |
| `SettingsCloudSection.swift` | `Views/Settings/` | Settings section view |
| `CloudBackupsView.swift` | `Views/Settings/` | Backup list screen |
| `BackupRowView.swift` | `Views/Settings/` | Individual backup row |
| `Tenra.entitlements` | `Tenra/` | iCloud + Push entitlements |

---

## 8. Modified Files

| File | Change |
|------|--------|
| `CoreDataStack.swift` | Conditional `NSPersistentCloudKitContainer`, `reloadContainer()`, `swapStore()`, file protection → `.completeUntilFirstUserAuthentication`, `initializeCloudKitSchema` |
| `AppCoordinator.swift` | Register new services and `CloudSyncViewModel` |
| `SettingsView.swift` | Add `SettingsCloudSection` |
| `en.lproj/Localizable.strings` | Add cloud sync localization keys |
| `ru.lproj/Localizable.strings` | Add cloud sync localization keys |
| `Info.plist` | CloudKit container identifier (if needed) |
| `Tenra.xcodeproj/project.pbxproj` | New files + capabilities |

---

## 9. Testing Strategy

- **Unit tests:** `CloudBackupService` create/restore/delete with in-memory store
- **Unit tests:** `CloudSyncSettingsService` read/write/external change handling, loop prevention
- **Unit tests:** `BackupMetadata` encoding/decoding
- **Unit tests:** `CoreDataStack.swapStore()` — detach/copy/reattach with option preservation
- **Integration:** Toggle sync on/off → verify container type switch via `reloadContainer()`
- **Integration:** `initializeCloudKitSchema(.dryRun)` succeeds after schema push
- **Manual:** Two-device sync with real iCloud account
- **Manual:** First-time sync with 19k transactions — verify `.initialSync` state and completion
- **Manual:** Backup create → delete app → restore
- **Edge cases:** No iCloud account, airplane mode, storage full, WAL checkpoint failure
