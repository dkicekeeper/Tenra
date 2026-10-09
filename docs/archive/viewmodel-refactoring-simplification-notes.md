# ViewModel Simplification Notes

## Статус упрощения TransactionsViewModel

**Date**: 15 января 2026  
**Status**: ⏳ В процессе

---

## Анализ дублирующихся методов

### Методы, которые должны быть удалены из TransactionsViewModel:

#### 1. Account методы (должны быть в AccountsViewModel):
- `addAccount(name:balance:currency:bankLogo:)` - ✅ Есть в AccountsViewModel
- `updateAccount(_:)` - ✅ Есть в AccountsViewModel
- `deleteAccount(_:)` - ✅ Есть в AccountsViewModel

#### 2. Category методы (должны быть в CategoriesViewModel):
- `addCategory(_:)` - ✅ Есть в CategoriesViewModel
- `updateCategory(_:)` - ✅ Есть в CategoriesViewModel
- `deleteCategory(_:deleteTransactions:)` - ✅ Есть в CategoriesViewModel
- `addSubcategory(name:)` - ✅ Есть в CategoriesViewModel
- `getSubcategoriesForCategory(_:)` - ✅ Есть в CategoriesViewModel
- `linkSubcategoryToCategory(subcategoryId:categoryId:)` - ✅ Есть в CategoriesViewModel
- `unlinkSubcategoryFromCategory(subcategoryId:categoryId:)` - ✅ Есть в CategoriesViewModel

#### 3. Subscription методы (должны быть в SubscriptionsViewModel):
- `createSubscription(...)` - ✅ Есть в SubscriptionsViewModel
- `updateSubscription(_:)` - ✅ Есть в SubscriptionsViewModel
- `pauseSubscription(_:)` - ✅ Есть в SubscriptionsViewModel
- `resumeSubscription(_:)` - ✅ Есть в SubscriptionsViewModel

#### 4. Deposit методы (должны быть в DepositsViewModel):
- `addDeposit(...)` - ✅ Есть в DepositsViewModel
- `updateDeposit(_:)` - ✅ Есть в DepositsViewModel
- `deleteDeposit(_:)` - ✅ Есть в DepositsViewModel
- `addDepositRateChange(...)` - ✅ Есть в DepositsViewModel
- `reconcileAllDeposits()` - ✅ Есть в DepositsViewModel

---

## Проблемы при удалении

### 1. Обратная совместимость
Некоторые методы все еще могут использоваться в старом коде. Нужно проверить все использования.

### 2. Взаимозависимости
TransactionsViewModel использует некоторые данные (например, `accounts`, `customCategories`) для своих операций. Эти свойства должны остаться, но методы управления должны быть удалены.

### 3. reconcileAllDeposits в init
В `init()` TransactionsViewModel вызывается `reconcileAllDeposits()`. Это нужно обновить, чтобы использовать DepositsViewModel.

---

## Рекомендации

### Вариант 1: Постепенное удаление (рекомендуется)
1. Пометить методы как `@available(*, deprecated, message: "Use AccountsViewModel/CategoriesViewModel/etc instead")`
2. Обновить все использования
3. Удалить методы

### Вариант 2: Немедленное удаление
1. Проверить все использования
2. Обновить все вызовы
3. Удалить методы

### Вариант 3: Оставить для обратной совместимости
1. Оставить методы, но они должны делегировать вызовы в специализированные ViewModels
2. Требует добавления зависимостей в TransactionsViewModel

---

## Текущий статус

- ✅ CSVImportService обновлен для использования CategoriesViewModel
- ⏳ Проверка всех использований методов
- ⏳ Удаление дублирующихся методов
- ⏳ Обновление init() для использования DepositsViewModel

---

## Следующие шаги

1. Проверить все использования методов в коде
2. Обновить все вызовы на использование специализированных ViewModels
3. Удалить дублирующиеся методы из TransactionsViewModel
4. Обновить init() TransactionsViewModel
5. Удалить неиспользуемые @Published свойства (если возможно)
