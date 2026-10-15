# Subscription → TransactionStore Direct Integration

> **Дата:** 2026-02-09
> **Версия:** Aggressive (No Users)
> **Время:** 15 часов (5 фаз)
> **Подход:** Прямая интеграция в TransactionStore без промежуточных слоев

---

## 🎯 Стратегия: Aggressive Integration

**Почему можем быть агрессивными:**
- ✅ Нет живых пользователей → нет backward compatibility
- ✅ Можем удалять старый код без deprecation warnings
- ✅ Можем ломать существующие API
- ✅ Можем менять data model без миграций

**Целевая архитектура:**
```
TransactionStore (SINGLE SOURCE OF TRUTH)
├── @Published transactions: [Transaction]
├── @Published accounts: [Account]
├── @Published categories: [CustomCategory]
├── @Published recurringSeries: [RecurringSeries]      ✨ NEW
├── @Published recurringOccurrences: [RecurringOccurrence] ✨ NEW
│
├── CRUD: add/update/delete/transfer
├── Recurring: createSeries/updateSeries/stopSeries/deleteSeries ✨ NEW
├── Recurring Queries: getPlannedTransactions/nextChargeDate ✨ NEW
│
└── Internal: balanceCoordinator + cache + generator + validator
```

**Преимущества:**
- ✅ Одно место для всех данных
- ✅ Автоматические обновления балансов
- ✅ Единый cache invalidation
- ✅ Простая архитектура

---

## 📊 Метрики (Aggressive vs Conservative)

| Метрика | Conservative | Aggressive | Разница |
|---------|-------------|-----------|---------|
| **Время реализации** | 25 часов | **15 часов** | **-40%** ⚡ |
| **Количество файлов** | +2 новых | +0 новых | **Проще** |
| **LOC изменений** | ~800 LOC | ~500 LOC | **-37%** |
| **Coordinator слой** | Нужен | **НЕ нужен** | **Проще** ✅ |
| **Cache service** | Отдельный файл | **В TransactionStore** | **Проще** ✅ |
| **Backward compatibility** | Сохраняется | **Удаляется** | **Чище** ✅ |
| **Результат** | 3 слоя | **1 слой** | **80% проще** 🎯 |

---

## 🗺️ План (5 фаз, 15 часов)

### ФАЗА 1: Extend TransactionStore — 4 часа
**Добавить recurring data в TransactionStore**

#### Шаг 1.1: Add @Published properties (30 мин)
```swift
@MainActor
final class TransactionStore: ObservableObject {
    // Existing
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var categories: [CustomCategory] = []

    // ✨ NEW: Recurring data
    @Published private(set) var recurringSeries: [RecurringSeries] = []
    @Published private(set) var recurringOccurrences: [RecurringOccurrence] = []

    // Dependencies
    private let generator: RecurringTransactionGenerator
    private let validator: RecurringValidationService
    private let recurringCache: LRUCache<String, [Transaction]>

    init(
        repository: DataRepositoryProtocol,
        balanceCoordinator: BalanceCoordinator,
        cacheCapacity: Int = 1000
    ) {
        // ...existing...

        // ✨ NEW
        self.generator = RecurringTransactionGenerator()
        self.validator = RecurringValidationService()
        self.recurringCache = LRUCache<String, [Transaction]>(maxSize: 100)
    }
}
```

#### Шаг 1.2: Add loadData for recurring (30 мин)
```swift
func loadData() async throws {
    // Existing
    accounts = repository.loadAccounts()
    transactions = repository.loadTransactions(dateRange: nil)
    categories = repository.loadCategories()

    // ✨ NEW: Load recurring data
    recurringSeries = repository.loadRecurringSeries()
    recurringOccurrences = repository.loadRecurringOccurrences()

    #if DEBUG
    print("✅ [TransactionStore] Loaded:")
    print("   - Transactions: \(transactions.count)")
    print("   - Recurring Series: \(recurringSeries.count)")
    print("   - Recurring Occurrences: \(recurringOccurrences.count)")
    #endif
}
```

