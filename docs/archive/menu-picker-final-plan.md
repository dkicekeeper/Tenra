# MenuPickerRow - Финальный план унификации ✅

> **Дата:** 2026-02-15
> **Цель:** Максимальная унификация на MenuPickerRow
> **Статус:** ✅ ГОТОВ К РЕАЛИЗАЦИИ

---

## 🎯 Что делаем

| Компонент | Действие | Причина | Время |
|-----------|----------|---------|-------|
| **FrequencyPickerView** | ❌ Удалить | Нигде не используется | 1 мин |
| **ReminderPickerView** | ❌ Удалить | Wrapper над MenuPickerRow | 20 мин |
| **BaseCurrencyPickerRow** | ✅ Заменить на MenuPickerRow | Старый picker style | 15 мин |
| **DatePickerRow** | ✅ Оставить | Календарь != Menu | - |
| **CurrencySelectorView** | ✅ Оставить | Filter chip style | - |

**Итого:** ~36 минут

---

## 📋 Детальный план

### Шаг 1: Удалить FrequencyPickerView ❌

**Причина:**
- Нигде не используется (только в старом комментарии)
- 180 строк мертвого кода
- Устаревший компонент

**Действия:**
```bash
rm Tenra/Views/Shared/Components/FrequencyPickerView.swift
```

**Обновить комментарий в SubscriptionEditView.swift:**
```swift
// Было:
//  Uses: FormSection, FormTextField, IconPickerRow, FrequencyPickerView,
//        DatePickerRow, ReminderPickerView

// Стало:
//  Uses: FormSection, FormTextField, IconPickerRow, MenuPickerRow,
//        DatePickerRow
```

**Время:** 1 минута
**Риски:** Нет
**Файлов:** 2 (удалить 1, обновить комментарий в 1)

---

### Шаг 2: Удалить ReminderPickerView ❌

**Причина:**
- Wrapper над MenuPickerRow
- Лишний слой абстракции
- Конвертация Set<Int> ↔ ReminderOption внутри wrapper

**Подшаги:**

#### 2.1. Добавить convenience init в MenuPickerRow

**Файл:** `MenuPickerRow.swift`

```swift
extension MenuPickerRow where T == ReminderOption {
    /// Convenience initializer for ReminderOption
    init(
        title: String = String(localized: "subscription.reminders"),
        selection: Binding<ReminderOption>
    ) {
        self.init(
            icon: "bell",
            title: title,
            selection: selection,
            options: [
                (label: String(localized: "reminder.none"), value: .none),
                (label: String(localized: "reminder.dayBefore.one"), value: .daysBefore(1)),
                (label: String(localized: "reminder.daysBefore.3"), value: .daysBefore(3)),
                (label: String(localized: "reminder.daysBefore.7"), value: .daysBefore(7)),
                (label: String(localized: "reminder.daysBefore.30"), value: .daysBefore(30))
            ]
        )
    }
}
```

#### 2.2. Переместить ReminderOption enum в отдельный файл

**Файл:** `Models/ReminderOption.swift` (новый)

```swift
//
//  ReminderOption.swift
//  Tenra
//
//  Reminder selection enum for subscriptions
//

import Foundation

/// Option for reminder selection: none or specific days before
enum ReminderOption: Hashable {
    case none
    case daysBefore(Int)

    var displayName: String {
        switch self {
        case .none:
            return String(localized: "reminder.none")
        case .daysBefore(let offset):
            switch offset {
            case 1:
                return String(localized: "reminder.dayBefore.one")
            case 3:
                return String(localized: "reminder.daysBefore.3")
            case 7:
                return String(localized: "reminder.daysBefore.7")
            case 30:
                return String(localized: "reminder.daysBefore.30")
            default:
                return "За \(offset) дней"
            }
        }
    }

    /// Convert to Set<Int> for backward compatibility
    var asOffsets: Set<Int> {
        switch self {
        case .none:
            return []
        case .daysBefore(let offset):
            return [offset]
        }
    }

    /// Create from Set<Int>
    static func from(offsets: Set<Int>) -> ReminderOption {
        if offsets.isEmpty {
            return .none
        } else if let first = offsets.first {
            return .daysBefore(first)
        } else {
            return .none
        }
    }
}
```

#### 2.3. Обновить SubscriptionEditView

