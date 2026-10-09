# SETTINGS — План полного рефакторинга и Full Rebuild

> **Дата:** 2026-02-04
> **Версия:** 1.0
> **Статус:** Ready for Implementation
> **Автор:** AI Architecture Audit (Deep Analysis)

---

## Executive Summary

Проведен глубокий анализ раздела **Settings** с учетом:
- ✅ Оптимизации и увеличения скорости работы
- ✅ Декомпозиции по Single Responsibility Principle
- ✅ LRU eviction для кэшей
- ✅ Удаления неиспользуемого кода
- ✅ Соблюдения дизайн-системы (AppTheme)
- ✅ Локализации проекта

**Ключевые находки:**
- SettingsView — 419 строк с 5 ViewModel зависимостями (нарушение SRP)
- CSVImportService — 799 строк MONOLITHIC код (DEPRECATED, но все еще используется)
- AppSettings — минимальная модель (только 2 свойства, нет валидации)
- 3 hardcoded русских строки (нелокализованные)
- Отсутствие единого SettingsViewModel (прямые вызовы из View)
- CSV компоненты частично рефакторены (Phase 4), но флоу не завершен

---

## 1. Текущая архитектура Settings

### 1.1 Структура файлов

```
Settings/
├── SettingsView.swift (419 LOC) ⚠️
│   └── Зависимости: 5 ViewModels
│
├── Components/
│   ├── ExportActivityView.swift (UIKit wrapper)
│   ├── BankLogoPickerView.swift
│   ├── BankLogoRow.swift
│   └── BrandLogoView.swift
│
└── LogoSearchView.swift

CSV/
├── DocumentPicker.swift (UIKit wrapper)
├── CSVPreviewView.swift ✅ (Refactored Phase 4)
├── CSVColumnMappingView.swift ✅ (Refactored Phase 4)
├── CSVEntityMappingView.swift
└── CSVImportResultView.swift ✅ (Refactored Phase 4)

Models/
├── AppSettings.swift (63 LOC, минимальная модель)
└── CSVColumnMapping.swift (различные структуры)

Services/
├── CSVExporter.swift
├── CSVImporter.swift
├── CSVImportService.swift ⚠️ (799 LOC - DEPRECATED, но используется)
└── CSV/ (Новая модульная архитектура)
    ├── CSVImportCoordinator.swift
    ├── CSVImportCoordinatorFactory.swift
    ├── CSVParsingService.swift
    ├── CSVValidationService.swift
    ├── EntityMappingService.swift
    ├── TransactionConverterService.swift
    ├── CSVStorageCoordinator.swift
    └── ImportCacheManager.swift
```

### 1.2 Текущие нарушения архитектуры

#### ❌ Критические проблемы

**1. SettingsView нарушает SRP:**
```swift
// 5 ViewModel зависимостей!
@ObservedObject var transactionsViewModel: TransactionsViewModel
@ObservedObject var accountsViewModel: AccountsViewModel
@ObservedObject var categoriesViewModel: CategoriesViewModel
@ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
@ObservedObject var depositsViewModel: DepositsViewModel

// Прямые вызовы бизнес-логики из View
transactionsViewModel.resetAllData()
transactionsViewModel.resetAndRecalculateAllBalances()
transactionsViewModel.appSettings.save()
accountsViewModel.reloadFromStorage()
```

**2. Отсутствие SettingsViewModel:**
- Нет единого координатора для settings операций
- View напрямую манипулирует данными
- Нет централизованной валидации
- Невозможно протестировать логику

**3. AppSettings — слишком минимальна:**
```swift
class AppSettings: ObservableObject {
    @Published var baseCurrency: String = "KZT"
    @Published var wallpaperImageName: String? = nil
}
```
- Нет валидации валюты
- Нет проверки существования файла обоев
- Нет default values fallback
- Нет миграции старых настроек

**4. CSVImportService (799 LOC) — монолит:**
```swift
// DEPRECATED, но все еще используется в SettingsView:291
let result = await CSVImportService.importTransactions(...)
```
- Должен использовать CSVImportCoordinator
- Дублирование логики между старым/новым кодом
- Технический долг

**5. Hardcoded строки (не локализованы):**
```swift
// SettingsView.swift:48
.alert("Пересчитать балансы?", isPresented: ...)

// SettingsView.swift:58
Text("Это пересчитает балансы всех счетов...")

// SettingsView.swift:173
Text("Пересчитать балансы счетов")
```

**6. Нет обработки ошибок:**
```swift
// SettingsView.swift:387
} catch {
    // Молча игнорируется!
}
```

**7. File Management без валидации:**
```swift
private func loadPhoto(_ item: PhotosPickerItem) async {
    // Нет проверки размера файла
    // Нет проверки формата
    // Нет проверки дискового пространства
    if let jpegData = image.jpegData(compressionQuality: 0.8) {
        try jpegData.write(to: fileURL) // Может упасть
    }
}
```

#### ⚠️ Средние проблемы