#### Шаг 1.3: Add RecurringTransactionEvent (1 час)
```swift
// Extend existing TransactionEvent enum
enum TransactionEvent {
    // Existing
    case added(Transaction)
    case updated(old: Transaction, new: Transaction)
    case deleted(Transaction)
    case bulkAdded([Transaction])

    // ✨ NEW: Recurring events
    case seriesCreated(RecurringSeries)
    case seriesUpdated(old: RecurringSeries, new: RecurringSeries)
    case seriesStopped(String, fromDate: String)
    case seriesDeleted(String, deleteTransactions: Bool)

    var debugDescription: String {
        switch self {
        case .added(let tx): return "Added: \(tx.id)"
        case .updated(let old, let new): return "Updated: \(old.id) → \(new.id)"
        case .deleted(let tx): return "Deleted: \(tx.id)"
        case .bulkAdded(let txs): return "BulkAdded: \(txs.count) transactions"
        case .seriesCreated(let series): return "SeriesCreated: \(series.id)"
        case .seriesUpdated(let old, let new): return "SeriesUpdated: \(old.id)"
        case .seriesStopped(let id, let date): return "SeriesStopped: \(id) from \(date)"
        case .seriesDeleted(let id, let deleteTransactions): return "SeriesDeleted: \(id), deleteTxns=\(deleteTransactions)"
        }
    }
}
```

#### Шаг 1.4: Implement apply() for recurring events (2 часа)
```swift
private func apply(_ event: TransactionEvent) async throws {
    // 1. Update state (recurringSeries, recurringOccurrences, transactions)
    updateState(event)

    // 2. Update balances (if transactions affected)
    updateBalances(for: event)

    // 3. Invalidate cache
    invalidateCache(for: event)

    // 4. Persist to repository
    try await persist()

    // 5. Notify observers
    objectWillChange.send()
}

private func updateState(_ event: TransactionEvent) {
    switch event {
    case .added(let tx):
        transactions.append(tx)

    case .deleted(let tx):
        transactions.removeAll { $0.id == tx.id }

    // ✨ NEW: Recurring events
    case .seriesCreated(let series):
        recurringSeries.append(series)
        // Generate transactions for this series
        let (newTxs, newOccurrences) = generator.generateTransactions(
            series: [series],
            existingOccurrences: recurringOccurrences,
            existingTransactionIds: Set(transactions.map { $0.id }),
            accounts: accounts,
            horizonMonths: 3
        )
        transactions.append(contentsOf: newTxs)
        recurringOccurrences.append(contentsOf: newOccurrences)

    case .seriesUpdated(let old, let new):
        if let index = recurringSeries.firstIndex(where: { $0.id == old.id }) {
            recurringSeries[index] = new

            // Check if need to regenerate
            if validator.needsRegeneration(oldSeries: old, newSeries: new) {
                // Delete future transactions
                let futureTransactions = transactions.filter { tx in
                    guard tx.recurringSeriesId == old.id else { return false }
                    // TODO: Check if date is in future
                    return true
                }
                transactions.removeAll { tx in
                    futureTransactions.contains { $0.id == tx.id }
                }

                // Regenerate
                let (newTxs, newOccurrences) = generator.generateTransactions(
                    series: [new],
                    existingOccurrences: recurringOccurrences.filter { $0.seriesId != old.id },
                    existingTransactionIds: Set(transactions.map { $0.id }),
                    accounts: accounts,
                    horizonMonths: 3
                )
                transactions.append(contentsOf: newTxs)
                recurringOccurrences.append(contentsOf: newOccurrences)
            }
        }

    case .seriesStopped(let seriesId, let fromDate):
        // Stop series
        if let index = recurringSeries.firstIndex(where: { $0.id == seriesId }) {
            recurringSeries[index].isActive = false
        }

        // Delete future transactions
        // TODO: Implement date filtering

    case .seriesDeleted(let seriesId, let deleteTransactions):
        // Remove series
        recurringSeries.removeAll { $0.id == seriesId }
        recurringOccurrences.removeAll { $0.seriesId == seriesId }

        if deleteTransactions {
            transactions.removeAll { $0.recurringSeriesId == seriesId }
        } else {
            // Convert to regular transactions (remove recurring IDs)
            transactions = transactions.map { tx in
                guard tx.recurringSeriesId == seriesId else { return tx }
                return Transaction(
                    id: tx.id,
                    date: tx.date,
                    description: tx.description,
                    amount: tx.amount,
                    currency: tx.currency,
                    convertedAmount: tx.convertedAmount,
                    type: tx.type,
                    category: tx.category,
                    subcategory: tx.subcategory,
                    accountId: tx.accountId,
                    targetAccountId: tx.targetAccountId,
                    accountName: tx.accountName,
                    targetAccountName: tx.targetAccountName,
                    targetCurrency: tx.targetCurrency,
                    targetAmount: tx.targetAmount,
                    recurringSeriesId: nil,  // ✅ Remove recurring ID
                    recurringOccurrenceId: nil,
                    createdAt: tx.createdAt
                )
            }
        }

    // ... existing cases ...
    }
}
```

