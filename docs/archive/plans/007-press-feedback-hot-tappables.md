# 007 — Press feedback на самых горячих тапаемых поверхностях

- **Status**: DONE (implemented 2026-07-13 on main; build succeeded; device feel-check pending)
- **Commit**: bef4de4
- **Severity**: HIGH
- **Category**: Physicality (press feedback)
- **Estimated scope**: 3 файла, ~30 строк

## Problem

Три самые часто нажимаемые поверхности приложения не дают никакого визуального отклика на нажатие — только хаптика. Правило: у нажимаемого элемента должен быть press feedback `scale ~0.96–0.97`, 100–160 мс, ease-out.

**1. Клавиатура калькулятора** — заменяет системную клавиатуру для ввода суммы (самое частое действие в финансовом приложении), но в отличие от системной клавиатуры клавиши визуально мертвы. `Button` со стилем `.plain` внутри `LazyVGrid` не рендерит pressed-состояние:

```swift
// Tenra/Views/Components/Input/CalculatorKeypad.swift:85-97 — текущий код
private func keyButton(
    background: Color,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> some View
) -> some View {
    Button {
        HapticManager.light()
        action()
    } label: {
        keyShape(background: background, content: label)
    }
    .buttonStyle(.plain)
}
```

Клавиша backspace — вообще не `Button`, а голый `onTapGesture`:

```swift
// Tenra/Views/Components/Input/CalculatorKeypad.swift:66-81 — текущий код
private func backspaceKey() -> some View {
    keyShape(background: AppColors.bgCard) {
        Image(systemName: "delete.left").foregroundStyle(AppColors.textSecondary)
    }
    .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    .onTapGesture {
        HapticManager.light()
        model.backspace()
    }
    .onLongPressGesture(minimumDuration: 0.35) {
        HapticManager.medium()
        model.clear()
    }
    .accessibilityLabel(Text(String(localized: "calculator.backspace", defaultValue: "Delete")))
    .accessibilityHint(Text(String(localized: "calculator.clearHint", defaultValue: "Press and hold to clear")))
}
```

**2. Карточка транзакции** — самый нажимаемый элемент списков. Рендерится в `LazyVStack` (не `List`), поэтому системной подсветки строки тоже нет; тап телепортирует в edit-sheet без подтверждения:

```swift
// Tenra/Views/Components/Cards/TransactionCard.swift:228-231 — текущий код
.onTapGesture {
    HapticManager.selection()
    showingEditModal = true
}
```

```swift
// Tenra/Views/Components/History/GroupedTransactionList.swift:210-211 — текущий код (вариант с tapAction)
.contentShape(Rectangle())
.onTapGesture { tapAction(transaction) }
```

**3. `selectableRow`** — строки выбора в фильтрах (TimeFilterView, AccountFilterView, CategoryFilterView, LinkPaymentsView):

```swift
// Tenra/Views/Components/Rows/UniversalRow.swift:313-322 — текущий код
func selectableRow(
    isSelected: Bool,
    action: @escaping () -> Void
) -> some View {
    self
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
}
```

## Target

Все три поверхности дают мгновенный тактильно-визуальный отклик через существующий `BounceButtonStyle` (scale 0.96 + brightness −0.05, Reduce-Motion-aware) — либо, где `Button` невозможен без поломки жестов, через эквивалентный pressed-scale.

## Repo conventions to follow

- Канонический press feedback уже существует и используется 6+ раз: `BounceButtonStyle` в `Tenra/Utils/AppAnimation.swift:125-139` (`scaleEffect(isPressed ? 0.96 : 1.0)` + `brightness(-0.05)` + `AppAnimation.adaptiveSpring`, который сам обрабатывает Reduce Motion). Применяется как `.buttonStyle(.bounce)`.
- Экземпляр для подражания: карточки на FinancesView и `AccountRadioButton` уже используют `.bounce`.
- Никаких новых стилей кнопок не создавать.

## Steps

