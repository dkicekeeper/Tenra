# Settings Refactoring Phase 2 — PARTIAL COMPLETE ⚠️

> **Date:** 2026-02-04
> **Status:** Phase 2 Infrastructure Complete, SettingsView Update Pending
> **Next:** Complete SettingsView migration & delete CSVImportService

---

## Executive Summary

✅ **Phase 2 Infrastructure: 90% Complete**

Создана полная инфраструктура для CSV импорта через новый модульный CSVImportCoordinator. Архитектура готова, осталось только обновить SettingsView для использования нового флоу.

---

## What Was Completed

### 1. CSVImportCoordinatorProtocol (NEW)

```swift
// Protocols/Settings/CSVImportCoordinatorProtocol.swift (50 LOC)
protocol CSVImportCoordinatorProtocol {
    @MainActor
    func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel?,
        progress: ImportProgress
    ) async -> ImportStatistics
}

class ImportProgress: ObservableObject {
    @Published var currentRow: Int
    @Published var totalRows: Int
    @Published var isCancelled: Bool

    var percentage: Double { ... }
    func cancel()
}
```

**Benefits:**
- ✅ Protocol for testability
- ✅ Progress tracking
- ✅ Cancellation support

### 2. ImportFlowCoordinator (NEW — 180 LOC)

```swift
// Services/Settings/ImportFlowCoordinator.swift
@MainActor
final class ImportFlowCoordinator: ObservableObject {
    @Published var currentStep: ImportStep
    @Published var csvFile: CSVFile?
    @Published var columnMapping: CSVColumnMapping?
    @Published var entityMapping: EntityMapping
    @Published var importProgress: ImportProgress?
    @Published var importResult: ImportStatistics?

    enum ImportStep {
        case idle
        case selectingFile
        case preview
        case columnMapping
        case entityMapping
        case importing
        case result
        case error(String)
    }

    // Creates CSVImportCoordinator lazily via factory
    func startImport(from url: URL) async
    func continueToColumnMapping()
    func continueToEntityMapping(with mapping: CSVColumnMapping)
    func performImport() async
    func cancel()
    func reset()
}
```

**Key Features:**
- ✅ State machine for import flow
- ✅ Lazy creation of CSVImportCoordinator (via factory)
- ✅ Progress tracking
- ✅ Error handling
- ✅ Cancellation support

**Architecture Decision:**
CSVImportCoordinator requires csvFile headers during initialization, so ImportFlowCoordinator creates it lazily in `startImport()` using the factory pattern:

```swift
// importCoordinator = CSVImportCoordinator.create(for: file)
```

### 3. SettingsViewModel Enhanced (+ Import Support)

```swift
// SettingsViewModel.swift
@MainActor
final class SettingsViewModel: ObservableObject {
    // NEW: Import Flow State
    @Published var importFlowCoordinator: ImportFlowCoordinator?

    // NEW: Import dependencies
    private let importCoordinator: CSVImportCoordinatorProtocol?
    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var categoriesViewModel: CategoriesViewModel?
    private weak var accountsViewModel: AccountsViewModel?

    // NEW: Import methods
    func startImportFlow(from url: URL) async
    func cancelImportFlow()
}
```

**Changes:**
- ✅ Import coordinator injection (optional, created lazily)
- ✅ ViewModel references (weak to prevent retain cycles)
- ✅ Import flow management methods

### 4. AppCoordinator Integration

```swift
// AppCoordinator.swift (Phase 2 changes)
// CSVImportCoordinator created lazily in ImportFlowCoordinator
let csvImportCoordinator: CSVImportCoordinatorProtocol? = nil

self.settingsViewModel = SettingsViewModel(
    storageService: storageService,
    wallpaperService: wallpaperService,
    resetCoordinator: dataResetCoordinator,
    validationService: validationService,
    exportCoordinator: exportCoordinator,
    importCoordinator: csvImportCoordinator,  // nil - created lazily
    transactionsViewModel: transactionsViewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel,
    initialSettings: transactionsViewModel.appSettings
)
```

**Rationale:**
- CSVImportCoordinator needs csvFile headers
- Factory creates it when file is parsed
- Cleaner initialization in AppCoordinator

### 5. Localization (+4 keys)

