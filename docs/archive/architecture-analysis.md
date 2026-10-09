# Анализ архитектуры расчёта балансов

## Проблема: Слишком сложная система с множеством слоёв

### Текущая архитектура (для обновления транзакции):

```
EditTransactionView
    ↓
TransactionsViewModel.updateTransaction()
    ↓
TransactionCRUDService.updateTransaction()
    ↓
[Параллельные операции]
    1. Обновление массива allTransactions (@Published)
    2. CategoryAggregateCacheOptimized.updateForTransaction()
        ↓
        CategoryAggregateService.updateAggregatesForUpdate()
            - Создаёт deletion aggregates (старые значения с минусом)
            - Создаёт addition aggregates (новые значения)
            - Мерджит их в один массив
        ↓
        Применяет дельты к кэшу (LRU cache)
    3. BalanceCoordinator.updateForTransaction()
        ↓
        BalanceUpdateQueue → BalanceCalculationEngine
    4. invalidateCaches()
        ↓
        CacheCoordinator.invalidate(scope: .summaryAndCurrency)
            - summaryCacheInvalidated = true
            - categoryListsCacheInvalidated = true
            - currencyService.invalidate()
        ↓
        TransactionCacheManager.invalidateCategoryExpenses()
            - categoryExpensesCache.removeAll()
```

### UI обновления (когда allTransactions меняется):

```
ContentView
    ↓
    Слушает: viewModel.$allTransactions
    ↓
    summaryUpdatePublisher (debounce 200ms)
    ↓
    updateSummary()
        ↓
        viewModel.summary(timeFilterManager)
            - Фильтрует транзакции по времени
            - Устанавливает summaryCacheInvalidated = true
            - Вызывает TransactionQueryService.calculateSummary()
                - Проверяет кэш
                - Пересчитывает summary
                - Сохраняет в кэш
                - Устанавливает summaryCacheInvalidated = false
            - ❌ БАГ: Восстанавливал старое значение флага!

QuickAddCoordinator (CategoryGridView)
    ↓
    Слушает: transactionsViewModel.$allTransactions
    ↓
    setupBindings() (debounce 150ms)
    ↓
    updateCategories()
        ↓
        categoryExpensesByFilter()
            ↓
            CategoryAggregateCacheOptimized.getCategoryExpenses()
                - Вычисляет из aggregates
                - Кэширует в categoryExpensesCache (LRU)

HistoryView
    ↓
    Слушает: transactionsViewModel.$allTransactions
    ↓
    expensesCache.invalidate() + updateTransactions()
        ↓
        DateSectionExpensesCache.getExpenses()
            - Пересчитывает суммы по дням
```

---

## Почему так сложно?

### 1. **Множественные источники истины**
- `allTransactions` - исходные данные
- `CategoryAggregateCache` - агрегированные данные по категориям
- `categoryExpensesCache` - производный кэш от агрегатов
- `summaryCacheInvalidated` - флаг инвалидации
- `DateSectionExpensesCache` - кэш дневных сумм
- `BalanceStore` - балансы счетов

### 2. **Сложная система инвалидации**
- При изменении транзакции нужно:
  - Инвалидировать summary cache
  - Инвалидировать category expenses cache
  - Инвалидировать currency cache
  - Обновить aggregate cache инкрементально
  - Обновить balance инкрементально
  - Уведомить UI через @Published

### 3. **Инкрементальные обновления с мерджингом**
- CategoryAggregateService создаёт deletion + addition aggregates
- Они мерджатся по ID
- Если ID неправильный → дубликаты → двойное применение дельты
- Это было источником последнего бага

### 4. **Множество Coordinators и Services**
- TransactionCRUDService
- CacheCoordinator
- CategoryAggregateService
- CategoryAggregateCacheOptimized
- BalanceCoordinator
- BalanceUpdateQueue
- BalanceCalculationEngine
- TransactionQueryService
- TransactionCurrencyService

### 5. **Временные флаги и восстановление состояния**
```swift
let wasInvalidated = cacheManager.summaryCacheInvalidated
cacheManager.summaryCacheInvalidated = true
// ...
cacheManager.summaryCacheInvalidated = wasInvalidated  // ❌ Конфликтует с нормальной инвалидацией
```

---

## Последствия сложности

### Баги, которые мы уже нашли:
1. ❌ Aggregate ID regeneration - пропущен параметр `day`, создавались дубликаты
2. ❌ Summary cache restoration - восстановление флага ломало инвалидацию
3. ❌ QuickAddCoordinator - слушал только `.count`, а не весь массив
4. ❌ Category balances not updating - не инвалидировался categoryExpensesCache

### Потенциальные проблемы:
- Race conditions между инкрементальными обновлениями
- Десинхронизация кэшей
- Memory leaks в LRU cache
- Performance issues из-за множественных debounce
- Сложность тестирования

