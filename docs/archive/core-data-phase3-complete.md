# Core Data - Фаза 3: RecurringOccurrences ✅

**Дата**: 23 января 2026
**Статус**: ✅ Реализовано и готово к тестированию
**Версия миграции**: v5

---

## 📊 Что реализовано

### 1. RecurringOccurrenceEntity ✅

**Файлы**:
- `RecurringOccurrenceEntity+CoreDataClass.swift` - класс Entity с методами конвертации
- `RecurringOccurrenceEntity+CoreDataProperties.swift` - свойства Entity

**Структура Entity**:
```swift
@NSManaged public var id: String?
@NSManaged public var seriesId: String?
@NSManaged public var occurrenceDate: String?
@NSManaged public var transactionId: String?
@NSManaged public var series: RecurringSeriesEntity?
```

**Методы конвертации**:
- ✅ `toRecurringOccurrence()` - Entity → Domain Model
- ✅ `from(_ occurrence:context:)` - Domain Model → Entity

**Relationships**:
- ✅ `series` - связь с RecurringSeriesEntity (many-to-one)
- ✅ Обратная связь `occurrences` добавлена в RecurringSeriesEntity (one-to-many)

---

### 2. CoreDataRepository - RecurringOccurrences ✅

**Файл**: `Tenra/Services/CoreDataRepository.swift`

**Реализованные методы**:

#### loadRecurringOccurrences()
```swift
func loadRecurringOccurrences() -> [RecurringOccurrence]
```
- ✅ Загрузка из Core Data
- ✅ Сортировка по дате (descending)
- ✅ Fallback на UserDefaults при ошибках
- ✅ Логирование и профилирование

#### saveRecurringOccurrences()
```swift
func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence])
```
- ✅ Асинхронное сохранение в background context
- ✅ Batch updates (update existing, create new, delete removed)
- ✅ Установка relationship с RecurringSeriesEntity
- ✅ Профилирование производительности

---

### 3. DataMigrationService - миграция RecurringOccurrences ✅

**Файл**: `Tenra/Services/DataMigrationService.swift`

**Изменения**:

#### 1. Обновлена версия миграции
```swift
private let migrationCompletedKey = "coreDataMigrationCompleted_v5"
```

#### 2. Добавлен шаг миграции
```swift
// Step 9: Migrate Recurring Occurrences
try await migrateRecurringOccurrences()
```

#### 3. Реализован метод migrateRecurringOccurrences()
```swift
private func migrateRecurringOccurrences() async throws
```
- ✅ Загрузка из UserDefaults
- ✅ Создание Entity в Core Data
- ✅ Установка relationship с RecurringSeriesEntity
- ✅ Batch сохранение
- ✅ Подробное логирование

#### 4. Обновлён clearAllCoreData()
```swift
let entityNames = [
    // ... existing entities ...
    "RecurringOccurrenceEntity"  // ← добавлено
]
```

---

## 🔄 Relationships

### RecurringSeriesEntity ↔ RecurringOccurrenceEntity

#### RecurringSeriesEntity (one-to-many)
```swift
@NSManaged public var occurrences: NSSet?

// Generated accessors
func addToOccurrences(_ value: RecurringOccurrenceEntity)
func removeFromOccurrences(_ value: RecurringOccurrenceEntity)
func addToOccurrences(_ values: NSSet)
func removeFromOccurrences(_ values: NSSet)
```

#### RecurringOccurrenceEntity (many-to-one)
```swift
@NSManaged public var series: RecurringSeriesEntity?
```

**Delete Rule**: Nullify (при удалении series, occurrence.series становится nil)

---

## 📈 Текущее состояние миграции

### ✅ Полностью в Core Data

