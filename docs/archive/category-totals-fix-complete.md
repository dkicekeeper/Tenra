# Исправление обновления сумм категорий расходов

**Дата:** 2026-02-01
**Статус:** ✅ ИСПРАВЛЕНО
**Связанные документы:** aggregate-cache-rebuild-fix.md, ui-refresh-trigger-fix.md

## Проблема

При изменении фильтра времени или при старте приложения суммы у категорий расходов на главном экране не обновлялись (показывали 0.00), хотя aggregate cache перестраивался правильно.

## Анализ проблемы

### Фаза 1: Aggregate cache перестраивается, но UI не обновляется

**Логи показали:**
```
✅ [CategoryAggregateCache] Cache rebuilt: isLoaded=true, keys=6850
✅ [CacheCoordinator] Aggregate rebuild complete
🔄 [TransactionStorageCoordinator] Triggered UI update after aggregate rebuild
[НЕТ ОБНОВЛЕНИЯ UI]
```

**Root Cause #1:**
`notifyDataChanged()` создавал новый массив `Array(allTransactions)`, но:
- `QuickAddCoordinator` наблюдает за `$allTransactions.map { $0.count }.removeDuplicates()`
- Количество транзакций не меняется (19254 → 19254)
- `.removeDuplicates()` блокирует обновление
- Combine publisher не срабатывает
- UI не обновляется

### Фаза 2: Добавили dataRefreshTrigger, но UI всё равно не обновляется

**Логи показали:**
```
🔔 [TransactionsViewModel] notifyDataChanged() - triggered dataRefreshTrigger
🔔 [QuickAddCoordinator] Combine publisher triggered:
   Refresh trigger: C5F56270-FD56-4147-A71E-B6278981CF30
📊 [TransactionsViewModel] Returning 28 categories, total: 202345175.31
🗺️ [CategoryDisplayDataMapper] Mapped to 28 display categories
   Example output: Кредиты = 24424806.67
[НО UI ВСЁ РАВНО НЕ ОБНОВЛЯЕТСЯ!]
```

**Root Cause #2:**
- `QuickAddCoordinator` получает правильные данные
- `categories` обновляется в coordinator
- НО `CategoryGridView` не перерисовывается!
- SwiftUI не понимает, что массив изменился, потому что:
  - Массив имеет тот же count (28)
  - `CategoryDisplayData` имеет те же `id`
  - SwiftUI использует структурное равенство, и не видит изменений в `total`

## Решение

### 1. Добавить `dataRefreshTrigger` в TransactionsViewModel

Вместо попытки заставить SwiftUI увидеть изменение массива, добавляем явный trigger:

```swift
@Published var dataRefreshTrigger: UUID = UUID()

func notifyDataChanged() {
    dataRefreshTrigger = UUID()  // Всегда уникальный
}
```

### 2. Подключить trigger к Combine publishers

**QuickAddCoordinator:**
```swift
Publishers.CombineLatest(
    Publishers.CombineLatest4(
        transactionsViewModel.$allTransactions.map { $0.count }.removeDuplicates(),
        categoriesViewModel.$customCategories.map { $0.count }.removeDuplicates(),
        timeFilterManager.$currentFilter.removeDuplicates(),
        transactionsViewModel.$dataRefreshTrigger  // ✅ НОВОЕ
    ),
    Just(()).eraseToAnyPublisher()
)
```

**ContentView:**
```swift
private var summaryUpdatePublisher: AnyPublisher<Void, Never> {
    Publishers.Merge3(
        timeFilterManager.$currentFilter.map { _ in () },
        viewModel.$allTransactions.map { _ in () },
        viewModel.$dataRefreshTrigger.map { _ in () }  // ✅ НОВОЕ
    )
}
```

### 3. Заставить SwiftUI перерисовать CategoryGridView

Даже с правильными данными в `categories`, SwiftUI не перерисовывает `CategoryGridView`, потому что не видит изменений. Добавляем `.id()` с hash суммы всех totals:

```swift
CategoryGridView(
    categories: coordinator.categories,
    baseCurrency: coordinator.baseCurrency,
    gridColumns: nil,
    onCategoryTap: { ... },
    emptyStateAction: coordinator.handleAddCategory
)
.id(categoriesHash)  // ✅ Заставляет SwiftUI перерисовать при изменении

private var categoriesHash: Int {
    coordinator.categories.reduce(0) { hash, category in
        hash ^ category.total.hashValue
    }
}
```

