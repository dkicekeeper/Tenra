# CSV Import Migration Guide

> **Version:** 3.0 (2026-02-03)
> **From:** CSVImportService (deprecated)
> **To:** CSVImportCoordinator (new architecture)

---

## Overview

CSV Import был полностью рефакторирован из монолитного сервиса (784 LOC) в модульную архитектуру с 6 специализированными сервисами.

### Why Migrate?

**Old Architecture (CSVImportService):**
- ❌ Монолитная функция 784 LOC
- ❌ Нарушение SRP
- ❌ Unbounded memory usage
- ❌ Hardcoded strings
- ❌ Tight coupling
- ❌ Untestable static methods

**New Architecture (CSVImportCoordinator):**
- ✅ 6 специализированных сервисов
- ✅ Single Responsibility Principle
- ✅ LRU eviction (bounded memory)
- ✅ 100% локализация
- ✅ Protocol-Oriented Design
- ✅ Testable with DI

---

## Quick Migration

### Before (Deprecated)

```swift
let result = await CSVImportService.importTransactions(
    csvFile: csvFile,
    columnMapping: columnMapping,
    entityMapping: entityMapping,
    transactionsViewModel: transactionsViewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel,
    progressCallback: { progress in
        importProgress = progress
    }
)

// result is ImportResult (old model)
print("Imported: \(result.importedCount)")
```

### After (New)

```swift
// 1. Create coordinator using factory
let coordinator = CSVImportCoordinator.create(for: csvFile)

// 2. Create progress tracker
let progress = ImportProgress()
progress.totalRows = csvFile.rowCount

// 3. Import
let statistics = await coordinator.importTransactions(
    csvFile: csvFile,
    columnMapping: columnMapping,
    entityMapping: entityMapping,
    transactionsViewModel: transactionsViewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel,
    progress: progress
)

// statistics is ImportStatistics (new model with performance metrics)
print("Imported: \(statistics.importedCount)")
print("Duration: \(statistics.duration)s")
print("Speed: \(statistics.rowsPerSecond) rows/s")
```

---

## Detailed Migration Steps

### Step 1: Replace Import Call

**Find:**
```swift
CSVImportService.importTransactions(...)
```

**Replace with:**
```swift
let coordinator = CSVImportCoordinator.create(for: csvFile)
coordinator.importTransactions(...)
```

---

### Step 2: Replace Progress Callback

**Before:**
```swift
progressCallback: { progress in
    importProgress = progress
}
```

**After:**
```swift
let progress = ImportProgress()
progress: progress

// In your view, observe:
@ObservedObject var importProgress: ImportProgress
```

---

### Step 3: Update Result Handling

**Before (ImportResult):**
```swift
struct ImportResult {
    let importedCount: Int
    let skippedCount: Int
    let duplicatesSkipped: Int
    let createdAccounts: Int
    let createdCategories: Int
    let createdSubcategories: Int
    let errors: [String]  // ❌ Just strings
}
```

**After (ImportStatistics):**
```swift
struct ImportStatistics {
    let totalRows: Int
    let importedCount: Int
    let skippedCount: Int
    let duplicatesSkipped: Int
    let createdAccounts: Int
    let createdCategories: Int
    let createdSubcategories: Int

    // ✅ New: Performance metrics
    let duration: TimeInterval
    let rowsPerSecond: Double

    // ✅ New: Structured errors
    let errors: [ValidationError]

    // ✅ New: Computed properties
    var successRate: Double
    var successPercentage: Int
    var hasErrors: Bool
}
```

---

### Step 4: Update Result View

**Before:**
```swift
CSVImportResultView(
    result: result,  // ImportResult
    onDismiss: { dismiss() }
)
```

**After:**
```swift
CSVImportResultView(
    statistics: statistics,  // ImportStatistics
    onDone: { dismiss() },
    onViewErrors: { showErrorsView() }  // Optional
)
```

---

## Complete Example

### Full Old Flow (Deprecated)

```swift
struct ContentView: View {
    @State private var importProgress: Double = 0.0
    @State private var showResult = false
    @State private var importResult: ImportResult?

    func performImport() async {
        let result = await CSVImportService.importTransactions(
            csvFile: csvFile,
            columnMapping: columnMapping,
            entityMapping: entityMapping,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            progressCallback: { progress in
                Task { @MainActor in
                    importProgress = progress
                }
            }
        )

        importResult = result
        showResult = true
    }
}
```

### Full New Flow

