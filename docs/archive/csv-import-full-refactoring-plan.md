# CSV Import Full Refactoring Plan
## Глубокий анализ и план полного rebuild

> **Дата создания:** 2026-02-03
> **Версия:** 1.0
> **Статус:** Ready for Implementation
> **Scope:** Full Rebuild с применением SRP, LRU eviction, оптимизации, локализации

---

## Executive Summary

### Текущее состояние CSV импорта

**Метрики:**
- **CSVImportService.swift:** 784 LOC — монолитная функция `importTransactions()`
- **CSV Views:** 1,084 LOC — 4 view файла с дублированием
- **Models:** 80 LOC — минимальная структура
- **CSVImporter.swift:** 162 LOC — парсинг с хардкодами

**Проблемы:** ❌
1. ❌ **Монолитная функция** — 784 строки в одном методе
2. ❌ **Нарушение SRP** — парсинг, валидация, создание сущностей, сохранение — всё в одном месте
3. ❌ **Hardcoded strings** — "Другое", "Перевод", error messages без локализации
4. ❌ **Отсутствие LRU eviction** — unbounded кэши для created accounts/categories
5. ❌ **Дублирование логики** — account lookup повторяется 3 раза
6. ❌ **Слабая производительность** — O(n) поиски, нет pre-allocation
7. ❌ **Отсутствие тестируемости** — статические методы, tight coupling
8. ❌ **Неоптимальная обработка ошибок** — массив строк вместо structured errors
9. ❌ **UI дублирование** — account/category mapping views с одинаковой структурой
10. ❌ **Отсутствие progress tracking** — только callback, нет cancellation

### Целевое состояние

**Архитектура:** ✅
```
┌─────────────────────────────────────────────────────────┐
│  CSV Import Architecture (Post-Refactoring)             │
│                                                          │
│  CSVImportCoordinator (Single Entry Point)              │
│    ├── parser: CSVParsingService                        │
│    ├── validator: CSVValidationService                  │
│    ├── mapper: EntityMappingService                     │
│    ├── converter: TransactionConverterService           │
│    ├── storage: CSVStorageCoordinator                   │
│    └── cache: ImportCacheManager (LRU)                  │
│                                                          │
│  Services Layer:                                         │
│    ├── CSVParsingService (file → CSVFile)               │
│    ├── CSVValidationService (row validation)            │
│    ├── EntityMappingService (account/category lookup)   │
│    ├── TransactionConverterService (row → Transaction)  │
│    ├── CSVStorageCoordinator (batch save + balance)     │
│    └── ImportCacheManager (LRU для lookup)              │
│                                                          │
│  Models Layer:                                           │
│    ├── CSVRow (parsed row DTO)                          │
│    ├── ValidationError (structured errors)              │
│    ├── ImportProgress (progress + cancellation)         │
│    └── ImportStatistics (comprehensive result)          │
│                                                          │
│  UI Layer (Props + Callbacks):                          │
│    ├── CSVPreviewView (refactored)                      │
│    ├── CSVColumnMappingView (refactored)                │
│    ├── CSVEntityMappingView (refactored)                │
│    └── CSVImportResultView (refactored)                 │
└─────────────────────────────────────────────────────────┘
```

**Метрики (целевые):**
- ✅ **CSVImportCoordinator:** ~200 LOC (orchestration only)
- ✅ **Services:** 6 сервисов × ~150 LOC avg = ~900 LOC (reusable)
- ✅ **Models:** ~200 LOC (structured DTOs)
- ✅ **Views:** ~800 LOC (Props + Callbacks, -26%)
- ✅ **Protocols:** 6 protocols для testability
- ✅ **100% локализация:** все hardcoded strings → localization keys
- ✅ **LRU caching:** automatic eviction для lookup caches
- ✅ **Performance:** O(1) lookups, pre-allocation, streaming

---

## Фаза 1: Архитектурный фундамент

### 1.1 Создание Protocols

**Цель:** Testability + Dependency Injection

#### Protocol 1: CSVParsingServiceProtocol
```swift
@MainActor
protocol CSVParsingServiceProtocol {
    /// Парсит CSV файл из URL
    func parseFile(from url: URL) async throws -> CSVFile

    /// Парсит CSV контент из строки
    func parseContent(_ content: String) async throws -> CSVFile
}
```

**Создать:** `Protocols/CSVParsingServiceProtocol.swift` (~30 LOC)

---

#### Protocol 2: CSVValidationServiceProtocol
```swift
@MainActor
protocol CSVValidationServiceProtocol {
    /// Валидирует одну строку CSV
    func validateRow(
        _ row: [String],
        at index: Int,
        mapping: CSVColumnMapping
    ) -> Result<CSVRow, ValidationError>

    /// Валидирует весь файл
    func validateFile(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping
    ) async -> [ValidationResult]
}
```

**Создать:** `Protocols/CSVValidationServiceProtocol.swift` (~40 LOC)

---

#### Protocol 3: EntityMappingServiceProtocol
```swift
@MainActor
protocol EntityMappingServiceProtocol {
    /// Находит или создаёт счёт
    func resolveAccount(
        name: String,
        currency: String,
        mapping: EntityMapping,
        accountsViewModel: AccountsViewModel?
    ) async -> AccountResolutionResult

    /// Находит или создаёт категорию
    func resolveCategory(
        name: String,
        type: TransactionType,
        mapping: EntityMapping,
        categoriesViewModel: CategoriesViewModel
    ) async -> CategoryResolutionResult

    /// Находит или создаёт подкатегорию
    func resolveSubcategories(
        names: [String],
        categoryId: String,
        categoriesViewModel: CategoriesViewModel
    ) async -> [SubcategoryResolutionResult]
}
```

**Создать:** `Protocols/EntityMappingServiceProtocol.swift` (~50 LOC)

---

#### Protocol 4: TransactionConverterServiceProtocol
```swift
@MainActor
protocol TransactionConverterServiceProtocol {
    /// Конвертирует CSV row в Transaction
    func convertRow(
        _ csvRow: CSVRow,
        accountId: String?,
        targetAccountId: String?,
        categoryId: String,
        subcategoryIds: [String],
        rowIndex: Int
    ) -> Transaction
}
```

**Создать:** `Protocols/TransactionConverterServiceProtocol.swift` (~30 LOC)

---

#### Protocol 5: CSVStorageCoordinatorProtocol
```swift
@MainActor
protocol CSVStorageCoordinatorProtocol {
    /// Сохраняет батч транзакций
    func saveBatch(
        _ transactions: [Transaction],
        subcategoryLinks: [String: [String]],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async

    /// Финализирует импорт (balance recalc, cache rebuild)
    func finalizeImport(
        accountsViewModel: AccountsViewModel?,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async
}
```

**Создать:** `Protocols/CSVStorageCoordinatorProtocol.swift` (~40 LOC)

---

#### Protocol 6: CSVImportCoordinatorProtocol
```swift
@MainActor
protocol CSVImportCoordinatorProtocol {
    /// Импортирует транзакции с progress tracking
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
```

**Создать:** `Protocols/CSVImportCoordinatorProtocol.swift` (~40 LOC)

---

### 1.2 Создание Models (Structured DTOs)

**Цель:** Type safety + clear contracts

#### Model 1: CSVRow
```swift
/// Представляет распарсенную и валидированную строку CSV
struct CSVRow {
    let rowIndex: Int
    let date: Date
    let type: TransactionType
    let amount: Double
    let currency: String

    // Account fields
    let rawAccountValue: String
    let rawTargetAccountValue: String?
    let targetCurrency: String?
    let targetAmount: Double?

    // Category fields
    let rawCategoryValue: String
    let subcategoryNames: [String]

    // Optional fields
    let note: String?

    // Computed effective values (based on type rules)
    var effectiveAccountValue: String { /* logic */ }
    var effectiveCategoryValue: String { /* logic */ }
}
```

**Создать:** `Models/CSVRow.swift` (~80 LOC)

---

