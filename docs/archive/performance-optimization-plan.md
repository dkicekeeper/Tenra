# План оптимизации производительности Tenra

## Проблема
При загрузке 19000+ транзакций приложение тормозит при:
- Открытии HistoryView (особенно с фильтром "За все время")
- Переключении между фильтрами
- Запуске приложения
- Переходе на главный экран

## Критические узкие места

### 1. HistoryView - отсутствие пагинации
**Файл**: `Tenra/Views/HistoryView.swift`
**Проблема**: Загружает все транзакции сразу в List
**Решение**: Внедрить пагинацию и LazyVStack

### 2. Множественные фильтрации
**Файл**: `Tenra/ViewModels/TransactionsViewModel.swift:146-208`
**Проблема**: 7 onChange триггеров, каждый пересчитывает все транзакции
**Решение**: Дебаунсинг и батчинг обновлений

### 3. Линейный поиск
**Проблема**: O(n) поиск при каждом изменении фильтров
**Решение**: Индексы для быстрого поиска

### 4. Синхронная конвертация валют
**Файл**: `Tenra/Views/HistoryView.swift:257-285`
**Проблема**: CurrencyConverter.convertSync() в UI потоке
**Решение**: Предварительное кеширование конвертаций

### 5. Тяжелые вычисления summary
**Файл**: `Tenra/ViewModels/TransactionsViewModel.swift:419-606`
**Проблема**: Синхронный пересчет с прогнозом на 2 года
**Решение**: Фоновые вычисления и кеширование

## Конкретные решения

### A. Пагинация в HistoryView (High Priority)

#### Шаг 1: Добавить PaginationManager
```swift
// Tenra/Managers/TransactionPaginationManager.swift
@MainActor
class TransactionPaginationManager: ObservableObject {
    @Published var visibleTransactions: [Transaction] = []
    @Published var hasMore = true

    private let pageSize = 50
    private var allTransactions: [Transaction] = []
    private var currentPage = 0

    func initialize(with transactions: [Transaction]) {
        self.allTransactions = transactions
        self.currentPage = 0
        loadNextPage()
    }

    func loadNextPage() {
        let start = currentPage * pageSize
        let end = min(start + pageSize, allTransactions.count)

        guard start < allTransactions.count else {
            hasMore = false
            return
        }

        let newTransactions = Array(allTransactions[start..<end])
        visibleTransactions.append(contentsOf: newTransactions)
        currentPage += 1
        hasMore = end < allTransactions.count
    }

    func reset() {
        visibleTransactions = []
        currentPage = 0
        hasMore = true
    }
}
```

#### Шаг 2: Интегрировать в HistoryView
Заменить:
```swift
ForEach(grouped[dateKey] ?? []) { transaction in
```
На:
```swift
ForEach(paginationManager.visibleTransactions.filter { grouped[dateKey]?.contains($0) ?? false }) { transaction in
```

Добавить:
```swift
.onAppear {
    if transaction == paginationManager.visibleTransactions.last {
        paginationManager.loadNextPage()
    }
}
```

### B. Индексирование транзакций (High Priority)

#### Создать индексы для быстрого поиска
```swift
// Tenra/Managers/TransactionIndexManager.swift
class TransactionIndexManager {
    private var byAccount: [String: Set<String>] = [:] // accountId -> transactionIds
    private var byCategory: [String: Set<String>] = [:] // category -> transactionIds
    private var byDateRange: [(start: Date, end: Date, ids: Set<String>)] = []
    private var allTransactions: [String: Transaction] = [:] // id -> transaction

    func buildIndexes(transactions: [Transaction]) {
        // Очистить индексы
        byAccount.removeAll()
        byCategory.removeAll()
        byDateRange.removeAll()
        allTransactions.removeAll()

        for tx in transactions {
            allTransactions[tx.id] = tx

            if let accountId = tx.accountId {
                byAccount[accountId, default: []].insert(tx.id)
            }
            byCategory[tx.category, default: []].insert(tx.id)
        }
    }

    func filter(accountId: String? = nil, category: String? = nil) -> [Transaction] {
        var resultIds: Set<String>?

        if let accountId = accountId {
            resultIds = byAccount[accountId]
        }

        if let category = category {
            let categoryIds = byCategory[category] ?? []
            if let existing = resultIds {
                resultIds = existing.intersection(categoryIds)
            } else {
                resultIds = categoryIds
            }
        }

        guard let ids = resultIds else {
            return Array(allTransactions.values)
        }

        return ids.compactMap { allTransactions[$0] }
    }
}
```

### C. Оптимизация конвертации валют (Medium Priority)

#### Предварительное кеширование
```swift
// В TransactionsViewModel добавить:
private var convertedAmountsCache: [String: Double] = [:] // "txId_baseCurrency" -> amount

func precomputeConversions() {
    Task.detached(priority: .utility) {
        let baseCurrency = await MainActor.run { self.appSettings.baseCurrency }
        let transactions = await MainActor.run { self.allTransactions }

        var cache: [String: Double] = [:]

        for tx in transactions {
            let cacheKey = "\(tx.id)_\(baseCurrency)"
            if tx.currency == baseCurrency {
                cache[cacheKey] = tx.amount
            } else if let converted = CurrencyConverter.convertSync(
                amount: tx.amount,
                from: tx.currency,
                to: baseCurrency
            ) {
                cache[cacheKey] = converted
            }
        }

        await MainActor.run {
            self.convertedAmountsCache = cache
        }
    }
}

func getConvertedAmount(transactionId: String, to baseCurrency: String) -> Double? {
    let cacheKey = "\(transactionId)_\(baseCurrency)"
    return convertedAmountsCache[cacheKey]
}
```