**8. Дублирование валидации:**
- CSVColumnMappingView проверяет обязательные поля
- CSVImportService повторяет эти же проверки
- Нет единого источника правил валидации

**9. Отсутствие LRU кэширования:**
- BankLogoPickerView загружает все логотипы каждый раз
- Нет кэша для recent currencies
- Нет кэша для recent wallpapers (history)

**10. Performance issues:**
```swift
// ExportActivityView создает CSV синхронно в main thread
let csvString = CSVExporter.exportTransactions(
    transactions: viewModel.allTransactions, // Может быть 19K+!
    accounts: viewModel.accounts
)
```

### 1.3 Метрики кода

| Компонент | LOC | Зависимости | Статус |
|-----------|-----|-------------|--------|
| SettingsView | 419 | 5 ViewModels | ❌ Нарушает SRP |
| AppSettings | 63 | 0 | ⚠️ Слишком минимальна |
| CSVImportService | 799 | Multiple | ❌ DEPRECATED монолит |
| CSVImportCoordinator | ~300 | 6 protocols | ✅ Правильная архитектура |
| ExportActivityView | ~50 | 1 ViewModel | ⚠️ Синхронный экспорт |
| DocumentPicker | ~80 | 0 | ✅ OK |

---

## 2. Целевая архитектура (MVVM + Clean Architecture)

### 2.1 Принципы новой архитектуры

```
┌─────────────────────────────────────────────────────┐
│  SettingsView (SwiftUI)                             │
│    ↓ (Props + Callbacks only)                       │
│  SettingsViewModel (@MainActor ObservableObject)    │
│    ↓ (Protocol-oriented delegates)                  │
│  Settings Services Layer                            │
│    ├── SettingsStorageService                       │
│    ├── WallpaperManagementService                   │
│    ├── DataResetCoordinator                         │
│    └── SettingsValidationService                    │
│    ↓                                                 │
│  Repository Layer                                   │
│    ├── UserDefaults (AppSettings)                   │
│    ├── FileManager (Wallpapers)                     │
│    └── CoreData (via DataRepository)                │
└─────────────────────────────────────────────────────┘
```

### 2.2 Новые компоненты

#### ✨ SettingsViewModel (NEW)

```swift
@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published State
    @Published var settings: AppSettings
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // MARK: - Wallpaper State
    @Published var currentWallpaper: UIImage?
    @Published var wallpaperHistory: [WallpaperHistoryItem] = []

    // MARK: - Export/Import State
    @Published var exportProgress: Double = 0
    @Published var importProgress: ImportProgress?

    // MARK: - Dependencies (Protocol-oriented)
    private let storageService: SettingsStorageServiceProtocol
    private let wallpaperService: WallpaperManagementServiceProtocol
    private let resetCoordinator: DataResetCoordinatorProtocol
    private let validationService: SettingsValidationServiceProtocol
    private let exportCoordinator: ExportCoordinatorProtocol
    private let importCoordinator: CSVImportCoordinatorProtocol

    // MARK: - Lazy Services (DI prevention circular deps)
    private lazy var wallpaperCache: LRUCache<String, UIImage> = {
        LRUCache(capacity: 10)
    }()

    // MARK: - Public API
    func updateBaseCurrency(_ currency: String) async throws
    func selectWallpaper(_ image: UIImage) async throws
    func removeWallpaper() async throws
    func exportAllData() async throws -> URL
    func importCSV(from url: URL) async throws -> ImportResult
    func resetAllData() async throws
    func recalculateBalances() async throws
}
```

#### ✨ SettingsStorageService (NEW)

```swift
protocol SettingsStorageServiceProtocol {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
    func validateSettings(_ settings: AppSettings) throws
}

@MainActor
final class SettingsStorageService: SettingsStorageServiceProtocol {
    private let userDefaults: UserDefaults
    private let validator: SettingsValidationServiceProtocol

    func loadSettings() async throws -> AppSettings {
        // Load + validate + fallback to defaults
    }

    func saveSettings(_ settings: AppSettings) async throws {
        // Validate before save
        try validator.validateSettings(settings)
        // Encode + save
    }
}
```

#### ✨ WallpaperManagementService (NEW)