#### Model 2: ValidationError
```swift
/// Структурированная ошибка валидации
struct ValidationError: LocalizedError {
    let rowIndex: Int
    let column: String?
    let code: ValidationErrorCode
    let context: [String: String]

    var errorDescription: String? {
        // Локализованное описание с интерполяцией context
    }
}

enum ValidationErrorCode: String {
    case missingRequiredColumn
    case invalidDateFormat
    case invalidAmount
    case invalidType
    case emptyValue
    case duplicateTransaction
}
```

**Создать:** `Models/ValidationError.swift` (~60 LOC)

---

#### Model 3: ImportProgress
```swift
/// Progress tracking с cancellation support
@MainActor
class ImportProgress: ObservableObject {
    @Published var currentRow: Int = 0
    @Published var totalRows: Int = 0
    @Published var isCancelled: Bool = false

    var progress: Double {
        guard totalRows > 0 else { return 0.0 }
        return Double(currentRow) / Double(totalRows)
    }

    func cancel() {
        isCancelled = true
    }
}
```

**Создать:** `Models/ImportProgress.swift` (~30 LOC)

---

#### Model 4: ImportStatistics
```swift
/// Comprehensive import result
struct ImportStatistics {
    let totalRows: Int
    let importedCount: Int
    let skippedCount: Int
    let duplicatesSkipped: Int

    // Entity creation stats
    let createdAccounts: Int
    let createdCategories: Int
    let createdSubcategories: Int

    // Performance metrics
    let duration: TimeInterval
    let rowsPerSecond: Double

    // Errors
    let errors: [ValidationError]

    var successRate: Double {
        guard totalRows > 0 else { return 0.0 }
        return Double(importedCount) / Double(totalRows)
    }
}
```

**Создать:** `Models/ImportStatistics.swift` (~50 LOC)

---

### 1.3 Создание ImportCacheManager (LRU)

**Цель:** Bounded memory usage + fast lookups

```swift
/// Manages lookup caches for CSV import with LRU eviction
@MainActor
class ImportCacheManager {
    // LRU caches
    private var accountCache: LRUCache<String, String> // [name.lowercased(): accountId]
    private var categoryCache: LRUCache<String, String> // [name+type: categoryId]
    private var subcategoryCache: LRUCache<String, String> // [name: subcategoryId]

    init(capacity: Int = 1000) {
        self.accountCache = LRUCache(capacity: capacity)
        self.categoryCache = LRUCache(capacity: capacity)
        self.subcategoryCache = LRUCache(capacity: capacity)
    }

    // Account cache operations
    func cacheAccount(name: String, id: String) {
        accountCache.set(name.lowercased(), id)
    }

    func getAccount(name: String) -> String? {
        accountCache.get(name.lowercased())
    }

    // Category cache operations
    func cacheCategory(name: String, type: TransactionType, id: String) {
        let key = "\(name.lowercased())_\(type.rawValue)"
        categoryCache.set(key, id)
    }

    func getCategory(name: String, type: TransactionType) -> String? {
        let key = "\(name.lowercased())_\(type.rawValue)"
        return categoryCache.get(key)
    }

    // Subcategory cache operations
    func cacheSubcategory(name: String, id: String) {
        subcategoryCache.set(name.lowercased(), id)
    }

    func getSubcategory(name: String) -> String? {
        subcategoryCache.get(name.lowercased())
    }

    func clear() {
        accountCache = LRUCache(capacity: accountCache.capacity)
        categoryCache = LRUCache(capacity: categoryCache.capacity)
        subcategoryCache = LRUCache(capacity: subcategoryCache.capacity)
    }
}
```

**Создать:** `Services/CSV/ImportCacheManager.swift` (~120 LOC)

---

### Результаты Phase 1

**Файлы созданы:** 11
- 6 Protocols (~230 LOC)
- 4 Models (~220 LOC)
- 1 Cache Manager (~120 LOC)

**Total новый код:** ~570 LOC (infrastructure)

---

## Фаза 2: Service Layer Implementation

### 2.1 CSVParsingService

**Цель:** Isolate file parsing logic

```swift
/// Сервис для парсинга CSV файлов
@MainActor
class CSVParsingService: CSVParsingServiceProtocol {

    func parseFile(from url: URL) async throws -> CSVFile {
        let content = try await readFile(from: url)
        return try await parseContent(content)
    }

    func parseContent(_ content: String) async throws -> CSVFile {
        // Existing logic from CSVImporter.parseCSVContent
        // + optimizations:
        // - Pre-allocate arrays with reserveCapacity
        // - Streaming для больших файлов (>10K rows)
    }

    private func readFile(from url: URL) async throws -> String {
        // Existing logic from CSVImporter.parseCSV
        // + improved encoding detection
        // + error handling
    }

    private func parseCSVLine(_ line: String) -> [String] {
        // Existing logic from CSVImporter.parseCSVLine
        // (no changes needed - already optimal)
    }

    private func normalizeRow(_ row: [String], expectedColumnCount: Int) -> [String] {
        // Existing logic from CSVImporter.normalizeRow
    }
}
```

**Создать:** `Services/CSV/CSVParsingService.swift` (~180 LOC)

**Оптимизации:**
- ✅ Pre-allocation для массивов
- ✅ Streaming для больших файлов
- ✅ Improved encoding detection

---

### 2.2 CSVValidationService

**Цель:** Separate validation from parsing

```swift
/// Сервис для валидации CSV строк
@MainActor
class CSVValidationService: CSVValidationServiceProtocol {

    func validateRow(
        _ row: [String],
        at index: Int,
        mapping: CSVColumnMapping
    ) -> Result<CSVRow, ValidationError> {

        // Extract required indices
        guard let dateIdx = getIndex(for: mapping.dateColumn, in: mapping),
              let typeIdx = getIndex(for: mapping.typeColumn, in: mapping),
              let amountIdx = getIndex(for: mapping.amountColumn, in: mapping) else {
            return .failure(ValidationError(
                rowIndex: index,
                column: nil,
                code: .missingRequiredColumn,
                context: [:]
            ))
        }

        // Validate date
        guard let dateString = row[safe: dateIdx]?.trimmingCharacters(in: .whitespaces),
              !dateString.isEmpty,
              let date = parseDate(dateString, format: mapping.dateFormat) else {
            return .failure(ValidationError(
                rowIndex: index,
                column: "date",
                code: .invalidDateFormat,
                context: ["value": row[safe: dateIdx] ?? ""]
            ))
        }

        // Validate type
        guard let typeString = row[safe: typeIdx]?.trimmingCharacters(in: .whitespaces),
              !typeString.isEmpty,
              let type = parseType(typeString, mappings: mapping.typeMappings) else {
            return .failure(ValidationError(
                rowIndex: index,
                column: "type",
                code: .invalidType,
                context: ["value": row[safe: typeIdx] ?? ""]
            ))
        }

        // Validate amount
        guard let amountString = row[safe: amountIdx]?.trimmingCharacters(in: .whitespaces),
              !amountString.isEmpty,
              let amount = parseAmount(amountString) else {
            return .failure(ValidationError(
                rowIndex: index,
                column: "amount",
                code: .invalidAmount,
                context: ["value": row[safe: amountIdx] ?? ""]
            ))
        }

        // Extract other fields
        let currency = getCurrency(from: row, mapping: mapping)
        let rawAccountValue = getAccountValue(from: row, mapping: mapping)
        let rawCategoryValue = getCategoryValue(from: row, mapping: mapping)
        let rawTargetAccountValue = getTargetAccountValue(from: row, mapping: mapping)
        let targetCurrency = getTargetCurrency(from: row, mapping: mapping)
        let targetAmount = getTargetAmount(from: row, mapping: mapping)
        let subcategoryNames = getSubcategoryNames(from: row, mapping: mapping)
        let note = getNote(from: row, mapping: mapping)

        // Create validated CSVRow
        let csvRow = CSVRow(
            rowIndex: index,
            date: date,
            type: type,
            amount: amount,
            currency: currency,
            rawAccountValue: rawAccountValue,
            rawTargetAccountValue: rawTargetAccountValue,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount,
            rawCategoryValue: rawCategoryValue,
            subcategoryNames: subcategoryNames,
            note: note
        )

        return .success(csvRow)
    }

    func validateFile(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping
    ) async -> [ValidationResult] {
        // Validate all rows in parallel batches
        // Return structured results
    }

    // Private helper methods for extraction
    private func getCurrency(from row: [String], mapping: CSVColumnMapping) -> String { }
    private func getAccountValue(from row: [String], mapping: CSVColumnMapping) -> String { }
    private func getCategoryValue(from row: [String], mapping: CSVColumnMapping) -> String { }
    // ... etc
}
```

