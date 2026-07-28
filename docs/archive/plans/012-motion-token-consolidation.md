# 012 — Консолидация motion-литералов в токены + interactive carousel

- **Status**: DONE (implemented 2026-07-13 on main; build succeeded; device feel-check pending)
- **Commit**: bef4de4
- **Severity**: MEDIUM (когезия; включает один feel-фикс — interactive scroll)
- **Category**: Cohesion & tokens + Interruptibility
- **Estimated scope**: 8 файлов, ~40 строк

## Problem

design-system.md §9: «Never use hardcoded springs; all animations must use `AppAnimation` constants». Аудит нашёл 14 полностью захардкоженных литералов + 6 гибридов вне `AppAnimation.swift`. Ключевые кластеры:

**1. «Скролл карусели к выбранному» закодирован 4 раза, с двумя разными кривыми:**

```swift
// Tenra/Utils/CarouselConfiguration.swift:92 — текущий код
scrollAnimation: .easeInOut(duration: 0.3),
```
```swift
// Tenra/Views/Components/Input/CategoryCardSelectorView.swift:104 — текущий код
withAnimation(.easeInOut(duration: 0.3)) {
    scrollPosition = target
}
```
```swift
// Tenra/Views/Components/Input/AccountSelectorView.swift:133 — текущий код (идентичный syncScrollToSelected)
withAnimation(.easeInOut(duration: 0.3)) {
    scrollPosition = target
}
```
```swift
// Tenra/Views/Components/Input/AccountsCarousel.swift:57-61 — текущий код
content.scrollTransition(.animated(.easeOut(duration: 0.3))) { content, phase in
    content
        .opacity(phase.isIdentity ? 1 : 0.75)
        .scaleEffect(phase.isIdentity ? 1 : 0.95)
}
```

Четвёртый сайт — ещё и feel-баг: `.animated(...)` перетвинивает fade/scale фиксированной кривой при смене фазы, вместо того чтобы **непрерывно следовать за пальцем**. На главном экране карточки «догоняют» скролл.

**2. `InsightDetailView` трижды перепечатывает значение токена `standard` (0.25):** строки 465 (`.animation(.easeInOut(duration: 0.25), value: index)` на chart band), 488 (то же на listPager) и 509 (`withAnimation(.easeInOut(duration: 0.25)) { index = next }`). Все три обязаны оставаться в локстепе — чарт и список листаются вместе.

**3. Одиночные литералы-сироты:**
- `Tenra/TenraApp.swift:49` — `.animation(.easeInOut(duration: 0.2), value: coordinator == nil)`: entrance по правилам — ease-out.
- `Tenra/Views/Components/EntityDetail/EntityDetailScaffold.swift:146` — `.animation(.smooth(duration: 0.2), value: isNavTitleVisible)`: единственный `.smooth` в репозитории, кривая-сирота для обычного fade.
- `Tenra/Views/Onboarding/OnboardingWelcomeStep.swift:101` — `.animation(.spring(response: 0.55, dampingFraction: 0.85), value: index)`: inline-spring, прямо запрещён §9.
- `Tenra/Views/Components/Input/InsightsGranularityPicker.swift:24` — `withAnimation(AppAnimation.adaptiveSpring)` для выбора гранулярности: `adaptiveSpring` (damping 0.6, видимый bounce) зарезервирован за press-feedback; для смены выбора в «строгом» приложении — несоответствие характера.
- `Tenra/Views/Components/Input/SubscriptionCalendarView.swift:193` — `.animation(.easeInOut(duration: AppAnimation.slow), value: currentMonthIndex)`: 0.35 с > бюджета 0.3 с для листания месяца.
- `Tenra/Views/Components/Input/SubscriptionCalendarView.swift:265,273` — `.transition(.scale.combined(with: .opacity))` на логотипах дат: голый `.scale` = рост из нуля (запрещено).

## Target

Один новый токен `carouselScroll`, интерактивный scrollTransition, все перечисленные литералы заменены токенами/дозволенными значениями. Поведение вне перечисленных мест не меняется.

## Repo conventions to follow

- Токены — статические константы/вары в `Tenra/Utils/AppAnimation.swift` с doc-комментарием «for …» (образец: `contentSpring`, строки 25-27).
- Компонентно-локальные константы допустимы через `private enum` (прецедент `BannerAnimation`, design-system.md:141), но общие паттерны — только в `AppAnimation`.

## Steps

1. **AppAnimation.swift** — добавить в Basic Durations:
   ```swift
   /// Programmatic carousel scroll-to-selection (account/category selectors).
   static let carouselScroll: Animation = .easeInOut(duration: 0.3)
   ```
2. **CarouselConfiguration.swift:92** — `scrollAnimation: AppAnimation.carouselScroll,`.
3. **CategoryCardSelectorView.swift:104** и **AccountSelectorView.swift:133** — `withAnimation(AppAnimation.carouselScroll) { scrollPosition = target }`.
4. **AccountsCarousel.swift:57** — `.scrollTransition(.animated(.easeOut(duration: 0.3)))` → `.scrollTransition(.interactive)` (замыкание с opacity/scale не меняется — теперь значения интерполируются от позиции скролла непрерывно).
5. **InsightDetailView.swift** — добавить в тип приватную константу `private static let pageAnimation: Animation = .easeInOut(duration: AppAnimation.standard)`; заменить все три литерала (:465, :488, :509) на `Self.pageAnimation`.
6. **TenraApp.swift:49** — `.animation(.easeOut(duration: 0.2), value: coordinator == nil)`.
7. **EntityDetailScaffold.swift:146** — `.animation(.easeInOut(duration: 0.2), value: isNavTitleVisible)`.
8. **OnboardingWelcomeStep.swift:101** — вынести в приватную константу типа: `private static let stepSpring: Animation = .spring(response: 0.55, dampingFraction: 0.85)` и использовать её (значение сохранить — feel онбординга менять нельзя; убирается только inline-литерал).
9. **InsightsGranularityPicker.swift:24** — `withAnimation(AppAnimation.contentSpring)`.
10. **SubscriptionCalendarView.swift:193** — `AppAnimation.slow` → `AppAnimation.standard`.
11. **SubscriptionCalendarView.swift:265 и 273** — `.transition(.scale.combined(with: .opacity))` → `.transition(.scale(scale: AppAnimation.facepileHiddenScale).combined(with: .opacity))` (0.5 — тот же старт, что у facepile-иконок той же крупности).

## Boundaries

- Не трогать `MessageBanner`, прогресс-бары, hero-иконки, DonutChart (планы 008–010).
- Не трогать `.linear(duration: 0)`-паттерны Reduce Motion и `#Preview`-блоки.
- Feel онбординга (шаг 8) — значение пружины сохранить бит-в-бит.
- Если код не совпадает с выдержками — STOP.

## Verification

- **Механика**: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30` — пусто. Затем `grep -rn "easeInOut(duration: 0.3)\|easeInOut(duration: 0.25)" Tenra --include="*.swift" | grep -v Preview` — не осталось сайтов из шагов 2-5.
- **Feel check** (владелец):
  - Home: медленно тянуть карусель счетов пальцем — крайние карточки бледнеют/сжимаются синхронно с пальцем, без «догоняющего» перехода после остановки (шаг 4 — единственное намеренное изменение ощущения).
  - Insights: листание периодов стрелками — чарт и список движутся как раньше, в локстепе.
  - Календарь подписок: листание месяца чуть бодрее; появление логотипов на датах — мягкий pop, не рост из точки.
  - Переключатель гранулярности Insights — выбор без прыгучего overshoot.
- **Done when**: grep чистый, feel check подтверждён.