```swift
protocol WallpaperManagementServiceProtocol {
    func saveWallpaper(_ image: UIImage) async throws -> String
    func loadWallpaper(named: String) async throws -> UIImage
    func removeWallpaper(named: String) async throws
    func getWallpaperHistory() async -> [WallpaperHistoryItem]
}

final class WallpaperManagementService: WallpaperManagementServiceProtocol {
    private let fileManager: FileManager
    private let cache: LRUCache<String, UIImage>
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB

    func saveWallpaper(_ image: UIImage) async throws -> String {
        // Validate size
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw WallpaperError.compressionFailed
        }
        guard data.count < maxFileSize else {
            throw WallpaperError.fileTooLarge
        }

        // Check disk space
        let freeSpace = try getFreeSpace()
        guard freeSpace > data.count * 2 else {
            throw WallpaperError.insufficientSpace
        }

        // Generate unique filename
        let fileName = "wallpaper_\(UUID().uuidString).jpg"
        let fileURL = getDocumentsURL().appendingPathComponent(fileName)

        // Save + add to cache
        try data.write(to: fileURL)
        cache.set(image, forKey: fileName)

        return fileName
    }

    func loadWallpaper(named: String) async throws -> UIImage {
        // Check cache first
        if let cached = cache.get(forKey: named) {
            return cached
        }

        // Load from disk
        let fileURL = getDocumentsURL().appendingPathComponent(named)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw WallpaperError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        guard let image = UIImage(data: data) else {
            throw WallpaperError.corruptedFile
        }

        // Add to cache
        cache.set(image, forKey: named)
        return image
    }
}

enum WallpaperError: LocalizedError {
    case compressionFailed
    case fileTooLarge
    case insufficientSpace
    case fileNotFound
    case corruptedFile

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return String(localized: "error.wallpaper.compressionFailed")
        case .fileTooLarge: return String(localized: "error.wallpaper.fileTooLarge")
        case .insufficientSpace: return String(localized: "error.wallpaper.insufficientSpace")
        case .fileNotFound: return String(localized: "error.wallpaper.fileNotFound")
        case .corruptedFile: return String(localized: "error.wallpaper.corruptedFile")
        }
    }
}
```

#### ✨ DataResetCoordinator (NEW)

```swift
protocol DataResetCoordinatorProtocol {
    func resetAllData() async throws
    func recalculateAllBalances() async throws
}

@MainActor
final class DataResetCoordinator: DataResetCoordinatorProtocol {
    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var accountsViewModel: AccountsViewModel?
    private weak var categoriesViewModel: CategoriesViewModel?
    private weak var subscriptionsViewModel: SubscriptionsViewModel?
    private weak var depositsViewModel: DepositsViewModel?

    func resetAllData() async throws {
        // Centralized reset logic
        transactionsViewModel?.resetAllData()
        accountsViewModel?.reloadFromStorage()
        categoriesViewModel?.reloadFromStorage()
        subscriptionsViewModel?.reloadFromStorage()
        depositsViewModel?.reloadFromStorage()
    }

    func recalculateAllBalances() async throws {
        transactionsViewModel?.resetAndRecalculateAllBalances()
        accountsViewModel?.reloadFromStorage()
        // Trigger UI updates
        accountsViewModel?.objectWillChange.send()
        transactionsViewModel?.objectWillChange.send()
    }
}
```

#### ✨ SettingsValidationService (NEW)

```swift
protocol SettingsValidationServiceProtocol {
    func validateSettings(_ settings: AppSettings) throws
    func validateCurrency(_ currency: String) throws
    func validateWallpaper(_ fileName: String?) throws
}

final class SettingsValidationService: SettingsValidationServiceProtocol {
    private let fileManager: FileManager

    func validateSettings(_ settings: AppSettings) throws {
        try validateCurrency(settings.baseCurrency)
        try validateWallpaper(settings.wallpaperImageName)
    }

    func validateCurrency(_ currency: String) throws {
        guard AppSettings.availableCurrencies.contains(currency) else {
            throw SettingsValidationError.invalidCurrency(currency)
        }
    }

    func validateWallpaper(_ fileName: String?) throws {
        guard let fileName = fileName else { return }

        let fileURL = getDocumentsURL().appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw SettingsValidationError.wallpaperFileNotFound(fileName)
        }
    }
}

enum SettingsValidationError: LocalizedError {
    case invalidCurrency(String)
    case wallpaperFileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidCurrency(let currency):
            return String(localized: "error.settings.invalidCurrency", defaultValue: "Invalid currency: \(currency)")
        case .wallpaperFileNotFound(let fileName):
            return String(localized: "error.settings.wallpaperNotFound", defaultValue: "Wallpaper file not found: \(fileName)")
        }
    }
}
```

#### ✨ ExportCoordinator (NEW)

```swift
protocol ExportCoordinatorProtocol {
    func exportAllData() async throws -> URL
}

final class ExportCoordinator: ExportCoordinatorProtocol {
    private weak var transactionsViewModel: TransactionsViewModel?
    private weak var accountsViewModel: AccountsViewModel?

    func exportAllData() async throws -> URL {
        // Run in background to avoid blocking UI
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    let csvString = CSVExporter.exportTransactions(
                        transactions: self.transactionsViewModel?.allTransactions ?? [],
                        accounts: self.accountsViewModel?.accounts ?? []
                    )

                    let fileName = "transactions_export_\(DateFormatters.fileNameFormatter.string(from: Date())).csv"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

                    try csvString.write(to: tempURL, atomically: true, encoding: .utf8)

                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

#### ✨ Enhanced AppSettings Model

```swift
class AppSettings: ObservableObject, Codable {
    @Published var baseCurrency: String
    @Published var wallpaperImageName: String?

