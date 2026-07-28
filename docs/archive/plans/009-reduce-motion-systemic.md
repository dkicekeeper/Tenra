# 009 — Reduce Motion: закрыть системный разрыв покрытия

- **Status**: DONE (implemented 2026-07-13 on main; build succeeded; device feel-check pending)
- **Commit**: bef4de4
- **Severity**: MEDIUM (доступность; ~20 незагейченных сайтов движения, включая полноэкранный)
- **Category**: Accessibility + Cohesion
- **Estimated scope**: ~9 файлов + 1 doc, ~120 строк

## Problem

`docs/design-system.md:1167` утверждает: «All decorative animations respect `UIAccessibility.isReduceMotionEnabled`» — это сейчас неправда. Токенный слой (`AppAnimation`) гейтится корректно, но самые заметные движения написаны мимо гейтов:

**P1 — SiriGlowView: полноэкранное непрерывное движение 30 fps без гейта.** Единственная постоянная полноэкранная анимация в приложении (весь сеанс записи голоса) — именно тот класс ambient-движения, ради которого настройка существует (вестибулярные триггеры). В файле нет ни одного упоминания Reduce Motion:

```swift
// Tenra/Views/Components/Charts/SiriGlowView.swift:29-40 — текущий код
var body: some View {
    TimelineView(.periodic(from: .now, by: Self.frameInterval)) { timeline in
        meshGlow(t: timeline.date.timeIntervalSinceReferenceDate)
    }
    .onGeometryChange(for: Double.self) { proxy in
        proxy.size.width / max(proxy.size.height, 1)
    } action: { newAspect in
        if abs(newAspect - aspect) > 0.01 {
            aspect = newAspect
        }
    }
}
```

**P2 — Прогресс-бары главного экрана и бюджетов: sweep ширины без гейта, три разные кривые.** `ExpenseIncomeProgressBar` (home, replay на каждый возврат), `BudgetProgressBar`, `ProportionBar`, `BudgetProgressCircle` — четыре компонента прогресса, три разные анимации, ни одна не гейтится:

```swift
// Tenra/Views/Components/Charts/ExpenseIncomeProgressBar.swift:30 — текущий код
private static let barAnimation = AppAnimation.progressBarSpring
```
```swift
// Tenra/Views/Components/Charts/BudgetProgressBar.swift:66-67 — текущий код
.animation(AppAnimation.gentleSpring, value: percentage)
.animation(AppAnimation.gentleSpring, value: isOverBudget)
```
```swift
// Tenra/Views/Components/Charts/ProportionBar.swift:28 — текущий код
.animation(AppAnimation.gentleSpring, value: ratio)
```
```swift
// Tenra/Views/Components/Charts/BudgetProgressCircle.swift:103-104 — текущий код
.animation(.easeInOut(duration: AppAnimation.standard), value: progress)
.animation(.easeInOut(duration: AppAnimation.standard), value: arcColor)
```

**P3 — MessageBanner: рукописные пружины (запрещены §9), entrance ~0.9 с для тоста (бюджет 200–500 мс), значения — точный дубликат `heroSpring`, без гейта:**

```swift
// Tenra/Views/Components/Feedback/MessageBanner.swift:11-19 — текущий код
private enum BannerAnimation {
    static let entranceResponse: Double = 0.6
    static let entranceDamping: Double = 0.7
    static let iconResponse: Double = 0.5
    static let iconDamping: Double = 0.6
    static let iconDelay: Double = 0.1
    static let hiddenScale: CGFloat = 0.85
    static let hiddenOffset: CGFloat = -20
}
```
Использование: `MessageBanner.swift:71-92` — `scaleEffect/opacity/offset` + два inline `withAnimation(.spring(...))` в `onAppear`.

**P4 — StaggeredCard (voice-превью): offset-entrance без гейта:**

```swift
// Tenra/Views/VoiceInput/VoiceInputView.swift:520-530 — текущий код
content()
    .opacity(visible ? 1 : 0)
    .offset(y: visible ? 0 : 12)
    .task {
        try? await Task.sleep(for: .milliseconds(index * 80))
        guard !Task.isCancelled else { return }
        withAnimation(AppAnimation.gentleSpring) {
            visible = true
        }
    }
```

