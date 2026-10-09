# Core Data - Фаза 2: Repository Layer & Data Migration

**Дата**: 23 января 2026  
**Статус**: 🔄 В процессе

---

## 📋 Обзор

Фаза 2 включает:
1. ✅ Создание CoreDataRepository
2. ⏳ Миграция данных из UserDefaults в Core Data
3. ⏳ Интеграция CoreDataRepository в AppCoordinator
4. ⏳ Тестирование

---

## ✅ Что уже сделано

### 1. CoreDataRepository создан

**Файл**: `Tenra/Services/CoreDataRepository.swift`

**Реализовано**:
- ✅ `loadTransactions()` / `saveTransactions()` - работа с Core Data
- ✅ `loadAccounts()` / `saveAccounts()` - работа с Core Data
- ⚠️ Остальные методы используют fallback на UserDefaults

**Особенности**:
- Автоматический fallback на UserDefaults при ошибках
- Асинхронное сохранение в фоновом контексте
- Пакетная обработка транзакций
- Управление relationships (account, targetAccount, recurringSeries)

### 2. DataMigrationService создан

**Файл**: `Tenra/Services/DataMigrationService.swift`

**Функции**:
- `isMigrationNeeded()` - проверка, нужна ли миграция
- `migrateAllData()` - полная миграция данных
- `resetMigrationStatus()` - сброс статуса (для тестирования)

**Процесс миграции**:
1. Проверка статуса миграции (ключ: `coreDataMigrationCompleted_v1`)
2. Миграция Accounts → Core Data
3. Миграция Transactions → Core Data (батчами по 500)
4. Установка relationships между Entity
5. Сохранение статуса миграции

---

## 🎯 Следующие шаги

### Шаг 1: Добавить миграцию в AppCoordinator

Обновить `AppCoordinator.swift`:

```swift
@MainActor
class AppCoordinator: ObservableObject {
    // ... existing code ...
    
    private let migrationService = DataMigrationService()
    private var migrationCompleted = false
    
    func initialize() async {
        guard !isInitialized else {
            print("⏭️ [APP_COORDINATOR] Already initialized, skipping")
            return
        }
        
        isInitialized = true
        print("🚀 [APP_COORDINATOR] Starting initialization")
        PerformanceProfiler.start("AppCoordinator.initialize")
        
        // STEP 1: Check and perform migration if needed
        if migrationService.isMigrationNeeded() {
            print("🔄 [APP_COORDINATOR] Starting data migration...")
            do {
                try await migrationService.migrateAllData()
                migrationCompleted = true
                print("✅ [APP_COORDINATOR] Migration completed")
            } catch {
                print("❌ [APP_COORDINATOR] Migration failed: \(error)")
                // Continue with UserDefaults fallback
            }
        } else {
            print("✅ [APP_COORDINATOR] Data already migrated")
            migrationCompleted = true
        }
        
        // TEMPORARY TEST CODE - Test Core Data
        #if DEBUG
        testCoreData()
        #endif
        
        // STEP 2: Load data asynchronously
        await transactionsViewModel.loadDataAsync()
        
        PerformanceProfiler.end("AppCoordinator.initialize")
        print("✅ [APP_COORDINATOR] Initialization complete")
    }
}
```

### Шаг 2: Переключить на CoreDataRepository (опционально)

**Вариант A: Постепенная миграция (рекомендуется)**

Оставить UserDefaultsRepository по умолчанию, но разрешить переключение:

```swift
// В AppCoordinator.swift
init(useCoreData: Bool = false) {
    let repository: DataRepositoryProtocol = useCoreData 
        ? CoreDataRepository() 
        : UserDefaultsRepository()
    
    self.repository = repository
    // ... rest of init
}
```

**Вариант B: Полное переключение**

```swift
// В AppCoordinator.swift
init(repository: DataRepositoryProtocol = CoreDataRepository()) {
    self.repository = repository
    // ... rest of init
}
```

### Шаг 3: Тестирование миграции

#### 3.1. Проверить миграцию в симуляторе

1. Запустить приложение (первый запуск)
2. Проверить консоль:
   ```
   🔄 [MIGRATION] Starting data migration from UserDefaults to Core Data
   📦 [MIGRATION] Migrating accounts...
   📊 [MIGRATION] Found 8 accounts to migrate
   ✅ [MIGRATION] Saved 8 accounts to Core Data
   📦 [MIGRATION] Migrating transactions...
   📊 [MIGRATION] Found 921 transactions to migrate
   📊 [MIGRATION] Migrating in 2 batches
   ✅ [MIGRATION] All transactions migrated successfully
   ✅ [MIGRATION] Data migration completed successfully
   ```
3. Перезапустить приложение
4. Убедиться, что миграция не запускается повторно:
   ```
   ✅ [MIGRATION] Data already migrated, skipping
   ```

#### 3.2. Проверить данные в Core Data

Добавить в `testCoreData()`:

