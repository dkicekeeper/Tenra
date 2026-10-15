# 📊 Анализ функционала бюджетирования категорий расходов

**Дата анализа**: 15 января 2026  
**Статус**: ✅ Реализовано и интегрировано  
**Версия**: 1.0

---

## 🎯 Обзор функционала

Бюджетирование категорий расходов позволяет пользователям:
- Устанавливать бюджет для категорий расходов
- Отслеживать прогресс расходования бюджета в реальном времени
- Визуализировать прогресс через круговой индикатор (stroke)
- Настраивать периоды бюджета (неделя/месяц/год)
- Получать визуальную индикацию превышения бюджета

---

## 📐 Архитектура

### 1. Модель данных

#### `CustomCategory` (расширена)
**Файл**: `Tenra/Models/CustomCategory.swift`

**Новые поля**:
```swift
var budgetAmount: Double?           // Сумма бюджета (опционально)
var budgetPeriod: BudgetPeriod      // Период: weekly/monthly/yearly
var budgetStartDate: Date?          // Дата начала отслеживания
var budgetResetDay: Int             // День месяца для сброса (1-31)
```

**Особенности**:
- ✅ Обратная совместимость через опциональные поля
- ✅ Автоматическая инициализация `budgetStartDate` при установке бюджета
- ✅ Дефолтное значение `budgetPeriod = .monthly`
- ✅ Дефолтное значение `budgetResetDay = 1`

#### `BudgetProgress` (новая модель)
**Файл**: `Tenra/Models/BudgetProgress.swift`

**Структура**:
```swift
struct BudgetProgress {
    let budgetAmount: Double      // Общий бюджет
    let spent: Double            // Потрачено в текущем периоде
    let remaining: Double        // Остаток (автоматически вычисляется)
    let percentage: Double       // Процент использования (0-100+)
    let isOverBudget: Bool       // Превышен ли бюджет
}
```

**Логика расчета**:
- `remaining = budgetAmount - spent`
- `percentage = (spent / budgetAmount) * 100` (может быть > 100%)
- `isOverBudget = spent > budgetAmount`

---

### 2. ViewModel слой

#### `CategoriesViewModel`
**Файл**: `Tenra/ViewModels/CategoriesViewModel.swift`

**Новые методы**:

##### `setBudget(for:amount:period:resetDay:)`
```swift
func setBudget(
    for categoryId: String,
    amount: Double,
    period: CustomCategory.BudgetPeriod = .monthly,
    resetDay: Int = 1
)
```
- Устанавливает или обновляет бюджет для категории
- Автоматически устанавливает `budgetStartDate = Date()`
- Сохраняет изменения через `updateCategory()`

##### `removeBudget(for:)`
```swift
func removeBudget(for categoryId: String)
```
- Удаляет бюджет из категории
- Устанавливает `budgetAmount = nil` и `budgetStartDate = nil`

##### `budgetProgress(for:transactions:)`
```swift
func budgetProgress(
    for category: CustomCategory,
    transactions: [Transaction]
) -> BudgetProgress?
```
- Вычисляет прогресс бюджета для категории
- Возвращает `nil` если:
  - Категория не имеет бюджета (`budgetAmount == nil`)
  - Категория не является расходом (`type != .expense`)
- Использует `calculateSpent()` для подсчета потраченной суммы

##### `calculateSpent(for:transactions:)` (private)
```swift
private func calculateSpent(
    for category: CustomCategory,
    transactions: [Transaction]
) -> Double
```
- Фильтрует транзакции по:
  - Названию категории
  - Типу (только `.expense`)
  - Дате (в пределах текущего периода)
- Суммирует суммы отфильтрованных транзакций

##### `budgetPeriodStart(for:)` (private)
```swift
private func budgetPeriodStart(for category: CustomCategory) -> Date
```
- Вычисляет начало текущего периода бюджета:
  - **Weekly**: Начало текущей недели (воскресенье)
  - **Monthly**: День месяца `budgetResetDay` (если еще не наступил в этом месяце → предыдущий месяц)
  - **Yearly**: Начало текущего года (1 января)

**Особенности расчета периода**:
- Для месячного бюджета с `resetDay = 15`:
  - Если сегодня 10 января → период: 15 декабря - 10 января
  - Если сегодня 20 января → период: 15 января - 20 января
- Использует `Calendar.current` для корректной работы с датами

---

### 3. UI компоненты

#### `CategoryRow` (обновлен)
**Файл**: `Tenra/Views/CategoriesManagementView.swift` (строки 134-231)

**Визуальные элементы**:

1. **Круговой индикатор прогресса** (stroke):
   ```swift
   Circle()
       .trim(from: 0, to: min(progress.percentage / 100, 1.0))
       .stroke(progress.isOverBudget ? Color.red : Color.green, ...)
   ```
   - Зеленый: 0-100% (в пределах бюджета)
   - Красный: >100% (превышен бюджет)
   - Анимация: 0.3s easeInOut
   - Размер: 50x50 (внешний), 44x44 (иконка)