**P5 — Статичное чтение `UIAccessibility.isReduceMotionEnabled` не реагирует на переключение настройки в течение сессии.** Структурные гейты застревают: уже запущенный beam продолжает крутиться. Единственный сайт, делающий правильно, — `BlinkingCursor` (`AnimatedInputComponents.swift:23`, через `@Environment(\.accessibilityReduceMotion)`):

```swift
// Tenra/Views/Components/Feedback/BorderBeamModifier.swift:26-28 — текущий код
func body(content: Content) -> some View {
    content
        .overlay {
            if isActive && !AppAnimation.isReduceMotionEnabled {
```

**P6 — Обратная ошибка: `chartBannerFade` гасит opacity-only fade.** Reduce Motion должен убирать движение, а не фидбек; в этом токене движения нет вообще, гейт лишний:

```swift
// Tenra/Utils/AppAnimation.swift:90-94 — текущий код
static var chartBannerFade: Animation {
    isReduceMotionEnabled
        ? .linear(duration: 0)
        : .easeInOut(duration: 0.15)
}
```

## Target

- SiriGlow под Reduce Motion — статичный mesh (тот же вид, замороженное t), без TimelineView.
- Все четыре прогресс-компонента — один Reduce-Motion-aware токен `progressFillAnimation` (на базе существующего `progressBarSpring`).
- MessageBanner — entrance-пружина response 0.4 / damping 0.8, hiddenScale 0.92, под Reduce Motion — opacity-only fade 0.2 c (движение и icon-pop отключены, fade остаётся: баннер — фидбек).
- StaggeredCard — под Reduce Motion offset убран, opacity-fade остаётся.
- Файлы с живыми структурными гейтами (`BorderBeamModifier`, `PulsingText`, `RecordingIndicatorView`) — на `@Environment(\.accessibilityReduceMotion)`.
- `chartBannerFade` — без гейта (обычный `.easeInOut(duration: 0.15)`).
- design-system.md:1167 — формулировка снова истинна.

## Repo conventions to follow

- Экземпляр gated-токена: `AppAnimation.chartAppearAnimation` (AppAnimation.swift:75-79).
- Экземпляр environment-гейта: `BlinkingCursor` (`Tenra/Views/Components/Input/AnimatedInputComponents.swift:23,31`).
- Правило AUDIT §6: reduce motion = убрать движение (offset/scale), сохранить opacity-фидбек.

## Steps

1. **AppAnimation.swift** — добавить в MARK "Reduce Motion Aware Animations":
   ```swift
   /// Reduce-Motion-aware fill animation for ALL progress bars/rings
   /// (ExpenseIncomeProgressBar, BudgetProgressBar, ProportionBar, BudgetProgressCircle).
   static var progressFillAnimation: Animation? {
       isReduceMotionEnabled ? nil : progressBarSpring
   }
   ```
2. **AppAnimation.swift:90-94** — `chartBannerFade` сделать константой без гейта:
   ```swift
   /// Fade for chart selection banner. Opacity-only — deliberately NOT
   /// Reduce-Motion-gated: fades aid comprehension and contain no movement.
   static let chartBannerFade: Animation = .easeInOut(duration: 0.15)
   ```
3. **ExpenseIncomeProgressBar.swift:30** — `private static let barAnimation = AppAnimation.progressBarSpring` → `private static var barAnimation: Animation? { AppAnimation.progressFillAnimation }`; три `withAnimation(Self.barAnimation)` (строки 55, 61, 66) работают с optional без изменений (`withAnimation(nil)` = без анимации).
4. **BudgetProgressBar.swift:66-67**, **ProportionBar.swift:28**, **BudgetProgressCircle.swift:103-104** — заменить каждую `.animation(...)` на `.animation(AppAnimation.progressFillAnimation, value: ...)` (у BudgetProgressCircle обе строки; кривая унифицируется на progressBarSpring — это плановое решение, см. аудит C6).
5. **SiriGlowView.swift** — добавить `@Environment(\.accessibilityReduceMotion) private var reduceMotion` и в `body`:
   ```swift
   var body: some View {
       Group {
           if reduceMotion {
               meshGlow(t: 0)
           } else {
               TimelineView(.periodic(from: .now, by: Self.frameInterval)) { timeline in
                   meshGlow(t: timeline.date.timeIntervalSinceReferenceDate)
               }
           }
       }
       .onGeometryChange(for: Double.self) { proxy in
           proxy.size.width / max(proxy.size.height, 1)
       } action: { newAspect in
           if abs(newAspect - aspect) > 0.01 {
               aspect = newAspect
           }
       }
   }
   ```
