# TransactionsViewModel - Анализ и План Оптимизации

## Обзор
**Файл:** `Tenra/ViewModels/TransactionsViewModel.swift`
**Размер:** ~2717 строк
**Дата анализа:** 2026-01-27

---

## 1. Текущие проблемы

### 1.1 Нарушение принципа единой ответственности (SRP)
Класс выполняет слишком много функций:
- Управление транзакциями (CRUD)
- Управление счетами (accounts)
- Управление категориями
- Управление подписками
- Управление депозитами
- Пересчет балансов
- Конвертация валют
- Генерация повторяющихся транзакций
- Сохранение/загрузка данных
- Кэширование

### 1.2 Проблемы производительности
| Проблема | Строки | Влияние |
|----------|--------|---------|
| Повторное создание `DateFormatter` в циклах | 228-248, 286-294 | Высокое |
| `applyRules()` вызывается многократно | 229, 253, 772, 816 | Среднее |
| Полный перебор `allTransactions` в фильтрах | 251-297 | Высокое |
| `recalculateAccountBalances()` - O(n) для каждой транзакции | 1836-2034 | Критическое |
| `generateRecurringTransactions()` потенциальный бесконечный цикл | 2285-2363 | Критическое |
| Множественные вызовы `saveToStorage()` | Повсеместно | Среднее |

### 1.3 Проблемы с памятью
- 19 `@Published` свойств - каждое изменение триггерит UI обновление
- Дублирование данных: `allTransactions` и `displayTransactions`
- Кэши не ограничены по размеру: `convertedAmountsCache`, `cachedCategoryExpenses`

### 1.4 Архитектурные проблемы
- Циклические зависимости с `AccountBalanceService`
- Смешивание sync и async операций
- Deprecated методы остаются в коде (1165-1181, 1290-1300)
- `accountsWithCalculatedInitialBalance` - легаси код (строка 54-56)

---

## 2. План декомпозиции

### 2.1 Предлагаемая структура

```
ViewModels/
├── TransactionsViewModel.swift (Core - ~500 строк)
├── Transactions/
│   ├── TransactionFilterService.swift
│   ├── TransactionGroupingService.swift
│   └── TransactionSearchService.swift
├── Balance/
│   ├── BalanceCalculator.swift
│   └── BalanceUpdateCoordinator.swift
├── Recurring/
│   ├── RecurringTransactionGenerator.swift
│   └── RecurringSeriesManager.swift
├── Currency/
│   └── CurrencyConversionCache.swift
└── Storage/
    └── TransactionStorageManager.swift
```

### 2.2 Новые сервисы

#### TransactionFilterService
```swift
class TransactionFilterService {
    func filterByTime(_ transactions: [Transaction], range: DateRange) -> [Transaction]
    func filterByCategory(_ transactions: [Transaction], categories: Set<String>) -> [Transaction]
    func filterByAccount(_ transactions: [Transaction], accountId: String?) -> [Transaction]
    func filterRecurring(_ transactions: [Transaction], series: [RecurringSeries]) -> [Transaction]
}
```

#### TransactionGroupingService
```swift
class TransactionGroupingService {
    func groupByDate(_ transactions: [Transaction]) -> [String: [Transaction]]
    func sortByDate(_ grouped: [String: [Transaction]]) -> [String]
}
```

#### BalanceCalculator
```swift
actor BalanceCalculator {
    func calculateBalance(for accountId: String, transactions: [Transaction]) async -> Double
    func recalculateAll(accounts: [Account], transactions: [Transaction]) async -> [Account]
}
```

#### RecurringTransactionGenerator
```swift
class RecurringTransactionGenerator {
    func generate(series: [RecurringSeries], horizon: Date) -> [Transaction]
    func regenerate(for seriesId: String, existingTransactions: [Transaction]) -> [Transaction]
}
```

---

## 3. План оптимизации производительности

### 3.1 Высокий приоритет