**Файл:** `SubscriptionEditView.swift`

```swift
// Было:
@State private var selectedReminderOffsets: Set<Int> = []

ReminderPickerView(
    selectedOffsets: $selectedReminderOffsets,
    title: String(localized: "subscription.reminders")
)

// Стало:
@State private var reminder: ReminderOption = .none

MenuPickerRow(
    title: String(localized: "subscription.reminders"),
    selection: $reminder
)
```

**Обновить save/load логику:**
```swift
// При загрузке subscription:
reminder = ReminderOption.from(offsets: subscription.reminderOffsets)

// При сохранении:
subscription.reminderOffsets = reminder.asOffsets
```

#### 2.4. Удалить ReminderPickerView.swift

```bash
rm Tenra/Views/Shared/Components/ReminderPickerView.swift
```

**Время:** 20 минут
**Риски:** Низкие
**Файлов:** 4 (создать 1, обновить 2, удалить 1)

---

### Шаг 3: Заменить BaseCurrencyPickerRow на MenuPickerRow ✅

**Причина:**
- Использует старый `.menu` style (без капсулы)
- Дублирует функционал MenuPickerRow
- Inconsistent с другими pickers

**Подшаги:**

#### 3.1. Найти использование BaseCurrencyPickerRow

**Файл:** `Views/Settings/SettingsView.swift` (примерно)

**Было:**
```swift
BaseCurrencyPickerRow(
    selectedCurrency: settings.baseCurrency,
    availableCurrencies: ["KZT", "USD", "EUR", "RUB"],
    onChange: { newCurrency in
        settings.baseCurrency = newCurrency
    }
)
```

**Стало:**
```swift
MenuPickerRow(
    icon: "dollarsign.circle",
    title: String(localized: "settings.baseCurrency"),
    selection: $settings.baseCurrency,
    options: ["KZT", "USD", "EUR", "RUB"].map { currency in
        (label: Formatting.currencySymbol(for: currency), value: currency)
    }
)
```

#### 3.2. Удалить BaseCurrencyPickerRow.swift

```bash
rm Tenra/Views/Settings/Components/BaseCurrencyPickerRow.swift
```

**Время:** 15 минут
**Риски:** Низкие
**Файлов:** 2 (обновить 1, удалить 1)

---

### Шаг 4: Оставить DatePickerRow ✅

**Причина:**
- DatePicker (календарь) ≠ Menu (список)
- Нельзя выбрать произвольную дату из menu
- iOS HIG рекомендует DatePicker для дат
- Специализированный UI

**Действия:** Ничего (оставить как есть)

---

### Шаг 5: Оставить другие компоненты ✅

#### WallpaperPickerRow
- PhotosPicker (выбор фото из галереи)
- Не выбор из списка

#### CurrencySelectorView
- Filter chip style (специальный дизайн)
- Используется в quick actions
- Не form row

#### AccountSelectorView / CategorySelectorView
- Полноэкранные списки с поиском
- Сложная логика
- NavigationLink к отдельному экрану

**Вывод:** Оставить все как есть

---

## 📊 Финальная архитектура

### Компоненты после унификации:

```
┌─────────────────────────────────────────────────┐
│  MenuPickerRow<T: Hashable> - ГЛАВНЫЙ           │
│  ├── RecurringFrequency (convenience init)      │
│  ├── RecurringOption (convenience init)         │
│  └── ReminderOption (convenience init) ← NEW    │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  RecurringToggleView                            │
│  └── Wrapper над MenuPickerRow + logic          │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  DatePickerRow                                  │
│  └── Wrapper над нативным DatePicker            │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  DateButtonsView                                │
│  └── Кнопки для быстрого выбора даты            │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  CurrencySelectorView                           │
│  └── Filter chip для currency (quick actions)   │
└─────────────────────────────────────────────────┘

❌ УДАЛЕНО:
├── FrequencyPickerView (мертвый код)
├── ReminderPickerView (wrapper)
└── BaseCurrencyPickerRow (заменен на MenuPickerRow)
```

---

## 🗂 Изменения в файлах

### Создать:
1. `Models/ReminderOption.swift` - enum ReminderOption