---

### ФАЗА 2: Add Recurring CRUD to TransactionStore — 3 часа

#### Шаг 2.1: createSeries() (1 час)
```swift
/// Create a new recurring series
/// Generates transactions for 3 months ahead
func createSeries(_ series: RecurringSeries) async throws {
    // 1. Validate
    try validator.validate(series)

    // 2. Create event
    let event = TransactionEvent.seriesCreated(series)

    // 3. Apply (updates state, balances, cache, persistence)
    try await apply(event)

    // 4. Schedule notifications if subscription
    if series.isSubscription, series.subscriptionStatus == .active {
        if let nextChargeDate = calculateNextChargeDate(for: series) {
            await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                for: series,
                nextChargeDate: nextChargeDate
            )
        }
    }

    #if DEBUG
    print("✅ [TransactionStore] Created recurring series: \(series.id)")
    #endif
}
```

#### Шаг 2.2: updateSeries() (1 час)
```swift
/// Update an existing recurring series
/// Regenerates future transactions if needed
func updateSeries(_ series: RecurringSeries) async throws {
    // Find existing
    guard let old = recurringSeries.first(where: { $0.id == series.id }) else {
        throw TransactionStoreError.transactionNotFound
    }

    // Validate
    try validator.validate(series)

    // Create event
    let event = TransactionEvent.seriesUpdated(old: old, new: series)

    // Apply
    try await apply(event)

    // Update notifications if subscription
    if series.isSubscription {
        await SubscriptionNotificationScheduler.shared.cancelNotifications(for: series.id)
        if series.subscriptionStatus == .active {
            if let nextChargeDate = calculateNextChargeDate(for: series) {
                await SubscriptionNotificationScheduler.shared.scheduleNotifications(
                    for: series,
                    nextChargeDate: nextChargeDate
                )
            }
        }
    }

    #if DEBUG
    print("✅ [TransactionStore] Updated recurring series: \(series.id)")
    #endif
}
```

#### Шаг 2.3: stopSeries() and deleteSeries() (1 час)
```swift
/// Stop a recurring series (no more future transactions)
func stopSeries(id seriesId: String, fromDate: String) async throws {
    // Validate exists
    guard recurringSeries.contains(where: { $0.id == seriesId }) else {
        throw TransactionStoreError.transactionNotFound
    }

    // Create event
    let event = TransactionEvent.seriesStopped(seriesId, fromDate: fromDate)

    // Apply
    try await apply(event)

    // Cancel notifications
    await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)

    #if DEBUG
    print("✅ [TransactionStore] Stopped recurring series: \(seriesId)")
    #endif
}

/// Delete a recurring series
func deleteSeries(id seriesId: String, deleteTransactions: Bool = true) async throws {
    // Validate exists
    guard recurringSeries.contains(where: { $0.id == seriesId }) else {
        throw TransactionStoreError.transactionNotFound
    }

    // Create event
    let event = TransactionEvent.seriesDeleted(seriesId, deleteTransactions: deleteTransactions)

    // Apply
    try await apply(event)

    // Cancel notifications
    await SubscriptionNotificationScheduler.shared.cancelNotifications(for: seriesId)

    #if DEBUG
    print("✅ [TransactionStore] Deleted recurring series: \(seriesId)")
    #endif
}
```