    // NEW: Additional settings
    @Published var appLanguage: String
    @Published var notificationsEnabled: Bool
    @Published var biometricAuthEnabled: Bool
    @Published var autoBackupEnabled: Bool
    @Published var lastBackupDate: Date?

    // NEW: Defaults
    static let defaultCurrency = "KZT"
    static let defaultLanguage = "en"
    static let availableCurrencies = ["KZT", "USD", "EUR", "RUB", "GBP", "CNY", "JPY"]
    static let availableLanguages = ["en", "ru"]

    // NEW: Validation
    var isValid: Bool {
        AppSettings.availableCurrencies.contains(baseCurrency) &&
        AppSettings.availableLanguages.contains(appLanguage)
    }

    // NEW: Factory methods
    static func makeDefault() -> AppSettings {
        AppSettings(
            baseCurrency: defaultCurrency,
            wallpaperImageName: nil,
            appLanguage: defaultLanguage,
            notificationsEnabled: true,
            biometricAuthEnabled: false,
            autoBackupEnabled: false
        )
    }
}
```

### 2.3 Рефакторенный SettingsView

```swift
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            generalSection
            dataManagementSection
            exportImportSection
            dangerZoneSection
        }
        .navigationTitle(String(localized: "settings.title"))
        .overlay(loadingOverlay)
        .alert(errorAlert)
        .toast(successToast)
    }

    private var generalSection: some View {
        Section(header: Text(String(localized: "settings.general"))) {
            CurrencySelectorRow(
                currentCurrency: viewModel.settings.baseCurrency,
                onSelect: { currency in
                    Task {
                        try? await viewModel.updateBaseCurrency(currency)
                    }
                }
            )

            WallpaperRow(
                currentWallpaper: viewModel.currentWallpaper,
                onSelect: { image in
                    Task {
                        try? await viewModel.selectWallpaper(image)
                    }
                },
                onRemove: {
                    Task {
                        try? await viewModel.removeWallpaper()
                    }
                }
            )
        }
    }

    // Props + Callbacks pattern — нет прямых ViewModel зависимостей!
}
```

---

## 3. План рефакторинга по фазам

### Phase 1: Foundation (Priority 0 — Критично)

**Цель:** Создать базовую инфраструктуру для Settings

#### Задачи:

1. **Создать SettingsViewModel** (NEW)
   - Файл: `ViewModels/SettingsViewModel.swift`
   - LOC: ~250
   - Все settings операции через ViewModel

2. **Создать Settings Services** (NEW)
   ```
   Services/Settings/
   ├── SettingsStorageService.swift (~100 LOC)
   ├── SettingsValidationService.swift (~80 LOC)
   ├── WallpaperManagementService.swift (~150 LOC)
   ├── DataResetCoordinator.swift (~100 LOC)
   └── ExportCoordinator.swift (~80 LOC)
   ```

3. **Создать Protocols** (NEW)
   ```
   Protocols/Settings/
   ├── SettingsStorageServiceProtocol.swift
   ├── SettingsValidationServiceProtocol.swift
   ├── WallpaperManagementServiceProtocol.swift
   ├── DataResetCoordinatorProtocol.swift
   └── ExportCoordinatorProtocol.swift
   ```

4. **Enhanced AppSettings Model**
   - Расширить до полноценной модели
   - Добавить валидацию
   - Добавить factory methods

5. **Добавить локализацию**
   - 20 новых ключей для ошибок
   - Исправить 3 hardcoded русских строки

**Метрики Phase 1:**
- Код добавлен: ~760 LOC (reusable services)
- Код изменен: AppSettings.swift (63 → ~120 LOC)
- Protocols: 5 новых
- Локализация: +40 keys (EN + RU)

---

### Phase 2: CSV Migration (Priority 1 — Высокий)

**Цель:** Завершить миграцию на CSVImportCoordinator

#### Задачи:

1. **Удалить CSVImportService.swift** (DEPRECATED)
   - Удалить файл (799 LOC)
   - Обновить SettingsView для использования CSVImportCoordinator

2. **Интегрировать CSVImportCoordinator в SettingsViewModel**
   ```swift
   func importCSV(from url: URL) async throws -> ImportResult {
       let file = try CSVImporter.parseCSV(from: url)
       // Show preview sheet
       await showPreview(file)
       // After mapping, import
       let result = try await importCoordinator.importTransactions(...)
       return result
   }
   ```

3. **Оптимизировать ExportCoordinator**
   - Асинхронный экспорт (background task)
   - Progress tracking
   - Cancel support

4. **Создать ImportFlowCoordinator** (NEW)
   ```swift
   @MainActor
   class ImportFlowCoordinator: ObservableObject {
       @Published var currentStep: ImportStep = .selectFile
       @Published var csvFile: CSVFile?
       @Published var columnMapping: CSVColumnMapping?
       @Published var entityMapping: EntityMapping?

       enum ImportStep {
           case selectFile
           case preview
           case columnMapping
           case entityMapping
           case importing
           case result
       }
   }
   ```

**Метрики Phase 2:**
- Код удален: -799 LOC (CSVImportService)
- Код добавлен: ~200 LOC (ImportFlowCoordinator)
- Net: -599 LOC

---

### Phase 3: UI Refactoring (Priority 2 — Средний)

**Цель:** Декомпозировать SettingsView, применить Props + Callbacks

#### Задачи:

1. **Создать специализированные Row компоненты**
   ```
   Views/Settings/Rows/
   ├── CurrencySelectorRow.swift (~50 LOC)
   ├── WallpaperRow.swift (~80 LOC)
   ├── DataManagementRow.swift (~40 LOC)
   ├── ExportImportRow.swift (~60 LOC)
   └── DangerZoneRow.swift (~50 LOC)
   ```

2. **Создать Section компоненты**
   ```
   Views/Settings/Sections/
   ├── GeneralSection.swift (~80 LOC)
   ├── DataManagementSection.swift (~60 LOC)
   ├── ExportImportSection.swift (~100 LOC)
   └── DangerZoneSection.swift (~80 LOC)
   ```

3. **Рефакторить SettingsView**
   - 419 LOC → ~150 LOC (-64%)
   - Удалить 5 ViewModel зависимостей
   - Оставить только SettingsViewModel

4. **Применить AppTheme tokens**
   - Заменить все hardcoded spacing на AppSpacing
   - Заменить все hardcoded colors на semantic colors
   - Использовать `.glassCardStyle()` для карточек

**Метрики Phase 3:**
- SettingsView: 419 → ~150 LOC (-64%)
- Новые компоненты: 10 файлов (~600 LOC reusable)
- ViewModel deps: 5 → 1 (-80%)

---

### Phase 4: Performance & Caching (Priority 3 — Низкий)

**Цель:** Оптимизация производительности

#### Задачи:

1. **LRU Cache для обоев**
   ```swift
   private lazy var wallpaperCache: LRUCache<String, UIImage> = {
       LRUCache(capacity: 10) // Last 10 wallpapers
   }()
   ```

2. **Recent Currencies Cache**
   ```swift
   @AppStorage("recentCurrencies") private var recentCurrencies: [String] = []

   func updateBaseCurrency(_ currency: String) async throws {
       // Add to recent (max 5)
       recentCurrencies.insert(currency, at: 0)
       if recentCurrencies.count > 5 {
           recentCurrencies.removeLast()
       }
   }
   ```

3. **Async Export с Progress**
   ```swift
   func exportAllData() async throws -> URL {
       await MainActor.run {
           exportProgress = 0
       }

       // Export in chunks with progress updates
       let chunks = allTransactions.chunked(into: 1000)
       for (index, chunk) in chunks.enumerated() {
           // Export chunk
           await MainActor.run {
               exportProgress = Double(index) / Double(chunks.count)
           }
       }
   }
   ```

4. **Wallpaper Compression Optimization**
   - Adaptive quality (0.5–0.9) based on image size
   - Max resolution (2048x2048)
   - Thumbnail generation (256x256) for previews

**Метрики Phase 4:**
- Export speed: 19K transactions → ~2-3 sec (с progress)
- Memory: -50% для wallpaper management (LRU)
- Disk usage: -30% для wallpapers (compression)

---

### Phase 5: Enhanced Features (Priority 4 — Optional)

**Цель:** Расширенные возможности настроек

#### Задачи:

1. **Settings Search**
   ```swift
   @State private var searchQuery: String = ""

   var filteredSections: [SettingsSection] {
       sections.filter { section in
           section.matches(query: searchQuery)
       }
   }
   ```

2. **Wallpaper History**
   ```swift
   struct WallpaperHistoryItem: Identifiable {
       let id: String
       let fileName: String
       let thumbnail: UIImage
       let createdAt: Date
   }

   // Quick restore previous wallpapers
   ```

3. **Export/Import Presets**
   ```swift
   struct ExportPreset {
       let name: String
       let dateRange: DateRange
       let accounts: [String]
       let includeCategories: Bool
   }
   ```

4. **Backup/Restore Settings**
   ```swift
   func backupSettings() async throws -> URL
   func restoreSettings(from url: URL) async throws
   ```

**Метрики Phase 5:**
- Новые features: 4
- Код добавлен: ~400 LOC

---

## 4. Метрики рефакторинга (сводка)

### До рефакторинга

| Компонент | LOC | Issues |
|-----------|-----|--------|
| SettingsView | 419 | 5 VM deps, hardcoded strings |
| AppSettings | 63 | Минимальная модель |
| CSVImportService | 799 | DEPRECATED монолит |
| No SettingsViewModel | 0 | Нет координации |
| No Settings Services | 0 | Logic in View |
| **Total** | **1,281** | **Multiple violations** |

### После Phase 1-3 (Required)

| Компонент | LOC | Change |
|-----------|-----|--------|
| SettingsView | ~150 | -269 (-64%) |
| SettingsViewModel | ~250 | NEW |
| AppSettings | ~120 | +57 (+90%) |
| Settings Services | ~510 | NEW (5 services) |
| Settings Protocols | ~100 | NEW (5 protocols) |
| UI Components | ~600 | NEW (10 components) |
| CSVImportService | 0 | DELETED (-799) |
| **Total** | **1,730** | **+449 LOC, but modular** |

### После Phase 4-5 (Optional)

| Feature | LOC | Benefit |
|---------|-----|---------|
| LRU Caching | ~100 | -50% memory |
| Async Export | ~80 | Progress tracking |
| Enhanced Features | ~400 | UX improvements |
| **Total Optional** | **~580** | **Quality of life** |

### Качественные улучшения

| Метрика | До | После | Улучшение |
|---------|-----|-------|-----------|
| SRP Violations | 3 | 0 | 100% |
| ViewModel Deps in View | 5 | 1 | -80% |
| Hardcoded Strings | 3 | 0 | 100% |
| Error Handling | Poor | Comprehensive | ∞ |
| Testability | 0% | 90% | ∞ |
| Code Duplication | High | Low | -70% |
| Performance | Sync | Async + LRU | 3-5x |

---

## 5. Детальный план локализации

### 5.1 Исправить существующие hardcoded строки

```swift
// ❌ БЫЛО (SettingsView.swift:48)
.alert("Пересчитать балансы?", isPresented: ...)