### Обновить:
1. `MenuPickerRow.swift` - добавить convenience init для ReminderOption
2. `SubscriptionEditView.swift` - заменить ReminderPickerView на MenuPickerRow
3. `SubscriptionEditView.swift` - убрать упоминание FrequencyPickerView из комментария
4. `SettingsView.swift` - заменить BaseCurrencyPickerRow на MenuPickerRow

### Удалить:
1. `FrequencyPickerView.swift`
2. `ReminderPickerView.swift`
3. `BaseCurrencyPickerRow.swift`

**Итого:**
- Создать: 1 файл
- Обновить: 3 файла
- Удалить: 3 файла

---

## ✅ Чек-лист реализации

### Шаг 1: FrequencyPickerView
- [ ] Удалить FrequencyPickerView.swift
- [ ] Обновить комментарий в SubscriptionEditView.swift
- [ ] Проверить компиляцию

### Шаг 2: ReminderPickerView
- [ ] Создать Models/ReminderOption.swift
- [ ] Добавить convenience init в MenuPickerRow
- [ ] Обновить SubscriptionEditView (тип + использование)
- [ ] Удалить ReminderPickerView.swift
- [ ] Проверить компиляцию
- [ ] Проверить preview

### Шаг 3: BaseCurrencyPickerRow
- [ ] Найти использование в SettingsView
- [ ] Заменить на MenuPickerRow
- [ ] Удалить BaseCurrencyPickerRow.swift
- [ ] Проверить компиляцию
- [ ] Протестировать в Settings

### Финал:
- [ ] BUILD SUCCEEDED
- [ ] Все previews работают
- [ ] Обновить документацию
- [ ] Коммит

---

## 📈 Метрики

### Код

| Метрика | До | После | Изменение |
|---------|-----|-------|-----------|
| **Picker компонентов** | 6 | 3 | -50% |
| **Строк кода (pickers)** | ~800 | ~350 | -56% |
| **Использование MenuPickerRow** | 3 места | 6+ мест | +100% |

### Консистентность

| Аспект | До | После |
|--------|-----|-------|
| **Разных UI стилей** | 5 | 2 |
| **Компонентов для выбора** | 6 | 3 |
| **Консистентность UX** | ❌ Низкая | ✅ Высокая |

---

## 🎯 Финальные использования MenuPickerRow

### 1. Частота подписки (SubscriptionEditView)
```swift
MenuPickerRow(
    icon: "arrow.triangle.2.circlepath",
    title: String(localized: "common.frequency"),
    selection: $frequency
)
```

### 2. Повторяющаяся операция (Transactions)
```swift
RecurringToggleView(
    isRecurring: $isRecurring,
    selectedFrequency: $frequency
)
// Внутри MenuPickerRow с RecurringOption
```

### 3. Напоминания (SubscriptionEditView) ⭐ НОВОЕ
```swift
MenuPickerRow(
    title: String(localized: "subscription.reminders"),
    selection: $reminder  // ReminderOption
)
```

### 4. Базовая валюта (Settings) ⭐ НОВОЕ
```swift
MenuPickerRow(
    icon: "dollarsign.circle",
    title: String(localized: "settings.baseCurrency"),
    selection: $baseCurrency,
    options: currencies.map { (label: $0.symbol, value: $0.code) }
)
```

### 5. Любые enum'ы (Generic)
```swift
MenuPickerRow(
    icon: "flag.fill",
    title: "Priority",
    selection: $priority,
    options: [
        (label: "Low", value: .low),
        (label: "High", value: .high)
    ]
)
```

---

## 🎊 Итого

### Что достигнем:

✅ **Один универсальный компонент** для всех single-select сценариев
✅ **Консистентный UI** везде (капсула справа)
✅ **-56% кода** в picker компонентах
✅ **3 компонента вместо 6**
✅ **Чистый codebase** без дублирования

### Что оставляем:

✅ **DatePickerRow** - для выбора дат (календарь)
✅ **DateButtonsView** - для быстрой даты (вчера/сегодня)
✅ **CurrencySelectorView** - для filter chips
✅ **AccountSelectorView** - сложный UI с поиском

---

## 🚀 Готов к реализации?

**Время:** ~36 минут
**Риски:** Минимальные
**Сложность:** Низкая
**Преимущества:** Огромные

**Жду твоего подтверждения для начала реализации!** ✅

---

*План подготовлен: 2026-02-15*
*Статус: Готов к реализации*
*Начинаем?* 🚀