2. **Текстовая информация**:
   - Формат: `"5000 / 10000₸ (50%)"`
   - Красный цвет текста при превышении бюджета
   - "No budget set" для категорий без бюджета

3. **Кнопка управления бюджетом**:
   - `"plus.circle"` если бюджета нет
   - `"pencil.circle"` если бюджет установлен
   - Открывает `SetBudgetSheet`

#### `SetBudgetSheet` (новый компонент)
**Файл**: `Tenra/Views/SetBudgetSheet.swift`

**Функционал**:
- Ввод суммы бюджета (TextField с `.decimalPad`)
- Выбор периода (Picker: Weekly/Monthly/Yearly)
- Настройка дня сброса (Stepper 1-31, только для Monthly)
- Отображение текущего бюджета (если существует)
- Кнопка удаления бюджета (destructive)
- Валидация: сумма > 0

**Локализация**:
- Все строки используют `String(localized:)`
- Поддержка EN + RU

#### `CategoryChipWithBudget` (новый компонент)
**Файл**: `Tenra/Views/Components/CategoryChipWithBudget.swift`

**Назначение**: Переиспользуемый компонент для отображения категории с индикатором бюджета

**Использование**: В настоящее время не используется в основном UI (CategoryRow имеет встроенную реализацию)

---

## 🔄 Поток данных

### Установка бюджета:
```
User → CategoryRow (tap "+") 
     → SetBudgetSheet (enter amount/period)
     → CategoriesViewModel.setBudget()
     → CustomCategory.budgetAmount = amount
     → Repository.saveCategories()
     → UI обновляется автоматически (@Published)
```

### Расчет прогресса:
```
CategoriesManagementView.render()
     → categoriesViewModel.budgetProgress(for:category, transactions:allTransactions)
     → calculateSpent() [фильтрует транзакции по периоду]
     → budgetPeriodStart() [вычисляет начало периода]
     → BudgetProgress(spent:spent, budgetAmount:budgetAmount)
     → CategoryRow отображает прогресс
```

### Обновление при добавлении транзакции:
```
TransactionsViewModel.addTransaction()
     → transactionsViewModel.allTransactions обновляется
     → CategoriesManagementView пересчитывает budgetProgress
     → CategoryRow обновляет stroke и текст
```

---

## 🎨 Визуальный дизайн

### Индикатор прогресса (stroke):

**Без бюджета**:
```
┌─────────┐
│  🍔 Food │  ← Нет stroke
└─────────┘
```

**В пределах бюджета (50%)**:
```
┌─────────┐
╱  🍔 Food  ╲  ← Зеленый stroke (половина круга)
│         │
 ╲ 5000/10000╱
  └─────────┘
```

**Превышен бюджет (120%)**:
```
┌─────────┐
╱  🚗 Auto  ╲  ← Красный stroke (полный круг)
│         │
 ╲ 12000/10000╱
  └─────────┘
```

### Цветовая схема:
- **Зеленый** (`Color.green`): 0-100% использования
- **Красный** (`Color.red`): >100% использования
- **Вторичный** (`Color.secondary`): Текст процента
- **Красный текст**: Сумма при превышении бюджета

---

## 📊 Интеграция с существующей архитектурой

### Зависимости:

1. **CategoriesViewModel**:
   - Использует `DataRepositoryProtocol` для сохранения
   - Не зависит от `TransactionsViewModel` (получает транзакции как параметр)

2. **CategoriesManagementView**:
   - Получает `transactionsViewModel.allTransactions` для расчета прогресса
   - Передает транзакции в `budgetProgress()`

3. **CustomCategory**:
   - Расширена без breaking changes
   - Обратная совместимость через опциональные поля

### Обратная совместимость:

✅ **Старые категории без бюджета**:
- `budgetAmount == nil` → бюджет не отображается
- `budgetPeriod` имеет дефолтное значение `.monthly`
- `budgetStartDate == nil` → `budgetPeriodStart()` возвращает текущую дату

✅ **Старые данные**:
- Decoder обрабатывает отсутствие бюджетных полей
- Использует дефолтные значения при отсутствии

---

## 🔍 Детали реализации

### Расчет периода для Monthly бюджета:

```swift
// Пример: resetDay = 15, сегодня = 10 января
let components = calendar.dateComponents([.year, .month], from: now) // 2026, 1
var startComponents = components
startComponents.day = 15 // 2026, 1, 15

let resetDate = calendar.date(from: startComponents) // 15 января 2026
if resetDate > now { // 15 января > 10 января
    // Еще не наступил → используем предыдущий месяц
    return calendar.date(byAdding: .month, value: -1, to: resetDate) // 15 декабря 2025
}
```

### Фильтрация транзакций:

```swift
transactions.filter { transaction in
    guard transaction.category == category.name,      // Совпадение категории
          transaction.type == .expense,                // Только расходы
          let transactionDate = dateFormatter.date(from: transaction.date) else {
        return false
    }
    return transactionDate >= periodStart && transactionDate <= periodEnd
}
```

**Важно**: Использует `DateFormatter` с форматом `"yyyy-MM-dd"` для парсинга даты транзакции.