// ✅ ДОЛЖНО БЫТЬ
.alert(String(localized: "alert.recalculateBalances.title"), isPresented: ...)
```

### 5.2 Новые локализационные ключи

**Settings Errors (10 keys):**
```
// English
"error.settings.invalidCurrency" = "Invalid currency: %@";
"error.settings.wallpaperNotFound" = "Wallpaper file not found: %@";
"error.wallpaper.compressionFailed" = "Failed to compress wallpaper image";
"error.wallpaper.fileTooLarge" = "Wallpaper file is too large (max 10 MB)";
"error.wallpaper.insufficientSpace" = "Insufficient disk space";
"error.wallpaper.fileNotFound" = "Wallpaper file not found";
"error.wallpaper.corruptedFile" = "Wallpaper file is corrupted";
"error.export.failed" = "Failed to export data";
"error.import.failed" = "Failed to import data";
"error.reset.failed" = "Failed to reset data";

// Russian
"error.settings.invalidCurrency" = "Недопустимая валюта: %@";
"error.settings.wallpaperNotFound" = "Файл обоев не найден: %@";
"error.wallpaper.compressionFailed" = "Не удалось сжать изображение обоев";
"error.wallpaper.fileTooLarge" = "Файл обоев слишком большой (макс 10 МБ)";
"error.wallpaper.insufficientSpace" = "Недостаточно места на диске";
"error.wallpaper.fileNotFound" = "Файл обоев не найден";
"error.wallpaper.corruptedFile" = "Файл обоев поврежден";
"error.export.failed" = "Не удалось экспортировать данные";
"error.import.failed" = "Не удалось импортировать данные";
"error.reset.failed" = "Не удалось сбросить данные";
```

**Alert Titles (10 keys):**
```
// English
"alert.recalculateBalances.title" = "Recalculate Balances?";
"alert.recalculateBalances.message" = "This will recalculate all account balances from scratch based on transactions. Use this if balances are displayed incorrectly.";
"alert.recalculateBalances.confirm" = "Recalculate";
"alert.selectWallpaper.title" = "Select Wallpaper";
"alert.removeWallpaper.title" = "Remove Wallpaper?";
"alert.removeWallpaper.message" = "This will remove the current wallpaper from the home screen";
"alert.exportSuccess.title" = "Export Successful";
"alert.exportSuccess.message" = "Data exported to %@";
"alert.importSuccess.title" = "Import Successful";
"alert.importSuccess.message" = "Imported %d transactions";

