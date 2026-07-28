# 008 — Hero-иконка: убрать scale-от-нуля и уложить entrance в бюджет

- **Status**: DONE (implemented 2026-07-13 on main; build succeeded; device feel-check pending)
- **Commit**: bef4de4
- **Severity**: MEDIUM (высокая частота — каждое открытие detail/edit-экрана)
- **Category**: Physicality + Easing & duration + Accessibility
- **Estimated scope**: 3 файла, ~25 строк

## Problem

Hero-иконка на каждом открытии detail-экрана (счёт, категория, подписка, депозит, займ) и каждого create/edit-экрана вырастает из **нуля** пружиной `heroSpring` (response 0.6, damping 0.7 — воспринимаемое время успокоения ~0.8–0.9 с, с видимым overshoot), без учёта Reduce Motion. Нарушены три правила: «never scale(0)» (цель 0.9–0.97 + opacity), бюджет entrance ≤300 мс для часто открываемых экранов, и обязательный Reduce-Motion-гейт для движения.

```swift
// Tenra/Views/Components/EntityDetail/HeroSection.swift:25 — текущий код
@State private var iconScale: CGFloat = 0
```

```swift
// Tenra/Views/Components/EntityDetail/HeroSection.swift:67-72 — текущий код
.scaleEffect(iconScale)
.onAppear {
    withAnimation(AppAnimation.heroSpring) {
        iconScale = 1.0
    }
}
```

```swift
// Tenra/Views/Components/Forms/EditableHeroSection.swift:56 — текущий код
@State private var iconScale: CGFloat = 0
```

```swift
// Tenra/Views/Components/Forms/EditableHeroSection.swift:85-91 — текущий код
heroIconView
    .scaleEffect(iconScale)
    .onAppear {
        withAnimation(AppAnimation.heroSpring) {
            iconScale = 1.0
        }
    }
```

## Target

Иконка появляется из scale **0.92** + opacity 0, пружиной response **0.35** / damping **0.75** (лёгкий pop без затянутого settle, укладывается в ~0.35–0.4 с восприятия), под Reduce Motion — мгновенно. Значения оформить токенами.

## Repo conventions to follow

- Токены живут в `Tenra/Utils/AppAnimation.swift`; Reduce-Motion-aware токены — computed var, возвращающие `.linear(duration: 0)` при включённом Reduce Motion. Экземпляр для подражания — `chartAppearAnimation` (AppAnimation.swift:75-79) и парные константы `chartHiddenScale: CGFloat = 0.94`.
- design-system.md §9: «Never use hardcoded springs» — новые значения только через токен.

## Steps

1. **AppAnimation.swift** — добавить рядом с `heroSpring` (после строки 35):
   ```swift
   /// Starting scale for hero icon entrance (grows from this to 1.0).
   static let heroHiddenScale: CGFloat = 0.92

   /// Reduce-Motion-aware hero icon entrance. Snappier than the legacy
   /// `heroSpring`: settles within the ~350ms entrance budget.
   static var heroEntranceAnimation: Animation {
       isReduceMotionEnabled
           ? .linear(duration: 0)
           : .spring(response: 0.35, dampingFraction: 0.75)
   }
   ```
   `heroSpring` НЕ удалять (его использует MessageBanner-дубликат — см. план 009) — но добавить к нему doc-комментарий `/// Legacy: prefer `heroEntranceAnimation` for icon entrances.`
2. **HeroSection.swift:25** — `@State private var iconScale: CGFloat = AppAnimation.heroHiddenScale`; добавить `@State private var iconOpacity: Double = 0`.
3. **HeroSection.swift:67-72** — заменить на:
   ```swift
   .scaleEffect(iconScale)
   .opacity(iconOpacity)
   .onAppear {
       withAnimation(AppAnimation.heroEntranceAnimation) {
           iconScale = 1.0
           iconOpacity = 1.0
       }
   }
   ```
4. **EditableHeroSection.swift:56 и 85-91** — те же два изменения (initial state + withAnimation-блок), код идентичен шагам 2–3.

## Boundaries

- Не трогать `BudgetProgressCircle` внутри HeroSection (его анимация — предмет плана 009).
- Не трогать другие использования `heroSpring` (MessageBanner — план 009).
- Не менять layout, размеры (`AppIconSize.ultra`), IconView-стили.
- Если код не совпадает с выдержками — STOP, сообщить о дрейфе.

## Verification

- **Механика**: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30` — пусто.
- **Feel check** (владелец, визуально):
  - Открыть детали счёта → иконка мягко «доплывает» из 92% с лёгким fade-in; никакого вырастания из точки и никакого качающегося settle после того, как контент уже читабелен.
  - Быстро открыть/закрыть/снова открыть detail — анимация каждый раз стартует чисто, ощущения «медленнее контента» нет.
  - Открыть create-форму счёта (EditableHeroSection) — идентичное поведение.
  - Включить Reduce Motion → иконка появляется мгновенно, без scale.
- **Done when**: feel check подтверждён на HeroSection и EditableHeroSection, в обоих режимах Reduce Motion.