```
// English
error.import.coordinatorNotAvailable = "Import coordinator not available"
error.import.viewModelsNotAvailable = "Required view models not available"

// Russian
error.import.coordinatorNotAvailable = "Координатор импорта недоступен"
error.import.viewModelsNotAvailable = "Требуемые ViewModels недоступны"
```

---

## What's NOT Done (Remaining Work)

### ❌ SettingsView Migration (PENDING)

**Current State (DEPRECATED):**
```swift
// SettingsView.swift:297
let result = await CSVImportService.importTransactions(
    csvFile: csvFile,
    columnMapping: mapping,
    entityMapping: EntityMapping(),
    transactionsViewModel: transactionsViewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel
)
```

**Target State (TODO):**
```swift
// Use SettingsViewModel.startImportFlow() instead
await settingsViewModel.startImportFlow(from: url)

// Then show sheets based on importFlowCoordinator.currentStep
.sheet(isPresented: Binding(
    get: { settingsViewModel.importFlowCoordinator?.currentStep == .preview },
    set: { ... }
)) {
    CSVPreviewView(
        csvFile: settingsViewModel.importFlowCoordinator?.csvFile,
        onContinue: {
            settingsViewModel.importFlowCoordinator?.continueToColumnMapping()
        },
        onCancel: {
            settingsViewModel.cancelImportFlow()
        }
    )
}

// Similar sheets for .columnMapping, .importing, .result steps
```

### ❌ CSVImportService Deletion (PENDING)

**File to Delete:**
- `Services/CSVImportService.swift` (799 LOC)

**Usages:**
- SettingsView.swift:297 (only usage)
- Comment references in AppCoordinator, CSVImportCoordinator

**After SettingsView migration:**
```bash
rm Tenra/Services/CSVImportService.swift
# Update comment references to mention "replaced by CSVImportCoordinator"
```

---

## Metrics

### Code Added (Phase 2)

| Component | LOC | Purpose |
|-----------|-----|---------|
| CSVImportCoordinatorProtocol | 50 | Protocol + ImportProgress |
| ImportFlowCoordinator | 180 | State management |
| SettingsViewModel (changes) | +30 | Import support |
| AppCoordinator (changes) | +5 | DI changes |
| Localization | 4 strings | Import errors |
| **Total New Code** | **269 LOC** | **Infrastructure** |

### Code to be Removed

| Component | LOC | Status |
|-----------|-----|--------|
| CSVImportService.swift | 799 | ⏳ Pending deletion |
| SettingsView CSV logic | ~100 | ⏳ Pending refactor |
| **Total Removal** | **~899 LOC** | **Net: -630 LOC** |

---

## Architecture

### Import Flow (NEW)

```
SettingsView
  ↓ (user selects CSV file)
SettingsViewModel.startImportFlow(url)
  ↓ (creates)
ImportFlowCoordinator
  ↓ (parses file)
CSVImporter.parseCSV()
  ↓ (creates via factory)
CSVImportCoordinator.create(for: csvFile)
  ↓ (state machine)
.preview → .columnMapping → .entityMapping → .importing → .result
  ↓ (import)
CSVImportCoordinator.importTransactions(...)
  ↓ (delegates to)
CSVParsingService, CSVValidationService, EntityMappingService, etc.
```

### Benefits of New Architecture

✅ **Modular** — each service has single responsibility
✅ **Testable** — all services implement protocols
✅ **Stateful** — ImportFlowCoordinator manages flow state
✅ **Lazy** — CSVImportCoordinator created when needed
✅ **Progress** — ImportProgress tracks current row
✅ **Cancellable** — user can cancel import
✅ **Clean** — no 799 LOC monolith

---

## Files Created/Modified

```
✨ NEW FILES (2):
  Protocols/Settings/CSVImportCoordinatorProtocol.swift
  Services/Settings/ImportFlowCoordinator.swift

📝 MODIFIED FILES (4):
  ViewModels/SettingsViewModel.swift (+30 LOC)
  ViewModels/AppCoordinator.swift (+5 LOC)
  en.lproj/Localizable.strings (+2 keys)
  ru.lproj/Localizable.strings (+2 keys)

⏳ PENDING CHANGES:
  Views/Settings/SettingsView.swift (refactor CSV import)

🗑️ TO DELETE:
  Services/CSVImportService.swift (799 LOC)
```