---

## Предложения по упрощению

### Вариант 1: Single Source of Truth (Радикальный)
```swift
class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []

    // Computed properties (нет кэша, всегда актуально)
    var summary: Summary { calculateSummary(transactions) }
    var categoryExpenses: [CategoryExpense] { calculateCategoryExpenses(transactions) }
    var balances: [String: Double] { calculateBalances(transactions) }
}
```

**Плюсы:**
- Всегда актуальные данные
- Нет проблем с инвалидацией
- Простота и надёжность

**Минусы:**
- Пересчёт при каждом обращении
- Медленнее для больших датасетов

---

### Вариант 2: Event Sourcing (Средний путь)
```swift
enum TransactionEvent {
    case added(Transaction)
    case updated(old: Transaction, new: Transaction)
    case deleted(Transaction)
}

class TransactionEventStore {
    func apply(event: TransactionEvent) {
        // Одно место для всех обновлений
        transactions.apply(event)
        aggregates.apply(event)
        balances.apply(event)
        // Автоматически синхронизированы
    }
}
```

**Плюсы:**
- Централизованная логика обновлений
- Легче отладка (history of events)
- Гарантированная консистентность

**Минусы:**
- Нужен рефакторинг
- Более сложная имплементация

---

### Вариант 3: Упрощение текущей системы (Минимальные изменения)

#### 3.1 Убрать лишние слои
```
СЕЙЧАС:
TransactionCRUDService → CacheCoordinator → CategoryAggregateService → CategoryAggregateCacheOptimized

МОЖНО:
TransactionCRUDService → CategoryAggregateCache (всё внутри)
```

#### 3.2 Унифицировать инвалидацию
```swift
class CacheManager {
    func invalidateAll() {
        summaryCacheInvalidated = true
        categoryExpensesCache.removeAll()
        currencyCache.removeAll()
        // Одна функция - всё инвалидирует
    }
}
```

#### 3.3 Убрать временные флаги
```swift
// ВМЕСТО:
let wasInvalidated = cache.invalidated
cache.invalidated = true
// ...
cache.invalidated = wasInvalidated

// ИСПОЛЬЗОВАТЬ:
func calculateSummary(forceRecalculate: Bool = false) {
    if forceRecalculate || cache.invalidated {
        // recalculate
    }
}
```

#### 3.4 Один Publisher для всех обновлений
```swift
// ВМЕСТО: Множество отдельных Publishers
@Published var allTransactions: [Transaction]
// + множество .onChange в разных View

// ИСПОЛЬЗОВАТЬ:
class TransactionUpdatePublisher {
    enum Update {
        case transactionsChanged
        case aggregatesUpdated
        case balancesUpdated
    }
    @Published var updates: Update?
}
```

---

## Рекомендации

### Немедленно (Quick wins):
1. ✅ Убрать восстановление флагов инвалидации
2. 🔄 Упростить CacheCoordinator - одна функция invalidateAll()
3. 🔄 Объединить CategoryAggregateService + CategoryAggregateCacheOptimized
4. 🔄 Документировать правила инвалидации кэша

### Среднесрочно (Refactoring):
1. Перейти на Event Sourcing для транзакций
2. Убрать TransactionCacheManager - использовать computed properties где возможно
3. Упростить BalanceCoordinator - убрать очередь, делать синхронно
4. Добавить интеграционные тесты для всех кейсов обновления

### Долгосрочно (Architecture):
1. Рассмотреть переход на TCA (The Composable Architecture)
2. Или на Redux-like паттерн с единым Store
3. Использовать CoreData как единственный source of truth
4. Убрать все in-memory кэши, полагаться на CoreData caching

---

## Сравнение подходов

| Аспект | Текущая система | Event Sourcing | Single Source of Truth |
|--------|----------------|----------------|----------------------|
| Сложность | 🔴 Высокая | 🟡 Средняя | 🟢 Низкая |
| Производительность | 🟢 Быстрая | 🟢 Быстрая | 🟡 Средняя |
| Надёжность | 🔴 Баги | 🟢 Надёжно | 🟢 Надёжно |
| Отладка | 🔴 Сложно | 🟢 Легко | 🟢 Легко |
| Рефакторинг | - | 🟡 Средний | 🔴 Большой |

---

## Вывод

**Текущая проблема:** Попытка оптимизации через кэширование привела к over-engineering.

**Корень проблемы:** Множественные источники истины, которые нужно синхронизировать вручную.

**Решение:** Начать с quick wins (упрощение текущей системы), затем постепенно двигаться к Event Sourcing или SSOT.

**Главный принцип:** Prefer correctness over performance. Можно оптимизировать позже, но сначала нужна надёжная система.
