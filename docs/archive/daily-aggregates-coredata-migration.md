# CoreData Migration: Adding `day` field to CategoryAggregateEntity

## ⚠️ MANUAL STEP REQUIRED

**Файл:** `Tenra.xcdatamodeld`
**Entity:** `CategoryAggregateEntity`
**Действие:** Добавить новый атрибут `day`

---

## 📝 Инструкция

### 1. Открой CoreData модель в Xcode

1. В Xcode найди файл: `Tenra/CoreData/Tenra.xcdatamodeld`
2. Кликни на него → откроется визуальный редактор CoreData

### 2. Найди CategoryAggregateEntity

1. В списке Entities слева найди `CategoryAggregateEntity`
2. Кликни на неё

### 3. Добавь новый атрибут

1. В секции **Attributes** нажми `+` (или кликни правой кнопкой → Add Attribute)
2. Настрой новый атрибут:
   - **Name:** `day`
   - **Type:** `Integer 16`
   - **Default Value:** `0`
   - **Optional:** ❌ (unchecked - обязательное поле)
   - **Indexed:** ✅ (checked - для быстрой фильтрации)

### 4. Сохрани изменения

1. Cmd+S для сохранения
2. CoreData автоматически регенерирует CategoryAggregateEntity

### 5. Проверь автогенерацию

Xcode должен автоматически обновить:
- `CategoryAggregateEntity+CoreDataProperties.swift`

**НО** я уже обновил этот файл вручную, так что если Xcode перезапишет его, нужно проверить, что там есть:

```swift
@NSManaged public var day: Int16
```

---

## 🔄 Миграция данных

### Lightweight Migration

CoreData может автоматически мигрировать данные, потому что:
- ✅ Добавляется новое поле (не удаляется)
- ✅ Новое поле имеет default value (0)
- ✅ Не меняются отношения (relationships)
- ✅ Не меняются типы существующих полей

**Результат:** Все существующие aggregates получат `day = 0` (non-daily aggregates)

### Как включить Lightweight Migration

В `CoreDataRepository.swift` или где инициализируется CoreData stack, убедись, что используется:

```swift
let options = [
    NSMigratePersistentStoresAutomaticallyOption: true,
    NSInferMappingModelAutomaticallyOption: true
]
```

Это уже должно быть настроено, но проверь!

---

## 🧪 Проверка после добавления

### 1. Build проекта

```bash
xcodebuild -scheme Tenra -sdk iphonesimulator build
```

**Ожидается:** ✅ BUILD SUCCEEDED

### 2. Проверь, что поле добавилось

Запусти приложение и проверь в консоли:

```swift
// Должно быть в логах при загрузке aggregates:
print("Loaded aggregate: year=\(aggregate.year), month=\(aggregate.month), day=\(aggregate.day)")
```

### 3. Проверь старые данные

- Все существующие aggregates должны иметь `day = 0`
- Приложение должно запуститься без крашей
- Aggregate cache должен загрузиться

---

## ❌ Если что-то пошло не так

### Ошибка: "The model used to open the store is incompatible"

**Причина:** CoreData не может автоматически мигрировать

**Решение:**
1. Удали приложение из симулятора (полностью)
2. Запусти заново → создастся новая БД с новой схемой

**ИЛИ** создай полноценную manual migration (сложнее, требуется mapping model)

### Ошибка: Build failed с ошибкой про CategoryAggregateEntity

**Причина:** Xcode не регенерировал Properties файл

**Решение:**
1. В CoreData модели:
   - Editor → Create NSManagedObject Subclass
   - Выбери CategoryAggregateEntity
   - Replace существующие файлы
2. Снова добавь `day` поле в Properties вручную (я уже это сделал)

---

## ✅ Checklist

После добавления поля в CoreData модель:

- [ ] Поле `day` добавлено в CategoryAggregateEntity (Type: Integer 16)
- [ ] Default Value = 0
- [ ] Optional = unchecked
- [ ] Indexed = checked
- [ ] Build succeeded
- [ ] Приложение запускается без краша
- [ ] Старые aggregates загружаются с day=0

---

**ВАЖНО:** Это нужно сделать ПЕРЕД тем, как продолжить с Phase 2-6!

После выполнения этого шага, я продолжу с обновлением CategoryAggregateService для создания daily aggregates.