| Entity | Status | Migration | Relationships |
|--------|--------|-----------|---------------|
| **TransactionEntity** | ✅ | v2+ | account, targetAccount, recurringSeries |
| **AccountEntity** | ✅ | v2+ | transactions, recurringSeries, deposits |
| **RecurringSeriesEntity** | ✅ | v4+ | account, transactions, **occurrences** |
| **CustomCategoryEntity** | ✅ | v4+ | - |
| **CategoryRuleEntity** | ✅ | v4+ | - |
| **SubcategoryEntity** | ✅ | v4+ | - |
| **CategorySubcategoryLinkEntity** | ✅ | v4+ | - |
| **TransactionSubcategoryLinkEntity** | ✅ | v4+ | - |
| **RecurringOccurrenceEntity** | ✅ | **v5** | **series** |

### ⚠️ Ещё в UserDefaults

- `AppSettings` (baseCurrency, wallpaperImageName)
- `TimeFilter` (currentFilter)
- Статус миграции (`coreDataMigrationCompleted_v5`)

---

## 🧪 Тестирование

### Шаг 1: Запуск миграции

При первом запуске после обновления вы увидите:

```
🔄 [MIGRATION] Starting data migration from UserDefaults to Core Data
📦 [MIGRATION] Migrating accounts...
✅ [MIGRATION] Saved 8 accounts to Core Data
📦 [MIGRATION] Migrating transactions...
✅ [MIGRATION] All transactions migrated successfully
📦 [MIGRATION] Migrating recurring series...
✅ [MIGRATION] Saved N recurring series to Core Data
📦 [MIGRATION] Migrating custom categories...
✅ [MIGRATION] Saved 22 categories to Core Data
📦 [MIGRATION] Migrating category rules...
✅ [MIGRATION] Saved N category rules to Core Data
📦 [MIGRATION] Migrating subcategories...
✅ [MIGRATION] Saved 60 subcategories to Core Data
📦 [MIGRATION] Migrating category-subcategory links...
✅ [MIGRATION] Saved N category-subcategory links to Core Data
📦 [MIGRATION] Migrating transaction-subcategory links...
✅ [MIGRATION] Saved N transaction-subcategory links to Core Data
📦 [MIGRATION] Migrating recurring occurrences...
✅ [MIGRATION] Saved N recurring occurrences to Core Data
✅ [MIGRATION] Data migration completed successfully
```

### Шаг 2: Проверка данных

```
📂 [CORE_DATA_REPO] Loading recurring occurrences from Core Data
✅ [CORE_DATA_REPO] Loaded N recurring occurrences
```

### Шаг 3: Сохранение данных

```
💾 [CORE_DATA_REPO] Saving N recurring occurrences to Core Data
✅ [CORE_DATA_REPO] Recurring occurrences saved successfully
```

---

## ⚠️ Важные замечания

### 1. Core Data Model (.xcdatamodeld)

**ВАЖНО**: Необходимо добавить RecurringOccurrenceEntity в Core Data модель через Xcode:

1. Открыть `Tenra.xcdatamodeld` в Xcode
2. Добавить новую Entity "RecurringOccurrenceEntity"
3. Добавить attributes:
   - `id` (String, optional)
   - `seriesId` (String, optional)
   - `occurrenceDate` (String, optional)
   - `transactionId` (String, optional)
4. Добавить relationship:
   - `series` → RecurringSeriesEntity (optional, to-one, delete rule: Nullify)
5. В RecurringSeriesEntity добавить обратный relationship:
   - `occurrences` → RecurringOccurrenceEntity (optional, to-many, delete rule: Nullify)

### 2. Безопасность данных

- ✅ Миграция **НЕ** удаляет данные из UserDefaults
- ✅ Fallback на UserDefaults при ошибках Core Data
- ✅ Статус миграции сохраняется в UserDefaults (v5)

### 3. Производительность

- ✅ Асинхронное сохранение в background context
- ✅ Batch updates для эффективности
- ✅ Сортировка по дате для быстрого доступа
- ✅ Relationships для целостности данных

---

## 🎯 Следующие шаги

### Немедленные действия

1. **Добавить RecurringOccurrenceEntity в .xcdatamodeld** (через Xcode)
2. Запустить приложение
3. Проверить миграцию в консоли
4. Проверить работу recurring occurrences

### Опциональные улучшения