**Создать:** `Services/CSV/CSVValidationService.swift` (~200 LOC)

**Преимущества:**
- ✅ Structured errors вместо String массива
- ✅ Single responsibility (только валидация)
- ✅ Reusable helper methods
- ✅ Type-safe CSVRow DTOs

---

### 2.3 EntityMappingService

**Цель:** Centralize entity resolution logic (biggest duplicate killer)

```swift
/// Сервис для маппинга и создания сущностей (accounts, categories)
@MainActor
class EntityMappingService: EntityMappingServiceProtocol {

    private let cache: ImportCacheManager

    init(cache: ImportCacheManager) {
        self.cache = cache
    }

    // MARK: - Account Resolution

    func resolveAccount(
        name: String,
        currency: String,
        mapping: EntityMapping,
        accountsViewModel: AccountsViewModel?
    ) async -> AccountResolutionResult {

        // Reserved names (never create accounts with these names)
        let reservedNames = [
            String(localized: "category.other").lowercased(),
            "other"
        ]

        let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased()

        guard !normalizedName.isEmpty,
              !reservedNames.contains(normalizedName) else {
            return .skipped
        }

        // Check mapping first
        if let mappedId = mapping.accountMappings[name] {
            cache.cacheAccount(name: name, id: mappedId)
            return .existing(id: mappedId)
        }

        // Check cache
        if let cachedId = cache.getAccount(name: name) {
            return .existing(id: cachedId)
        }

        // Check AccountsViewModel
        if let accountsVM = accountsViewModel,
           let account = accountsVM.accounts.first(where: {
               $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName
           }) {
            cache.cacheAccount(name: name, id: account.id)
            return .existing(id: account.id)
        }

        // Create new account
        guard let accountsVM = accountsViewModel else {
            return .skipped
        }

        accountsVM.addAccount(
            name: name,
            balance: 0.0,
            currency: currency,
            bankLogo: .none
        )

        // Get newly created account ID
        if let newAccount = accountsVM.accounts.first(where: {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normalizedName
        }) {
            cache.cacheAccount(name: name, id: newAccount.id)
            return .created(id: newAccount.id)
        }

        return .skipped
    }

    // MARK: - Category Resolution

    func resolveCategory(
        name: String,
        type: TransactionType,
        mapping: EntityMapping,
        categoriesViewModel: CategoriesViewModel
    ) async -> CategoryResolutionResult {

        // Check mapping first
        if let mappedName = mapping.categoryMappings[name] {
            return await resolveCategoryByName(
                mappedName,
                type: type,
                categoriesViewModel: categoriesViewModel
            )
        }

        // Resolve by actual name
        return await resolveCategoryByName(
            name,
            type: type,
            categoriesViewModel: categoriesViewModel
        )
    }

    private func resolveCategoryByName(
        _ name: String,
        type: TransactionType,
        categoriesViewModel: CategoriesViewModel
    ) async -> CategoryResolutionResult {

        // Check cache
        if let cachedId = cache.getCategory(name: name, type: type) {
            return .existing(id: cachedId, name: name)
        }

        // Check existing categories
        if let existing = categoriesViewModel.customCategories.first(where: {
            $0.name == name && $0.type == type
        }) {
            cache.cacheCategory(name: name, type: type, id: existing.id)
            return .existing(id: existing.id, name: name)
        }

        // Create new category
        let iconName = CategoryIcon.iconName(
            for: name,
            type: type,
            customCategories: categoriesViewModel.customCategories
        )
        let colorHex = CategoryColors.hexColor(
            for: name,
            customCategories: categoriesViewModel.customCategories
        )
        let hexString = colorToHex(colorHex)

        let newCategory = CustomCategory(
            name: name,
            iconName: iconName,
            colorHex: hexString,
            type: type
        )

        var newCategories = categoriesViewModel.customCategories
        newCategories.append(newCategory)
        categoriesViewModel.updateCategories(newCategories)

        cache.cacheCategory(name: name, type: type, id: newCategory.id)
        return .created(id: newCategory.id, name: name)
    }

    // MARK: - Subcategory Resolution

    func resolveSubcategories(
        names: [String],
        categoryId: String,
        categoriesViewModel: CategoriesViewModel
    ) async -> [SubcategoryResolutionResult] {

        var results: [SubcategoryResolutionResult] = []
        results.reserveCapacity(names.count)

        for name in names {
            let result = await resolveSubcategory(
                name: name,
                categoryId: categoryId,
                categoriesViewModel: categoriesViewModel
            )
            results.append(result)
        }

        return results
    }

    private func resolveSubcategory(
        name: String,
        categoryId: String,
        categoriesViewModel: CategoriesViewModel
    ) async -> SubcategoryResolutionResult {

        // Check cache
        if let cachedId = cache.getSubcategory(name: name) {
            // Ensure link exists
            categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(
                subcategoryId: cachedId,
                categoryId: categoryId
            )
            return .existing(id: cachedId)
        }

        // Check existing subcategories
        if let existing = categoriesViewModel.subcategories.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) {
            cache.cacheSubcategory(name: name, id: existing.id)
            categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(
                subcategoryId: existing.id,
                categoryId: categoryId
            )
            return .existing(id: existing.id)
        }

        // Create new subcategory
        let newSubcategory = categoriesViewModel.addSubcategory(name: name)
        cache.cacheSubcategory(name: name, id: newSubcategory.id)
        categoriesViewModel.linkSubcategoryToCategoryWithoutSaving(
            subcategoryId: newSubcategory.id,
            categoryId: categoryId
        )
        return .created(id: newSubcategory.id)
    }

    // MARK: - Helper

    private func colorToHex(_ color: Color) -> String {
        // Existing logic from CSVImportService
    }
}

// MARK: - Resolution Results

enum AccountResolutionResult {
    case existing(id: String)
    case created(id: String)
    case skipped
}

enum CategoryResolutionResult {
    case existing(id: String, name: String)
    case created(id: String, name: String)
}

enum SubcategoryResolutionResult {
    case existing(id: String)
    case created(id: String)
}
```

**Создать:** `Services/CSV/EntityMappingService.swift` (~280 LOC)

**Преимущества:**
- ✅ Устранено дублирование lookup logic (было 3 копии)
- ✅ LRU cache integration (bounded memory)
- ✅ Structured results вместо side effects
- ✅ Single responsibility

---

### 2.4 TransactionConverterService

**Цель:** Convert validated CSV rows to Transactions

```swift
/// Конвертирует валидированные CSV строки в транзакции
@MainActor
class TransactionConverterService: TransactionConverterServiceProtocol {

    func convertRow(
        _ csvRow: CSVRow,
        accountId: String?,
        targetAccountId: String?,
        categoryId: String,
        subcategoryIds: [String],
        rowIndex: Int
    ) -> Transaction {

        let dateFormatter = DateFormatters.dateFormatter
        let dateString = dateFormatter.string(from: csvRow.date)

        // Generate deterministic createdAt (date + row offset)
        let createdAt = csvRow.date.timeIntervalSince1970 + Double(rowIndex) * 0.001

        // Generate transaction ID
        let descriptionForID = csvRow.note?.isEmpty == false
            ? csvRow.note!
            : csvRow.effectiveCategoryValue

        let transactionId = TransactionIDGenerator.generateID(
            date: dateString,
            description: descriptionForID,
            amount: csvRow.amount,
            type: csvRow.type,
            currency: csvRow.currency,
            createdAt: createdAt
        )

        // Resolve account names
        // (simplified - actual resolution happens in coordinator)

        // Create transaction
        return Transaction(
            id: transactionId,
            date: dateString,
            description: csvRow.note ?? "",
            amount: csvRow.amount,
            currency: csvRow.currency,
            convertedAmount: nil,
            type: csvRow.type,
            category: csvRow.effectiveCategoryValue,
            subcategory: subcategoryIds.first.map { _ in csvRow.subcategoryNames.first } ?? nil,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: nil, // Will be set by coordinator
            targetAccountName: nil, // Will be set by coordinator
            targetCurrency: csvRow.targetCurrency,
            targetAmount: csvRow.targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: createdAt
        )
    }
}
```

