# План полного переезда на Core Data

**Дата**: 23 января 2026
**Статус**: 📋 План готов к выполнению
**Цель**: Полностью отказаться от UserDefaults, перенести все данные в Core Data

---

## 📊 Текущее состояние

### ✅ Уже в Core Data
- **TransactionEntity** - 921 транзакций (полностью мигрировано)
- **AccountEntity** - 8 счетов (полностью мигрировано)
- **RecurringSeriesEntity** - модель создана, миграция пока через fallback
- **CustomCategoryEntity** - модель создана, миграция пока через fallback
- **CategoryRuleEntity** - модель создана, миграция пока через fallback
- **SubcategoryEntity** - модель создана, миграция пока через fallback

### ⚠️ Ещё в UserDefaults (требуется миграция)

#### 1. **Основные сущности** (в CoreDataRepository через fallback)
- `CustomCategories` - ~22 категории
- `CategoryRules` - правила автокатегоризации
- `RecurringSeries` - периодические операции
- `Subcategories` - ~60 подкатегорий

#### 2. **Связующие таблицы**
- `CategorySubcategoryLinks` - связи категория → подкатегория
- `TransactionSubcategoryLinks` - связи транзакция → подкатегория
- `RecurringOccurrences` - случаи выполнения периодических операций

#### 3. **Настройки приложения**
- `AppSettings` - валюта, обои (AppSettings.swift)
- `TimeFilter` - текущий фильтр времени (TimeFilterManager.swift)

#### 4. **Системные данные**
- `coreDataMigrationCompleted_v1` - статус миграции
- `coreDataMigrationCompleted_v2` - статус миграции v2

---

## 🎯 План миграции (4 фазы)

### Фаза 1: Миграция основных сущностей ✅ (частично)

**Цель**: Перенести Categories, Rules, RecurringSeries в Core Data

**Текущий статус**: Entity созданы, но используется fallback

**Что нужно сделать**:

1. **Обновить CoreDataRepository**
   - Удалить fallback на UserDefaults для:
     - `loadCategories()` / `saveCategories()`
     - `loadCategoryRules()` / `saveCategoryRules()`
     - `loadRecurringSeries()` / `saveRecurringSeries()`
     - `loadSubcategories()` / `saveSubcategories()`
   - Реализовать полноценные методы с Core Data

2. **Обновить DataMigrationService**
   - Убедиться, что миграция полностью работает для всех сущностей
   - Проверить установку relationships

3. **Тестирование**
   - Запустить миграцию
   - Проверить целостность данных
   - Сравнить количество записей

**Файлы**:
- `Tenra/Services/CoreDataRepository.swift`
- `Tenra/Services/DataMigrationService.swift`

**Время**: ~1-2 часа

---

### Фаза 2: Связующие таблицы (Links)

**Цель**: Перенести CategorySubcategoryLinks и TransactionSubcategoryLinks в Core Data

**Проблема**: Сейчас это отдельные массивы связей

**Решение**: Два варианта

#### Вариант A: Использовать relationships (рекомендуется)

**Преимущества**:
- Нативный Core Data подход
- Автоматический каскад удалений
- Более эффективные запросы
- Меньше кода

**Изменения**:

1. **Обновить CustomCategoryEntity**
   ```swift
   // Добавить relationship
   subcategories: [SubcategoryEntity] (to-many)
   ```

2. **Обновить TransactionEntity**
   ```swift
   // Добавить relationship
   subcategories: [SubcategoryEntity] (to-many)
   ```

3. **Обновить SubcategoryEntity**
   ```swift
   // Добавить inverse relationships
   categories: [CustomCategoryEntity] (to-many, inverse)
   transactions: [TransactionEntity] (to-many, inverse)
   ```

4. **Миграция данных**
   - Загрузить Links из UserDefaults
   - Установить relationships в Entity
   - Удалить Links из UserDefaults

#### Вариант B: Создать отдельные Entity

**Преимущества**:
- Проще миграция
- Можно хранить дополнительные данные в связях

