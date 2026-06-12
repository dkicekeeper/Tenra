# Plan 002: Fix the backup model-version stamp/gate and put the restore path under test

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 4392be3..HEAD -- Tenra/Services/Utilities/CloudBackupService.swift Tenra/CoreData/CoreDataStack.swift Tenra/Models/BackupMetadata.swift CLAUDE.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW–MED (touches the restore path; mitigated by the new tests)
- **Depends on**: none (001 recommended first so CI verifies this work)
- **Category**: bug + tests
- **Planned at**: commit `4392be3`, 2026-06-11

## Why this matters

The iCloud/local backup feature stamps every backup's `metadata.json` with `modelVersion: "v7"` — hardcoded — while the actual CoreData schema is at **v12** (`Tenra/CoreData/Tenra.xcdatamodeld/.xccurrentversion` → `Tenra v12.xcdatamodel`). Restore gates on **exact string equality** against another hardcoded `"v7"`. Today this is self-consistently wrong, so restores work; but the first schema bump where someone "fixes" the constant makes **every existing user backup unrestorable**, and conversely the string gate provides no real compatibility protection because the label never tracked the schema. Restore is a destructive operation (it replaces the live database via `swapStore`) and currently has **zero test coverage**. This plan derives the version from the compiled model, replaces the string gate with a real CoreData store-compatibility check, and adds tests around backup/restore.

## Current state

Files:

- `Tenra/Services/Utilities/CloudBackupService.swift` (403 lines) — `nonisolated final class CloudBackupService: @unchecked Sendable`. Creates/lists/restores/deletes SQLite backups in local Documents or the iCloud Drive container.
- `Tenra/CoreData/CoreDataStack.swift` (455 lines) — owns the `NSPersistentContainer`; `swapStore(from:)` performs the restore; `CloudBackupError` enum lives here (line 339). Has a testing seam: `init(container:)` at line 49.
- `Tenra/Models/BackupMetadata.swift` — `Codable` struct with a `modelVersion: String` field.
- `CLAUDE.md` — claims "v8 schema" at lines 69, 167, 336 while line 244 correctly documents v12 (folded-in doc fix).

The bug, verbatim from `CloudBackupService.swift`:

```swift
// line 223–232 (inside createBackup)
let metadata = BackupMetadata(
    id: UUID().uuidString,
    date: Date(),
    transactionCount: transactionCount,
    accountCount: accountCount,
    categoryCount: categoryCount,
    modelVersion: "v7",          // ← hardcoded; schema is actually v12
    fileSize: fileSize,
    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
)
```

```swift
// line 296–310
/// Current model version — must match backup to allow restore
private nonisolated static let currentModelVersion = "v7"   // ← also hardcoded

func restoreBackup(_ metadata: BackupMetadata) async throws {
    // Reject incompatible model versions
    guard metadata.modelVersion == Self.currentModelVersion else {
        throw CoreDataStack.CloudBackupError.incompatibleVersion(metadata.modelVersion)
    }
    ...
```

Key facts about the restore mechanics (verified by reading `CoreDataStack.swift`):

- The store is loaded with **automatic lightweight migration** enabled (`createAndLoadContainer`, lines 126–127: `NSMigratePersistentStoresAutomaticallyOption` + `NSInferMappingModelAutomaticallyOption`).
- `swapStore(from:)` (line 363) re-adds the swapped-in store using `store.options` captured from the live store (line 371) — i.e. **with the same automatic-migration options**. So a backup whose store is an *older* schema would lightweight-migrate fine on restore; the schema history is strictly additive (documented in CLAUDE.md "CoreData Schema Bumps").
- Therefore the right gate is not a version string at all: it's "can the current model open this store file, directly or via migration" — answerable from the store file's own metadata.
- Important wrinkle: **existing backups in the wild are stamped `"v7"` regardless of the schema that actually produced them** (the label never changed). The `metadata.json` version string is unreliable historical data; the SQLite file's CoreData metadata is the truth. The new gate must read the file, not the JSON.

Repo conventions that apply:

- Default actor isolation is MainActor (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); `CloudBackupService` and `swapStore` are explicitly `nonisolated`. Keep new members' isolation consistent with their surroundings.
- Test suites constructing MainActor-isolated types must be annotated `@MainActor` (CLAUDE.md Testing section).
- swift-testing style: `@Suite`/`@Test`/`#expect`, see `TenraTests/CoreDataRoundTripTests.swift` for the in-memory CoreData fixture pattern.
- Swift test filenames must be unique within the target.
- Files added on disk are auto-included in the target (file-system-synchronized groups) — no pbxproj edits.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| grep -E "error:" \| head -30` | no output |
| Run the new suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/CloudBackupServiceTests 2>&1 \| grep -aE "Test case .* (passed\|failed)\|\*\* TEST (SUCCEEDED\|FAILED)"` | all `passed`, `** TEST SUCCEEDED **` |
| Full unit suite | same with `-only-testing:TenraTests` | `** TEST SUCCEEDED **` |