// Russian
"alert.recalculateBalances.title" = "Пересчитать балансы?";
"alert.recalculateBalances.message" = "Это пересчитает балансы всех счетов с нуля на основе транзакций. Используйте это, если балансы отображаются неправильно.";
"alert.recalculateBalances.confirm" = "Пересчитать";
"alert.selectWallpaper.title" = "Выбрать обои";
"alert.removeWallpaper.title" = "Удалить обои?";
"alert.removeWallpaper.message" = "Это удалит текущие обои с главного экрана";
"alert.exportSuccess.title" = "Экспорт завершен";
"alert.exportSuccess.message" = "Данные экспортированы в %@";
"alert.importSuccess.title" = "Импорт завершен";
"alert.importSuccess.message" = "Импортировано %d транзакций";
```

**Settings Labels (10 keys):**
```
// English
"settings.recalculateBalances" = "Recalculate Account Balances";
"settings.wallpaperHistory" = "Wallpaper History";
"settings.recentCurrencies" = "Recent Currencies";
"settings.exportProgress" = "Exporting... %d%%";
"settings.importProgress" = "Importing... %d%%";
"settings.notifications" = "Notifications";
"settings.biometricAuth" = "Biometric Authentication";
"settings.autoBackup" = "Automatic Backup";
"settings.lastBackup" = "Last Backup";
"settings.language" = "Language";