**Недостатки**:
- Больше кода
- Менее эффективно

**Изменения**:

1. **Создать LinkEntity**
   - `categoryId: UUID`
   - `subcategoryId: UUID`
   - `transactionId: UUID?`
   - `linkType: String` (category-subcategory / transaction-subcategory)

2. **Миграция**
   - Конвертировать Links → LinkEntity

**Рекомендация**: Вариант A (relationships)

**Файлы**:
- `Tenra.xcdatamodeld/contents`
- `CustomCategoryEntity+CoreDataClass.swift`
- `TransactionEntity+CoreDataClass.swift`
- `SubcategoryEntity+CoreDataClass.swift`
- `DataMigrationService.swift`

**Время**: ~2-3 часа

---

### Фаза 3: RecurringOccurrences

**Цель**: Перенести RecurringOccurrences в Core Data

**Текущее состояние**: Нет Entity в Core Data

**Решение**:

1. **Создать RecurringOccurrenceEntity**
   ```swift
   - id: UUID
   - seriesId: UUID
   - scheduledDate: Date
   - actualDate: Date?
   - status: String (pending/completed/skipped)
   - transactionId: UUID?
   ```

2. **Добавить relationship**
   ```swift
   RecurringSeriesEntity.occurrences: [RecurringOccurrenceEntity] (to-many)
   RecurringOccurrenceEntity.series: RecurringSeriesEntity (to-one, inverse)
   ```

3. **Создать методы конвертации**
   - `toRecurringOccurrence()` - Entity → Model
   - `from(occurrence:context:)` - Model → Entity

4. **Обновить CoreDataRepository**
   ```swift
   func loadRecurringOccurrences() -> [RecurringOccurrence]
   func saveRecurringOccurrences(_ occurrences: [RecurringOccurrence])
   ```

5. **Миграция**
   - Загрузить из UserDefaults
   - Сохранить в Core Data
   - Установить relationships с RecurringSeries

**Файлы**:
- `Tenra.xcdatamodeld/contents`
- `RecurringOccurrenceEntity+CoreDataClass.swift`
- `RecurringOccurrenceEntity+CoreDataProperties.swift`
- `CoreDataRepository.swift`
- `DataMigrationService.swift`

**Время**: ~1-2 часа

---

### Фаза 4: Настройки приложения (AppSettings & TimeFilter)

**Цель**: Перенести настройки в Core Data

**Текущее состояние**:
- `AppSettings` - отдельный класс с сохранением в UserDefaults
- `TimeFilterManager` - отдельный класс с сохранением в UserDefaults

**Решение**: Два варианта

#### Вариант A: Создать AppSettingsEntity (рекомендуется)

**Преимущества**:
- Единый источник данных (Core Data)
- Консистентность
- Возможность синхронизации с iCloud

**Изменения**:

1. **Создать AppSettingsEntity**
   ```swift
   - id: UUID (всегда один экземпляр)
   - baseCurrency: String
   - wallpaperImageName: String?
   - currentTimeFilterPreset: String
   - customFilterStartDate: Date?
   - customFilterEndDate: Date?
   - lastModified: Date
   ```

2. **Обновить AppSettings**
   ```swift
   // Добавить методы
   static func loadFromCoreData() -> AppSettings
   func saveToCoreData()
   ```

3. **Обновить TimeFilterManager**
   ```swift
   // Сохранять фильтр в AppSettingsEntity
   private func saveToStorage() {
       // Save to Core Data instead of UserDefaults
   }
   ```

#### Вариант B: Оставить в UserDefaults

**Аргументы**:
- Настройки - это небольшой объем данных
- Критичны для запуска приложения
- Не требуют сложных запросов
- Низкий приоритет для миграции

**Рекомендация**:
- Если цель - **полностью убрать UserDefaults** → Вариант A
- Если цель - **оптимизация производительности** → Вариант B