**Почему это работает:**
- Когда totals меняются, hash меняется
- SwiftUI видит новый `.id()` и полностью перерисовывает view
- Это гарантирует, что новые данные отобразятся

## Файлы изменены

### 1. TransactionsViewModel.swift
- Добавлено: `@Published var dataRefreshTrigger: UUID = UUID()`
- Изменено: `notifyDataChanged()` - меняет trigger вместо массива

### 2. QuickAddCoordinator.swift
- Изменено: `setupBindings()` - наблюдает за `$dataRefreshTrigger`
- Изменено: `updateCategories()` - явно присваивает результат в `categories`

### 3. QuickAddTransactionView.swift
- Добавлено: `.id(categoriesHash)` на `CategoryGridView`
- Добавлено: `categoriesHash` computed property

### 4. ContentView.swift
- Изменено: `summaryUpdatePublisher` - наблюдает за `$dataRefreshTrigger`

## Call Flow (Полный)

```
App Startup
  ↓
TransactionStorageCoordinator.loadFromStorage()
  ↓
[Загружает 19,254 транзакций из CoreData]
  ↓
rebuildAggregateCacheAfterImport()
  ↓
CacheCoordinator.rebuildAggregates()
  ↓
1. invalidateCategoryExpenses()  // Очищает кэш ДО rebuild
2. aggregateCache.clear()
3. aggregateCache.rebuildFromTransactions()
     ↓
     [Строит 6,850 агрегатов]
     isLoaded = true
  ↓
notifyDataChanged()
  ↓
dataRefreshTrigger = UUID()  ← НОВЫЙ UUID
  ↓
═══════════════════════════════════════
║  COMBINE PUBLISHERS СРАБАТЫВАЮТ     ║
═══════════════════════════════════════
  ↓
QuickAddCoordinator.setupBindings() видит новый UUID
  ↓
updateCategories()
  ↓
transactionsViewModel.categoryExpenses()
  ↓
TransactionQueryService.getCategoryExpenses()
  ↓
CategoryAggregateCache.getCategoryExpenses()
  ↓
[isLoaded=true, возвращает 28 категорий с totals]
  ↓
CategoryDisplayDataMapper.mapCategories()
  ↓
[Преобразует в CategoryDisplayData]
  ↓
coordinator.categories = newCategories  ← @Published обновляется
  ↓
QuickAddTransactionView body вызывается
  ↓
categoriesHash вычисляется (новый hash от totals)
  ↓
CategoryGridView получает новый .id()
  ↓
SwiftUI перерисовывает view с нуля
  ↓
✅ UI ОБНОВЛЁН С ПРАВИЛЬНЫМИ СУММАМИ!
```

## Тестирование

### Сценарий 1: Старт приложения
✅ При запуске приложения суммы категорий должны отображаться сразу (не 0.00)

### Сценарий 2: Смена фильтра времени
✅ При переключении между "Всё время", "Этот месяц", "Этот год" суммы должны обновляться мгновенно

### Сценарий 3: Добавление транзакции
✅ После добавления транзакции суммы должны обновиться

### Сценарий 4: Импорт CSV
✅ После импорта большого файла (19K+ транзакций) суммы должны появиться после rebuild

## Метрики

| Метрика | До | После |
|---------|:--:|:-----:|
| Суммы при старте | ❌ 0.00 | ✅ Правильные |
| Обновление при смене фильтра | ❌ Не работает | ✅ Мгновенно |
| Aggregate cache rebuild | ✅ Работает | ✅ Работает |
| UI обновление после rebuild | ❌ Не работает | ✅ Работает |

## Ключевые уроки

1. **SwiftUI не всегда видит изменения в массивах**
   Даже если массив `@Published`, SwiftUI может не перерисовать view, если структурное равенство не меняется (те же IDs, тот же count).

2. **`.id()` модификатор - мощный инструмент**
   Когда SwiftUI не видит изменений, можно заставить перерисовку через изменение `.id()`. Hash от totals гарантирует новый ID при изменении данных.

3. **Комбинация подходов**
   Одного `dataRefreshTrigger` недостаточно - нужно:
   - Trigger для Combine publishers (чтобы coordinator обновился)
   - Hash-based `.id()` (чтобы view перерисовался)

4. **Debug logging критичен**
   Без детального логирования на каждом этапе было бы невозможно понять, что данные обновляются правильно, но UI не перерисовывается.

## Связанные проблемы

- Per-filter caching (aggregate-cache-rebuild-fix.md)
- Race condition в cache invalidation
- Empty result caching prevention
- Combine publisher optimization с `.removeDuplicates()`