---

### ФАЗА 3: Add Recurring Queries with LRU Cache — 3 часа

#### Шаг 3.1: getPlannedTransactions() with cache (1.5 часа)
```swift
/// Get planned transactions for a recurring series (past + future)
/// Uses LRU cache for O(1) performance on cache hits
func getPlannedTransactions(for seriesId: String, horizonMonths: Int = 3) -> [Transaction] {
    // 1. Try cache first (O(1))
    if let cached = recurringCache.get(seriesId) {
        #if DEBUG
        print("✅ [TransactionStore] Cache HIT for planned transactions: \(seriesId)")
        #endif
        return cached
    }

    #if DEBUG
    print("⚠️ [TransactionStore] Cache MISS for planned transactions: \(seriesId)")
    #endif

    // 2. Cache miss: generate transactions
    guard let series = recurringSeries.first(where: { $0.id == seriesId }) else {
        return []
    }

    // Get existing transactions for this series
    let existingTransactions = transactions.filter { $0.recurringSeriesId == seriesId }

    // Generate planned future transactions
    let existingIds = Set(existingTransactions.map { $0.id })
    let existingOccurrences = recurringOccurrences.filter { $0.seriesId == seriesId }

    let (plannedTransactions, _) = generator.generateTransactions(
        series: [series],
        existingOccurrences: existingOccurrences,
        existingTransactionIds: existingIds,
        accounts: accounts,
        horizonMonths: horizonMonths
    )

    // 3. Combine existing + planned, sorted by date descending
    let allTransactions = (existingTransactions + plannedTransactions)
        .sorted { $0.date > $1.date }

    // 4. Save to cache
    recurringCache.set(allTransactions, forKey: seriesId)

    #if DEBUG
    print("✅ [TransactionStore] Generated \(allTransactions.count) planned transactions for series \(seriesId)")
    #endif

    return allTransactions
}
```

#### Шаг 3.2: nextChargeDate() (1 час)
```swift
/// Calculate next charge date for a subscription
/// Returns nil if not a subscription or inactive
func nextChargeDate(for subscriptionId: String) -> Date? {
    guard let series = recurringSeries.first(where: {
        $0.id == subscriptionId && $0.isSubscription
    }) else {
        return nil
    }

    return SubscriptionNotificationScheduler.shared.calculateNextChargeDate(for: series)
}
```

#### Шаг 3.3: Convenience computed properties (30 мин)
```swift
/// Get all subscriptions (convenience)
var subscriptions: [RecurringSeries] {
    recurringSeries.filter { $0.isSubscription }
}

/// Get active subscriptions (convenience)
var activeSubscriptions: [RecurringSeries] {
    subscriptions.filter { $0.subscriptionStatus == .active && $0.isActive }
}

/// Generate all recurring transactions (3 months ahead)
/// Called at startup and when time passes
func generateAllRecurringTransactions(horizonMonths: Int = 3) async {
    let activeSeries = recurringSeries.filter { $0.isActive }
    guard !activeSeries.isEmpty else { return }

    let existingIds = Set(transactions.map { $0.id })
    let (newTxs, newOccurrences) = generator.generateTransactions(
        series: activeSeries,
        existingOccurrences: recurringOccurrences,
        existingTransactionIds: existingIds,
        accounts: accounts,
        horizonMonths: horizonMonths
    )

    if !newTxs.isEmpty {
        // Use bulkAdded event for efficiency
        let event = TransactionEvent.bulkAdded(newTxs)
        try? await apply(event)

        // Add occurrences
        recurringOccurrences.append(contentsOf: newOccurrences)

        #if DEBUG
        print("✅ [TransactionStore] Generated \(newTxs.count) recurring transactions")
        #endif
    }
}
```

