# 010 — DonutChart: sweep только при первом появлении, короче и с Reduce Motion

- **Status**: DONE (implemented 2026-07-13 on main; build succeeded; device feel-check pending)
- **Commit**: bef4de4
- **Severity**: MEDIUM
- **Category**: Easing & duration + Purpose & frequency + Cohesion
- **Estimated scope**: 2 файла, ~30 строк

## Problem

Круговая «отрисовка» донат-чарта — красивый first-appearance flourish, но он реализован так, что:

1. **0.7 с — 2.3× бюджета UI-анимаций (≤300 мс)**, кривая захардкожена мимо reduce-motion-aware чарт-токенов (единственный чарт в приложении мимо них; соседняя строка 181 использует gated `chartUpdateAnimation`):

```swift
// Tenra/Views/Components/Charts/DonutChart.swift:190-193 — текущий код
.onAppear {
    drawProgress = 0
    withAnimation(.easeOut(duration: 0.7)) { drawProgress = 1 }
}
```

2. **Sweep реплеится на каждый свайп периода** в InsightDetailView: `.id(index)` пересоздаёт DonutChart, его `onAppear` сбрасывает `drawProgress = 0` — и полный 0.7-секундный wipe играет заново при каждом листании, одновременно кроссфейдясь с уходящим донатом (двойная экспозиция):

```swift
// Tenra/Views/Insights/InsightDetailView.swift:446-455 — текущий код
Group {
    if let page, !page.items.isEmpty {
        DonutChart(slices: DonutSlice.from(page.items))
            .screenPadding()
    } else {
        Color.clear.frame(height: 200)
    }
}
.id(index)
.transition(.opacity)
```

Состояние: `DonutChart.swift:123` — `@State private var drawProgress: CGFloat = 0`; маска — `sweepMask` (:199-208).

## Target

- Sweep играет **один раз** — при первом появлении chart band, длительностью **0.45 с** `easeOut`, под Reduce Motion — мгновенно (`drawProgress = 1` без анимации).
- Листание периодов — обычный кроссфейд контента (существующий `.transition(.opacity)` + `chartUpdateAnimation` для перестроения долей), без повторного wipe.

## Repo conventions to follow

- Gated-чарт-токены: `AppAnimation.chartAppearAnimation` / `chartUpdateAnimation` (`Tenra/Utils/AppAnimation.swift:75-86`) — образец для нового токена.
- Компонентные параметры по умолчанию — через init с default-значением (по образцу `DonutChart`'s `centerContent`).

## Steps

1. **AppAnimation.swift** — в MARK "Chart Animations" добавить:
   ```swift
   /// Reduce-Motion-aware one-shot sweep for the donut ring reveal.
   static var donutSweepAnimation: Animation {
       isReduceMotionEnabled ? .linear(duration: 0) : .easeOut(duration: 0.45)
   }
   ```
2. **DonutChart.swift** — добавить параметр `var animatesOnAppear: Bool = true` (сохранив существующие вызовы без изменений — default true). Изменить onAppear:
   ```swift
   .onAppear {
       guard animatesOnAppear else {
           drawProgress = 1
           return
       }
       drawProgress = 0
       withAnimation(AppAnimation.donutSweepAnimation) { drawProgress = 1 }
   }
   ```
3. **InsightDetailView.swift (chartBand, :442-466)** — добавить в содержащий view `@State private var hasPlayedSweep = false`; передавать и взводить флаг:
   ```swift
   DonutChart(slices: DonutSlice.from(page.items), animatesOnAppear: !hasPlayedSweep)
       .screenPadding()
       .onAppear { hasPlayedSweep = true }
   ```
   (`onAppear` дочернего view выполняется до родительского модификатора только при первом монтировании того же identity; здесь identity меняется через `.id(index)`, поэтому взводить флаг надо на **контейнере** — если при проверке первый sweep не играет, перенести `.onAppear { hasPlayedSweep = true }` на `Group` уровнем выше, после `.transition(.opacity)`, с задержкой не требуется: `@State` уже true к следующему пересозданию.)
4. Проверить остальные call-sites `DonutChart(` (grep) — `InsightDeepDiveView` и прочие оставить с default `animatesOnAppear: true` (там нет `.id`-пересозданий при листании; если есть — применить тот же приём и отметить в отчёте).

## Boundaries

- Не трогать `sweepMask`, слайсы, легенду, центральный контент.
- Не менять `.transition(.opacity)`/`.animation(.easeInOut(duration: 0.25), value: index)` band-а (их консолидация — план 012).
- Если код не совпадает с выдержками — STOP.

## Verification

- **Механика**: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30` — пусто.
- **Feel check** (владелец):
  - Открыть Insights → детальный экран с донатом: кольцо отрисовывается по кругу заметно бодрее прежнего (~полсекунды).
  - Листнуть период стрелкой → доли просто кроссфейдятся; кругового wipe НЕТ, двойной экспозиции двух колец не видно.
  - Вернуться назад и снова открыть экран → sweep играет снова (новый экран = новое первое появление — это ожидаемо).
  - Reduce Motion ON → кольцо появляется сразу целиком.
- **Done when**: все четыре пункта подтверждены.
