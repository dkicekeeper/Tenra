# Charts Domain

Swift Charts patterns for `PeriodBarChart`, `IncomeExpenseLineChart`, `PeriodLineChart`, `DonutChart`, and mini-charts.

## Native Scroll Pattern

Use **native `chartScrollableAxes`** instead of wrapping `Chart{}` in `ScrollView`:

```swift
.chartScrollableAxes(.horizontal)
.chartXVisibleDomain(length: visibleCount)
.chartScrollPosition(x: $binding)  // OR .chartScrollPosition(initialX: ...)
```

Better per-frame than `ScrollView { Chart }` with `defaultScrollAnchor`.

## Bleed-to-Edge Scrollable Charts

Scrollable charts must be **bleed-to-edge** — without `.screenPadding()` on parent, otherwise plot area is clipped and the first point sticks to the screen edge. Apply padding to header/list neighbours, NOT to the chart itself.

## Gesture Conflicts

### MagnifyGesture vs NavigationStack swipe-back

⚠️ **`MagnifyGesture` conflicts with NavigationStack swipe-back** — on detail pages, do NOT use pinch zoom. Replace with `+/-` buttons.

If `MagnifyGesture` is unavoidable, attach `.simultaneousGesture(...)` so native chart gestures (selection) aren't intercepted.

### Horizontal paging vs swipe-back

⚠️ **For swipeable horizontal paging inside a pushed detail, use `TabView(.page(indexDisplayMode:))`, NOT a custom horizontal `DragGesture`.** A `DragGesture` fights the NavigationStack edge swipe-to-go-back (the user gets inconsistent paging vs. dismiss). TabView paging consumes content-area horizontal swipes; edge-back still works from the screen edge. Precedent: `PagedCategoryBreakdownView` in `InsightDetailView.swift`.

### Adding a `PeriodLineChartSeries` case

Adding a case touches ~9 switches: `value`/`yDomain`/`pointColor`/`lineStyle`/`areaStyle`/`showZeroRuler`/`fullLineWidth` in the enum, `fullYDomain` in `PeriodLineChart`, and `tintColor` in `MiniSparkline`. The compiler flags all of them (exhaustive switches) — none are silent.

### Custom tap selection blocks scroll

⚠️ **Custom tap selection blocks scroll on `chartScrollableAxes` charts**: `chartOverlay { Color.clear.contentShape(...) ... }` absorbs touches at SwiftUI hit-testing layer, before gesture arbitration — `simultaneousGesture` / `onTapGesture(coordinateSpace:)` don't help.

For tap selection on scrollable charts use **only** `chartXSelection(value:)`.

## Chart Selection

### value + range simultaneously

`chartXSelection(value:)` + `chartXSelection(range:)` together — **value=tap, range=long-press-drag**, no conflict.

⚠️ **Both bindings must be set simultaneously**, otherwise one overrides the other.

### `chartScrollPosition(x:)` requires non-optional `Plottable`

For `String?` wrap via `Binding<String>` with fallback to initial label.

### Setter race during range-selection

⚠️ Apple calls `chartScrollPosition.setter` during `chartXSelection(range:)` drag → if scroll position controls dynamic Y → bars jump.

**Solution**: block setter and **freeze dynamic Y** while `selectedRange != nil`.

## Multi-Series AreaMark

`AreaMark` **stacks by default** — for overlay (income vs expense) you need `series:` PLUS `stacking: .unstacked` together.

Without `series:`, two areas merge into one zigzag-series between x-points.

## Axis Labels

### Collision resolution

```swift
AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 6))
```

Standard label thinning when dates collide. Apply everywhere `AxisMarks { }` uses String x-axis.

### Initial trailing scroll

```swift
let initialLeftLabel = dataPoints[max(0, count - visibleCount)].label
.chartScrollPosition(initialX: initialLeftLabel)
```

`chartXVisibleDomain(length: N)` for category axis shows N categories regardless of frame width — no `GeometryReader` needed; derive `visibleCount` from `zoomScale` only.

### `chartScrollPosition(initialX:)` is stable

For one-shot trailing-anchor when no other re-anchor sources exist (static yDomain, no `chartScrollPosition(x: $binding)`).

The `x: $binding` form re-anchors viewport on body re-eval — caused "x-axis flips on tap" bug.

