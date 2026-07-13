# 011 — AnimatedTitleInput: задокументированный анти-паттерн курсора + morph всей строки на каждый символ

- **Status**: DONE (implemented 2026-07-13 on main; build succeeded; device feel-check pending)
- **Commit**: bef4de4
- **Severity**: MEDIUM (латентный визуальный баг + анимация на каждое нажатие клавиши)
- **Category**: Interruptibility + Purpose & frequency
- **Estimated scope**: 1 файл, ~15 строк

## Problem

**1. Курсор скрывается через parent-opacity — ровно тот анти-паттерн, который уже был пойман, задокументирован и исправлен в AmountDigitDisplay.** `BlinkingCursor` держит внутреннюю `.repeatForever`-анимацию собственной opacity; если его прятать родительской opacity, эти две анимации борются и курсор «не успокаивается» в скрытое состояние. Исправление в `AnimatedInputComponents.swift:121-129` (условное монтирование) сопровождено комментарием, объясняющим баг. `AnimatedTitleInput` использует старый паттерн:

```swift
// Tenra/Views/Components/Input/AnimatedTitleInput.swift:60-70 — текущий код
HStack(spacing: 1) {
    Text(text.isEmpty ? "" : text)
        .font(font)
        .foregroundStyle(color)
        .contentTransition(.interpolate)
        .animation(AppAnimation.contentSpring, value: text)

    BlinkingCursor(height: 44)
        .opacity(showCursor ? 1 : 0)
        .animation(AppAnimation.fastAnimation, value: showCursor)
}
```

Эталонное исправление того же бага:

```swift
// Tenra/Views/Components/Input/AnimatedInputComponents.swift:121-129 — образец
// Render the cursor ONLY while focused. Previously it stayed mounted
// and was hidden with `.opacity(isFocused ? 1 : 0)`, but BlinkingCursor's
// internal `.repeatForever` opacity animation kept running and fought the
// parent opacity, so the cursor never visually settled to hidden on blur.
// Removing it from the hierarchy tears the animation down (onDisappear).
if isFocused {
    BlinkingCursor(height: cursorHeight)
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
}
```

Дополнительно: пока курсор просто «прозрачный», его `repeatForever` продолжает тикать на всех create/edit-формах, где поле не в фокусе — лишняя постоянная анимация.

**2. `.contentTransition(.interpolate)` морфит ВСЮ строку на каждый введённый символ.** В отличие от `.numericText()` (пер-символьный, применён к суммам), `.interpolate` перерисовывает-морфит весь текст при любом изменении `text` — анимация на каждое нажатие клавиши (правило: действия с частотой печати не анимируются). Используется в `EditableHeroSection` — все create/edit-формы сущностей.

## Target

- Курсор монтируется условно (`if showCursor`), с `.transition(.opacity.animation(.easeInOut(duration: 0.15)))` — как в эталоне.
- Текст заголовка вводится без content-morph: убрать `.contentTransition(.interpolate)` и `.animation(AppAnimation.contentSpring, value: text)`. Fade плейсхолдера (`showPlaceholder`, строка ~89 `.animation(AppAnimation.fastAnimation, value: showPlaceholder)`) остаётся как есть.

## Repo conventions to follow

- Образец условного монтирования курсора: `AnimatedInputComponents.swift:126-129` (см. выше) — повторить включая пояснительный комментарий (сослаться на него одной строкой, не копировать целиком).

## Steps

1. **AnimatedTitleInput.swift:60-70** — заменить блок на:
   ```swift
   HStack(spacing: 1) {
       Text(text.isEmpty ? "" : text)
           .font(font)
           .foregroundStyle(color)

       // Conditional mount — see AnimatedInputComponents.BlinkingCursor note:
       // hiding via parent opacity fights the cursor's internal repeatForever.
       if showCursor {
           BlinkingCursor(height: 44)
               .transition(.opacity.animation(.easeInOut(duration: 0.15)))
       }
   }
   ```
2. **AnimatedTitleInput.swift:89** — строку `.animation(AppAnimation.fastAnimation, value: showCursor)` на контейнере удалить, если после шага 1 она осталась и относится только к курсору; `.animation(AppAnimation.fastAnimation, value: showPlaceholder)` (строка 88) НЕ трогать.

## Boundaries

- Не трогать `BlinkingCursor` сам по себе, фокус-логику, `asyncAfter`-workaround автофокуса (:90-98 — задокументированный обходной путь responder chain).
- Не трогать `AmountDigitDisplay` и `contentSpring`.
- Если код не совпадает с выдержками — STOP.

## Verification

- **Механика**: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30` — пусто.
- **Feel check** (владелец):
  - Создание счёта → быстро печатать название: буквы появляются мгновенно, без «переливания» всей строки; поле ощущается как обычный текстовый ввод.
  - Тапнуть в поле → курсор появляется fade-ом и мигает; убрать фокус (тап вне / Done) → курсор полностью исчезает и НЕ остаётся полупрозрачно подмигивающим (это и был латентный баг).
  - Плейсхолдер по-прежнему появляется/исчезает мягким fade.
- **Done when**: все три пункта подтверждены на форме создания и редактирования.