---

### ФАЗА 4: Simplify ViewModels — 3 часа

#### Шаг 4.1: Delete SubscriptionsViewModel entirely (1 час)
```swift
// ❌ DELETE FILE: ViewModels/SubscriptionsViewModel.swift

// Views теперь используют TransactionStore напрямую:
struct SubscriptionsListView: View {
    @EnvironmentObject var transactionStore: TransactionStore

    var body: some View {
        List(transactionStore.activeSubscriptions) { subscription in
            SubscriptionCard(
                subscription: subscription,
                nextChargeDate: transactionStore.nextChargeDate(for: subscription.id)
            )
        }
    }
}
```

#### Шаг 4.2: Update Views to use TransactionStore (2 часа)
**Файлы для обновления:**

1. **SubscriptionsListView.swift**
```swift
// ❌ БЫЛО:
@ObservedObject var subscriptionsViewModel: SubscriptionsViewModel

// ✅ СТАНЕТ:
@EnvironmentObject var transactionStore: TransactionStore

var activeSubscriptions: [RecurringSeries] {
    transactionStore.activeSubscriptions
}
```

2. **SubscriptionDetailView.swift**
```swift
// ❌ БЫЛО:
let plannedTransactions = subscriptionsViewModel.getPlannedTransactions(for: subscription.id)

// ✅ СТАНЕТ:
let plannedTransactions = transactionStore.getPlannedTransactions(for: subscription.id)
```

3. **SubscriptionEditView.swift**
```swift
// ❌ БЫЛО:
func saveSubscription() {
    subscriptionsViewModel.updateSubscription(subscription)
}

// ✅ СТАНЕТ:
func saveSubscription() {
    Task {
        try await transactionStore.updateSeries(subscription)
    }
}
```

4. **TransactionCard.swift**
```swift
// ❌ БЫЛО:
transactionsViewModel.stopRecurringSeriesAndCleanup(seriesId, date)

// ✅ СТАНЕТ:
Task {
    try await transactionStore.stopSeries(id: seriesId, fromDate: date)
}
```

---

### ФАЗА 5: Delete Old Code & Update AppCoordinator — 2 часа

#### Шаг 5.1: Delete deprecated files (30 мин)
```bash
# ❌ DELETE FILES:
rm ViewModels/SubscriptionsViewModel.swift
rm Services/Recurring/RecurringTransactionCoordinator.swift
rm Services/Recurring/RecurringValidationService.swift  # ⚠️ Keep if used by TransactionStore

# ⚠️ KEEP (integrated into TransactionStore):
# - RecurringTransactionGenerator.swift
# - SubscriptionNotificationScheduler.swift
```

#### Шаг 5.2: Update AppCoordinator (1 час)
```swift
@MainActor
class AppCoordinator: ObservableObject {
    // MARK: - ViewModels

    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    // ❌ DELETED: subscriptionsViewModel
    let depositsViewModel: DepositsViewModel
    let transactionsViewModel: TransactionsViewModel
    let settingsViewModel: SettingsViewModel

    // MARK: - Core Services

    let transactionStore: TransactionStore  // ✅ Now includes recurring functionality
    let balanceCoordinator: BalanceCoordinator

    init() {
        let repository = CoreDataRepository.shared

        // 1. Create BalanceCoordinator
        balanceCoordinator = BalanceCoordinator(repository: repository)

        // 2. Create TransactionStore (includes recurring)
        transactionStore = TransactionStore(
            repository: repository,
            balanceCoordinator: balanceCoordinator
        )

        // 3. Create ViewModels
        accountsViewModel = AccountsViewModel(repository: repository)
        categoriesViewModel = CategoriesViewModel(repository: repository)
        // ❌ subscriptionsViewModel removed
        depositsViewModel = DepositsViewModel(repository: repository)
        transactionsViewModel = TransactionsViewModel(repository: repository)
        settingsViewModel = SettingsViewModel(repository: repository)

        // 4. Setup dependencies
        accountsViewModel.transactionStore = transactionStore
        accountsViewModel.balanceCoordinator = balanceCoordinator

        transactionsViewModel.transactionStore = transactionStore
        transactionsViewModel.balanceCoordinator = balanceCoordinator

        depositsViewModel.balanceCoordinator = balanceCoordinator

        // 5. Setup observers
        accountsViewModel.setupTransactionStoreObserver()

        // 6. Load initial data
        Task { @MainActor in
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        // Load data into TransactionStore (includes recurring)
        try? await transactionStore.loadData()

        // Register accounts with BalanceCoordinator
        await balanceCoordinator.registerAccounts(accountsViewModel.accounts)

        // Generate recurring transactions for 3 months ahead
        await transactionStore.generateAllRecurringTransactions(horizonMonths: 3)
    }
}
```

