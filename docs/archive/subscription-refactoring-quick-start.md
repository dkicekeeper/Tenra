# Subscription Refactoring — Quick Start Guide

> **Дата:** 2026-02-09
> **Версия:** 1.0
> **Для:** Быстрый старт рефакторинга подписок

---

## 🎯 Цель рефакторинга

**Проблема:** Система подписок разбросана между 3 ViewModels, дублирование 365 LOC, нет интеграции с новой архитектурой балансов.

**Решение:** Единая система через `RecurringTransactionCoordinator` + LRU Cache + полная интеграция с `TransactionStore` и `BalanceCoordinator`.

---

## 📊 Ключевые метрики

| Метрика | Было | Станет | Улучшение |
|---------|------|--------|-----------|
| **Дублирование кода** | 365 LOC | 0 LOC | **-100%** |
| **SubscriptionsViewModel** | 540 LOC | 325 LOC | **-40%** |
| **Точек входа** | 6 мест | 1 место | **-83%** |
| **Производительность (cache hit)** | O(n) ~50ms | O(1) <1ms | **50-100x** |
| **Blocking семафоры** | 1 | 0 | **-100%** |
| **Локализация** | 60% | 100% | **+40%** |

---

## 🗺️ Roadmap (8 фаз, 25 часов)

### ФАЗА 0: Подготовка — 2 часа ✅
```bash
git checkout -b feature/subscriptions-full-rebuild-phase9
cp -r Tenra/ViewModels/SubscriptionsViewModel.swift Docs/backup/
```

### ФАЗА 1: RecurringCacheService (LRU Cache) — 4 часа
**Создать:**
- `Services/Recurring/RecurringCacheService.swift` (150 LOC)
- `TenraTests/RecurringCacheServiceTests.swift`

**Что делает:**
- LRU cache для planned transactions (O(1) vs O(n))
- LRU cache для next charge dates
- TTL cache для active subscriptions
- Eviction policy (maxSize: 100)

**API:**
```swift
class RecurringCacheService {
    func getPlannedTransactions(for seriesId: String) -> [Transaction]?
    func setPlannedTransactions(_ transactions: [Transaction], for seriesId: String)
    func invalidate(seriesId: String)
    func invalidateAll()
}
```

---

### ФАЗА 2: TransactionStore Integration — 6 часов
**Обновить:** `Services/Recurring/RecurringTransactionCoordinator.swift`

**Что изменить:**
1. Добавить обязательные зависимости:
   - `transactionStore: TransactionStore` (было optional)
   - `balanceCoordinator: BalanceCoordinator` (NEW)
   - `cacheService: RecurringCacheService` (NEW)

2. Удалить legacy fallback paths:
```swift
// ❌ УДАЛИТЬ:
if let transactionStore = transactionsVM.transactionStore {
    try await transactionStore.delete(transaction)
} else {
    // Fallback: legacy path
}

// ✅ ЗАМЕНИТЬ:
try await transactionStore.delete(transaction)
```

3. Рефакторинг методов:
   - `createSeries()` — через `TransactionStore.add()`
   - `stopSeries()` — без `DispatchSemaphore`
   - `deleteFutureTransactions()` — DRY helper

**Результат:**
- ✅ Автоматические обновления балансов через `BalanceCoordinator`
- ✅ Никаких blocking семафоров
- ✅ Полностью async/await

---

### ФАЗА 3: Cache Integration — 4 часа
**Обновить:** `RecurringTransactionCoordinator`

**Добавить кэширование:**
```swift
func getPlannedTransactions(for seriesId: String) -> [Transaction] {
    // 1. Try cache first (O(1))
    if let cached = cacheService.getPlannedTransactions(for: seriesId) {
        return cached  // ✅ Cache HIT
    }

    // 2. Cache miss: generate + cache
    let transactions = generator.generateTransactions(...)
    cacheService.setPlannedTransactions(transactions, for: seriesId)
    return transactions
}

func nextChargeDate(for subscriptionId: String) -> Date? {
    // Similar caching logic
}
```

**Invalidation триггеры:**
- createSeries() ✅
- updateSeries() ✅
- stopSeries() ✅
- deleteSeries() ✅
- pauseSubscription() ✅

---

### ФАЗА 4: Simplify SubscriptionsViewModel — 3 часа
**Файл:** `ViewModels/SubscriptionsViewModel.swift`

**УДАЛИТЬ:**
- ❌ `getPlannedTransactions()` — 110 LOC (переместить в coordinator)
- ❌ `nextChargeDate()` — 10 LOC (переместить в coordinator)
- ❌ 7 "Internal methods" — 100 LOC (coordinator делает прямые вызовы)
- ❌ 2 helper methods — 50 LOC (уже в generator)

**ДОБАВИТЬ:**
- ✅ `coordinator: RecurringTransactionCoordinatorProtocol` injection
- ✅ Делегирующие методы (50 LOC)

**Результат:** 540 LOC → **325 LOC** (-40%)

---

### ФАЗА 5: Clean TransactionsViewModel — 3 часа
**Файл:** `ViewModels/TransactionsViewModel.swift`

**УДАЛИТЬ:**
- ❌ `stopRecurringSeriesAndCleanup()` — 80 LOC (с семафором)
- ❌ `deleteRecurringSeries()` — 30 LOC
- ❌ `generateRecurringTransactions()` — 40 LOC
- ❌ `setupRecurringSeriesObserver()` — 20 LOC (NotificationCenter)

**Обновить Views:**
- `TransactionCard.swift` — использовать callbacks вместо ViewModel
- `HistoryView.swift` — вызывать coordinator напрямую

