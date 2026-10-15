# Debug: Delete Transaction Balance Issue

## 🔍 Диагностика проблемы обнуления балансов

Добавлено детальное логирование для выявления причины обнуления балансов при удалении транзакции.

---

## 📝 Инструкция по тестированию

### Шаг 1: Подготовка
1. Запустите приложение
2. Откройте Xcode Console (⌘ + Shift + C)
3. Очистите console (кнопка 🗑️)

### Шаг 2: Удаление транзакции
1. Откройте список транзакций
2. **ЗАПОМНИТЕ** текущий баланс счета (например, "Kaspi: 51,409.84 ₸")
3. **ВЫБЕРИТЕ** транзакцию для удаления (запомните сумму)
4. **УДАЛИТЕ** транзакцию
5. **ПОСМОТРИТЕ** новый баланс в UI

### Шаг 3: Скопируйте логи
В Console найдите секцию, начинающуюся с:
```
🗑️ [TRANSACTION] ========== DELETING TRANSACTION ==========
```

И заканчивающуюся:
```
✅ [TRANSACTION] ========== DELETE COMPLETED ==========
```

**Скопируйте ВСЕ логи** между этими маркерами.

---

## 🔎 Что искать в логах

### 1. Балансы ДО удаления
```
💰 [TRANSACTION] BALANCES BEFORE DELETE:
   💳 'Kaspi Gold': 51409.84
   💳 'Jusan': 398695.57
```

### 2. Initial balances
```
📊 [TRANSACTION] Initial balances: ["ABC123": 50000.0, "XYZ789": 400000.0]
```

### 3. Пересчет балансов
```
🔄 [BALANCE] Starting recalculateAccountBalances
💰 [BALANCE] BEFORE - Account 'Kaspi Gold' (ID: ABC123): balance = 51409.84
...
💳 [BALANCE] REGULAR 'Kaspi Gold': 51409.84 -> 56409.84 (initial: 50000.0, changes: 6409.84)
💰 [BALANCE] AFTER - Account 'Kaspi Gold' (ID: ABC123): balance = 56409.84
```

### 4. Синхронизация с AccountsViewModel
```
🔗 [BALANCE] Syncing balances with AccountsViewModel
📊 [BALANCE] Accounts to sync:
   💳 'Kaspi Gold': 56409.84
```

### 5. Сохранение в Core Data
```
💾 [BALANCE] Saving updated balances to Core Data
💾 [ACCOUNT] Saving all accounts synchronously
   💰 'Kaspi Gold': balance = 56409.84
✅ [CORE_DATA_REPO] Accounts saved synchronously
```

### 6. Асинхронное сохранение
```
💾 [STORAGE] ========== STARTING ASYNC SAVE ==========
💾 [STORAGE] Captured 8 accounts from TransactionsViewModel:
   💰 'Kaspi Gold': balance = 56409.84
```

---

## ⚠️ Возможные проблемы

### Проблема 1: accountsViewModel = nil
```
⚠️ [BALANCE] AccountsViewModel is nil, skipping balance sync
```

**Причина:** `TransactionsViewModel.accountsViewModel` не инициализирован  
**Решение:** Проверить `AppCoordinator` - должен быть `transactionsViewModel.accountsViewModel = accountsViewModel`

### Проблема 2: Initial balance неправильный
```
💳 [BALANCE] REGULAR 'Kaspi': 51409.84 -> 0.0 (initial: -45000.0, changes: 45000.0)
```

**Причина:** `initialAccountBalances` рассчитан неправильно при импорте  
**Решение:** Сбросить балансы через Settings → Reset Balances

### Проблема 3: Старые балансы в async save
```
💾 [STORAGE] Captured 8 accounts from TransactionsViewModel:
   💰 'Kaspi Gold': balance = 51409.84  ← Старый баланс!
```

**Причина:** Race condition - `saveToStorage()` захватил балансы ДО пересчета  
**Решение:** Изменить порядок вызовов в `deleteTransaction()`

### Проблема 4: Два разных баланса
```
💾 [ACCOUNT] Saving all accounts synchronously
   💰 'Kaspi': 56409.84  ← Правильный

💾 [STORAGE] Calling repository.saveAccounts() with:
   💰 'Kaspi': 51409.84  ← Старый (перезаписывает!)
```

**Причина:** `TransactionsViewModel.accounts` и `AccountsViewModel.accounts` рассинхронизированы  
**Решение:** Не сохранять accounts через `TransactionsViewModel.saveToStorage()`

---

## 🛠️ Следующие шаги

После получения логов:

1. **Проверить**, на каком шаге баланс становится 0
2. **Найти** место, где происходит обнуление
3. **Исправить** конкретную проблему
4. **Повторить** тест

---

## 📊 Пример успешного удаления (ожидаемые логи)

```
🗑️ [TRANSACTION] ========== DELETING TRANSACTION ==========
🗑️ [TRANSACTION] Description: Продукты
🗑️ [TRANSACTION] Amount: 5000.0 KZT
🗑️ [TRANSACTION] Type: expense
🗑️ [TRANSACTION] Account ID: ABC123

💰 [TRANSACTION] BALANCES BEFORE DELETE:
   💳 'Kaspi Gold': 51409.84

📊 [TRANSACTION] Initial balances: ["ABC123": 50000.0]

🔄 [BALANCE] Starting recalculateAccountBalances
💰 [BALANCE] BEFORE - Account 'Kaspi Gold': balance = 51409.84
💳 [BALANCE] REGULAR 'Kaspi Gold': 51409.84 -> 56409.84 (initial: 50000.0, changes: 6409.84)
💰 [BALANCE] AFTER - Account 'Kaspi Gold': balance = 56409.84

🔗 [BALANCE] Syncing balances with AccountsViewModel
   💳 'Kaspi Gold': 56409.84

💾 [BALANCE] Saving updated balances to Core Data
💾 [ACCOUNT] Saving all accounts synchronously
   💰 'Kaspi Gold': balance = 56409.84
✅ [CORE_DATA_REPO] Accounts saved synchronously

💰 [TRANSACTION] BALANCES AFTER RECALCULATE:
   💳 'Kaspi Gold': 56409.84

💾 [STORAGE] ========== STARTING ASYNC SAVE ==========
💾 [STORAGE] Captured 8 accounts:
   💰 'Kaspi Gold': balance = 56409.84
✅ [STORAGE] ========== ASYNC SAVE COMPLETED ==========

✅ [TRANSACTION] ========== DELETE COMPLETED ==========
```

В UI должно показывать: **Kaspi Gold: 56,409.84 ₸** ✅

---

## ❓ Что делать дальше

**Пожалуйста, выполните тестирование и пришлите мне:**

1. ✅ Полные логи удаления транзакции
2. ✅ Скриншот баланса в UI после удаления
3. ✅ Информацию о том, какая транзакция была удалена (тип, сумма)

Это поможет точно определить, где происходит обнуление баланса!