1. **CalculatorKeypad.swift** — в `keyButton(...)` заменить `.buttonStyle(.plain)` на `.buttonStyle(.bounce)`.
2. **CalculatorKeypad.swift** — переписать `backspaceKey()` так, чтобы тап шёл через `Button` со стилем `.bounce`, а long-press остался жестом поверх него:
   ```swift
   private func backspaceKey() -> some View {
       Button {
           HapticManager.light()
           model.backspace()
       } label: {
           keyShape(background: AppColors.bgCard) {
               Image(systemName: "delete.left").foregroundStyle(AppColors.textSecondary)
           }
       }
       .buttonStyle(.bounce)
       .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
       .onLongPressGesture(minimumDuration: 0.35) {
           HapticManager.medium()
           model.clear()
       }
       .accessibilityLabel(Text(String(localized: "calculator.backspace", defaultValue: "Delete")))
       .accessibilityHint(Text(String(localized: "calculator.clearHint", defaultValue: "Press and hold to clear")))
   }
   ```
   ⚠️ Проверить, что long-press (очистка) продолжает срабатывать: `onLongPressGesture` поверх `Button` в iOS 18+/26 работает, но если при ручной проверке long-press перестанет вызывать `model.clear()`, откатить именно этот шаг к `onTapGesture`-варианту и добавить pressed-scale вручную через `ButtonStyle`-обёртку не получится — вместо этого использовать `.onLongPressGesture(minimumDuration: 0.35, perform: { model.clear() }, onPressingChanged: { pressing in ... })` с `@State`-масштабом 0.96.
3. **TransactionCard.swift:228-231** — карточка имеет `.contextMenu` (long-press) и `.sheet`; заменить `.onTapGesture` на `Button`-обёртку нельзя без риска сломать context menu. Вместо этого добавить pressed-scale через `onLongPressGesture(onPressingChanged:)`-паттерн НЕ нужно — правильный минимальный вариант: обернуть содержимое карточки в `Button { HapticManager.selection(); showingEditModal = true } label: { <текущее содержимое> }` с `.buttonStyle(.bounce)`, а `.contextMenu` навесить на `Button` снаружи (SwiftUI поддерживает contextMenu на Button; system-precedent — иконки Home Screen). Если при проверке context menu перестанет открываться по long-press — STOP и откатить шаг 3, оставив остальные.
4. **GroupedTransactionList.swift:210-211** — тот же приём для варианта с `tapAction`: `Button { tapAction(transaction) } label: { ... }` + `.buttonStyle(.bounce)`.
5. **UniversalRow.swift:313-322** — переписать `selectableRow` через `Button(action:)` + `.buttonStyle(.bounce)`, сохранив `contentShape` и оба accessibility-модификатора (`.isButton` trait у `Button` уже есть — оставить только логику `.isSelected`).

## Boundaries

- Не трогать `BounceButtonStyle` и токены в `AppAnimation.swift`.
- Не трогать `.contextMenu`-содержимое, хаптику и навигацию — только оболочку нажатия.
- Не добавлять press feedback никаким другим поверхностям в этом плане.
- Если код на месте правки не совпадает с приведёнными выдержками — STOP, сообщить о дрейфе.

## Verification

- **Механика**: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30` — пусто.
- **Feel check** (владелец проверяет визуально, Simulator не запускать автоматически — правило CLAUDE.md):
  - Быстрый набор `123456` на клавиатуре калькулятора: каждая клавиша заметно «подпружинивает», при этом быстрые повторные нажатия не тормозят ввод и не съедают тапы.
  - Тап по транзакции в истории: карточка сжимается до ~0.96 перед открытием шита; long-press по-прежнему открывает context menu.
  - Long-press по backspace по-прежнему очищает всё поле.
  - Включить Reduce Motion (Настройки → Универсальный доступ → Движение): scale-отклик исчезает (adaptiveSpring → мгновенно), функциональность не меняется.
- **Done when**: все четыре пункта feel check подтверждены владельцем.