#### 1. Удалить fallback на UserDefaults (Фаза 4)

Сейчас все методы имеют fallback:
```swift
return userDefaultsRepository.loadRecurringOccurrences()
```

Можно:
- Оставить fallback только для критичных ошибок
- Убрать fallback полностью (если уверены в стабильности)

#### 2. Мигрировать AppSettings в Core Data

Создать AppSettingsEntity для хранения:
- baseCurrency
- wallpaperImageName
- currentTimeFilter (preset, startDate, endDate)

#### 3. Оптимизация

- Добавить индексы для часто используемых полей
- Использовать NSFetchedResultsController для автоматического обновления UI
- Добавить CoreData CloudKit sync для синхронизации между устройствами

---

## 📋 Checklist

### Реализация
- [x] Создать RecurringOccurrenceEntity+CoreDataClass.swift
- [x] Создать RecurringOccurrenceEntity+CoreDataProperties.swift
- [x] Добавить loadRecurringOccurrences() в CoreDataRepository
- [x] Добавить saveRecurringOccurrences() в CoreDataRepository
- [x] Добавить migrateRecurringOccurrences() в DataMigrationService
- [x] Обновить clearAllCoreData()
- [x] Добавить relationship в RecurringSeriesEntity
- [x] Обновить версию миграции на v5

### Core Data Model (требуется в Xcode)
- [ ] Добавить RecurringOccurrenceEntity в .xcdatamodeld
- [ ] Настроить attributes
- [ ] Настроить relationships
- [ ] Проверить delete rules

### Тестирование
- [ ] Запустить приложение
- [ ] Проверить миграцию v5
- [ ] Проверить загрузку recurring occurrences
- [ ] Проверить сохранение recurring occurrences
- [ ] Проверить relationships с RecurringSeries
- [ ] Проверить удаление (cascade delete)

---

## 🐛 Troubleshooting

### Ошибка: "Entity not found"

```
❌ [CORE_DATA_REPO] Error loading recurring occurrences: Entity not found
```

**Причина**: RecurringOccurrenceEntity не добавлена в .xcdatamodeld

**Решение**: Добавить Entity в Core Data модель через Xcode

### Ошибка: "No relationship found"

```
❌ [CORE_DATA_REPO] Error: No relationship 'series' found
```

**Причина**: Relationship не настроен в .xcdatamodeld

**Решение**: Добавить relationship в Core Data модель

### Миграция не запускается

```
✅ [MIGRATION] Data already migrated, skipping
```

**Причина**: Статус миграции v5 уже установлен

**Решение**: Сбросить статус для тестирования:
```swift
UserDefaults.standard.removeObject(forKey: "coreDataMigrationCompleted_v5")
```

---

## 📚 Связанные документы

- [core-data-full-migration-plan.md](core-data-full-migration-plan.md) - Общий план миграции
- [core-data-phase2-complete.md](core-data-phase2-complete.md) - Фаза 2
- [core-data-migration-complete.md](core-data-migration-complete.md) - Миграция v2
- [CoreDataRepository.swift](./Tenra/Services/CoreDataRepository.swift) - Repository
- [DataMigrationService.swift](./Tenra/Services/DataMigrationService.swift) - Migration

---

## ✅ Итог

**Фаза 3 завершена!** Реализованы:

1. ✅ RecurringOccurrenceEntity с полной поддержкой Core Data
2. ✅ Методы load/save в CoreDataRepository
3. ✅ Миграция в DataMigrationService (v5)
4. ✅ Relationships с RecurringSeriesEntity
5. ✅ Fallback на UserDefaults при ошибках
6. ✅ Полная обратная совместимость

**Следующий шаг**: Добавить RecurringOccurrenceEntity в .xcdatamodeld через Xcode и протестировать!

---

## 📊 Статистика

| Показатель | Значение |
|-----------|----------|
| Новые файлы | 2 |
| Изменённые файлы | 3 |
| Строк кода добавлено | ~150 |
| Версия миграции | v5 |
| Entities в Core Data | 9 |
| Статус | ✅ Готово |