---

## Remaining Tasks

### Task 1: Update SettingsView (~30 min)

**Steps:**
1. Remove `performImport()` method
2. Remove `handleCSVImport()` method
3. Replace DocumentPicker logic with `settingsViewModel.startImportFlow()`
4. Add sheets for import flow steps:
   - `.preview` → CSVPreviewView
   - `.columnMapping` → CSVColumnMappingView
   - `.importing` → ProgressView
   - `.result` → CSVImportResultView
5. Bind sheets to `settingsViewModel.importFlowCoordinator?.currentStep`

**Example:**
```swift
.sheet(isPresented: Binding(
    get: {
        if case .preview = settingsViewModel.importFlowCoordinator?.currentStep {
            return true
        }
        return false
    },
    set: { if !$0 { settingsViewModel.cancelImportFlow() } }
)) {
    if let flowCoordinator = settingsViewModel.importFlowCoordinator,
       let csvFile = flowCoordinator.csvFile {
        CSVPreviewView(
            csvFile: csvFile,
            onContinue: {
                flowCoordinator.continueToColumnMapping()
            },
            onCancel: {
                settingsViewModel.cancelImportFlow()
            }
        )
    }
}
```

### Task 2: Delete CSVImportService (~5 min)

```bash
rm Tenra/Services/CSVImportService.swift

# Update comments referencing CSVImportService
# - AppCoordinator.swift
# - CSVImportCoordinator.swift
```

### Task 3: Test Import Flow (~15 min)

**Manual Test:**
1. Settings → Import Data
2. Select CSV file → shows preview
3. Continue → column mapping
4. Continue → entity mapping (if needed)
5. Import → shows progress
6. Complete → shows results
7. Verify transactions imported correctly

**Edge Cases:**
- Cancel during preview
- Cancel during import
- Import with errors
- Import with no data

---

## Known Issues

### ⚠️ ImportFlowCoordinator requires SettingsView changes

ImportFlowCoordinator is ready but SettingsView still uses old `performImport()` method. Need to refactor SettingsView to use the new flow.

### ⚠️ CSVImportService still in codebase

799 LOC deprecated file will be deleted after SettingsView migration completes.

---

## Success Criteria (Phase 2)

| Criterion | Target | Current | Status |
|-----------|--------|---------|--------|
| ImportFlowCoordinator Created | Yes | Yes | ✅ |
| SettingsViewModel Enhanced | Yes | Yes | ✅ |
| AppCoordinator Updated | Yes | Yes | ✅ |
| Localization Added | 4 keys | 4 keys | ✅ |
| SettingsView Migrated | Yes | No | ❌ |
| CSVImportService Deleted | Yes | No | ❌ |
| End-to-end Test | Pass | — | ⏳ |

**Phase 2: 70% Complete** ⚠️

---

## Recommendations

### Priority 1: Complete SettingsView Migration

**Estimated time:** 30-45 minutes

This is the critical blocker. Once SettingsView uses the new flow, we can:
1. Delete CSVImportService (-799 LOC)
2. Test end-to-end import
3. Move to Phase 3 (UI Refactoring)

### Priority 2: Test Thoroughly

After migration, test:
- CSV preview
- Column mapping
- Entity mapping
- Import progress
- Error handling
- Cancellation

### Priority 3: Update Documentation

After completion, update:
- project-bible.md (CSV import architecture)
- component-inventory.md (new components)

---

## Conclusion

**Phase 2: 70% Complete — Infrastructure Ready**

**Completed:**
- ✅ CSVImportCoordinatorProtocol
- ✅ ImportFlowCoordinator (180 LOC)
- ✅ SettingsViewModel import support
- ✅ AppCoordinator integration
- ✅ Localization (4 keys)

**Remaining:**
- ❌ SettingsView migration (30-45 min)
- ❌ CSVImportService deletion (5 min)
- ❌ End-to-end testing (15 min)

**Total Remaining Time:** ~1 hour

**Next:** Complete SettingsView migration to unlock CSVImportService deletion (-799 LOC)

---

**End of Phase 2 Partial Report**
**Status:** ⚠️ 70% Complete, Ready to Finish
**Date:** 2026-02-04
