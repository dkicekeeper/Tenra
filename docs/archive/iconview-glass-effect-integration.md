# IconView Glass Effect Integration

## Дата: 2026-02-13

## Описание
Интеграция glass effect в IconView как встроенного стиля с автоматической обрезкой контента по форме.

---

## Проблема

### До изменений:
1. **Glass effect применялся снаружи IconView**:
   ```swift
   IconView(source: subscription.iconSource, size: AppIconSize.largeButton)
       .glassEffect()  // ❌ Применяется после IconView
   ```

2. **Контент выходил за границы**:
   - `IconView` обрезал по форме внутри
   - `.glassEffect()` создавал новый визуальный слой поверх
   - Логотипы/изображения могли выходить за круглые границы

3. **Дублирование кода**:
   - Нужно было помнить применять `.glassEffect()` везде
   - Порядок модификаторов критичен

---

## Решение

### 1. Добавлено поле `hasGlassEffect` в `IconStyle`
```swift
struct IconStyle: Equatable, Hashable {
    var size: CGFloat
    var shape: IconShape
    var tint: IconTint
    var contentMode: ContentMode
    var backgroundColor: Color?
    var padding: CGFloat?
    var hasGlassEffect: Bool  // ✅ Новое поле
}
```

### 2. Обновлены все методы создания стилей
```swift
static func circle(
    size: CGFloat,
    tint: IconTint = .original,
    backgroundColor: Color? = nil,
    padding: CGFloat? = nil,
    hasGlassEffect: Bool = false  // ✅ Новый параметр
) -> IconStyle
```

### 3. Добавлены новые пресеты с glass effect
```swift
// Для hero секций (подписки, счета)
static func glassHero(size: CGFloat = AppIconSize.largeButton) -> IconStyle {
    .circle(size: size, tint: .original, hasGlassEffect: true)
}

// Для сервисных логотипов
static func glassService(size: CGFloat = AppIconSize.avatar) -> IconStyle {
    .roundedSquare(size: size, cornerRadius: AppRadius.lg, tint: .original, hasGlassEffect: true)
}
```

### 4. IconView автоматически применяет glass effect
```swift
// В containerView:
let viewWithShape = Group {
    switch style.shape {
    case .circle:
        viewWithPadding
            .clipShape(Circle())
            .contentShape(Circle())  // ✅ Гарантирует обрезку
    // ...
    }
}

// Применяем glass effect если требуется
if style.hasGlassEffect {
    if #available(iOS 18.0, *) {
        switch style.shape {
        case .circle:
            viewWithShape
                .glassEffect(in: Circle())  // ✅ С указанием формы
        // ...
        }
    }
}
```

### 5. Всегда добавляется `.contentShape()` для корректной обрезки
- Гарантирует, что контент ВСЕГДА обрезается по заданной форме
- Работает независимо от того, применяется ли glass effect

---

## Использование

### До:
```swift
IconView(source: subscription.iconSource, size: AppIconSize.largeButton)
    .glassEffect()  // ❌ Снаружи
```

### После:
```swift
// Вариант 1: Использование пресета
IconView(source: subscription.iconSource, style: .glassHero())

// Вариант 2: Кастомный стиль
IconView(
    source: subscription.iconSource,
    style: .circle(size: AppIconSize.xl, hasGlassEffect: true)
)

// Вариант 3: Без glass effect (по умолчанию)
IconView(source: subscription.iconSource, size: AppIconSize.xl)
```

---

## Преимущества

### ✅ Инкапсуляция
- Glass effect - часть стиля IconView
- Не нужно помнить применять снаружи

### ✅ Гарантированная обрезка
- `.clipShape()` + `.contentShape()` гарантируют правильную обрезку
- Контент НИКОГДА не выходит за границы формы

### ✅ Чистый API
```swift
// Было
IconView(...).glassEffect()

// Стало
IconView(..., style: .glassHero())
```

### ✅ Совместимость
- Fallback для iOS < 18.0
- Не ломает существующий код (hasGlassEffect = false по умолчанию)

### ✅ Пресеты
- `.glassHero()` - для hero секций
- `.glassService()` - для логотипов сервисов
- Легко расширять

---

## Затронутые файлы

1. **IconStyle.swift**
   - Добавлено поле `hasGlassEffect`
   - Обновлены все методы создания стилей
   - Добавлены пресеты `.glassHero()` и `.glassService()`

2. **IconView.swift**
   - Обновлен `containerView()` для применения glass effect
   - Добавлен `.contentShape()` для гарантированной обрезки
   - Добавлен Preview "Glass Effect"

3. **SubscriptionDetailView.swift**
   - Заменено `.glassEffect()` на встроенный стиль
   - Использует новый пресет `.glassHero()`

---

## Preview

Добавлен новый Preview "Glass Effect" в IconView.swift:
- Демонстрирует все варианты glass effect
- Показывает круглые и квадратные формы
- Примеры с SF Symbols и brand logos
- Требует iOS 18.0+ (с fallback)

---

## Миграция

### Для существующего кода:
1. Найти все `.glassEffect()` после IconView
2. Заменить на встроенный стиль:
   ```swift
   // До
   IconView(source: icon, size: 60).glassEffect()

   // После
   IconView(source: icon, style: .glassHero(size: 60))
   ```

### Обратная совместимость:
- Все существующие использования IconView продолжат работать
- `hasGlassEffect` по умолчанию `false`
- Не требует изменений в существующем коде

---

## Технические детали

### iOS 18.0+ Glass Effect
```swift
if #available(iOS 18.0, *) {
    viewWithShape.glassEffect(in: Circle())
}
```

### Обрезка контента
```swift
.clipShape(Circle())        // Обрезает визуально
.contentShape(Circle())     // Определяет область взаимодействия
```

### Порядок модификаторов
1. Контент
2. Background (если есть)
3. Padding (если есть)
4. ClipShape + ContentShape
5. Glass Effect (если hasGlassEffect = true)

---

## Выводы

- ✅ Glass effect теперь часть IconView API
- ✅ Контент всегда обрезается корректно
- ✅ Чище и понятнее код
- ✅ Легче поддерживать
- ✅ Готово к расширению