## Category X-axis Order

⚠️ **First-occurrence across marks in declaration order.**

Lock via `chartXScale(domain: dataPoints.map { $0.label })` AND put conditional/selection marks AFTER `ForEach(dataPoints)`. A selection `RuleMark` declared first silently reorders the axis (tap-flips-date bug).

## Conditional Styling

`AnyShapeStyle` for conditional gradient/color on `LineMark.foregroundStyle()` — allows switching between solid and `LinearGradient` without overload conflicts.

## Selection Banner Anti-Jump

Wrap conditional banner in fixed-height `ZStack` (e.g. `.frame(height: 56)`) with opacity transition.

Banner placed directly in VStack shifts chart vertically on selection appear/disappear.

## Reusable Components

### ChartZoomControls

`ChartZoomControls(zoomScale: $zoomScale, range:)` — `+/-` buttons with step ×1.5 via `Views/Components/Charts/PeriodChartSwitcher.swift`. Used in `PeriodChartSwitcher` (picker left, zoom right in HStack) and standalone `PeriodLineChart` (own `zoomToolbar`).

### PeriodChartHelpers

Period charts share [Views/Components/Charts/PeriodChartHelpers.swift](../../Tenra/Views/Components/Charts/PeriodChartHelpers.swift):

- `PeriodChartCache` — label→index + yMin/yMax + todayLabel + identity fingerprint
- `rebuildPeriodCacheIfNeeded(_:dataPoints:values:)`
- `.periodChartXAxis(labelMap:)` / `.periodChartYAxis()`
- `.chartXLabelSelectionWithFeedback($selectedValueLabel)` (haptic via `HapticManager.selection()`)
- `.chartBannerSlotStyle(animationKey:)`
- `.chartSelectionAnnouncement(_:)` + `chartBannerAnnouncementText(...)`

New `PeriodDataPoint`-driven charts plug into these — don't reimplement inline.

### Body-time cache priming

`let _ = rebuildCacheIfNeeded()` at the top of `body` runs synchronously before any cache-reading getter.

⚠️ **`.onAppear` fires AFTER the first body-eval** — cold cache returns defaults on the first frame.

### ChartSelectionBanner

`ChartSelectionBanner` ([Views/Components/Charts/ChartSelectionBanner.swift](../../Tenra/Views/Components/Charts/ChartSelectionBanner.swift)) — `.dual(income:expenses:)` or `.single(value:color:)`. Capitalises the title's first char; falls back to `formatCompact` when `currency` is empty.

## Compact Mode

⚠️ **No compact mode** on `PeriodBarChart` / `IncomeExpenseLineChart` / `PeriodLineChart` / `PeriodChartSwitcher`.

For insight-feed compact charts use **Canvas-based** `MiniSparkline` / `MiniDonut` (~50× cheaper to instantiate than Apple Charts).

`ChartDisplayMode` enum still applies to `DonutChart`.

## Mini-Charts in Scroll Feeds

⚠️ **Mini-charts in scroll feeds → Canvas, not `Chart{}`**: Apple Charts per-card instantiation hitches `LazyVStack` section materialization at ~5ms per chart.

For compact sparklines/donuts inside cards, use `Canvas`-based components:
- [MiniDonut.swift](../../Tenra/Views/Components/Charts/MiniDonut.swift)
- [MiniSparkline.swift](../../Tenra/Views/Components/Charts/MiniSparkline.swift)

## Performance Anti-Patterns

### Animation on hot paths

⚠️ **`.animation(value:)` on scroll/zoom-dependent state = hot-path catastrophe**: every scroll event triggers spring → animation accumulation → lag. Apple Charts already smoothly interpolate — no spring needed on top.

### `String(localized:)` in body

⚠️ **`String(localized:)` in hot-path body of chart = anti-pattern**: each scroll frame recreates the localized string. Cache in `@State` / `static let` outside `body` or use stable string keys for `position(by:)`.

### Heavy axis-label maps

Use `ChartAxisLabelMapCache` (MainActor singleton, key = count + first + last) for cache.

Any new heavy chart format function (`DateFormatter`, `Dictionary` builds) should go through a similar cache, otherwise rebuild on scroll/zoom dominates frame budget at 60fps.