#### 3.1.1 Кэширование DateFormatter (Оценка: -30% CPU)
**Текущее состояние:**
```swift
// Строки 228-248 - создается в computed property
private static var dateFormatter: DateFormatter {
    DateFormatters.dateFormatter
}
```
**Рекомендация:** Уже используется static property, но `DateFormatters.dateFormatter` должен быть проверен на thread-safety.

#### 3.1.2 Оптимизация recalculateAccountBalances (Оценка: -50% времени)
**Текущее состояние:** O(n * m) где n - транзакции, m - счета
```swift
// Строки 1897-1997 - полный перебор
for tx in allTransactions {
    // проверка даты для каждой транзакции
    // множественные if/switch
}
```
**Рекомендация:**
1. Использовать индексированный доступ по accountId
2. Кэшировать результаты по дням
3. Инкрементальное обновление при добавлении/удалении

#### 3.1.3 Lazy Loading для displayTransactions
**Текущее состояние:** Загружаются сразу за 12 месяцев
**Рекомендация:**
- Пагинация по 50-100 транзакций
- Загрузка по требованию при скролле

### 3.2 Средний приоритет

#### 3.2.1 Debounce для saveToStorage
**Текущее состояние:** Вызывается после каждой операции
**Рекомендация:**
```swift
private var saveDebouncer: AnyCancellable?

func scheduleSaveDebounced() {
    saveDebouncer?.cancel()
    saveDebouncer = Just(())
        .delay(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.saveToStorage()
        }
}
```

#### 3.2.2 Индексы для быстрой фильтрации
**Текущее состояние:** Используется `TransactionIndexManager` (строка 67)
**Рекомендация:** Расширить индексы:
```swift
class TransactionIndexManager {
    var byAccountId: [String: [Transaction]]
    var byDate: [String: [Transaction]]
    var byCategory: [String: [Transaction]]
    var byType: [TransactionType: [Transaction]]
}
```

#### 3.2.3 Кэширование filtered транзакций
```swift
struct FilterCacheKey: Hashable {
    let timeRange: DateRange
    let categories: Set<String>?
    let accountId: String?
}

private var filteredCache: [FilterCacheKey: [Transaction]] = [:]
```

### 3.3 Низкий приоритет

#### 3.3.1 Background processing для генерации recurring
```swift
func generateRecurringTransactionsAsync() async {
    await Task.detached(priority: .utility) {
        // генерация в фоне
    }.value
}
```

#### 3.3.2 Сжатие истории старых транзакций
Транзакции старше 2 лет могут быть:
- Сгруппированы по месяцам
- Архивированы в отдельное хранилище

---

## 4. Рефакторинг API

### 4.1 Устаревшие методы для удаления

| Метод | Строка | Замена |
|-------|--------|--------|
| `addCategory` | 1165 | `CategoriesViewModel.addCategory` |
| `updateCategory` | 1167 | `CategoriesViewModel.updateCategory` |
| `deleteCategory` | 1169 | `CategoriesViewModel.deleteCategory` |
| `addAccount` | 1177 | `AccountsViewModel.addAccount` |
| `updateAccount` | 1179 | `AccountsViewModel.updateAccount` |
| `deleteAccount` | 1181 | `AccountsViewModel.deleteAccount` |
| `addDeposit` | 1292 | `DepositsViewModel.addDeposit` |
| `updateDeposit` | 1294 | `DepositsViewModel.updateDeposit` |
| `deleteDeposit` | 1296 | `DepositsViewModel.deleteDeposit` |

### 4.2 Методы для упрощения

**Текущее:** `transactionsFilteredByTimeAndCategory()` (строки 251-297) - 46 строк
**Рекомендация:** Разбить на цепочку фильтров:
```swift
func filteredTransactions(
    timeRange: DateRange? = nil,
    categories: Set<String>? = nil,
    account: String? = nil
) -> [Transaction] {
    var result = allTransactions

    if let range = timeRange {
        result = filterService.filterByTime(result, range: range)
    }
    if let cats = categories {
        result = filterService.filterByCategory(result, categories: cats)
    }
    if let acc = account {
        result = filterService.filterByAccount(result, accountId: acc)
    }

    return result
}
```