// Russian
"settings.recalculateBalances" = "Пересчитать балансы счетов";
"settings.wallpaperHistory" = "История обоев";
"settings.recentCurrencies" = "Недавние валюты";
"settings.exportProgress" = "Экспорт... %d%%";
"settings.importProgress" = "Импорт... %d%%";
"settings.notifications" = "Уведомления";
"settings.biometricAuth" = "Биометрическая аутентификация";
"settings.autoBackup" = "Автоматический бэкап";
"settings.lastBackup" = "Последний бэкап";
"settings.language" = "Язык";
```

**Total:** 30 новых ключей × 2 языка = **60 строк локализации**

---

## 6. Соблюдение дизайн-системы (AppTheme)

### 6.1 Текущие нарушения

```swift
// ❌ БЫЛО (SettingsView — hardcoded values)
.padding(16)           // Должно быть AppSpacing.lg
.padding(.vertical, 8) // Должно быть AppSpacing.sm
.cornerRadius(10)      // Должно быть AppRadius.md
```

### 6.2 Правильное использование AppTheme

```swift
// ✅ ДОЛЖНО БЫТЬ
.screenPadding()                    // AppSpacing.lg horizontal
.padding(.vertical, AppSpacing.sm)
.glassCardStyle()                   // Standard card style
.buttonStyle(.bounce)               // Standard button behavior

// Row spacing
VStack(spacing: AppSpacing.listRowSpacing) { ... }

// Icon + Text
HStack(spacing: AppSpacing.iconText) {
    Image(systemName: "gear")
        .font(.system(size: AppIconSize.md))
    Text("Settings")
}
```

### 6.3 Специализированные view modifiers для Settings

```swift
// NEW: Settings-specific modifiers
extension View {
    func settingsRowStyle() -> some View {
        self
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.lg)
    }

    func settingsSectionStyle() -> some View {
        self
            .padding(.vertical, AppSpacing.md)
    }

    func dangerZoneStyle() -> some View {
        self
            .foregroundColor(.red)
            .padding(.vertical, AppSpacing.sm)
    }
}
```

---

## 7. Удаление неиспользуемого кода

### 7.1 Файлы для удаления

```
✂️ DELETE:
Services/CSVImportService.swift (799 LOC) — DEPRECATED, заменен CSVImportCoordinator
```

### 7.2 Неиспользуемые методы

```swift
// SettingsView.swift
// Проверить использование следующих методов:
private func handleCSVImport(url: URL) async
private func performImport(csvFile: CSVFile, mapping: CSVColumnMapping) async

// Если используются только в SettingsView, оставить
// Если дублируются в CSVImportCoordinator, удалить
```

### 7.3 Legacy code patterns

```swift
// ❌ Удалить manual objectWillChange.send()
accountsViewModel.objectWillChange.send()
transactionsViewModel.objectWillChange.send()

// ✅ SwiftUI автоматически отслеживает @Published changes
```

---

## 8. План тестирования

### 8.1 Unit Tests (NEW)

```swift
// Tests/SettingsViewModelTests.swift
final class SettingsViewModelTests: XCTestCase {
    func testUpdateBaseCurrency() async throws
    func testSelectWallpaper_ValidImage() async throws
    func testSelectWallpaper_ImageTooLarge_ThrowsError() async throws
    func testRemoveWallpaper() async throws
    func testExportData() async throws
    func testImportCSV() async throws
    func testResetAllData() async throws
}

// Tests/WallpaperManagementServiceTests.swift
final class WallpaperManagementServiceTests: XCTestCase {
    func testSaveWallpaper_Success()
    func testSaveWallpaper_FileTooLarge_ThrowsError()
    func testSaveWallpaper_InsufficientSpace_ThrowsError()
    func testLoadWallpaper_FromCache()
    func testLoadWallpaper_FromDisk()
    func testLoadWallpaper_FileNotFound_ThrowsError()
}
```

### 8.2 Integration Tests

```swift
// Tests/SettingsIntegrationTests.swift
final class SettingsIntegrationTests: XCTestCase {
    func testFullCSVImportFlow()
    func testFullExportFlow()
    func testWallpaperLifecycle()
    func testDataResetFlow()
}
```

### 8.3 UI Tests

```swift
// UITests/SettingsUITests.swift
final class SettingsUITests: XCTestCase {
    func testChangeCurrency()
    func testSelectWallpaper()
    func testRemoveWallpaper()
    func testExportData()
    func testImportCSV()
    func testResetData()
}
```

---

## 9. Риски и митигация

### 9.1 Критические риски

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| Breaking existing CSV import | Средняя | Высокое | Parallel implementation, feature flag |
| Data loss при reset | Низкая | Критическое | Double confirmation, backup before reset |
| Wallpaper file corruption | Средняя | Среднее | Validation, fallback to default |
| Performance degradation | Низкая | Среднее | Async operations, progress tracking |

### 9.2 План отката

```swift
// Feature Flag для постепенного rollout
@AppStorage("useNewSettingsArchitecture")
private var useNewArchitecture: Bool = false

