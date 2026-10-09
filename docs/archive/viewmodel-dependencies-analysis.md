# Анализ зависимостей TransactionsViewModel

## Текущая структура (2487 строк)

### Основные секции (MARK comments):

1. **Transactions Core** (строки ~83-1243)
   - `allTransactions`, `filteredTransactions`
   - Методы фильтрации и группировки
   - CRUD операции: `addTransaction`, `updateTransaction`, `deleteTransaction`
   - `addTransactions`, `updateTransactionCategory`
   - `summary`, `categoryExpenses`, `popularCategories`

2. **Custom Categories** (строки ~1243-1371)
   - `customCategories`, `categoryRules`
   - CRUD: `addCategory`, `updateCategory`, `deleteCategory`
   - `getCategory`

3. **Accounts** (строки ~1372-1596)
   - `accounts`
   - CRUD: `addAccount`, `updateAccount`, `deleteAccount`
   - `transfer`
   - `recalculateAccountBalances`

4. **Deposits** (строки ~1505-1596)
   - Методы депозитов: `addDeposit`, `updateDeposit`, `deleteDeposit`
   - `addDepositRateChange`, `reconcileAllDeposits`

5. **Recurring Transactions** (строки ~1888-1977)
   - `recurringSeries`, `recurringOccurrences`
   - CRUD: `createRecurringSeries`, `updateRecurringSeries`, `deleteRecurringSeries`
   - `generateRecurringTransactions`

6. **Subscriptions** (строки ~1977-2144)
   - Методы подписок (используют recurringSeries)
   - `subscriptions`, `activeSubscriptions`
   - `createSubscription`, `updateSubscription`, `pauseSubscription`, etc.

7. **Subcategories** (строки ~2400-2478)
   - `subcategories`, `categorySubcategoryLinks`, `transactionSubcategoryLinks`
   - CRUD: `addSubcategory`, `updateSubcategory`, `deleteSubcategory`
   - Linking методы

8. **Storage & Helpers** (разбросано по файлу)
   - `saveToStorage`, `loadFromStorage`
   - `applyRules`, `insertTransactionsSorted`

## Ключевые зависимости

### 1. Transactions → Categories
- **Использование**: 
  - `applyRules(to:)` применяет `categoryRules` к транзакциям
  - `matchCategory` сопоставляет категории транзакций с `customCategories`
  - `createCategoriesForTransactions` создает категории из транзакций
  - `updateTransactionCategory` использует `customCategories`
- **Тип зависимости**: Сильная (бизнес-логика)
- **Последствия разделения**: TransactionsViewModel должен иметь доступ к CategoriesViewModel или его данные

### 2. Transactions → Accounts
- **Использование**:
  - `accountId`, `targetAccountId` в Transaction
  - `recalculateAccountBalances` пересчитывает балансы на основе транзакций
  - `transfer` использует accounts для переводов
- **Тип зависимости**: Сильная (структурная)
- **Последствия разделения**: TransactionsViewModel должен иметь доступ к AccountsViewModel

### 3. Transactions → Subcategories
- **Использование**:
  - `getSubcategoriesForTransaction` в фильтрации
  - `linkSubcategoriesToTransaction`
- **Тип зависимости**: Средняя (частичная)
- **Последствия разделения**: TransactionsViewModel должен иметь доступ к SubcategoriesViewModel

### 4. Categories ↔ Subcategories
- **Использование**:
  - `categorySubcategoryLinks` связывают категории и подкатегории
  - `getSubcategoriesForCategory`
- **Тип зависимости**: Сильная (структурная связь)
- **Последствия разделения**: Могут быть в одном ViewModel или тесно связаны

### 5. Accounts ↔ Transactions
- **Использование**:
  - `deleteAccount` удаляет связанные транзакции
  - `recalculateAccountBalances` использует `allTransactions`
  - Балансы пересчитываются при изменениях транзакций
- **Тип зависимости**: Двусторонняя сильная
- **Последствия разделения**: Сложная циклическая зависимость

### 6. Recurring → Transactions, Categories, Accounts
- **Использование**:
  - `generateRecurringTransactions` создает транзакции
  - Использует категории и счета из транзакций
- **Тип зависимости**: Средняя
- **Последствия разделения**: RecurringViewModel должен иметь доступ к TransactionsViewModel

## Стратегии разделения

### Вариант 1: Минимальное разделение (рекомендуется)
**Оставить TransactionsViewModel как основной**, но выделить:
- **SubcategoriesViewModel** - можно выделить относительно независимо
  - `subcategories`, `categorySubcategoryLinks`, `transactionSubcategoryLinks`
  - CRUD операции
  - Слабая связь с остальным кодом

**Преимущества**:
- Минимальный риск
- Subcategories относительно независимы
- Остальные зависимости слишком тесные

**Недостатки**:
- Основная проблема (большой ViewModel) остается

### Вариант 2: Умеренное разделение
Выделить:
1. **SubcategoriesViewModel** (как в варианте 1)
2. **CategoriesViewModel** - с пониманием, что TransactionsViewModel будет иметь ссылку
   - `customCategories`, `categoryRules`
   - CRUD операции

**Преимущества**:
- Уменьшение размера основного ViewModel
- Categories логически отдельны

**Недостатки**:
- TransactionsViewModel все еще нуждается в доступе к CategoriesViewModel
- Нужно решить проблему синхронизации (ObservableObject, Combine)

### Вариант 3: Агрессивное разделение (не рекомендуется)
Выделить все: Categories, Accounts, Subcategories, Recurring в отдельные ViewModels.

**Проблемы**:
- Сложные циклические зависимости
- Необходимость синхронизации между ViewModels
- Риск потери согласованности данных
- Сложность тестирования
- Большой объем рефакторинга

## Рекомендация

### Краткосрочная (сейчас):
1. ✅ **Выделить SubcategoriesViewModel** - наиболее независимый модуль
2. **Рефакторинг не критичен** - текущая архитектура работает
3. **Фокус на оптимизации** - использовать @StateObject правильно, кеширование

### Среднесрочная (если необходимо):
1. **Выделить CategoriesViewModel** с сохранением ссылки в TransactionsViewModel
2. Использовать Combine для синхронизации
3. Осторожно тестировать изменения

### Долгосрочная (архитектурный рефакторинг):
1. Рассмотреть **Repository pattern** для данных
2. Использовать **Coordinator/Manager** для координации между ViewModels
3. Возможно, перейти на **SwiftData** или другую архитектуру данных

## Метрики сложности

- **Всего строк**: 2487
- **Всего методов**: ~60+
- **@Published свойств**: 11
- **Секций (MARK)**: 8
- **Зависимостей между секциями**: Сильные (циклические)

## Вывод

**Текущее состояние**: TransactionsViewModel - это "God Object", но функционально работоспособный.

**Разделение на отдельные ViewModels возможно, но:**
- Потребует значительных изменений в архитектуре
- Риск появления багов выше
- Выгода от разделения может не оправдать затраты

**Альтернативные подходы к оптимизации:**
1. Оптимизация использования @StateObject vs @ObservedObject
2. Улучшение кеширования (уже частично реализовано)
3. Выделение тяжелых вычислений в отдельные методы/структуры
4. Использование протоколов для лучшей тестируемости