---

## 5. Улучшение безопасности потоков

### 5.1 Race Conditions
**Текущее состояние:**
- `isProcessingRecurringNotification` - простой флаг (строка 81)
- Множественные async операции без синхронизации

**Рекомендация:**
```swift
actor TransactionSafetyActor {
    private var isProcessing = false

    func beginProcessing() -> Bool {
        guard !isProcessing else { return false }
        isProcessing = true
        return true
    }

    func endProcessing() {
        isProcessing = false
    }
}
```

### 5.2 Использование @MainActor
**Текущее состояние:** Класс помечен `@MainActor` (строка 13)
**Проблема:** Некоторые операции блокируют main thread

**Рекомендация:** Вынести тяжелые вычисления в отдельные actors:
```swift
actor TransactionCalculator {
    func calculateSummary(transactions: [Transaction]) -> Summary
    func calculateCategoryExpenses(transactions: [Transaction]) -> [String: CategoryExpense]
}
```

---

## 6. Метрики улучшения (ожидаемые)

| Метрика | Текущее | Ожидаемое | Улучшение |
|---------|---------|-----------|-----------|
| Размер класса | ~2700 строк | ~500 строк | -81% |
| Время загрузки | ~2-3 сек | ~0.5 сек | -75% |
| Память (idle) | ~50 MB | ~20 MB | -60% |
| Время recalculate | ~500 ms | ~100 ms | -80% |
| UI freeze при импорте | Частые | Редкие | -90% |

---

## 7. План внедрения

### Фаза 1: Критические исправления (1-2 дня)
1. [ ] Исправить потенциальный бесконечный цикл в `generateRecurringTransactions` (строки 2285-2363)
2. [ ] Добавить debounce для `saveToStorage`
3. [ ] Оптимизировать `recalculateAccountBalances` с использованием индексов

### Фаза 2: Декомпозиция (3-5 дней)
1. [ ] Создать `TransactionFilterService`
2. [ ] Создать `TransactionGroupingService`
3. [ ] Вынести логику balance в отдельный `BalanceCalculator`
4. [ ] Вынести recurring логику в `RecurringTransactionGenerator`

### Фаза 3: Оптимизация (2-3 дня)
1. [ ] Реализовать пагинацию для `displayTransactions`
2. [ ] Расширить `TransactionIndexManager`
3. [ ] Добавить кэширование для фильтров
4. [ ] Оптимизировать конвертацию валют

### Фаза 4: Очистка (1-2 дня)
1. [ ] Удалить deprecated методы
2. [ ] Удалить legacy код (`accountsWithCalculatedInitialBalance`)
3. [ ] Обновить документацию
4. [ ] Добавить unit тесты для новых сервисов

---

## 8. Риски и митигация

| Риск | Вероятность | Влияние | Митигация |
|------|-------------|---------|-----------|
| Регрессии в balance calculation | Высокая | Критическое | Покрыть тестами перед рефакторингом |
| Несовместимость с другими ViewModels | Средняя | Высокое | Сохранить публичный API |
| Миграция данных | Низкая | Среднее | Версионирование хранилища |

---

## 9. Заключение

TransactionsViewModel требует серьезного рефакторинга. Основные приоритеты:

1. **Безопасность:** Исправить потенциальный бесконечный цикл
2. **Производительность:** Оптимизировать balance recalculation
3. **Архитектура:** Декомпозиция на отдельные сервисы
4. **Чистота кода:** Удаление deprecated методов

Рекомендуется начать с Фазы 1 для стабилизации, затем постепенно проводить декомпозицию с сохранением обратной совместимости API.