**Создать:** `Services/CSV/TransactionConverterService.swift` (~120 LOC)

---

### 2.5 CSVStorageCoordinator

**Цель:** Handle batch saves + balance recalculation

```swift
/// Координирует сохранение импортированных данных
@MainActor
class CSVStorageCoordinator: CSVStorageCoordinatorProtocol {

    private let batchSize = 500

    func saveBatch(
        _ transactions: [Transaction],
        subcategoryLinks: [String: [String]],
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async {

        // Add transactions without save
        transactionsViewModel.addTransactionsForImport(transactions)

        // Batch link subcategories
        if !subcategoryLinks.isEmpty {
            categoriesViewModel.batchLinkSubcategoriesToTransaction(subcategoryLinks)
        }

        // Memory cleanup
        autoreleasepool {}
    }

    func finalizeImport(
        accountsViewModel: AccountsViewModel?,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel
    ) async {

        // Sync accounts
        if let accountsVM = accountsViewModel {
            transactionsViewModel.accounts = accountsVM.accounts
        }

        // Sync categories
        transactionsViewModel.subcategories = categoriesViewModel.subcategories
        transactionsViewModel.categorySubcategoryLinks = categoriesViewModel.categorySubcategoryLinks
        transactionsViewModel.transactionSubcategoryLinks = categoriesViewModel.transactionSubcategoryLinks

        // Save all category data
        categoriesViewModel.saveAllData()

        // End batch + recalculate balances
        transactionsViewModel.endBatchWithoutSave()

        // CRITICAL: Sync save for data safety
        transactionsViewModel.saveToStorageSync()

        // Rebuild indexes
        transactionsViewModel.rebuildIndexes()

        // Precompute currency conversions
        transactionsViewModel.precomputeCurrencyConversions()

        // Sync balances back to accounts
        if let accountsVM = accountsViewModel {
            syncBalances(from: transactionsViewModel, to: accountsVM)
            accountsVM.saveAllAccountsSync()

            // Register accounts in BalanceCoordinator
            await registerAccountsInBalanceCoordinator(
                accountsVM,
                transactionsViewModel
            )
        }

        // Rebuild aggregate cache
        await transactionsViewModel.rebuildAggregateCacheAfterImport()

        // Notify UI
        transactionsViewModel.objectWillChange.send()
        categoriesViewModel.objectWillChange.send()
        accountsViewModel?.objectWillChange.send()
    }

    private func syncBalances(
        from transactionsVM: TransactionsViewModel,
        to accountsVM: AccountsViewModel
    ) {
        for (index, account) in accountsVM.accounts.enumerated() {
            if let updatedAccount = transactionsVM.accounts.first(where: { $0.id == account.id }) {
                accountsVM.accounts[index].balance = updatedAccount.balance
            }
        }
    }

    private func registerAccountsInBalanceCoordinator(
        _ accountsVM: AccountsViewModel,
        _ transactionsVM: TransactionsViewModel
    ) async {
        guard let balanceCoordinator = transactionsVM.balanceCoordinator else { return }

        await balanceCoordinator.registerAccounts(accountsVM.accounts)

        for account in accountsVM.accounts {
            let initialBalance = accountsVM.getInitialBalance(for: account.id) ?? account.balance
            await balanceCoordinator.setInitialBalance(initialBalance, for: account.id)
            await balanceCoordinator.markAsManual(account.id)
        }
    }
}
```

**Создать:** `Services/CSV/CSVStorageCoordinator.swift` (~180 LOC)

---

### 2.6 CSVImportCoordinator

**Цель:** Orchestrate entire import flow

```swift
/// Главный координатор CSV импорта
@MainActor
class CSVImportCoordinator: CSVImportCoordinatorProtocol {

    // Dependencies
    private let parser: CSVParsingServiceProtocol
    private let validator: CSVValidationServiceProtocol
    private let mapper: EntityMappingServiceProtocol
    private let converter: TransactionConverterServiceProtocol
    private let storage: CSVStorageCoordinatorProtocol
    private let cache: ImportCacheManager

    init(
        parser: CSVParsingServiceProtocol,
        validator: CSVValidationServiceProtocol,
        mapper: EntityMappingServiceProtocol,
        converter: TransactionConverterServiceProtocol,
        storage: CSVStorageCoordinatorProtocol,
        cache: ImportCacheManager
    ) {
        self.parser = parser
        self.validator = validator
        self.mapper = mapper
        self.converter = converter
        self.storage = storage
        self.cache = cache
    }

    func importTransactions(
        csvFile: CSVFile,
        columnMapping: CSVColumnMapping,
        entityMapping: EntityMapping,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel?,
        progress: ImportProgress
    ) async -> ImportStatistics {

        let startTime = Date()

        // Initialize statistics
        var stats = ImportStatisticsBuilder()
        stats.totalRows = csvFile.rowCount

        // Build fingerprint set for duplicate detection
        let existingFingerprints = Set(
            transactionsViewModel.allTransactions.map { TransactionFingerprint(from: $0) }
        )

        // Begin batch mode
        transactionsViewModel.beginBatch()

        // Process rows in batches
        var transactionsBatch: [Transaction] = []
        var subcategoryLinksBatch: [String: [String]] = [:]

        transactionsBatch.reserveCapacity(500)

        for (rowIndex, row) in csvFile.rows.enumerated() {

            // Check cancellation
            if progress.isCancelled {
                break
            }

            // Update progress
            progress.currentRow = rowIndex + 1

            // Validate row
            let validationResult = validator.validateRow(
                row,
                at: rowIndex,
                mapping: columnMapping
            )

            guard case .success(let csvRow) = validationResult else {
                if case .failure(let error) = validationResult {
                    stats.addError(error)
                }
                stats.incrementSkipped()
                continue
            }

            // Resolve account
            let accountResult = await mapper.resolveAccount(
                name: csvRow.effectiveAccountValue,
                currency: csvRow.currency,
                mapping: entityMapping,
                accountsViewModel: accountsViewModel
            )

            let accountId: String?
            switch accountResult {
            case .existing(let id), .created(let id):
                accountId = id
                if case .created = accountResult {
                    stats.incrementCreatedAccounts()
                }
            case .skipped:
                accountId = nil
            }

            // Resolve target account (for transfers)
            var targetAccountId: String? = nil
            if csvRow.type != .income,
               let targetAccountValue = csvRow.rawTargetAccountValue,
               !targetAccountValue.isEmpty {

                let targetResult = await mapper.resolveAccount(
                    name: targetAccountValue,
                    currency: csvRow.targetCurrency ?? csvRow.currency,
                    mapping: entityMapping,
                    accountsViewModel: accountsViewModel
                )

                switch targetResult {
                case .existing(let id), .created(let id):
                    targetAccountId = id
                    if case .created = targetResult {
                        stats.incrementCreatedAccounts()
                    }
                case .skipped:
                    break
                }
            }

            // Resolve category
            let categoryName = csvRow.type == .internalTransfer
                ? String(localized: "transactionForm.transfer")
                : (csvRow.effectiveCategoryValue.isEmpty
                    ? String(localized: "category.other")
                    : csvRow.effectiveCategoryValue)

            let categoryResult = await mapper.resolveCategory(
                name: categoryName,
                type: csvRow.type,
                mapping: entityMapping,
                categoriesViewModel: categoriesViewModel
            )

            let categoryId: String
            switch categoryResult {
            case .existing(let id, _):
                categoryId = id
            case .created(let id, _):
                categoryId = id
                stats.incrementCreatedCategories()
            }

            // Resolve subcategories
            var subcategoryIds: [String] = []
            if !csvRow.subcategoryNames.isEmpty {
                let subcategoryResults = await mapper.resolveSubcategories(
                    names: csvRow.subcategoryNames,
                    categoryId: categoryId,
                    categoriesViewModel: categoriesViewModel
                )

                for result in subcategoryResults {
                    switch result {
                    case .existing(let id):
                        subcategoryIds.append(id)
                    case .created(let id):
                        subcategoryIds.append(id)
                        stats.incrementCreatedSubcategories()
                    }
                }
            }

            // Convert to transaction
            let transaction = converter.convertRow(
                csvRow,
                accountId: accountId,
                targetAccountId: targetAccountId,
                categoryId: categoryId,
                subcategoryIds: subcategoryIds,
                rowIndex: rowIndex
            )

            // Check duplicates
            let fingerprint = TransactionFingerprint(from: transaction)
            if existingFingerprints.contains(fingerprint) {
                stats.incrementDuplicates()
                stats.incrementSkipped()
                continue
            }

            // Add to batch
            transactionsBatch.append(transaction)
            if !subcategoryIds.isEmpty {
                subcategoryLinksBatch[transaction.id] = subcategoryIds
            }

            stats.incrementImported()

            // Process batch if full
            if transactionsBatch.count >= 500 || rowIndex == csvFile.rowCount - 1 {
                await storage.saveBatch(
                    transactionsBatch,
                    subcategoryLinks: subcategoryLinksBatch,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel
                )

                transactionsBatch.removeAll(keepingCapacity: true)
                subcategoryLinksBatch.removeAll(keepingCapacity: true)
            }
        }

        // Finalize import
        await storage.finalizeImport(
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel
        )

        // Clear cache
        cache.clear()

        // Build final statistics
        let duration = Date().timeIntervalSince(startTime)
        return stats.build(duration: duration)
    }
}

// MARK: - Statistics Builder

private class ImportStatisticsBuilder {
    var totalRows: Int = 0
    var importedCount: Int = 0
    var skippedCount: Int = 0
    var duplicatesSkipped: Int = 0
    var createdAccounts: Int = 0
    var createdCategories: Int = 0
    var createdSubcategories: Int = 0
    var errors: [ValidationError] = []

    func incrementImported() { importedCount += 1 }
    func incrementSkipped() { skippedCount += 1 }
    func incrementDuplicates() { duplicatesSkipped += 1 }
    func incrementCreatedAccounts() { createdAccounts += 1 }
    func incrementCreatedCategories() { createdCategories += 1 }
    func incrementCreatedSubcategories() { createdSubcategories += 1 }
    func addError(_ error: ValidationError) { errors.append(error) }

    func build(duration: TimeInterval) -> ImportStatistics {
        let rowsPerSecond = totalRows > 0 ? Double(totalRows) / duration : 0.0

        return ImportStatistics(
            totalRows: totalRows,
            importedCount: importedCount,
            skippedCount: skippedCount,
            duplicatesSkipped: duplicatesSkipped,
            createdAccounts: createdAccounts,
            createdCategories: createdCategories,
            createdSubcategories: createdSubcategories,
            duration: duration,
            rowsPerSecond: rowsPerSecond,
            errors: errors
        )
    }
}
```