```swift
private func testCoreData() {
    let stack = CoreDataStack.shared
    let context = stack.viewContext
    
    // Check transactions count
    let transactionRequest = TransactionEntity.fetchRequest()
    if let count = try? context.count(for: transactionRequest) {
        print("📊 [CORE_DATA_TEST] Total transactions in Core Data: \(count)")
    }
    
    // Check accounts count
    let accountRequest = AccountEntity.fetchRequest()
    if let count = try? context.count(for: accountRequest) {
        print("📊 [CORE_DATA_TEST] Total accounts in Core Data: \(count)")
    }
    
    // Fetch sample transaction
    transactionRequest.fetchLimit = 1
    transactionRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
    if let transaction = try? context.fetch(transactionRequest).first {
        print("📊 [CORE_DATA_TEST] Latest transaction: \(transaction.descriptionText ?? "N/A")")
        print("   Amount: \(transaction.amount)")
        print("   Account: \(transaction.account?.name ?? "N/A")")
    }
}
```

#### 3.3. Сравнить данные

Создать временный тест для сравнения:

```swift
private func compareData() {
    let userDefaultsRepo = UserDefaultsRepository()
    let coreDataRepo = CoreDataRepository()
    
    let udTransactions = userDefaultsRepo.loadTransactions()
    let cdTransactions = coreDataRepo.loadTransactions()
    
    print("📊 [COMPARISON] UserDefaults: \(udTransactions.count) transactions")
    print("📊 [COMPARISON] Core Data: \(cdTransactions.count) transactions")
    
    if udTransactions.count == cdTransactions.count {
        print("✅ [COMPARISON] Transaction counts match!")
    } else {
        print("⚠️ [COMPARISON] Transaction counts differ!")
    }
    
    let udAccounts = userDefaultsRepo.loadAccounts()
    let cdAccounts = coreDataRepo.loadAccounts()
    
    print("📊 [COMPARISON] UserDefaults: \(udAccounts.count) accounts")
    print("📊 [COMPARISON] Core Data: \(cdAccounts.count) accounts")
    
    if udAccounts.count == cdAccounts.count {
        print("✅ [COMPARISON] Account counts match!")
    } else {
        print("⚠️ [COMPARISON] Account counts differ!")
    }
}
```

---

## 🔧 Troubleshooting

### Проблема: Миграция не запускается

**Решение**: Проверить ключ миграции
```swift
// Сбросить статус миграции
UserDefaults.standard.removeObject(forKey: "coreDataMigrationCompleted_v1")
```

### Проблема: Duplicate key errors

**Причина**: Данные уже существуют в Core Data

**Решение**: Очистить Core Data перед миграцией
```swift
try CoreDataStack.shared.resetAllData()
```

### Проблема: Relationships не устанавливаются

**Причина**: Accounts должны быть мигрированы до Transactions

**Решение**: Убедиться, что порядок миграции:
1. Accounts
2. RecurringSeries
3. Transactions

### Проблема: Медленная миграция

**Решение**: Увеличить размер батча
```swift
let batchSize = 1000 // Вместо 500
```

---

## 📊 Ожидаемые результаты

### Производительность

| Операция | UserDefaults | Core Data | Улучшение |
|----------|-------------|-----------|-----------|
| Загрузка 1000 транзакций | ~200ms | ~50ms | **4x быстрее** |
| Сохранение 100 транзакций | ~150ms | ~30ms | **5x быстрее** |
| Поиск по дате | O(n) | O(log n) | **Значительно** |
| Память | ~15MB | ~5MB | **3x меньше** |

### Функциональность

- ✅ Relationships между сущностями
- ✅ Каскадное удаление
- ✅ Атомарные операции
- ✅ Версионирование модели
- ✅ Индексы для быстрого поиска

---

## ⚠️ Важные замечания

### Совместимость

- CoreDataRepository полностью совместим с DataRepositoryProtocol
- Можно переключаться между UserDefaults и Core Data без изменения ViewModels
- Fallback на UserDefaults при ошибках Core Data

### Безопасность данных

- Миграция не удаляет данные из UserDefaults
- В случае проблем можно вернуться к UserDefaults
- Статус миграции сохраняется в UserDefaults

### Производительность

- Миграция выполняется в фоновом потоке
- Батчами по 500 транзакций для избежания проблем с памятью
- UI не блокируется во время миграции

---

## 🎯 Следующие фазы

### Фаза 3: Полная интеграция Core Data

1. Реализовать RecurringSeriesEntity в Core Data
2. Реализовать CustomCategoryEntity в Core Data
3. Реализовать CategoryRuleEntity в Core Data
4. Удалить fallback на UserDefaults

### Фаза 4: Расширенные функции

1. NSFetchedResultsController для автообновления UI
2. Background синхронизация
3. iCloud sync (опционально)
4. Экспорт/импорт данных

---

## ✅ Checklist

- [x] CoreDataRepository создан
- [x] DataMigrationService создан
- [ ] Миграция добавлена в AppCoordinator
- [ ] Тестирование миграции
- [ ] Сравнение данных UserDefaults vs Core Data
- [ ] Переключение на CoreDataRepository
- [ ] Удаление тестового кода
- [ ] Документирование изменений

---

## 📚 Дополнительные ресурсы

- [core-data-model-instructions.md](core-data-model-instructions.md) - Фаза 1
- [core-data-migration-plan.md](core-data-migration-plan.md) - Общий план
- [CoreDataStack.swift](./Tenra/CoreData/CoreDataStack.swift) - Основной стек

---

**Готовы продолжить?** Следующий шаг: добавить миграцию в AppCoordinator и протестировать.