```swift
struct ContentView: View {
    @StateObject private var importProgress = ImportProgress()
    @State private var showResult = false
    @State private var importStatistics: ImportStatistics?

    func performImport() async {
        // Create coordinator
        let coordinator = CSVImportCoordinator.create(for: csvFile)

        // Setup progress
        importProgress.totalRows = csvFile.rowCount

        // Import
        let statistics = await coordinator.importTransactions(
            csvFile: csvFile,
            columnMapping: columnMapping,
            entityMapping: entityMapping,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            progress: importProgress
        )

        importStatistics = statistics
        showResult = true
    }
}
```

---

## API Mapping

### Old API → New API

| Old | New | Notes |
|-----|-----|-------|
| `CSVImportService.importTransactions()` | `CSVImportCoordinator.importTransactions()` | Static → Instance method |
| `progressCallback: (Double) -> Void` | `progress: ImportProgress` | Observable object |
| `ImportResult` | `ImportStatistics` | Richer metrics |
| `errors: [String]` | `errors: [ValidationError]` | Structured errors |
| N/A | `duration: TimeInterval` | New metric |
| N/A | `rowsPerSecond: Double` | New metric |
| N/A | `successRate: Double` | New computed property |

---

## Breaking Changes

### 1. Result Type Changed

**Impact:** Medium

`ImportResult` → `ImportStatistics`

**Migration:**
- Update result variable types
- Update CSVImportResultView usage
- Access new performance metrics if needed

---

### 2. Progress Callback → Progress Object

**Impact:** Low

`progressCallback: (Double) -> Void` → `progress: ImportProgress`

**Migration:**
- Replace callback with `@StateObject var importProgress`
- Use `importProgress.progress` for Double value
- Cancellation support via `importProgress.cancel()`

---

### 3. Errors Type Changed

**Impact:** Low

`errors: [String]` → `errors: [ValidationError]`

**Migration:**
- Use `error.localizedDescription` for display
- Access `error.rowIndex`, `error.code`, `error.context` for details

---

## Advanced Usage

### Custom Cache Capacity

```swift
// Default capacity: 1000
let coordinator = CSVImportCoordinator.create(for: csvFile)

// Custom capacity for very large imports
let coordinator = CSVImportCoordinator.create(
    for: csvFile,
    cacheCapacity: 5000
)
```

---

### Manual Dependency Injection (Testing)

```swift
// For tests: inject mocks
let coordinator = CSVImportCoordinator(
    parser: MockCSVParsingService(),
    validator: MockCSVValidationService(headers: csvFile.headers),
    mapper: MockEntityMappingService(cache: ImportCacheManager()),
    converter: MockTransactionConverterService(),
    storage: MockCSVStorageCoordinator(),
    cache: ImportCacheManager()
)
```

---

### Progress Cancellation

```swift
// Setup progress
let progress = ImportProgress()

// Start import
Task {
    let statistics = await coordinator.importTransactions(
        ...,
        progress: progress
    )
}

// Cancel from UI
Button("Cancel") {
    progress.cancel()
}
```

---

## Benefits of New Architecture

### 1. Performance

- ✅ LRU eviction (bounded memory)
- ✅ O(1) entity lookups (was O(n))
- ✅ Parallel validation ready (Phase 5)
- ✅ Batch processing optimized

### 2. Maintainability

- ✅ 6 focused services vs 1 monolith
- ✅ Single Responsibility Principle
- ✅ Clear separation of concerns
- ✅ Reusable components

### 3. Testability

- ✅ Protocol-oriented design
- ✅ Dependency injection
- ✅ Mockable interfaces
- ✅ Independent testing

### 4. Localization

- ✅ 64 localization keys
- ✅ Structured error messages
- ✅ User-friendly descriptions

### 5. Features

- ✅ Progress tracking
- ✅ Cancellation support
- ✅ Performance metrics
- ✅ Rich statistics

---

## Rollback Plan

If you need to rollback to old implementation temporarily:

1. Remove `@available(*, deprecated)` from `CSVImportService`
2. Use old API (will continue working alongside new)
3. File bug report with details

**Note:** Old implementation will be removed in future version.

---

## Checklist

Use this checklist for migration:

- [ ] Replace `CSVImportService.importTransactions()` calls
- [ ] Replace `progressCallback` with `ImportProgress`
- [ ] Update `ImportResult` → `ImportStatistics`
- [ ] Update `CSVImportResultView` usage
- [ ] Test full import flow
- [ ] Test progress updates
- [ ] Test cancellation
- [ ] Test error display
- [ ] Remove deprecated warnings

---

## Support

**Issues:** See `docs/csv-import-refactoring-status.md` for current status

**Documentation:**
- Architecture: `docs/project-bible.md` (Section 13)
- Full Plan: `docs/csv-import-full-refactoring-plan.md`
- Phase Reports: `docs/CSV_IMPORT_REFACTORING_PHASE*.md`

---

**Migration Guide v1.0**
**Updated:** 2026-02-03