**Файлы** (если Вариант A):
- `Tenra.xcdatamodeld/contents`
- `AppSettingsEntity+CoreDataClass.swift`
- `AppSettings.swift`
- `TimeFilterManager.swift`

**Время**: ~1-2 часа

---

## 🔄 Порядок выполнения

### Шаг 1: Завершить Фазу 1 (основные сущности)
**Приоритет**: 🔴 Высокий
**Зависимости**: Нет
**Результат**: Categories, Rules, RecurringSeries полностью в Core Data

### Шаг 2: Фаза 2 (связующие таблицы)
**Приоритет**: 🟡 Средний
**Зависимости**: Фаза 1
**Результат**: Links через relationships или отдельные Entity

### Шаг 3: Фаза 3 (RecurringOccurrences)
**Приоритет**: 🟡 Средний
**Зависимости**: Фаза 1 (RecurringSeries)
**Результат**: RecurringOccurrences в Core Data

### Шаг 4: Фаза 4 (настройки приложения)
**Приоритет**: 🟢 Низкий (опционально)
**Зависимости**: Нет
**Результат**: AppSettings в Core Data (или остаются в UserDefaults)

---

## 📋 Детальный чеклист

### Фаза 1: Основные сущности ✅
- [ ] Убрать fallback на UserDefaults в CoreDataRepository
- [ ] Реализовать полные методы для Categories
- [ ] Реализовать полные методы для CategoryRules
- [ ] Реализовать полные методы для RecurringSeries
- [ ] Реализовать полные методы для Subcategories
- [ ] Обновить миграцию в DataMigrationService
- [ ] Тестирование миграции
- [ ] Проверка целостности данных

### Фаза 2: Связующие таблицы
- [ ] Выбрать подход (relationships vs отдельные Entity)
- [ ] Обновить Core Data модель
- [ ] Добавить relationships в Entity (если Вариант A)
- [ ] Создать LinkEntity (если Вариант B)
- [ ] Обновить методы конвертации
- [ ] Реализовать миграцию Links
- [ ] Обновить CoreDataRepository (если нужно)
- [ ] Тестирование

### Фаза 3: RecurringOccurrences
- [ ] Создать RecurringOccurrenceEntity
- [ ] Добавить relationships
- [ ] Создать методы конвертации
- [ ] Обновить CoreDataRepository
- [ ] Реализовать миграцию
- [ ] Тестирование

### Фаза 4: Настройки приложения (опционально)
- [ ] Решить: мигрировать или оставить в UserDefaults
- [ ] Создать AppSettingsEntity (если мигрировать)
- [ ] Обновить AppSettings.swift
- [ ] Обновить TimeFilterManager.swift
- [ ] Реализовать миграцию
- [ ] Тестирование

### Финальная очистка
- [ ] Удалить все UserDefaults ключи (кроме миграции)
- [ ] Удалить UserDefaultsRepository (или пометить как deprecated)
- [ ] Удалить fallback код
- [ ] Удалить DEBUG методы
- [ ] Обновить документацию
- [ ] Финальное тестирование

---

## ⚡ Оценка времени

| Фаза | Время | Приоритет |
|------|-------|-----------|
| Фаза 1: Основные сущности | 1-2 часа | 🔴 Высокий |
| Фаза 2: Связующие таблицы | 2-3 часа | 🟡 Средний |
| Фаза 3: RecurringOccurrences | 1-2 часа | 🟡 Средний |
| Фаза 4: Настройки | 1-2 часа | 🟢 Низкий |
| **Итого** | **5-9 часов** | |

---

## 🎯 Критерии успеха

### Обязательные
- ✅ Все данные мигрированы в Core Data
- ✅ Приложение работает без ошибок
- ✅ Не потеряно ни одной записи
- ✅ Производительность не ухудшилась
- ✅ Relationships работают корректно

### Желательные
- ✅ UserDefaults используется только для статуса миграции
- ✅ Код чище и понятнее
- ✅ Производительность улучшена
- ✅ Готовность к iCloud Sync