Note (repo-documented quirks): suite-level filtering only — `-only-testing:TenraTests/Suite/method()` silently runs 0 tests; the suite name must be the **type name**, not the `@Suite("display name")` string. Do not grep test output for `expect`.

## Scope

**In scope** (the only files you should modify/create):
- `Tenra/Services/Utilities/CloudBackupService.swift`
- `CLAUDE.md` (the three "v8" → "v12" mentions, lines 69/167/336, plus one line in the schema-bump checklist)
- `TenraTests/Services/CloudBackupServiceTests.swift` (create)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `Tenra/CoreData/CoreDataStack.swift` — `swapStore` works and is referenced by recovery paths; the gate change lives entirely in `CloudBackupService`. (Adding a *new* case to `CloudBackupError` would touch this file — don't; reuse `.incompatibleVersion`.)
- `Tenra/Models/BackupMetadata.swift` — the struct stays as is; `modelVersion` remains a stored display field. Changing the Codable shape would break decoding of existing users' `metadata.json`.
- Any UI in `Views/Settings/` that displays backups.
- The `.xcdatamodeld` — no schema changes.

## Git workflow

- Work directly on `main` (owner's preference). Do **NOT** push.
- One commit per step (or steps 1+2 together), message style: short descriptive line + `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Steps

### Step 1: Derive the current model version from the compiled model

In `CloudBackupService.swift`, replace the hardcoded constant (line 297) with a derivation that reads the compiled `.momd` bundle's `VersionInfo.plist` — the compiled model contains `NSManagedObjectModel_CurrentVersionName` (e.g. `"Tenra v12"`). Normalize to the short form (`"v12"`) to stay format-compatible with existing metadata:

```swift
/// Current model version, derived from the compiled model so it can never
/// drift from the schema again (was hardcoded "v7" while the schema was v12).
/// Display/diagnostic value only — restore compatibility is decided from the
/// backup store file's own metadata, not this string.
nonisolated static let currentModelVersion: String = {
    guard
        let momdURL = Bundle.main.url(forResource: "Tenra", withExtension: "momd"),
        let info = NSDictionary(contentsOf: momdURL.appendingPathComponent("VersionInfo.plist")),
        let current = info["NSManagedObjectModel_CurrentVersionName"] as? String
    else { return "unknown" }
    // "Tenra v12" → "v12"
    return current.components(separatedBy: " ").last ?? current
}()
```

Make it `static` (not `private`) so the test target can assert on it. Update `createBackup` (line 229) to stamp `modelVersion: Self.currentModelVersion`.

**Verify**: build command → no errors. `grep -n '"v7"' Tenra/Services/Utilities/CloudBackupService.swift` → no matches.

### Step 2: Replace the string-equality restore gate with a store-metadata compatibility check

In `restoreBackup(_:)`:

1. **Delete** the guard at lines 307–310 (`metadata.modelVersion == Self.currentModelVersion`). Rationale (inline a comment): existing backups are stamped "v7" regardless of actual schema; the JSON label is unreliable, the store file's metadata is the truth.
2. Inside the existing `Task.detached` block (lines 345–353), after the `ensureDownloaded` calls and the `fileExists` guard, **before** `try stack.swapStore(from: sourceURL)`, add the real check:

```swift
// Compatibility gate: read the backup store's own CoreData metadata.
// - Directly compatible with the current model → restore as-is.
// - Openable by an older bundled model version → swapStore re-adds the store
//   with automatic lightweight migration options, so restore is safe.
// - Neither (e.g. backup made by a NEWER app version) → reject.
let storeMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
    type: .sqlite, at: sourceURL
)
let currentModel = stack.persistentContainer.managedObjectModel
if !currentModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: storeMetadata) {
    guard NSManagedObjectModel.mergedModel(from: [.main], forStoreMetadata: storeMetadata) != nil else {
        throw CoreDataStack.CloudBackupError.incompatibleVersion(metadata.modelVersion)
    }
}
```

Notes: `metadataForPersistentStore(type:at:)` is the modern API; if the compiler rejects it on this SDK, fall back to `metadataForPersistentStore(ofType: NSSQLiteStoreType, at: sourceURL, options: nil)`. `mergedModel(from:forStoreMetadata:)` returns the bundled model version whose entity hashes match the store — non-nil means a lightweight-migration source exists.

**Verify**: build → no errors.

### Step 3: Add a test seam for the backups directory

`backupsDirectoryURL()` (line 109) resolves to the real app Documents folder, which would make tests pollute the simulator container. Add an internal override, checked first:

```swift
/// Test seam: when set, backups read/write under this directory instead of
/// Documents/iCloud. Internal so only the module + @testable tests see it.
var backupsRootOverride: URL?
```

In `backupsDirectoryURL()`, return `backupsRootOverride` first if non-nil (after `createDirectoryIfNeeded` on it).

**Verify**: build → no errors.

### Step 4: Write `TenraTests/Services/CloudBackupServiceTests.swift`

`@MainActor @Suite struct CloudBackupServiceTests` (MainActor because it constructs `CoreDataStack`, which is implicitly MainActor-isolated under the project's default-isolation setting). Fixture: build an **on-disk SQLite** `NSPersistentContainer` in a unique temp directory (in-memory stores won't work — `swapStore` and `metadataForPersistentStore` need real files):

```swift
// Pattern: NSPersistentContainer(name: "Tenra") loads the production model;
// point its first description at a temp-dir SQLite URL before loadPersistentStores,
// then wrap with the testing seam CoreDataStack(container:) (CoreDataStack.swift:49)
// and inject into CloudBackupService(coreDataStack:); set backupsRootOverride
// to another temp dir.
```

Tests (each its own `@Test`):

1. **`currentModelVersion` is derived, not stale** — parse the integer out of `CloudBackupService.currentModelVersion` (regex `^v(\d+)$`) and `#expect` it is ≥ 12. Also `#expect` it is not `"unknown"`. (This test fails loudly if the momd lookup breaks, and never needs editing on future schema bumps.)
2. **`createBackup` stamps the derived version** — seed the store with 2–3 `TransactionEntity` rows (mirror the seeding in `TenraTests/CoreDataRoundTripTests.swift`), call `try await service.createBackup(transactionCount: 3, accountCount: 0, categoryCount: 0)`, `#expect(metadata.modelVersion == CloudBackupService.currentModelVersion)`, and `#expect` the backup directory contains `Tenra.sqlite` + `metadata.json`.
3. **Restore round-trip** — create a backup, then mutate the live store (insert one more entity), then `try await service.restoreBackup(metadata)` and `#expect` the store's entity count is back to the backed-up count. (Fetch via the stack's `viewContext` after restore.)
4. **A legacy `"v7"`-stamped backup still restores** — create a backup, rewrite its `metadata.json` on disk with `modelVersion` forced to `"v7"` (decode → mutate via a new `BackupMetadata` value → re-encode), then restore by that metadata and `#expect` success. This pins the critical behavior: the old mislabeled backups in the wild must keep working.
5. **A garbage store file is rejected** — write a backup directory by hand whose `Tenra.sqlite` is random bytes plus a valid `metadata.json`; `#expect(throws:)` that `restoreBackup` throws (either `.incompatibleVersion` or the metadata-read error — assert it throws, not the exact case).