---

## ⚠️ Потенциальные проблемы и ограничения

### 1. Производительность:
- `budgetProgress()` вызывается для каждой категории при каждом рендере
- Фильтрация транзакций происходит каждый раз
- **Решение**: Можно кэшировать результаты, но пока не критично

### 2. Точность дат:
- Использует `DateFormatter` для парсинга дат транзакций
- Зависит от формата даты в модели `Transaction`
- **Риск**: Если формат изменится, расчет сломается

### 3. Граничные случаи:
- **День 31 в феврале**: `budgetResetDay = 31` → может вызвать проблемы
- **Високосные годы**: Не обрабатывается явно (полагается на Calendar)
- **Часовые пояса**: Использует `Calendar.current` (локальное время)

### 4. Только расходы:
- Бюджет работает только для категорий типа `.expense`
- Доходы (`income`) не поддерживают бюджетирование
- **Ожидаемое поведение**: По дизайну

---

## 🧪 Тестирование

### Ручное тестирование (из документации):

#### Базовые операции:
- [ ] Создание бюджета (сумма, период, день сброса)
- [ ] Редактирование бюджета
- [ ] Удаление бюджета
- [ ] Отображение прогресса

#### Расчет прогресса:
- [ ] Добавление транзакций → обновление прогресса
- [ ] Превышение бюджета → красный индикатор
- [ ] Разные периоды (weekly/monthly/yearly)

#### Граничные случаи:
- [ ] День 31 в феврале
- [ ] Переход между месяцами
- [ ] Начало/конец года

### Автоматическое тестирование:
- ❌ Unit тесты отсутствуют
- ❌ UI тесты отсутствуют
- **Рекомендация**: Добавить тесты для `budgetPeriodStart()` и `calculateSpent()`

---

## 📈 Метрики и статистика

### Код:
- **Новые файлы**: 3 (BudgetProgress.swift, SetBudgetSheet.swift, CategoryChipWithBudget.swift)
- **Измененные файлы**: 4 (CustomCategory.swift, CategoriesViewModel.swift, CategoriesManagementView.swift, Localizable.strings)
- **Новых строк кода**: ~260
- **Измененных строк**: ~130
- **Всего**: ~390 строк

### Функционал:
- **Методы ViewModel**: 5 новых методов
- **UI компоненты**: 2 новых компонента
- **Локализация**: 14 новых ключей (EN + RU)

---

## 🚀 Возможные улучшения

### Краткосрочные (v1.1):
1. **Уведомления**:
   - Push-уведомления при 80%, 100%, 120% использования
   - Локальные уведомления через `UNUserNotificationCenter`

2. **Кэширование**:
   - Кэш результатов `budgetProgress()` для производительности
   - Инвалидация при изменении транзакций

3. **Тестирование**:
   - Unit тесты для `budgetPeriodStart()` и `calculateSpent()`
   - UI тесты для SetBudgetSheet

### Среднесрочные (v1.2):
1. **История бюджета**:
   - Сохранение истории использования по периодам
   - Графики трендов

2. **Аналитика**:
   - Средние расходы по категориям
   - Рекомендации по бюджету на основе истории

3. **Общий бюджет**:
   - Сумма всех бюджетов категорий
   - Общий прогресс расходов

### Долгосрочные (v2.0):
1. **Гибкие периоды**:
   - Кастомные периоды (например, каждые 2 недели)
   - Календарные периоды (например, с 1 по 15 число)

2. **Бюджетные правила**:
   - Автоматическое распределение бюджета
   - Перенос остатка на следующий период

---

## 📚 Связанные файлы

### Модели:
- `Tenra/Models/CustomCategory.swift`
- `Tenra/Models/BudgetProgress.swift`
- `Tenra/Models/Transaction.swift` (используется для расчета)

### ViewModels:
- `Tenra/ViewModels/CategoriesViewModel.swift`
- `Tenra/ViewModels/TransactionsViewModel.swift` (предоставляет транзакции)

### Views:
- `Tenra/Views/CategoriesManagementView.swift`
- `Tenra/Views/SetBudgetSheet.swift`
- `Tenra/Views/Components/CategoryChipWithBudget.swift`

### Локализация:
- `Tenra/en.lproj/Localizable.strings`
- `Tenra/ru.lproj/Localizable.strings`

### Документация:
- `budget-feature-implementation-complete.md`
- `budget-feature-ui-integration-complete.md`

---

## ✅ Заключение

Функционал бюджетирования категорий расходов **полностью реализован и интегрирован** в приложение. Архитектура следует существующим паттернам проекта, обеспечивает обратную совместимость и готова к использованию.

**Статус**: ✅ Production Ready (требуется ручное тестирование)

**Следующие шаги**:
1. Ручное тестирование всех сценариев
2. Проверка локализации (EN + RU)
3. Тестирование accessibility (VoiceOver)
4. Опционально: добавление unit тестов

---

**Подготовлено**: Claude Sonnet 4.5  
**Дата**: 15 января 2026  
**Версия документа**: 1.0