if useNewArchitecture {
    // New SettingsViewModel-based flow
} else {
    // Legacy direct ViewModel access
}
```

---

## 10. Timeline и приоритеты

### Critical Path (Required)

| Phase | Duration | Effort | Priority |
|-------|----------|--------|----------|
| Phase 1: Foundation | 3-4 days | High | P0 |
| Phase 2: CSV Migration | 2-3 days | Medium | P1 |
| Phase 3: UI Refactoring | 2-3 days | Medium | P2 |
| **Total Critical** | **7-10 days** | **~25 hours** | **Must Have** |

### Optional Enhancements

| Phase | Duration | Effort | Priority |
|-------|----------|--------|----------|
| Phase 4: Performance | 1-2 days | Low | P3 |
| Phase 5: Enhanced Features | 2-3 days | Medium | P4 |
| **Total Optional** | **3-5 days** | **~15 hours** | **Nice to Have** |

---

## 11. Success Criteria

### Architectural Metrics

- ✅ SettingsView LOC: 419 → ~150 (-64%)
- ✅ ViewModel dependencies in View: 5 → 1 (-80%)
- ✅ SRP violations: 3 → 0 (100%)
- ✅ Deprecated code: CSVImportService removed (-799 LOC)
- ✅ Test coverage: 0% → 80%+ (NEW)

### Code Quality Metrics

- ✅ Hardcoded strings: 3 → 0 (100% localized)
- ✅ Error handling: Poor → Comprehensive (NEW)
- ✅ Protocols created: 5 (testability)
- ✅ Services created: 5 (modularity)
- ✅ UI Components: 10 reusable (Props + Callbacks)

### Performance Metrics

- ✅ Export time (19K txns): Blocking → 2-3 sec async
- ✅ Wallpaper memory: -50% (LRU cache)
- ✅ Import flow: Monolithic → Modular coordinator

### User Experience Metrics

- ✅ Settings response time: Instant (async ops)
- ✅ Error messages: Localized + actionable
- ✅ Progress tracking: Export/Import
- ✅ Undo support: Wallpaper history

---

## 12. Рекомендации по реализации

### Best Practices

1. **Implement Phase by Phase**
   - НЕ пытаться сделать все сразу
   - Завершить Phase 1 → Test → Commit
   - Завершить Phase 2 → Test → Commit
   - И так далее

2. **Feature Flag для рискованных изменений**
   ```swift
   @AppStorage("useNewCSVImport") var useNewImport = false
   ```

3. **Extensive Testing**
   - Unit tests для всех сервисов
   - Integration tests для флоу
   - Manual testing чек-лист

4. **Code Review Checklist**
   - ✅ SRP соблюдается?
   - ✅ Props + Callbacks используются?
   - ✅ AppTheme tokens применены?
   - ✅ Все строки локализованы?
   - ✅ Error handling корректный?
   - ✅ LRU eviction настроен?

5. **Documentation**
   - Update project-bible.md
   - Update component-inventory.md
   - Create SETTINGS_ARCHITECTURE.md (NEW)

---

## 13. Заключение

### Summary

Раздел **Settings** требует **полного рефакторинга** для соответствия архитектурным принципам проекта:

**Основные проблемы:**
1. ❌ SettingsView нарушает SRP (5 ViewModel зависимостей)
2. ❌ Нет SettingsViewModel (logic в View)
3. ❌ CSVImportService — deprecated монолит (799 LOC)
4. ❌ Hardcoded русские строки (3)
5. ❌ Нет error handling
6. ❌ Синхронные операции (блокируют UI)

**Решение:**
- ✅ Создать SettingsViewModel + 5 специализированных сервисов
- ✅ Применить Protocol-Oriented Design
- ✅ Декомпозировать UI (Props + Callbacks pattern)
- ✅ Завершить CSV миграцию (удалить deprecated код)
- ✅ Добавить LRU кэширование
- ✅ Полная локализация (60 строк)
- ✅ Async operations с progress tracking

**Результат:**
- Модульная, тестируемая архитектура
- -64% LOC в SettingsView
- -799 LOC deprecated кода
- +80% test coverage
- 3-5x производительность

### Next Steps

1. **Approve Plan** — Review и утверждение плана
2. **Start Phase 1** — Создание foundation (ViewModel + Services)
3. **Test & Iterate** — После каждой фазы
4. **Document** — Обновить project-bible.md

---

**Конец документа**
**Статус:** Ready for Implementation ✅
**Estimated Effort:** 7-10 days (Critical Path) + 3-5 days (Optional)
**ROI:** High — Architecture compliance, maintainability, performance
