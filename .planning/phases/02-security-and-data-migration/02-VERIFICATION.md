---
phase: 02-security-and-data-migration
verified: 2026-03-03T00:25:00Z
status: gaps_found
score: 4/5 must-haves verified
gaps:
  - truth: "A CoreData mapping model file exists for the v2 → v3 schema transition and is compiled into the app bundle"
    status: failed
    reason: "The xcmappingmodel source file (contents) exists in the repo but is never compiled by the build system. Two issues: (1) the internal file is named 'contents' but mapc expects 'xcmapping.xml'; (2) the xcmappingmodel bundle is placed inside the xcdatamodeld bundle — Xcode's MappingModelCompile build rule treats xcmappingmodel as a standalone file type and will not find it there. Result: no MappingModelCompile (mapc) step runs at all, and no .cdm file appears in the built app bundle (AIFinanceManager.momd/ has 4 files but no .cdm)."
    artifacts:
      - path: "AIFinanceManager/CoreData/AIFinanceManager.xcdatamodeld/AIFinanceManager_v2_to_v3.xcmappingmodel/contents"
        issue: "File is named 'contents' — mapc expects 'xcmapping.xml'. Running mapc on this bundle crashes with 'The file xcmapping.xml doesn't exist.'"
      - path: "AIFinanceManager/CoreData/AIFinanceManager.xcdatamodeld/AIFinanceManager_v2_to_v3.xcmappingmodel/"
        issue: "Placed inside the .xcdatamodeld bundle. Xcode build system's MappingModelCompile rule only fires for standalone .xcmappingmodel files added to the target, not for ones nested inside .xcdatamodeld."
    missing:
      - "Rename the internal file from 'contents' to 'xcmapping.xml' inside the xcmappingmodel bundle"
      - "Move (or add a standalone copy of) the AIFinanceManager_v2_to_v3.xcmappingmodel directory to alongside the .xcdatamodeld (i.e., AIFinanceManager/CoreData/AIFinanceManager_v2_to_v3.xcmappingmodel/) so the PBXFileSystemSynchronizedRootGroup picks it up as an xcmappingmodel file type and triggers the MappingModelCompile rule"
      - "Verify after fix: a .cdm file appears inside AIFinanceManager.momd/ in the built app bundle"
human_verification:
  - test: "After fixing the mapping model location and filename, launch the app on a simulator that previously had app data from the v2 schema"
    expected: "App launches without crash; existing data is intact"
    why_human: "Cannot simulate an in-place migration from v2 to v3 schema programmatically from the build verifier; requires a real device or simulator with v2 store present"
---

# Phase 2: Security & Data Migration Verification Report

**Phase Goal:** Financial data is protected at rest and validated at entry; a CoreData schema migration model exists so an app update cannot crash existing users
**Verified:** 2026-03-03T00:25:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CoreData SQLite store is created with `NSFileProtectionKey: .complete`; option visible in `CoreDataStack.swift` | VERIFIED | `CoreDataStack.swift` line 119: `description?.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)` |
| 2 | The `resetAllData()` path restores file protection on store re-addition | VERIFIED | `CoreDataStack.swift` line 269: `NSPersistentStoreFileProtectionKey: FileProtectionType.complete` in options dict passed to `coordinator.addPersistentStore` |
| 3 | `AmountFormatter.validate()` returns false for amounts above 999,999,999.99 | VERIFIED | `AmountFormatter.swift` lines 112-117: `static func validate(_ amount: Decimal) -> Bool` with `let max = Decimal(string: "999999999.99")!; return amount > 0 && amount <= max` |
| 4 | `AddTransactionCoordinator.validate()` rejects amounts exceeding the upper bound | VERIFIED | `AddTransactionCoordinator.swift` lines 261-262: `guard AmountFormatter.validate(decimalAmount) else { errors.append(.amountExceedsMaximum)` |
| 5 | A CoreData mapping model for v2 → v3 is compiled into the app bundle so upgrading users do not crash | FAILED | Source XML exists at correct path but: (a) internal file named `contents` instead of `xcmapping.xml`; (b) bundle nested inside `.xcdatamodeld` so `MappingModelCompile` (mapc) build rule never fires; no `.cdm` file in built `AIFinanceManager.momd/` bundle |

