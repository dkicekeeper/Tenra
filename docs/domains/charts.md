# Charts Domain

Swift Charts patterns for `LineChart` / `BarChart` (multi-series), the `OrbChart` breakdown chart, and mini-charts.

## 2026-07 charts refactor — rename map

Feature-bound names replaced with reusable ones (old → new; grep for the new name):

| Old | New |
|---|---|
| `SpendingOrbChart` | `OrbChart` (renders income breakdowns too) |
| `PeriodLineChart` + `IncomeExpenseLineChart` | `LineChart` (multi-series; income/expense = `series: [.income, .spending]`) |
| `PeriodBarChart` + `IncomeExpenseBarChart` | `BarChart` (multi-series, grouped via `position(by:)`) |
| `PeriodChartSwitcher` / `IncomeExpenseChartSwitcher` / `PeriodTrendChartSwitcher` | `ChartSwitcher` |
| `PeriodLineChartSeries` | `PeriodChartSeries` (kept the Period prefix — bound to `PeriodDataPoint`) |
| `BudgetProgressBar` | `LinearProgressBar` (also renders health scores) |
| `BudgetProgressCircle` | `ProgressRing` |
| `ExpenseIncomeProgressBar` | `AmountComparisonBar` (now built on `ProportionBar`) |

`ChartZoomControls` extracted to its own file (also hosts the shared `ChartStyle` bar/line enum). `ChartDisplayMode` deleted (dead code).

### Multi-series period charts (the 4→2 merge)

`LineChart` and `BarChart` take `series: [PeriodChartSeries]` (single-value convenience inits exist). The income/expense overlay is NOT a separate chart — it's `[.income, .spending]`: both cases already carried the needed styles in the enum, so the former `IncomeExpenseLineChart`/`IncomeExpenseBarChart`/`IncomeExpenseChartSwitcher` were deleted.

- Marks always pass `series: .value("Type", s.seriesKey)` + `stacking: .unstacked` (line) / `position(by:)` when grouped (bar).
- ⚠️ **Banner assumption**: 2+ series render the `.dual(income:expenses:)` banner reading `p.income`/`p.expenses` directly — the only shipped multi-series combo IS income+expense. A new combo needs a generalized banner first.
- Selection halos: multi-series skips zero-valued points (halo at the baseline reads as noise); single-series always highlights.
- Adding a `PeriodChartSeries` case: also set `seriesKey` (mark grouping) — plus the ~9 style switches listed below.

`ChartSwitcher` (segmented bar/line picker + `ChartZoomControls`; zoom state lives here, passed down as a binding) wraps the pair everywhere: InsightsSummaryDetailView (`[.income, .spending]`, default `.bar`), InsightDetailView periodTrend details (single series, default `.line`). Charts no longer own a zoom toolbar — standalone use gets `.constant(1.0)`.

### Y-domain headroom (peak clipping)

⚠️ Both full-size charts pad the Y domain by **~6% of the span** (and below the floor when the domain goes negative) — without it the peak `PointMark`/bar top sits exactly on the plot edge and renders clipped. Keep the headroom when touching `fullYDomain`.

⚠️ **Gradient styles must use the UNPADDED envelope, not the padded domain.** `lineStyle`/`areaStyle` gradients resolve against the mark's own bounds (the raw data envelope) — computing the cashFlow `zeroRatio` from the padded `fullYDomain` shifts the green→red transition above the true zero line (renders as a red band over y=0 when negatives exist). `LineChart.fullChart` passes `styleEnvelope = min(yMin,0)...max(yMax,1)` to the style builders and the padded `domain` only to `chartYScale`.

### Progress components & entrance animation

`ProportionBar` (base two-segment primitive), `LinearProgressBar` (percentage + overshoot), `ProgressRing`, `AmountComparisonBar` (ProportionBar + amount labels) all share the sweep-from-zero entrance pattern: `@State` display value + `onAppear`/`onChange` + Reduce Motion → `.linear(duration: 0)`.

⚠️ **`animatesOnAppear: false` in lazy containers** (CategoryRow, CategoryChip, InsightsCardView feed) — `onAppear` re-fires each time a lazy row re-materialises during scroll, replaying the sweep. Detail screens and one-off cards keep the default `true`.

**`ProgressRing` color model** — a static full-circle "trajectory" `AngularGradient` (green ≤45% → warning by 80% → destructive at 100%; over-budget = warning→red) revealed by the animated `trim`. The tip color tracks the fill level continuously with zero interpolation code — do NOT reintroduce threshold-snapped solid colors; gradient stops are progress fractions and must NOT be tied to the animated display value (stops aren't animatable).

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

### Adding a `PeriodChartSeries` case

Adding a case touches ~9 switches: `value`/`yDomain`/`pointColor`/`lineStyle`/`areaStyle`/`showZeroRuler`/`fullLineWidth` in the enum, `fullYDomain` in `LineChart`, and `tintColor` in `MiniSparkline`. The compiler flags all of them (exhaustive switches) — none are silent.

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

`ChartZoomControls(zoomScale: $zoomScale, range:)` — `+/-` buttons with step ×1.5, own file `Views/Components/Charts/ChartZoomControls.swift` (also hosts `ChartStyle`). Used in `ChartSwitcher` (picker left, zoom right in HStack).

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

⚠️ **No compact mode** on `BarChart` / `LineChart` / `ChartSwitcher`.

For insight-feed compact charts use **Canvas-based** `MiniSparkline` / `MiniDonut` (~50× cheaper to instantiate than Apple Charts).

(`ChartDisplayMode` was dead code and deleted in the 2026-07 charts refactor.)

## Breakdown Chart (OrbChart)

⚠️ **`DonutChart` was removed** — [`OrbChart`](../../Tenra/Views/Components/Charts/OrbChart.swift) is the full-size category/subcategory breakdown chart (a blended glass "orb" + thin perimeter arcs + centred `%` labels). `DonutSlice` and its `from(_:)` / `from(_:baseColor:)` factories (sliver aggregation: merge <5% into "Other", drop a <3% tail) live in that file now, NOT a `DonutChart.swift`. `MiniDonut` still backs compact feed charts.
- **Params**: `showLabels`, `centerIcon` (white glyph in the sphere centre) + `showsCenterIcon`, `size`, `animatesOnAppear`.
- **Motion highlight**: `CMMotionManager` device-motion drives the specular glint. No Info.plist usage string needed (only pedometer/activity require one); Simulator `isDeviceMotionAvailable == false` → static no-op; neutral pose captured on first reading. 30 Hz updates isolated in a child view so only it invalidates.
- **Staggered entrance**: one `@State` flip + per-layer `.animation(anim.delay(i·step), value: entered)` — see the SwiftUI note in [gotchas.md](../gotchas.md).

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