#### Шаг 5.3: Update ContentView environment (30 мин)
```swift
struct ContentView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @EnvironmentObject var timeFilterManager: TimeFilterManager

    // Access TransactionStore directly
    private var transactionStore: TransactionStore {
        appCoordinator.transactionStore
    }

    var body: some View {
        NavigationView {
            ScrollView {
                // Subscriptions card
                NavigationLink(destination: SubscriptionsListView()) {
                    SubscriptionsCardView(
                        subscriptions: transactionStore.activeSubscriptions,
                        baseCurrency: appCoordinator.accountsViewModel.accounts.first?.currency ?? "KZT"
                    )
                }
            }
        }
        .environmentObject(transactionStore)  // ✅ Pass to all child views
    }
}
```

---

## 📊 Результаты Aggressive Approach

### LOC Changes

| Component | Before | After | Change |
|-----------|--------|-------|--------|
| **TransactionStore.swift** | 800 LOC | 1,200 LOC | **+400 LOC** (все recurring functionality) |
| **SubscriptionsViewModel.swift** | 540 LOC | **0 LOC** | **-540 LOC** (DELETED) |
| **RecurringTransactionCoordinator.swift** | 417 LOC | **0 LOC** | **-417 LOC** (DELETED) |
| **RecurringCacheService.swift** | 0 LOC | **0 LOC** | **Not needed** (LRU in TransactionStore) |
| **Views (updates)** | — | — | **-200 LOC** (simplified) |
| **NET CHANGE** | — | — | **-757 LOC** ✅ |

### Architecture Comparison

**Before (Phase 3 — Conservative):**
```
SubscriptionsViewModel (540 LOC)
    ↓
RecurringTransactionCoordinator (417 LOC)
    ↓
RecurringTransactionGenerator (200 LOC)
    ↓
TransactionStore (800 LOC)
    ↓
BalanceCoordinator

Total: 4 layers, ~2000 LOC
```

**After (Aggressive):**
```
TransactionStore (1200 LOC) — включает всё
    ├── @Published recurringSeries
    ├── @Published recurringOccurrences
    ├── createSeries/updateSeries/stopSeries/deleteSeries
    ├── getPlannedTransactions (with LRU cache)
    ├── nextChargeDate
    ├── RecurringTransactionGenerator (internal)
    └── BalanceCoordinator (automatic updates)

Total: 1 layer, ~1400 LOC (generator + store)
```

**Savings:**
- **-30% LOC** overall
- **-75% complexity** (4 layers → 1 layer)
- **-100% ViewModels** для recurring (deleted SubscriptionsViewModel)

---

## 🎯 Success Criteria

### Must Have ✅
- [ ] TransactionStore содержит все recurring data (@Published)
- [ ] CRUD operations для recurring series работают
- [ ] Автоматические обновления балансов при recurring transactions
- [ ] LRU cache для planned transactions (O(1) на cache hits)
- [ ] SubscriptionsViewModel DELETED
- [ ] RecurringTransactionCoordinator DELETED
- [ ] Views обновлены и используют TransactionStore напрямую