**Verify**: the suite-filter test command → 5 `passed`, `** TEST SUCCEEDED **`.

### Step 5: Fix CLAUDE.md version drift

Change "v8 schema" / "CoreData v8 model" / "CoreData v8" at CLAUDE.md lines 69, 167, 336 to v12. In the "CoreData Schema Bumps" checklist (~line 244), append one item: "5. No backup-version constant to bump — `CloudBackupService.currentModelVersion` derives from the compiled model."

**Verify**: `grep -n "v8" CLAUDE.md` → no schema-related matches (the literal string may legitimately appear nowhere).

### Step 6: Full regression run + commit

**Verify**: full `TenraTests` run → `** TEST SUCCEEDED **`. `git status` shows only in-scope files.

## Test plan

Covered by Step 4 (5 new tests; file `TenraTests/Services/CloudBackupServiceTests.swift`; structural pattern `CoreDataRoundTripTests.swift` for entity seeding, `AccountRepositoryTests.swift` for service-level structure). Verification command in "Commands you will need".

## Done criteria

- [ ] `grep -rn '"v7"' Tenra/Services/Utilities/CloudBackupService.swift` → no matches
- [ ] `grep -n 'metadata.modelVersion == ' Tenra/Services/Utilities/CloudBackupService.swift` → no matches (string gate removed)
- [ ] New suite: 5 tests exist and pass (suite-filter command → `** TEST SUCCEEDED **`)
- [ ] Full `-only-testing:TenraTests` run → `** TEST SUCCEEDED **`
- [ ] `grep -cn "v8" CLAUDE.md` → 0 schema mentions
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts above don't match the live code (drift since `4392be3`).
- `Bundle.main.url(forResource: "Tenra", withExtension: "momd")` returns nil **in the app target at runtime or in hosted tests** — the compiled model may be nested differently (e.g. inside another bundle); report what `Bundle.main` actually contains rather than guessing a path.
- `NSPersistentContainer(name: "Tenra")` in the test target can't find the model — report; do not copy the model into the test bundle.
- Test 3 (round-trip) fails because `swapStore` misbehaves under the test container — that's a real finding about the restore path; report it, do not patch `CoreDataStack.swift`.
- You need to change `BackupMetadata`'s Codable shape for any reason.

## Maintenance notes

- Future schema bumps (v13+) now require **no** backup-code changes; the gate reads store files. A reviewer should confirm test 1's `≥ 12` assertion still passes post-bump (it will).
- If a backup is ever made by a *newer* app version and restored on an older one, the gate correctly rejects it with `.incompatibleVersion` — the error string shown to the user comes from `error.backup.incompatibleVersion` localization; consider a friendlier message in a future pass.
- Deferred (out of scope here): `restoreBackup` throws `noActiveStore` for several distinct failure modes (backup dir missing, metadata not found, file missing) — error-case granularity would improve supportability but requires touching `CoreDataStack.CloudBackupError`.