**Создать:** `Services/CSV/CSVImportCoordinator.swift` (~300 LOC)

---

### Результаты Phase 2

**Сервисы созданы:** 6
- CSVParsingService (~180 LOC)
- CSVValidationService (~200 LOC)
- EntityMappingService (~280 LOC)
- TransactionConverterService (~120 LOC)
- CSVStorageCoordinator (~180 LOC)
- CSVImportCoordinator (~300 LOC)

**Total новый код:** ~1,260 LOC (services)

**Код удалён:**
- CSVImportService.importTransactions: -680 LOC (монолитная функция → distributed)

**Net change:** +580 LOC (но reusable + testable + maintainable)

---

## Фаза 3: Локализация

### 3.1 Localization Keys (EN + RU)

**Создать:** Добавить в `en.lproj/Localizable.strings` и `ru.lproj/Localizable.strings`

```swift
// MARK: - CSV Import

// Categories
"category.other" = "Other"; // "Другое"
"category.transfer" = "Transfer"; // "Перевод"

// Validation Errors
"csvImport.error.missingRequiredColumn" = "Missing required column"; // "Отсутствует обязательная колонка"
"csvImport.error.invalidDateFormat" = "Invalid date format in row %d"; // "Неверный формат даты в строке %d"
"csvImport.error.invalidAmount" = "Invalid amount in row %d: %@"; // "Неверная сумма в строке %d: %@"
"csvImport.error.invalidType" = "Invalid transaction type in row %d: %@"; // "Неверный тип операции в строке %d: %@"
"csvImport.error.emptyValue" = "Empty value in row %d, column '%@'"; // "Пустое значение в строке %d, колонка '%@'"
"csvImport.error.duplicateTransaction" = "Duplicate transaction in row %d"; // "Дубликат транзакции в строке %d"

// Import Progress
"csvImport.progress.parsing" = "Parsing CSV file..."; // "Парсинг CSV файла..."
"csvImport.progress.validating" = "Validating rows..."; // "Валидация строк..."
"csvImport.progress.importing" = "Importing transactions..."; // "Импорт транзакций..."
"csvImport.progress.finalizing" = "Finalizing import..."; // "Завершение импорта..."

// Import Results
"csvImport.result.imported" = "%d imported"; // "%d импортировано"
"csvImport.result.skipped" = "%d skipped"; // "%d пропущено"
"csvImport.result.duplicates" = "%d duplicates"; // "%d дубликатов"
"csvImport.result.createdAccounts" = "%d accounts created"; // "%d счетов создано"
"csvImport.result.createdCategories" = "%d categories created"; // "%d категорий создано"
"csvImport.result.createdSubcategories" = "%d subcategories created"; // "%d подкатегорий создано"
"csvImport.result.duration" = "Duration: %.1fs"; // "Время: %.1fс"
"csvImport.result.speed" = "Speed: %.0f rows/s"; // "Скорость: %.0f строк/с"

// Buttons
"csvImport.button.cancel" = "Cancel Import"; // "Отменить импорт"
"csvImport.button.retry" = "Retry"; // "Повторить"
"csvImport.button.viewErrors" = "View Errors"; // "Посмотреть ошибки"
```

**Файлы изменены:**
- `Localization/en.lproj/Localizable.strings` (+25 keys)
- `Localization/ru.lproj/Localizable.strings` (+25 keys)

---

### 3.2 Update ValidationError

```swift
struct ValidationError: LocalizedError {
    let rowIndex: Int
    let column: String?
    let code: ValidationErrorCode
    let context: [String: String]

    var errorDescription: String? {
        switch code {
        case .missingRequiredColumn:
            return String(localized: "csvImport.error.missingRequiredColumn")

        case .invalidDateFormat:
            return String(
                localized: "csvImport.error.invalidDateFormat",
                defaultValue: "Invalid date format in row \(rowIndex + 2)"
            )

        case .invalidAmount:
            let value = context["value"] ?? ""
            return String(
                localized: "csvImport.error.invalidAmount",
                defaultValue: "Invalid amount in row \(rowIndex + 2): \(value)"
            )

        case .invalidType:
            let value = context["value"] ?? ""
            return String(
                localized: "csvImport.error.invalidType",
                defaultValue: "Invalid transaction type in row \(rowIndex + 2): \(value)"
            )

        case .emptyValue:
            let columnName = column ?? "unknown"
            return String(
                localized: "csvImport.error.emptyValue",
                defaultValue: "Empty value in row \(rowIndex + 2), column '\(columnName)'"
            )

        case .duplicateTransaction:
            return String(
                localized: "csvImport.error.duplicateTransaction",
                defaultValue: "Duplicate transaction in row \(rowIndex + 2)"
            )
        }
    }
}
```

---

### 3.3 Update CSVImporter Errors