Вызывать `precomputeConversions()` после загрузки транзакций и импорта.

### D. Фоновые вычисления summary (Medium Priority)

#### Переместить вычисления в фон
```swift
// В TransactionsViewModel изменить метод summary:
func summary(timeFilterManager: TimeFilterManager) -> Summary {
    // Если кеш актуален, вернуть сразу
    if !summaryCacheInvalidated, let cached = cachedSummary {
        return cached
    }

    // Запустить вычисления в фоне
    Task.detached(priority: .userInitiated) {
        let result = await self.computeSummary(timeFilterManager: timeFilterManager)
        await MainActor.run {
            self.cachedSummary = result
            self.summaryCacheInvalidated = false
        }
    }

    // Вернуть старый кеш или пустой summary
    return cachedSummary ?? Summary(
        totalIncome: 0,
        totalExpenses: 0,
        totalInternalTransfers: 0,
        netFlow: 0,
        currency: appSettings.baseCurrency,
        startDate: "",
        endDate: "",
        plannedAmount: 0
    )
}

private func computeSummary(timeFilterManager: TimeFilterManager) async -> Summary {
    // Текущая логика из summary(), но в фоне
    // ...
}
```

### E. Дебаунсинг фильтров (Low Priority)

Уже реализовано для поиска (HistoryView.swift:104-120), применить к другим фильтрам:

```swift
@State private var filterDebounceTask: Task<Void, Never>?

.onChange(of: selectedAccountFilter) { oldValue, newValue in
    filterDebounceTask?.cancel()
    filterDebounceTask = Task {
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        guard !Task.isCancelled else { return }
        await MainActor.run {
            updateCachedTransactions()
        }
    }
}
```

### F. LazyVStack вместо List (Low Priority)

Для лучшего контроля над рендерингом:
```swift
ScrollView {
    LazyVStack(pinnedViews: [.sectionHeaders]) {
        ForEach(sortedKeys, id: \.self) { dateKey in
            Section {
                ForEach(grouped[dateKey] ?? []) { transaction in
                    TransactionCard(...)
                }
            } header: {
                dateHeader(for: dateKey, transactions: grouped[dateKey] ?? [])
            }
        }
    }
}
```

### G. Оптимизация загрузки при старте (High Priority)

В `TransactionsViewModel.swift:49-62` `init()` вызывает синхронные операции:
```swift
init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
    self.repository = repository
    loadFromStorage() // БЛОКИРУЕТ!
    Task {
        generateRecurringTransactions() // Еще больше работы
    }
}
```

**Решение**: Отложенная загрузка
```swift
init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
    self.repository = repository
    // Не загружаем сразу!
}

func loadDataAsync() async {
    await Task.detached(priority: .userInitiated) {
        let transactions = await self.repository.loadTransactions()
        let rules = await self.repository.loadCategoryRules()
        // ... остальные данные

        await MainActor.run {
            self.allTransactions = transactions
            self.categoryRules = rules
            // ...
            self.recalculateAccountBalances()
            self.generateRecurringTransactions()
        }
    }.value
}
```

Вызывать из AppCoordinator:
```swift
func initialize() async {
    await transactionsViewModel.loadDataAsync()
    await accountsViewModel.loadDataAsync()
}
```

## Приоритеты внедрения

### Фаза 1: Критически важное (1-2 дня)
1. ✅ **Пагинация в HistoryView** - даст мгновенный эффект
2. ✅ **Отложенная загрузка при старте** - быстрый запуск
3. ✅ **Предварительное кеширование конвертаций** - плавная прокрутка

### Фаза 2: Важное (2-3 дня)
4. ✅ **Индексирование транзакций** - быстрые фильтры
5. ✅ **Фоновые вычисления summary** - отзывчивый UI
6. ✅ **Дебаунсинг всех фильтров** - меньше пересчетов

### Фаза 3: Полировка (1-2 дня)
7. ✅ **LazyVStack вместо List** - лучший контроль
8. ✅ **Виртуализация TransactionCard** - меньше памяти

## Ожидаемые результаты

### До оптимизации (19000 транзакций):
- Открытие HistoryView: ~3-5 секунд
- Переключение фильтра: ~2-3 секунды
- Запуск приложения: ~2-4 секунды
- Прокрутка: лаги и фризы

### После оптимизации:
- Открытие HistoryView: <0.5 секунд
- Переключение фильтра: <0.3 секунды
- Запуск приложения: <1 секунда
- Прокрутка: плавная, 60 FPS

## Метрики для отслеживания

Использовать существующий `PerformanceProfiler`:
```swift
PerformanceProfiler.start("HistoryView.loadInitialPage")
// ... код
PerformanceProfiler.end("HistoryView.loadInitialPage")
```

Добавить метрики:
- `history.initial_load` - первая загрузка
- `history.filter_change` - смена фильтра
- `history.pagination` - загрузка страницы
- `app.startup` - запуск приложения
- `summary.calculation` - вычисление summary

## Дополнительные рекомендации

### Использование Core Data (долгосрочно)
UserDefaults не подходит для 19000+ объектов. Рассмотреть миграцию на Core Data:
- Встроенная пагинация через `NSFetchRequest`
- Индексы на уровне БД
- Фоновые контексты для тяжелых операций
- Меньше использования памяти

### Архивирование старых транзакций
Транзакции старше 2 лет можно архивировать:
- Хранить отдельно от активных
- Загружать только по запросу
- Уменьшить объем данных в памяти

### Прогрессивная загрузка
Показывать скелетоны при загрузке:
```swift
if isLoading {
    ForEach(0..<10) { _ in
        TransactionCardSkeleton()
    }
}
```
