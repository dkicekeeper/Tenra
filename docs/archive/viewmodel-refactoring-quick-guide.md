# 🚀 ViewModel Refactoring - Quick Guide

**Краткое руководство по использованию новой архитектуры**

---

## 📋 Что изменилось?

### До рефакторинга:
```swift
@ObservedObject var viewModel: TransactionsViewModel

// Все операции через один ViewModel
viewModel.addAccount(...)
viewModel.addCategory(...)
viewModel.createSubscription(...)
viewModel.addDeposit(...)
```

### После рефакторинга:
```swift
@ObservedObject var transactionsViewModel: TransactionsViewModel
@ObservedObject var accountsViewModel: AccountsViewModel
@ObservedObject var categoriesViewModel: CategoriesViewModel
@ObservedObject var subscriptionsViewModel: SubscriptionsViewModel
@ObservedObject var depositsViewModel: DepositsViewModel

// Каждая операция через свой ViewModel
accountsViewModel.addAccount(...)
categoriesViewModel.addCategory(...)
subscriptionsViewModel.createSubscription(...)
depositsViewModel.addDeposit(...)
```

---

## 🎯 Новая архитектура

### ViewModels по ответственности:

1. **TransactionsViewModel** - Транзакции
   - Добавление/удаление/обновление транзакций
   - Фильтрация и поиск
   - Расчет summary и categoryExpenses
   - Применение правил категорий

2. **AccountsViewModel** - Счета
   - CRUD операции со счетами
   - Управление балансами
   - Переводы между счетами
   - Начальные балансы

3. **CategoriesViewModel** - Категории
   - CRUD операции с категориями
   - CRUD операции с подкатегориями
   - Связи категорий и подкатегорий
   - Правила категорий

4. **SubscriptionsViewModel** - Подписки
   - CRUD операции с подписками
   - Управление статусами (активна/приостановлена)
   - Уведомления о подписках

5. **DepositsViewModel** - Депозиты
   - CRUD операции с депозитами
   - Управление процентными ставками
   - Расчет процентов

---

## 🔧 Как использовать в Views

### Вариант 1: Через AppCoordinator (рекомендуется)

```swift
struct MyView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        // Доступ к ViewModels через coordinator
        List(coordinator.accountsViewModel.accounts) { account in
            // ...
        }
    }
}
```

### Вариант 2: Через @ObservedObject

```swift
struct MyView: View {
    @ObservedObject var accountsViewModel: AccountsViewModel
    @ObservedObject var categoriesViewModel: CategoriesViewModel
    
    var body: some View {
        // Использование ViewModels напрямую
        List(accountsViewModel.accounts) { account in
            // ...
        }
    }
}
```

---

## 📝 Примеры миграции

### Пример 1: Добавление счета

**Было:**
```swift
viewModel.addAccount(name: "Новый счет", balance: 1000, currency: "KZT")
```

**Стало:**
```swift
accountsViewModel.addAccount(name: "Новый счет", balance: 1000, currency: "KZT")
```

### Пример 2: Добавление категории

**Было:**
```swift
viewModel.addCategory(category)
```

**Стало:**
```swift
categoriesViewModel.addCategory(category)
```

### Пример 3: Создание подписки

**Было:**
```swift
viewModel.createSubscription(...)
```

**Стало:**
```swift
subscriptionsViewModel.createSubscription(...)
```

---

## ⚠️ Deprecated методы

Все старые методы в `TransactionsViewModel` помечены как `@available(*, deprecated)`. Они все еще работают, но рекомендуется использовать специализированные ViewModels:

- `addAccount` → `AccountsViewModel.addAccount`
- `updateAccount` → `AccountsViewModel.updateAccount`
- `deleteAccount` → `AccountsViewModel.deleteAccount`
- `addCategory` → `CategoriesViewModel.addCategory`
- `updateCategory` → `CategoriesViewModel.updateCategory`
- `deleteCategory` → `CategoriesViewModel.deleteCategory`
- `addSubcategory` → `CategoriesViewModel.addSubcategory`
- `createSubscription` → `SubscriptionsViewModel.createSubscription`
- `addDeposit` → `DepositsViewModel.addDeposit`
- `reconcileAllDeposits` → `DepositsViewModel.reconcileAllDeposits`

---

## 🏗️ Структура проекта

```
Tenra/
├── ViewModels/
│   ├── TransactionsViewModel.swift    # Транзакции
│   ├── AccountsViewModel.swift        # Счета
│   ├── CategoriesViewModel.swift      # Категории
│   ├── SubscriptionsViewModel.swift   # Подписки
│   ├── DepositsViewModel.swift        # Депозиты
│   └── AppCoordinator.swift           # Координатор
├── Services/
│   ├── DataRepositoryProtocol.swift   # Протокол репозитория
│   └── UserDefaultsRepository.swift   # Реализация репозитория
└── Views/
    └── [Все View-файлы обновлены]
```

---

## 🔄 Порядок инициализации

`AppCoordinator` инициализирует ViewModels в правильном порядке:

1. `DataRepository` (UserDefaultsRepository)
2. `AccountsViewModel` (зависит от Repository)
3. `CategoriesViewModel` (зависит от Repository)
4. `SubscriptionsViewModel` (зависит от Repository)
5. `DepositsViewModel` (зависит от Repository и AccountsViewModel)
6. `TransactionsViewModel` (зависит от Repository, AccountsViewModel, CategoriesViewModel)

---

## ✅ Преимущества новой архитектуры

1. **Разделение ответственности** - каждый ViewModel отвечает за свою область
2. **Тестируемость** - легко тестировать каждый ViewModel отдельно
3. **Масштабируемость** - легко добавлять новые функции
4. **Поддерживаемость** - код проще понимать и изменять
5. **Гибкость** - можно легко заменить Repository на CoreData/SwiftData

---

## 📚 Дополнительные ресурсы

- `viewmodel-refactoring-plan.md` - Детальный план рефакторинга
- `viewmodel-refactoring-report.md` - Отчет о выполнении
- `viewmodel-refactoring-complete.md` - Финальный отчет

---

**Версия**: 1.0  
**Дата**: 15 января 2026