**Результат:** 757 LOC → **587 LOC** (-22%)

---

### ФАЗА 6: Update AppCoordinator — 2 часа
**Файл:** `ViewModels/AppCoordinator.swift`

**Добавить:**
```swift
class AppCoordinator {
    let recurringCoordinator: RecurringTransactionCoordinator
    private let recurringCacheService: RecurringCacheService

    init() {
        // Create cache service
        recurringCacheService = RecurringCacheService(maxCacheSize: 100)

        // Create coordinator with all dependencies
        recurringCoordinator = RecurringTransactionCoordinator(
            subscriptionsViewModel: subscriptionsViewModel,
            transactionStore: transactionStore,           // ✅ Required
            balanceCoordinator: balanceCoordinator,       // ✅ NEW
            generator: recurringGenerator,
            validator: recurringValidator,
            cacheService: recurringCacheService,          // ✅ NEW
            repository: repository
        )

        // Property injection to avoid circular dependency
        subscriptionsViewModel.coordinator = recurringCoordinator
    }
}
```

---

### ФАЗА 7: Localization — 3 часа
**Создать:** `Utils/LocalizationKeys.swift`

**Добавить ключи:**
```swift
enum LocalizationKeys {
    enum Subscriptions {
        static let title = "subscriptions.title"
        static let nextCharge = "subscriptions.nextCharge"
        // ...
    }

    enum RecurringErrors {
        static let coordinatorNotInitialized = "recurring.error.coordinatorNotInitialized"
        // ...
    }
}
```

**Обновить:**
- `RecurringTransactionError` — LocalizedError с errorDescription
- `Localizable.strings` (en + ru)

**Результат:** 100% локализация для subscriptions

---

### ФАЗА 8: Testing & Documentation — 4 часа
**Создать:**
- `RecurringTransactionIntegrationTests.swift` (end-to-end тесты)
- `Docs/SUBSCRIPTION_FULL_REBUILD_SUMMARY.md` (итоговая сводка)

**Обновить:**
- `Docs/project-bible.md` — добавить Phase 9
- `Docs/component-inventory.md` — обновить metrics

**Тесты:**
- ✅ createSubscription → balances updated
- ✅ stopSubscription → future transactions deleted
- ✅ updateSubscription → regeneration works
- ✅ Cache performance (10-100x improvement)

---

## ⚡ Quick Commands

### Start рефакторинга
```bash
# 1. Create branch
git checkout -b feature/subscriptions-full-rebuild-phase9

# 2. Backup files
mkdir -p Docs/backup
cp Tenra/ViewModels/SubscriptionsViewModel.swift Docs/backup/
cp -r Tenra/Services/Recurring/ Docs/backup/Recurring_before_phase9/

# 3. Create cache service
touch Tenra/Services/Recurring/RecurringCacheService.swift
touch TenraTests/RecurringCacheServiceTests.swift
```

### Run tests
```bash
# Unit tests
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 15'

# Specific test file
xcodebuild test -scheme Tenra -only-testing:RecurringCacheServiceTests
```

### Check code metrics
```bash
# Count LOC for SubscriptionsViewModel
wc -l Tenra/ViewModels/SubscriptionsViewModel.swift

# Find all recurring-related files
find Tenra -name "*Recurring*" -type f
```

---

## 🎯 Success Criteria

### Must Have ✅
- [x] LRU cache работает (O(1) queries)
- [x] TransactionStore integration (automatic balance updates)
- [x] No DispatchSemaphore (full async/await)
- [x] Дублирование кода устранено (365 LOC → 0)
- [x] 100% локализация subscriptions

### Nice to Have ⭐
- [ ] Performance improvement измерен (before/after)
- [ ] Integration tests покрытие >70%
- [ ] Documentation обновлена (project-bible.md)
- [ ] Migration guide для developers

---

## 🚨 Critical Risks

### Риск 1: Circular Dependency
**Проблема:** SubscriptionsViewModel ↔ Coordinator

**Решение:**
```swift
// Use property injection after init
subscriptionsViewModel.coordinator = recurringCoordinator
```

### Риск 2: Balance Regression
**Проблема:** Неправильные балансы после изменений

**Решение:**
- Comprehensive integration tests
- Manual testing с known scenarios
- Debug logging для всех balance updates

### Риск 3: Cache Invalidation Bugs
**Проблема:** Stale data в UI

**Решение:**
- Invalidate при ВСЕХ CRUD операциях
- TTL для activeSubscriptions (5 мин)
- Manual refresh button

---

## 📚 Документация

**Полный план:**
- `Docs/subscription-full-rebuild-plan.md` (детали всех фаз)

**Текущая архитектура:**
- `Docs/project-bible.md` (Phase 3 recurring system)
- `Docs/component-inventory.md` (ViewModels analysis)

**Новая архитектура балансов:**
- `Services/Balance/BalanceCoordinator.swift` (SSOT для балансов)
- `ViewModels/TransactionStore.swift` (SSOT для транзакций, Phase 7.1)

---

## 🔥 Start Now!

```bash
# 1. Прочитать полный план
open Docs/subscription-full-rebuild-plan.md

# 2. Create branch и backup
git checkout -b feature/subscriptions-full-rebuild-phase9
mkdir -p Docs/backup && cp -r Tenra/Services/Recurring/ Docs/backup/

# 3. Начать с ФАЗЫ 1 (RecurringCacheService)
# См. детали в subscription-full-rebuild-plan.md → ФАЗА 1

# 4. Run tests после каждой фазы
xcodebuild test -scheme Tenra
```

---

**Готов к реализации! 🚀**