```swift
enum CSVImportError: LocalizedError {
    case fileAccessDenied
    case invalidEncoding
    case emptyFile
    case noHeaders
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return String(localized: "csvImport.error.fileAccessDenied", defaultValue: "File access denied")
        case .invalidEncoding:
            return String(localized: "csvImport.error.invalidEncoding", defaultValue: "Invalid file encoding (UTF-8 required)")
        case .emptyFile:
            return String(localized: "csvImport.error.emptyFile", defaultValue: "File is empty")
        case .noHeaders:
            return String(localized: "csvImport.error.noHeaders", defaultValue: "No headers found in file")
        case .invalidFormat:
            return String(localized: "csvImport.error.invalidFormat", defaultValue: "Invalid CSV format")
        }
    }
}
```

**Дополнительные ключи:**
```
"csvImport.error.fileAccessDenied" = "File access denied"; // "Нет доступа к файлу"
"csvImport.error.invalidEncoding" = "Invalid file encoding (UTF-8 required)"; // "Неверная кодировка файла (требуется UTF-8)"
"csvImport.error.emptyFile" = "File is empty"; // "Файл пуст"
"csvImport.error.noHeaders" = "No headers found in file"; // "В файле отсутствуют заголовки"
"csvImport.error.invalidFormat" = "Invalid CSV format"; // "Неверный формат CSV"
```

---

### Результаты Phase 3

**Localization keys добавлено:** ~30 keys (EN + RU)
**Файлы изменены:**
- `Localization/en.lproj/Localizable.strings`
- `Localization/ru.lproj/Localizable.strings`
- `Models/ValidationError.swift`
- `Services/CSVImporter.swift`

**Hardcoded strings удалено:** 100%

---

## Фаза 4: UI Refactoring (Props + Callbacks)

### 4.1 Current CSV Views

**CSVPreviewView.swift** (~280 LOC)
- Показывает preview CSV файла
- **Проблема:** Tight coupling к `TransactionsViewModel`

**CSVColumnMappingView.swift** (~320 LOC)
- Маппинг колонок к полям
- **Проблема:** Tight coupling, внутренний state management

**CSVEntityMappingView.swift** (~350 LOC)
- Маппинг account/category значений
- **Проблема:** Дублирование account/category mapping detail views

**CSVImportResultView.swift** (~134 LOC)
- Результаты импорта
- **Проблема:** Использует старый `ImportResult` вместо `ImportStatistics`

---

### 4.2 Refactored Views (Props + Callbacks)

#### CSVPreviewView (Refactored)

```swift
struct CSVPreviewView: View {
    // Props
    let csvFile: CSVFile
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Header
            Text(String(localized: "csvImport.preview.title"))
                .font(AppTypography.h2)

            // Stats
            HStack {
                InfoRow(
                    label: String(localized: "csvImport.preview.rows"),
                    value: "\(csvFile.rowCount)"
                )
                InfoRow(
                    label: String(localized: "csvImport.preview.columns"),
                    value: "\(csvFile.headers.count)"
                )
            }

            // Preview table
            ScrollView([.horizontal, .vertical]) {
                previewTable
            }

            // Buttons
            HStack {
                Button(String(localized: "button.cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(String(localized: "button.continue")) {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppSpacing.lg)
    }

    private var previewTable: some View {
        // Existing table logic
    }
}
```

**Changes:**
- ❌ Removed: `@ObservedObject var viewModel: TransactionsViewModel`
- ✅ Added: `onContinue`, `onCancel` callbacks
- ✅ Локализация всех strings

**Lines:** ~220 LOC (-21%)

---

#### CSVColumnMappingView (Refactored)

```swift
struct CSVColumnMappingView: View {
    // Props
    let csvFile: CSVFile
    let onComplete: (CSVColumnMapping) -> Void
    let onCancel: () -> Void

    // Internal state (допустимо для form logic)
    @State private var mapping = CSVColumnMapping()

    var body: some View {
        Form {
            Section(header: Text(String(localized: "csvImport.mapping.required"))) {
                columnPicker(
                    title: String(localized: "csvImport.mapping.date"),
                    binding: $mapping.dateColumn
                )
                columnPicker(
                    title: String(localized: "csvImport.mapping.type"),
                    binding: $mapping.typeColumn
                )
                columnPicker(
                    title: String(localized: "csvImport.mapping.amount"),
                    binding: $mapping.amountColumn
                )
            }

            Section(header: Text(String(localized: "csvImport.mapping.optional"))) {
                columnPicker(
                    title: String(localized: "csvImport.mapping.currency"),
                    binding: $mapping.currencyColumn
                )
                columnPicker(
                    title: String(localized: "csvImport.mapping.account"),
                    binding: $mapping.accountColumn
                )
                // ... etc
            }

            Section {
                Button(String(localized: "button.continue")) {
                    onComplete(mapping)
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle(String(localized: "csvImport.mapping.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "button.cancel")) {
                    onCancel()
                }
            }
        }
    }

    private var isValid: Bool {
        mapping.dateColumn != nil &&
        mapping.typeColumn != nil &&
        mapping.amountColumn != nil
    }

    private func columnPicker(
        title: String,
        binding: Binding<String?>
    ) -> some View {
        Picker(title, selection: binding) {
            Text(String(localized: "csvImport.mapping.none"))
                .tag(nil as String?)
            ForEach(csvFile.headers, id: \.self) { header in
                Text(header).tag(header as String?)
            }
        }
    }
}
```

**Changes:**
- ✅ Props + Callbacks pattern
- ✅ Локализация всех strings
- ✅ Internal state для form допустим

**Lines:** ~280 LOC (-13%)

---

#### CSVEntityMappingView (Refactored)

**Дублирование устранено:** `AccountMappingDetailView` + `CategoryMappingDetailView` → Generic `EntityMappingDetailView<T>`

```swift
struct CSVEntityMappingView: View {
    // Props
    let csvFile: CSVFile
    let columnMapping: CSVColumnMapping
    let accounts: [Account]
    let categories: [CustomCategory]
    let onComplete: (EntityMapping) -> Void
    let onCancel: () -> Void

    // Internal state
    @State private var mapping = EntityMapping()
    @State private var uniqueAccounts: [String] = []
    @State private var uniqueCategories: [String] = []

    var body: some View {
        Form {
            // Account mappings
            if !uniqueAccounts.isEmpty {
                Section(header: Text(String(localized: "csvImport.entityMapping.accounts"))) {
                    ForEach(uniqueAccounts, id: \.self) { csvValue in
                        EntityMappingRow(
                            csvValue: csvValue,
                            mappedValue: mapping.accountMappings[csvValue],
                            onEdit: {
                                // Show account picker
                            }
                        )
                    }
                }
            }

            // Category mappings
            if !uniqueCategories.isEmpty {
                Section(header: Text(String(localized: "csvImport.entityMapping.categories"))) {
                    ForEach(uniqueCategories, id: \.self) { csvValue in
                        EntityMappingRow(
                            csvValue: csvValue,
                            mappedValue: mapping.categoryMappings[csvValue],
                            onEdit: {
                                // Show category picker
                            }
                        )
                    }
                }
            }

            Section {
                Button(String(localized: "button.continue")) {
                    onComplete(mapping)
                }
            }
        }
        .navigationTitle(String(localized: "csvImport.entityMapping.title"))
        .onAppear {
            extractUniqueValues()
        }
    }

    private func extractUniqueValues() {
        // Existing logic
    }
}

// MARK: - Generic Entity Mapping Row

struct EntityMappingRow: View {
    let csvValue: String
    let mappedValue: String?
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(csvValue)
                    .font(AppTypography.body)
                if let mapped = mappedValue {
                    Text(mapped)
                        .font(AppTypography.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(localized: "csvImport.entityMapping.autoCreate"))
                        .font(AppTypography.caption)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
            }
        }
    }
}
```

**Changes:**
- ❌ Removed: `AccountMappingDetailView` (95 LOC)
- ❌ Removed: `CategoryMappingDetailView` (85 LOC)
- ✅ Added: Generic `EntityMappingRow` (30 LOC)
- ✅ Props + Callbacks pattern
- ✅ Локализация

**Lines:** ~270 LOC (-23%)

---

#### CSVImportResultView (Refactored)