6. **MessageBanner.swift** — переписать `BannerAnimation` и onAppear:
   ```swift
   private enum BannerAnimation {
       static let entrance = Animation.spring(response: 0.4, dampingFraction: 0.8)
       static let icon = Animation.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)
       static let reducedFade = Animation.easeInOut(duration: 0.2)
       static let hiddenScale: CGFloat = 0.92
       static let hiddenOffset: CGFloat = -20
   }
   ```
   В `MessageBanner` добавить `@Environment(\.accessibilityReduceMotion) private var reduceMotion`. Модификаторы (строки 71-73): `scaleEffect(isVisible || reduceMotion ? 1 : BannerAnimation.hiddenScale)`, `.offset(y: isVisible || reduceMotion ? 0 : BannerAnimation.hiddenOffset)`, opacity без изменений. В `onAppear`: `withAnimation(reduceMotion ? BannerAnimation.reducedFade : BannerAnimation.entrance) { isVisible = true }`; icon-pop выполнять только при `!reduceMotion` (иначе сразу `iconScale = 1.0` без анимации). Inline-`.spring(...)` на строках 100-104 (`bannerContent`) заменить на `BannerAnimation.icon`.
7. **VoiceInputView.swift (StaggeredCard, ~:515-530)** — добавить `@Environment(\.accessibilityReduceMotion) private var reduceMotion`; `.offset(y: visible || reduceMotion ? 0 : 12)`; в `.task` — `withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : AppAnimation.gentleSpring) { visible = true }` (fade остаётся, слайд уходит; stagger-задержку оставить — она не движение).
8. **VoiceInputView.swift (PulsingText :547-550, RecordingIndicatorView :568-571)** и **BorderBeamModifier.swift:28** — заменить `AppAnimation.isReduceMotionEnabled` на `@Environment(\.accessibilityReduceMotion)` в каждом из трёх view/modifier (добавить property, использовать в том же выражении). Логика не меняется — меняется только реактивность на mid-session переключение.
9. **docs/design-system.md:1165-1168** — уточнить раздел Reduce Motion: перечислить `progressFillAnimation` среди gated-токенов и зафиксировать правило «opacity-only fades НЕ гейтятся» (пример: `chartBannerFade`).

## Boundaries

- Не трогать onboarding (`LoopOnBoardingView` keyframe-анимации) — отдельное решение владельца (delight-бюджет, редкий экран).
- Не трогать hero-иконки (план 008) и DonutChart (план 010).
- Не менять визуал при выключенном Reduce Motion, кроме оговорённых: MessageBanner entrance быстрее (0.4/0.8), BudgetProgressBar/Circle переходят на progressBarSpring.
- Если код не совпадает с выдержками — STOP.

## Verification

- **Механика**: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30` — пусто. Затем `grep -rn "isReduceMotionEnabled" Tenra/Views` — не должно остаться сайтов из шага 8.
- **Feel check** (владелец; Reduce Motion: Настройки → Универсальный доступ → Движение):
  - RM ON: голосовой экран — glow статичен (красивый, но неподвижный); прогресс-бары на home заполняются мгновенно; баннер сообщения появляется чистым fade без слайда/scale; voice-карточки появляются fade-ом без подъёма.
  - RM OFF: баннер стал заметно быстрее, но по-прежнему с мягким entrance; прогресс-круг бюджета (кольцо вокруг hero-иконки и в строках категорий) — тот же характер sweep, что и бары.
  - Переключить RM, НЕ убивая приложение, вернуться на экран записи голоса — pulsing-подсказка и красная точка записи останавливаются/возобновляются без перезапуска приложения.
- **Done when**: оба режима проверены; grep из механики чистый; строка в design-system.md соответствует коду.