### Performance ✅
- [ ] Cache hit: <1ms (было ~50ms)
- [ ] generateAllRecurringTransactions: <200ms для 100 series
- [ ] No UI freezes (no semaphores)

### Testing ✅
- [ ] Unit tests для TransactionStore recurring methods
- [ ] Integration tests end-to-end
- [ ] Manual testing всех subscription flows

---

## ⚠️ Риски Aggressive Approach

### Риск 1: TransactionStore становится большим (1200+ LOC)
**Вероятность:** Высокая
**Влияние:** Среднее (сложнее поддерживать)

**Митигация:**
- ✅ Разбить на extensions:
  ```swift
  // TransactionStore+Recurring.swift
  extension TransactionStore {
      // All recurring methods here
  }
  ```
- ✅ Хорошая документация и комментарии
- ✅ Clear separation внутри файла (MARK: - Recurring Operations)

### Риск 2: Слишком много ответственности в одном классе
**Вероятность:** Средняя
**Влияние:** Среднее (нарушение SRP)

**Митигация:**
- ✅ TransactionStore = **Facade** для всех transaction operations
- ✅ Внутри использует generator, validator (composition)
- ✅ Single Source of Truth оправдывает централизацию
- ✅ Если станет проблемой → легко выделить позже

### Риск 3: Удаление SubscriptionsViewModel ломает Views
**Вероятность:** Средняя
**Влияние:** Высокое (Views не компилируются)

**Митигация:**
- ✅ Пошаговая замена (один View за раз)
- ✅ Compiler укажет все места, требующие изменений
- ✅ Simple find & replace для большинства случаев:
  ```swift
  subscriptionsViewModel.activeSubscriptions
  → transactionStore.activeSubscriptions
  ```

---

## 📅 Timeline

### Realistic: 3 дня (5 hours/day)

**День 1: ФАЗЫ 1-2** (7 часов)
- Extend TransactionStore (4ч)
- Add Recurring CRUD (3ч)
- Тестирование базовых операций

**День 2: ФАЗА 3** (3 часа)
- Add Recurring Queries with Cache (3ч)
- Тестирование cache performance

**День 3: ФАЗЫ 4-5** (5 часов)
- Simplify ViewModels (3ч)
- Delete Old Code & Update AppCoordinator (2ч)
- Integration testing
- Manual testing всех flows

**Total: 15 часов** (vs 25 часов conservative approach)

---

## 🚀 Quick Start

### 1. Backup files
```bash
mkdir -p Docs/backup/aggressive
cp Tenra/ViewModels/TransactionStore.swift Docs/backup/aggressive/
cp Tenra/ViewModels/SubscriptionsViewModel.swift Docs/backup/aggressive/
cp -r Tenra/Services/Recurring/ Docs/backup/aggressive/Recurring/
```

### 2. Start with ФАЗА 1
```bash
# Open TransactionStore.swift
open Tenra/ViewModels/TransactionStore.swift

# Add @Published properties для recurring data
# Add RecurringTransactionEvent cases
# Implement apply() for recurring events
```

### 3. Test after each phase
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## 💡 Ключевые преимущества Aggressive Approach

1. **Простота** — один слой вместо четырех
2. **Скорость** — -40% времени реализации (15ч vs 25ч)
3. **Меньше кода** — -757 LOC overall
4. **Единый источник** — TransactionStore для всего
5. **Автоматические балансы** — через BalanceCoordinator
6. **Чистая архитектура** — нет промежуточных слоев

---

## 📚 Документация

**Этот план:**
- `subscription-transactionstore-integration.md` (этот файл)

**Альтернативный план (conservative):**
- `subscription-full-rebuild-plan.md` (30 страниц, 8 фаз, 25 часов)

**Рекомендация:** **Используйте Aggressive approach** — проще, быстрее, меньше кода.

---

**Готов начать! 🚀**

**Следующий шаг:** ФАЗА 1 → Extend TransactionStore