```swift
struct CSVImportResultView: View {
    // Props
    let statistics: ImportStatistics
    let onDone: () -> Void
    let onViewErrors: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Success icon
            Image(systemName: statistics.successRate > 0.8 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(statistics.successRate > 0.8 ? .green : .orange)

            // Title
            Text(String(localized: "csvImport.result.title"))
                .font(AppTypography.h2)

            // Stats
            VStack(spacing: AppSpacing.md) {
                StatRow(
                    label: String(localized: "csvImport.result.imported"),
                    value: "\(statistics.importedCount)",
                    color: .green,
                    icon: "checkmark.circle"
                )

                StatRow(
                    label: String(localized: "csvImport.result.skipped"),
                    value: "\(statistics.skippedCount)",
                    color: .orange,
                    icon: "minus.circle"
                )

                StatRow(
                    label: String(localized: "csvImport.result.duplicates"),
                    value: "\(statistics.duplicatesSkipped)",
                    color: .blue,
                    icon: "doc.on.doc"
                )

                Divider()

                StatRow(
                    label: String(localized: "csvImport.result.createdAccounts"),
                    value: "\(statistics.createdAccounts)",
                    color: .purple,
                    icon: "plus.circle"
                )

                StatRow(
                    label: String(localized: "csvImport.result.createdCategories"),
                    value: "\(statistics.createdCategories)",
                    color: .purple,
                    icon: "plus.circle"
                )

                Divider()

                InfoRow(
                    label: String(localized: "csvImport.result.duration"),
                    value: String(format: "%.1fs", statistics.duration)
                )

                InfoRow(
                    label: String(localized: "csvImport.result.speed"),
                    value: String(format: "%.0f rows/s", statistics.rowsPerSecond)
                )
            }
            .padding(AppSpacing.lg)
            .background(Color(.systemGray6))
            .cornerRadius(AppRadius.lg)

            // Errors section
            if !statistics.errors.isEmpty {
                Button(String(localized: "csvImport.button.viewErrors")) {
                    onViewErrors()
                }
                .buttonStyle(.bordered)
            }

            // Done button
            Button(String(localized: "button.done")) {
                onDone()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(AppSpacing.lg)
    }
}

// MARK: - StatRow Component

struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    let icon: String?

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            Text(label)
                .font(AppTypography.body)
            Spacer()
            Text(value)
                .font(AppTypography.bodyLarge)
                .foregroundColor(color)
        }
    }
}
```

**Changes:**
- ✅ Использует новый `ImportStatistics` вместо старого `ImportResult`
- ✅ Props + Callbacks pattern
- ✅ Локализация
- ✅ Добавлен performance metrics (duration, speed)
- ✅ Новый компонент `StatRow` (reusable)

**Lines:** ~150 LOC (+12%)

---

### Результаты Phase 4

**Views refactored:** 4
- CSVPreviewView: 280 → 220 LOC (-21%)
- CSVColumnMappingView: 320 → 280 LOC (-13%)
- CSVEntityMappingView: 350 → 270 LOC (-23%)
- CSVImportResultView: 134 → 150 LOC (+12%)

**Total:** 1,084 → ~920 LOC (-15%)

**Дублирование устранено:** -180 LOC (AccountMappingDetailView + CategoryMappingDetailView)
**Новые компоненты:** +2 (EntityMappingRow, StatRow)

**ViewModel dependencies:** 100% устранены

---

## Фаза 5: Performance Optimizations

### 5.1 Streaming для больших файлов

**Цель:** Обработка файлов >100K rows без memory spikes

```swift
extension CSVParsingService {

    func parseFileStreaming(from url: URL, chunkSize: Int = 1000) async throws -> AsyncStream<[String]> {

        return AsyncStream { continuation in
            Task {
                do {
                    guard let fileHandle = FileHandle(forReadingAtPath: url.path) else {
                        throw CSVImportError.fileAccessDenied
                    }

                    defer {
                        try? fileHandle.close()
                    }

                    var buffer = ""
                    var lineCount = 0

                    while autoreleasepool(invoking: {
                        guard let data = try? fileHandle.read(upToCount: 4096) else {
                            return false
                        }

                        guard !data.isEmpty else {
                            return false
                        }

                        buffer += String(data: data, encoding: .utf8) ?? ""

                        // Process complete lines
                        let lines = buffer.components(separatedBy: .newlines)
                        buffer = lines.last ?? ""

                        for line in lines.dropLast() where !line.isEmpty {
                            let fields = parseCSVLine(line)
                            continuation.yield(fields)
                            lineCount += 1
                        }

                        return true
                    }) {}

                    // Process remaining buffer
                    if !buffer.isEmpty {
                        let fields = parseCSVLine(buffer)
                        continuation.yield(fields)
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

**Добавить в:** `Services/CSV/CSVParsingService.swift` (+80 LOC)

---

### 5.2 Параллельная валидация

**Цель:** Validate rows in parallel batches

```swift
extension CSVValidationService {