**Score:** 4/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AIFinanceManager/CoreData/CoreDataStack.swift` | Persistent store description with `NSPersistentStoreFileProtectionKey` | VERIFIED | 2 occurrences: line 119 (container) + line 269 (resetAllData) |
| `AIFinanceManager/Utils/AmountFormatter.swift` | `static func validate(_:)` checking upper bound `999_999_999.99` | VERIFIED | Lines 112-117; substantive implementation, not stub |
| `AIFinanceManager/Views/Transactions/AddTransactionCoordinator.swift` | Upper-bound guard calling `AmountFormatter.validate()` with `.amountExceedsMaximum` error | VERIFIED | Lines 261-262; wired to `ValidationError` enum in `TransactionFormServiceProtocol.swift` |
| `AIFinanceManager/Protocols/TransactionFormServiceProtocol.swift` | `ValidationError.amountExceedsMaximum` case with user-visible string | VERIFIED | Lines 29 + 40-44; localised string "Amount cannot exceed 999,999,999.99" |
| `AIFinanceManager/CoreData/AIFinanceManager.xcdatamodeld/AIFinanceManager_v2_to_v3.xcmappingmodel/contents` | Explicit CoreData mapping model v2 → v3 (XML, 11 entities) | STUB | File exists with correct XML content (11 entities, correct source/destination names, dateSectionKey expression) BUT: wrong internal filename (`contents` vs `xcmapping.xml`) AND wrong placement inside `.xcdatamodeld` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `CoreDataStack.persistentContainer` | `NSPersistentStoreDescription` | `setOption(FileProtectionType.complete, forKey: NSPersistentStoreFileProtectionKey)` | WIRED | Confirmed at line 119 |
| `CoreDataStack.resetAllData()` | `coordinator.addPersistentStore` | options dict with `NSPersistentStoreFileProtectionKey` | WIRED | Confirmed at lines 268-271 |
| `AddTransactionCoordinator.validate()` | `AmountFormatter.validate()` | `guard AmountFormatter.validate(decimalAmount)` | WIRED | Confirmed at line 261 |
| `AddTransactionCoordinator.validate()` | `ValidationError.amountExceedsMaximum` | `errors.append(.amountExceedsMaximum)` | WIRED | Confirmed at line 262 |
| `CoreDataStack.persistentContainer` | `AIFinanceManager_v2_to_v3.xcmappingmodel` | `NSMigratePersistentStoresAutomaticallyOption + NSInferMappingModelAutomaticallyOption` | NOT_WIRED | Migration flags present (lines 123-124) but the `.cdm` file is absent from the app bundle — `momc` does not compile `.xcmappingmodel` bundles nested inside `.xcdatamodeld`; the `MappingModelCompile` (mapc) step never runs |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SEC-01 | 02-01-PLAN.md | Enable `NSFileProtectionComplete` for CoreData SQLite store | SATISFIED | `CoreDataStack.swift` both creation and reset paths have the key set |
| SEC-02 | 02-02-PLAN.md | Upper-bound validation (≤ 999,999,999.99) in `AmountInputView`; `AmountFormatter.validate()` called before store write | SATISFIED | `AmountFormatter.validate()` implemented and called in `AddTransactionCoordinator.validate(accounts:)` before store write |
| DATA-01 | 02-03-PLAN.md | Explicit CoreData migration mapping model for deprecated aggregate entities; prevent crash on update | BLOCKED | Mapping model source XML exists and is structurally correct, but is not compiled into the app bundle due to wrong internal filename and wrong placement. No `.cdm` appears in `AIFinanceManager.momd/`. Migration cannot be triggered. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `AIFinanceManager.xcdatamodeld/AIFinanceManager_v2_to_v3.xcmappingmodel/contents` | 1 | Wrong filename — `contents` instead of `xcmapping.xml` | Blocker | `mapc` crashes with "file doesn't exist" when targeting this bundle; mapping model is never compiled |
| (placement) | - | `.xcmappingmodel` nested inside `.xcdatamodeld` bundle | Blocker | Xcode `MappingModelCompile` rule fires only for standalone `.xcmappingmodel` files added to the target; nesting inside `.xcdatamodeld` causes the build rule to be silently skipped |

### Human Verification Required

#### 1. Schema Migration on Existing Data

**Test:** Install the current app on a simulator that has existing data from the v2 schema (or export a v2-era SQLite file, copy it to the app container, and launch the updated app)
**Expected:** App launches without crash; CoreData migration succeeds; all existing transactions, accounts, and categories are visible
**Why human:** Cannot simulate an in-place migration from a previous schema version programmatically from this verifier; requires a real device or simulator with a v2 store present before verifying the migration path

### Gaps Summary

SEC-01 and SEC-02 are fully achieved. The CoreData store is protected at rest and amount validation is enforced end-to-end.

DATA-01 has a structural issue in the implementation of the mapping model. The source XML exists with the correct content (11 entity mappings, correct source `AIFinanceManager v2` and destination `AIFinanceManager v3`, `dateSectionKey` expression), but two defects prevent it from being compiled into the app:

1. **Wrong internal filename**: The file inside the `.xcmappingmodel` bundle is named `contents`. Xcode's `mapc` tool (which compiles `.xcmappingmodel` to `.cdm`) expects the file to be named `xcmapping.xml`. Running `mapc` on the current bundle crashes with "The file xcmapping.xml doesn't exist."

2. **Wrong placement**: The `.xcmappingmodel` is placed inside the `.xcdatamodeld` bundle (`AIFinanceManager.xcdatamodeld/AIFinanceManager_v2_to_v3.xcmappingmodel/`). Xcode's build system handles `xcmappingmodel` via a separate `MappingModelCompile` build rule that only fires for standalone `.xcmappingmodel` files added to the app target. `momc` (which compiles `.xcdatamodeld`) does not process nested `.xcmappingmodel` files. Because the project uses `PBXFileSystemSynchronizedRootGroup`, a standalone `.xcmappingmodel` placed at `AIFinanceManager/CoreData/AIFinanceManager_v2_to_v3.xcmappingmodel/` (alongside the `.xcdatamodeld`, not inside it) would be automatically picked up and compiled via `mapc`.

The consequence: no `MappingModelCompile` step runs during the build, no `.cdm` file is produced, and the app bundle's `AIFinanceManager.momd/` contains only the four expected files (`AIFinanceManager.mom`, `AIFinanceManager v2.mom`, `AIFinanceManager v3.mom`, `VersionInfo.plist`) with no mapping model. If a user upgrades from an app build with a v2 schema store, CoreData will fall back to inferred lightweight migration (which may succeed for this trivial change), but the explicit deterministic mapping model the plan intended is not in effect.

The fix requires two changes: (a) rename the internal file from `contents` to `xcmapping.xml`, and (b) move the `.xcmappingmodel` bundle to a standalone location at `AIFinanceManager/CoreData/` (alongside `.xcdatamodeld`, not nested inside it). After this fix, the clean build should show a `MappingModelCompile` step and a `.cdm` file should appear inside `AIFinanceManager.momd/`.

---

_Verified: 2026-03-03T00:25:00Z_
_Verifier: Claude (gsd-verifier)_
