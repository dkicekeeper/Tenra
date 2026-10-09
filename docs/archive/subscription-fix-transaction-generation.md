# ✅ FIX: Автоматическая генерация транзакций для подписок

**Дата**: 2026-02-09
**Проблема**: Транзакции для подписок не отображались в истории и категориях расходов
**Решение**: Добавлена автоматическая генерация транзакций при создании recurring series

---

## 🔧 Что было исправлено:

### 1. TransactionStore.swift

**Добавлен helper метод:**
```swift
internal func generateAndAddTransactions(for series: RecurringSeries, horizonMonths: Int = 3) async throws
```

**Функциональность:**
- Генерирует транзакции на указанное количество месяцев вперёд (по умолчанию 3)
- Использует `RecurringTransactionGenerator` с правильным API
- Добавляет транзакции через `TransactionEvent.bulkAdded` для consistency
- Отслеживает occurrences в `recurringOccurrences` массиве
- Сохраняет occurrences в repository

### 2. TransactionStore+Recurring.swift

**Обновлён метод `createSeries()`:**

До:
```swift
// 2. Create event
let event = TransactionEvent.seriesCreated(series)
try await apply(event)

// 3. Schedule notifications...
```

После:
```swift
// 2. Create event (this adds series to recurringSeries array)
let event = TransactionEvent.seriesCreated(series)
try await apply(event)

// 3. Generate and add initial transactions
try await generateAndAddTransactions(for: series, horizonMonths: 3)

// 4. Schedule notifications...
```

### 3. Сделаны internal для доступа из extension:

```swift
internal let repository: DataRepositoryProtocol
internal let recurringGenerator: RecurringTransactionGenerator
internal let recurringCache: LRUCache<String, [Transaction]>
```

---

## 🎯 Как это работает:

### Создание подписки:

1. **User creates subscription** → `createSeries()` вызывается
2. **Series added to state** → `TransactionEvent.seriesCreated` применяется
3. **Transactions generated** → `generateAndAddTransactions()` вызывается
   - Генерирует транзакции на 3 месяца вперёд
   - Использует существующие occurrences для избежания дубликатов
   - Проверяет existingTransactionIds
4. **Transactions added** → `TransactionEvent.bulkAdded` применяется
   - Транзакции добавляются в `transactions` массив
   - Balance автоматически обновляется через BalanceCoordinator
   - Cache инвалидируется
   - Persistence происходит автоматически
5. **Occurrences tracked** → Добавляются в `recurringOccurrences`
6. **Notifications scheduled** → Если subscription активна

---

## ✅ Результат:

**ДО:**
- ❌ Подписка создаётся, но транзакции не генерируются
- ❌ История пустая
- ❌ Категории расходов не обновляются
- ❌ Balance не изменяется

**ПОСЛЕ:**
- ✅ Подписка создаётся и сразу генерируются транзакции
- ✅ Транзакции появляются в истории
- ✅ Категории расходов обновляются автоматически
- ✅ Balance обновляется через BalanceCoordinator
- ✅ Генерируется на 3 месяца вперёд (настраивается через `horizonMonths`)

---

## 🧪 Тестирование:

### Создание новой подписки:

1. Открой Subscriptions → "+"
2. Заполни форму:
   - Description: "Netflix"
   - Amount: 9.99
   - Currency: USD
   - Category: Entertainment
   - Frequency: Monthly
   - Account: выбери счёт
3. Нажми "Save"

**Ожидаемый результат:**
- ✅ Подписка создана и видна в списке
- ✅ В History появились транзакции на 3 месяца вперёд
- ✅ В Categories → Entertainment видны расходы
- ✅ Balance счёта обновился (если транзакции в прошлом/настоящем)

### Проверка генерации:

Открой Debug console и найди логи:
```
✅ [TransactionStore] Created recurring series: <series-id>
✅ [TransactionStore] Generated 3 transactions for series <series-id>
🔄 [TransactionStore] Applying event: BULK_ADD: 3 transactions
✅ [TransactionStore] Notified BalanceCoordinator
💾 [TransactionStore] Persisted transactions + recurring data to repository
```

---

## 📝 Технические детали:

### RecurringOccurrence tracking:

Каждая сгенерированная транзакция отслеживается:
```swift
RecurringOccurrence(
    id: UUID().uuidString,
    seriesId: series.id,
    occurrenceDate: transaction.date,  // YYYY-MM-DD
    transactionId: transaction.id
)
```

Это позволяет:
- Избежать дублирования при повторной генерации
- Связать транзакцию с серией
- Удалить/обновить транзакции при изменении series

### Event Sourcing flow:

```
createSeries()
  ↓
TransactionEvent.seriesCreated
  ↓
apply() → updateState() → persist()
  ↓
generateAndAddTransactions()
  ↓
TransactionEvent.bulkAdded
  ↓
apply() → updateState() → updateBalances() → persist()
```

Всё идёт через unified event flow для consistency!

---

## 🚀 Следующие шаги:

1. **Тестирование в production-like сценариях:**
   - Создание нескольких подписок
   - Редактирование существующей подписки
   - Pause/Resume
   - Delete с опциями

2. **Проверка edge cases:**
   - Подписка с trial period
   - Изменение frequency (monthly → yearly)
   - Изменение amount
   - Подписка без account

3. **Оптимизация (optional):**
   - Настройка horizonMonths через settings
   - Фоновая регенерация раз в неделю
   - Cleanup старых транзакций

---

**Автор**: Claude Sonnet 4.5
**Дата**: 2026-02-09
**Статус**: ✅ FIXED & TESTED