    func validateFileParallel(
        _ csvFile: CSVFile,
        mapping: CSVColumnMapping,
        batchSize: Int = 100
    ) async -> [ValidationResult] {

        let batches = csvFile.rows.chunked(into: batchSize)
        var results: [ValidationResult] = []
        results.reserveCapacity(csvFile.rowCount)

        await withTaskGroup(of: [ValidationResult].self) { group in
            for (batchIndex, batch) in batches.enumerated() {
                group.addTask {
                    var batchResults: [ValidationResult] = []
                    batchResults.reserveCapacity(batch.count)

                    for (index, row) in batch.enumerated() {
                        let globalIndex = batchIndex * batchSize + index
                        let result = self.validateRow(row, at: globalIndex, mapping: mapping)
                        batchResults.append(result)
                    }

                    return batchResults
                }
            }

            for await batchResults in group {
                results.append(contentsOf: batchResults)
            }
        }

        return results
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

**Добавить в:** `Services/CSV/CSVValidationService.swift` (+60 LOC)

---

### 5.3 Pre-allocation optimizations

**Уже применено в:**
- `ImportCacheManager`: LRU caches
- `EntityMappingService`: `reserveCapacity` для arrays
- `CSVImportCoordinator`: `reserveCapacity(500)` для batches

**Дополнительно:** Применить в `CSVRow` parsing

```swift
private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    // Estimate: average 10 columns per CSV
    fields.reserveCapacity(10)

    var currentField = ""
    currentField.reserveCapacity(50) // Average field length

    // ... existing logic
}
```

---

### Результаты Phase 5

**Optimizations добавлено:** 3
- Streaming parsing (+80 LOC)
- Parallel validation (+60 LOC)
- Pre-allocation improvements (+10 LOC)

**Total performance code:** +150 LOC

**Expected improvements:**
- ✅ Memory usage: -60% для больших файлов (streaming)
- ✅ Validation speed: 3-4x faster (parallel batches)
- ✅ Pre-allocation: -20% allocation overhead

---

## Фаза 6: Migration & Cleanup

### 6.1 Deprecate Old CSVImportService

```swift
@available(*, deprecated, message: "Use CSVImportCoordinator instead")
class CSVImportService {

    @available(*, deprecated, message: "Use CSVImportCoordinator.importTransactions instead")
    static func importTransactions(...) async -> ImportResult {
        fatalError("This method is deprecated. Use CSVImportCoordinator instead.")
    }
}
```

**Изменить:** `Services/CSVImportService.swift`

---

### 6.2 Update ContentView Integration

**Before:**
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
```

**After:**
```swift
// Initialize coordinator (can be @StateObject in real app)
let coordinator = CSVImportCoordinator(
    parser: CSVParsingService(),
    validator: CSVValidationService(),
    mapper: EntityMappingService(cache: ImportCacheManager()),
    converter: TransactionConverterService(),
    storage: CSVStorageCoordinator(),
    cache: ImportCacheManager()
)

// Create progress tracker
let progress = ImportProgress()
progress.totalRows = csvFile.rowCount

// Import
let statistics = await coordinator.importTransactions(
    csvFile: csvFile,
    columnMapping: columnMapping,
    entityMapping: entityMapping,
    transactionsViewModel: transactionsViewModel,
    categoriesViewModel: categoriesViewModel,
    accountsViewModel: accountsViewModel,
    progress: progress
)
```

**Изменить:** `Views/ContentView.swift` (CSV import section)

---

### 6.3 Cleanup старого кода

**Удалить после миграции:**
- ❌ `CSVImportService.swift` (deprecated) - после тестирования
- ❌ Старые inline parsing helpers (если дублируются)

**Сохранить:**
- ✅ `CSVImporter.swift` - используется `CSVParsingService`
- ✅ `CSVColumnMapping.swift` - модели актуальны
- ✅ `CSVExporter.swift` - export логика (не затронута рефакторингом)

---

## Final Summary

### Метрики рефакторинга

| Метрика | Before | After | Change |
|---------|--------|-------|--------|
| **CSVImportService** | 784 LOC | 0 LOC (deprecated) | -784 LOC |
| **Services (новые)** | 0 LOC | 1,260 LOC | +1,260 LOC |
| **Models (новые)** | 80 LOC | 300 LOC | +220 LOC |
| **Protocols** | 0 LOC | 230 LOC | +230 LOC |
| **Cache Manager** | 0 LOC | 120 LOC | +120 LOC |
| **CSV Views** | 1,084 LOC | 920 LOC | -164 LOC |
| **Localization keys** | 0 | 30 keys | +60 strings (EN+RU) |
| **Total code** | 1,948 LOC | 2,830 LOC | **+882 LOC** |

### Качественные улучшения

✅ **Single Responsibility Principle**
- 1 монолитная функция → 6 focused services

✅ **LRU Eviction**
- Unbounded dictionaries → LRUCache с automatic eviction

✅ **Performance**
- O(n) lookups → O(1) with caching
- Sequential processing → Parallel validation
- Memory spikes → Streaming для больших файлов

✅ **Локализация**
- Hardcoded strings → 100% localized (30 keys)

✅ **Testability**
- Static methods → Protocol-oriented design
- Tight coupling → Dependency injection

✅ **Maintainability**
- 784-line monolith → 6 reusable services
- Unclear responsibilities → Clear separation of concerns

✅ **UI Architecture**
- ViewModel dependencies → Props + Callbacks
- Дублирование → Generic components

✅ **Error Handling**
- String arrays → Structured ValidationError
- Limited context → Rich error context

### Файловая структура (после рефакторинга)

```
Tenra/
├── Protocols/
│   ├── CSVParsingServiceProtocol.swift (30 LOC)
│   ├── CSVValidationServiceProtocol.swift (40 LOC)
│   ├── EntityMappingServiceProtocol.swift (50 LOC)
│   ├── TransactionConverterServiceProtocol.swift (30 LOC)
│   ├── CSVStorageCoordinatorProtocol.swift (40 LOC)
│   └── CSVImportCoordinatorProtocol.swift (40 LOC)
│
├── Models/
│   ├── CSVRow.swift (80 LOC)
│   ├── ValidationError.swift (60 LOC)
│   ├── ImportProgress.swift (30 LOC)
│   ├── ImportStatistics.swift (50 LOC)
│   └── CSVColumnMapping.swift (80 LOC) — existing
│
├── Services/
│   ├── CSV/
│   │   ├── CSVParsingService.swift (180 LOC)
│   │   ├── CSVValidationService.swift (200 LOC)
│   │   ├── EntityMappingService.swift (280 LOC)
│   │   ├── TransactionConverterService.swift (120 LOC)
│   │   ├── CSVStorageCoordinator.swift (180 LOC)
│   │   ├── CSVImportCoordinator.swift (300 LOC)
│   │   └── ImportCacheManager.swift (120 LOC)
│   ├── CSVImporter.swift (162 LOC) — existing, used by parsing service
│   ├── CSVExporter.swift (existing, unchanged)
│   └── CSVImportService.swift (deprecated)
│
├── Views/
│   └── CSV/
│       ├── CSVPreviewView.swift (220 LOC, -21%)
│       ├── CSVColumnMappingView.swift (280 LOC, -13%)
│       ├── CSVEntityMappingView.swift (270 LOC, -23%)
│       └── CSVImportResultView.swift (150 LOC, +12%)
│
└── Localization/
    ├── en.lproj/Localizable.strings (+30 keys)
    └── ru.lproj/Localizable.strings (+30 keys)
```

---

## Implementation Checklist

### Phase 1: Архитектурный фундамент
- [ ] Создать 6 Protocols (~230 LOC)
- [ ] Создать 4 Models (~220 LOC)
- [ ] Создать ImportCacheManager (~120 LOC)
- [ ] Интеграция LRUCache (уже есть в проекте)

### Phase 2: Service Layer
- [ ] Создать CSVParsingService (~180 LOC)
- [ ] Создать CSVValidationService (~200 LOC)
- [ ] Создать EntityMappingService (~280 LOC)
- [ ] Создать TransactionConverterService (~120 LOC)
- [ ] Создать CSVStorageCoordinator (~180 LOC)
- [ ] Создать CSVImportCoordinator (~300 LOC)

### Phase 3: Локализация
- [ ] Добавить 30 localization keys (EN)
- [ ] Добавить 30 localization keys (RU)
- [ ] Обновить ValidationError локализацию
- [ ] Обновить CSVImportError локализацию

### Phase 4: UI Refactoring
- [ ] Refactor CSVPreviewView (Props + Callbacks)
- [ ] Refactor CSVColumnMappingView (Props + Callbacks)
- [ ] Refactor CSVEntityMappingView (Props + Callbacks)
- [ ] Refactor CSVImportResultView (ImportStatistics)
- [ ] Создать EntityMappingRow компонент
- [ ] Создать StatRow компонент

### Phase 5: Performance
- [ ] Добавить streaming parsing
- [ ] Добавить parallel validation
- [ ] Улучшить pre-allocation

### Phase 6: Migration
- [ ] Deprecate старый CSVImportService
- [ ] Обновить ContentView integration
- [ ] Тестирование миграции
- [ ] Удалить deprecated код

---

## Estimated Effort

| Phase | LOC | Complexity | Estimated Time |
|-------|-----|------------|----------------|
| Phase 1 | ~570 | Medium | 4-6 hours |
| Phase 2 | ~1,260 | High | 10-14 hours |
| Phase 3 | ~100 | Low | 2-3 hours |
| Phase 4 | ~920 | Medium | 6-8 hours |
| Phase 5 | ~150 | Medium | 3-4 hours |
| Phase 6 | ~50 | Low | 2-3 hours |
| **Total** | **~3,050** | **High** | **27-38 hours** |

---

## Risk Mitigation

### Риски

1. **Breaking changes** — старый код зависит от CSVImportService
   - **Mitigation:** Deprecation warnings + parallel run

2. **Performance regression** — новая архитектура медленнее
   - **Mitigation:** Benchmarking на реальных данных

3. **Data loss** — баги в migration logic
   - **Mitigation:** Extensive testing + user backups

### Testing Strategy

1. **Unit Tests** — каждый сервис отдельно
2. **Integration Tests** — полный import flow
3. **Performance Tests** — benchmarks на 1K, 10K, 100K rows
4. **Manual Tests** — реальные CSV файлы

---

## Success Criteria

✅ **Functional:**
- [ ] Все existing CSV import тесты проходят
- [ ] Новые сервисы покрыты unit tests
- [ ] UI компоненты работают без ViewModel dependencies

✅ **Performance:**
- [ ] Import 10K rows: <10 секунд (baseline: ~15s)
- [ ] Memory usage: <200MB для 100K rows (baseline: ~500MB)
- [ ] LRU cache: automatic eviction работает

✅ **Code Quality:**
- [ ] 0 hardcoded strings
- [ ] 100% localization coverage
- [ ] SRP соблюдён для всех сервисов
- [ ] Protocol-oriented design применён

✅ **Documentation:**
- [ ] README обновлён
- [ ] PROJECT_BIBLE обновлён
- [ ] COMPONENT_INVENTORY обновлён
- [ ] Migration guide написан

---

**Конец документа**
**Статус:** Ready for Implementation
**Next Step:** Phase 1 — Архитектурный фундамент
