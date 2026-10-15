# Следующие шаги для завершения миграции

**Статус**: 🎯 95% готово, осталось 1 действие в Xcode

---

## ✅ Что уже сделано

1. ✅ Созданы все Entity классы (9 типов)
2. ✅ Реализован CoreDataRepository
3. ✅ Реализован DataMigrationService v5
4. ✅ Настроены relationships в коде
5. ✅ Создана документация

---

## ⚠️ Что нужно сделать СЕЙЧАС

### 1. Добавить RecurringOccurrenceEntity в Core Data модель (Xcode)

#### Шаг 1: Открыть Xcode
```bash
open Tenra.xcodeproj
```

#### Шаг 2: Открыть Core Data модель
Навигатор → `Tenra/CoreData/Tenra.xcdatamodeld`

#### Шаг 3: Добавить новую Entity
1. Кликнуть "Add Entity" (внизу окна)
2. Назвать: `RecurringOccurrenceEntity`

#### Шаг 4: Добавить Attributes

В Inspector (справа) добавить:

| Attribute | Type | Optional |
|-----------|------|----------|
| `id` | String | ✓ |
| `seriesId` | String | ✓ |
| `occurrenceDate` | String | ✓ |
| `transactionId` | String | ✓ |

#### Шаг 5: Добавить Relationship

В Inspector добавить relationship:

```
Name:         series
Destination:  RecurringSeriesEntity
Type:         To One
Optional:     ✓
Delete Rule:  Nullify
```

#### Шаг 6: Добавить обратный Relationship в RecurringSeriesEntity

1. Выбрать `RecurringSeriesEntity` в списке
2. Добавить relationship:

```
Name:         occurrences
Destination:  RecurringOccurrenceEntity
Type:         To Many
Optional:     ✓
Delete Rule:  Nullify
Inverse:      series
```

#### Шаг 7: Связать Relationships

1. Выбрать `RecurringOccurrenceEntity`
2. В relationship `series` установить:
   - Inverse: `occurrences`

#### Шаг 8: Сохранить

⌘ + S или File → Save

---

## 🧪 Тестирование

### 1. Запустить приложение

```bash
# В Xcode:
⌘ + R
```

### 2. Проверить логи миграции

Если это первый запуск после обновления, вы должны увидеть:

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
✅ [MIGRATION] Saved N links to Core Data
📦 [MIGRATION] Migrating transaction-subcategory links...
✅ [MIGRATION] Saved N links to Core Data
📦 [MIGRATION] Migrating recurring occurrences...
✅ [MIGRATION] Saved N recurring occurrences to Core Data
✅ [MIGRATION] Data migration completed successfully
```

### 3. Проверить работу приложения

- ✅ Транзакции загружаются
- ✅ Счета отображаются
- ✅ Категории работают
- ✅ Можно создавать новые транзакции
- ✅ Recurring series функционирует

### 4. Если миграция не запускается

Сбросить статус миграции:

```swift
// В коде или через lldb:
UserDefaults.standard.removeObject(forKey: "coreDataMigrationCompleted_v5")
UserDefaults.standard.synchronize()
```

Затем перезапустить приложение.

---

## 🐛 Возможные проблемы

### "Entity not found"

```
❌ [CORE_DATA_REPO] Error: Entity 'RecurringOccurrenceEntity' not found
```

**Причина**: Entity не добавлена в .xcdatamodeld

**Решение**: Выполнить шаги 1-8 выше

### Ошибка компиляции

```
Cannot find 'RecurringOccurrenceEntity' in scope
```

**Причина**: Классы созданы, но модель не обновлена

**Решение**: Добавить Entity в .xcdatamodeld

### Relationships не работают

```
⚠️ Relationship 'series' is nil
```

**Причина**: Inverse relationship не установлен

**Решение**: Убедиться, что:
- В `RecurringOccurrenceEntity.series` → inverse = `occurrences`
- В `RecurringSeriesEntity.occurrences` → inverse = `series`

---

## 📚 Документация

После завершения изучите документацию:

1. **userdefaults-to-coredata-complete.md** - полная сводка
2. **core-data-phase3-complete.md** - детали Фазы 3
3. **core-data-full-migration-plan.md** - исходный план

---

## ✅ Checklist

- [ ] Открыть Xcode
- [ ] Открыть .xcdatamodeld
- [ ] Добавить RecurringOccurrenceEntity
- [ ] Добавить 4 атрибута
- [ ] Добавить relationship `series`
- [ ] Добавить обратный relationship `occurrences` в RecurringSeriesEntity
- [ ] Связать relationships (inverse)
- [ ] Сохранить модель (⌘ + S)
- [ ] Запустить приложение (⌘ + R)
- [ ] Проверить логи миграции
- [ ] Проверить работу приложения
- [ ] Готово! 🎉

---

## 🚀 После завершения

### Опциональные улучшения

1. **Производительность**
   - Добавить NSFetchedResultsController
   - Оптимизировать fetch requests

2. **iCloud Sync**
   - NSPersistentCloudKitContainer
   - Синхронизация между устройствами

3. **Тестирование**
   - Unit tests для Repository
   - UI tests для CRUD операций

4. **AppSettings**
   - Мигрировать в Core Data (Фаза 4)
   - Полностью убрать UserDefaults

---

**Удачи! При проблемах смотрите userdefaults-to-coredata-complete.md** 🚀