### Опциональные
- ⚪ Настройки приложения в Core Data
- ⚪ Полное удаление UserDefaultsRepository
- ⚪ CloudKit интеграция

---

## 🐛 Потенциальные проблемы

### Проблема 1: Дублирование данных
**Риск**: 🟡 Средний
**Причина**: Некорректная проверка миграции
**Решение**:
- Использовать версионирование миграции (v3, v4...)
- Очищать старые данные перед миграцией
- Проверять существование Entity перед созданием

### Проблема 2: Потеря relationships
**Риск**: 🔴 Высокий
**Причина**: Неправильный порядок миграции
**Решение**:
- Сначала мигрировать основные Entity
- Затем устанавливать relationships
- Использовать fetch requests для поиска связанных Entity

### Проблема 3: Производительность
**Риск**: 🟡 Средний
**Причина**: Слишком много relationships
**Решение**:
- Использовать fetch limits
- Добавить индексы
- Оптимизировать fetch requests

### Проблема 4: Swift 6 concurrency
**Риск**: 🟡 Средний
**Причина**: Actor isolation в Core Data
**Решение**:
- Использовать `await context.perform { }`
- Правильно маркировать методы (@MainActor / nonisolated)

---

## 🔧 Рекомендации

### Обязательно
1. **Делать резервные копии** перед каждой фазой
2. **Тестировать каждую фазу** отдельно
3. **Проверять количество записей** после миграции
4. **Использовать версионирование** миграции (v3, v4...)

### Желательно
1. **Логировать все операции** для отладки
2. **Профилировать производительность** после каждой фазы
3. **Писать unit tests** для критичных методов
4. **Документировать изменения** в отдельных файлах

### Опционально
1. **Добавить UI для статуса миграции**
2. **Реализовать откат миграции**
3. **Добавить метрики** для мониторинга

---

## 📚 Связанные документы

- [core-data-phase2-complete.md](core-data-phase2-complete.md) - Фаза 2
- [core-data-migration-complete.md](core-data-migration-complete.md) - Результаты миграции v2
- [core-data-integration-complete.md](core-data-integration-complete.md) - Интеграция Core Data
- [CoreDataRepository.swift](./Tenra/Services/CoreDataRepository.swift) - Repository
- [DataMigrationService.swift](./Tenra/Services/DataMigrationService.swift) - Migration

---

## 🚀 С чего начать?

### Рекомендуемый подход

1. **Запустить приложение** и убедиться, что текущая миграция работает
2. **Начать с Фазы 1** - завершить миграцию основных сущностей
3. **Перейти к Фазе 2** - relationships для Links
4. **Затем Фаза 3** - RecurringOccurrences
5. **Решить по Фазе 4** - нужна ли миграция настроек

### Команды для начала работы

```bash
# 1. Проверить текущее состояние
# Запустить приложение и посмотреть логи миграции

# 2. Создать ветку для работы
git checkout -b feature/core-data-full-migration

# 3. Начать с Фазы 1
# Открыть CoreDataRepository.swift
```

---

## ✅ Итоговое состояние после полной миграции

### Данные в Core Data
- ✅ Transactions (921)
- ✅ Accounts (8)
- ✅ CustomCategories (22)
- ✅ CategoryRules
- ✅ RecurringSeries
- ✅ Subcategories (60)
- ✅ CategorySubcategoryLinks (через relationships)
- ✅ TransactionSubcategoryLinks (через relationships)
- ✅ RecurringOccurrences
- ✅ AppSettings (опционально)

### Данные в UserDefaults (минимум)
- ⚪ Статус миграции (`coreDataMigrationCompleted_v3`)
- ⚪ AppSettings (если не мигрировать)
- ⚪ TimeFilter (если не мигрировать)

### Удалённые файлы/код
- ❌ UserDefaultsRepository (deprecated или удалён)
- ❌ Fallback код в CoreDataRepository
- ❌ DEBUG методы миграции

---

**Готовы начать? Давайте начнём с Фазы 1!** 🚀
