# Gotchas

Known traps, performance hot-paths, and surprising behaviors. Domain-specific gotchas live in `docs/domains/<domain>.md`.

## SwiftUI Layout

- **`containerRelativeFrame` wrong container**: Plain `HStack`/`VStack` are NOT qualifying containers — use `GeometryReader` for proportional sizing inside non-lazy containers.
- **`layoutPriority` is not proportional**: Higher priority takes all remaining space first — it's not a ratio.
- **`Task.yield()` for focus timing**: Replace `Task.sleep(nanoseconds:)` focus hacks with `await Task.yield()` inside `.task {}`.
- **Missing struct `}` after Button wrap**: Wrapping a view's body in `Button { }` can absorb the struct's closing brace — verify brace balance.
- **`.task` vs `.onAppear { Task {} }`**: `.task` is automatically cancelled on view removal; unstructured `Task {}` in `.onAppear` is unowned and can fire after dismissal.
- **`Text("localization.key")` renders the raw key**: Always use `Text(String(localized: "some.key"))` for guaranteed localized output.
- **`Task.sleep(nanoseconds:)` → Duration API**: Use `try? await Task.sleep(for: .milliseconds(150))` instead.
- **ForEach identity — never use `UUID()`**: `UUID()` generates a new id every render → spurious animations, sheet dismiss/reopen. Use stable identifiers: name-based id, `"\(name)_\(type.rawValue)"` fallback.
- **Prefer `.searchable(text:placement:.navigationBarDrawer(.always))` over custom TextField**: gives native Cancel for keyboard dismiss + scope/tokens support. Custom search bars in nav stacks typically need manual `@FocusState` + keyboard toolbar that `.searchable` handles for free.
- **Extra toolbar items in `EditSheetContainer`**: container uses `.cancellationAction` (xmark) + `.confirmationAction` (Save). Child views nest `.toolbar { ToolbarItem(placement: .primaryAction) { ... } }` inside the content closure — iOS auto-places `.primaryAction` items LEFT of `.confirmationAction`. Do NOT use `.topBarTrailing` / `.navigationBarTrailing` — they land on the wrong side of Save.
- **`.contentReveal(isReady:)` only hides via opacity** — it does NOT skip body evaluation, layout, or render. For genuinely deferred rendering of heavy sections (glass cards, PackedCircleIconsView, large grids), gate them behind an `if` condition instead.
- **iOS 26 TabView lazy-renders non-active tab content** — verified: `AnalyticsTab.body` and `SettingsTab.body` don't fire on launch when `.home` is selected. Don't worry about non-active tab init being on the launch critical path.
- **`.frame(height:)` doesn't resize a segmented `Picker`** — `Picker(.segmented)` has fixed intrinsic height. Use `.controlSize(.large)` (~36pt) or `.controlSize(.extraLarge)` (~44pt) to match adjacent button heights.
- **`.localizedCapitalized` capitalizes EVERY word** — wrong for date-range strings like `"3 янв – 9 янв"` → `"3 Янв – 9 Янв"`. For first-char-only capitalization: `first.uppercased() + dropFirst()`.
- **Liquid Glass merged button group**: `GlassEffectContainer(spacing: AppSpacing.sm) { HStack(spacing: 0) { Button { … }.buttonStyle(.glass).buttonBorderShape(.circle) } }`. `HStack(spacing: 0)` is intentional — adjacent glass shapes blend into a continuous merged look. For separated round glass buttons use HStack with non-zero spacing.
- **Animated `AngularGradient` border — rotate the gradient, NOT the shape**: Using `.stroke(AngularGradient(...)).rotationEffect(.degrees(t))` tilts the entire stroked rectangle in space (you see a diagonal beam floating around the card). Correct: keep the shape fixed and pass the rotation into the gradient itself via `AngularGradient(gradient:center:angle: .degrees(t))`. The bright spot then travels along the perimeter as time advances. See `BorderBeamModifier`.

## Performance Hot-Paths

### List rendering

- ⚠️ **SwiftUI `List` + 500+ sections = hard freeze** — SwiftUI renders all `Section` headers eagerly. Always slice: `Array(sections.prefix(visibleSectionLimit))` with `@State var visibleSectionLimit = 100`. Add `ProgressView().onAppear { visibleSectionLimit += 100 }` as the last List row for infinite scroll.
- **Pre-resolve per-row data at ForEach call site**: Passing `[Account]` or `[CustomCategory]` arrays to a row view means any element change forces ALL rows to re-render. Pre-resolve per-row `let` bindings inside `ForEach` and pass `Equatable` scalars.
- **`@State` cache for 2k+ row lists**: Computed props for filter/group-by/lookup re-run per view-body eval and dominate tap latency. Move `filteredX`, `dateSections`, `accountById`, `allSatisfy`-flags into `@State`, rebuild in a single `rebuildDerivedCaches()` pass on input changes. See `SubscriptionLinkPaymentsView` for the pattern.

### View triggers

- **`.onAppear` for synchronous cache warm-up**: Use `.onAppear { rebuildCache() }` (runs synchronously before next frame), NOT `.task { await rebuildCache() }` (async — fires after List body renders).
- ⚠️ **`onAppear` fires on every back-navigation** — use `.task(id: trigger)` instead: combine reactive inputs in `Equatable` struct (`SummaryTrigger` pattern); SwiftUI manages cancellation automatically. Use debounce inside `if !isFullyInitialized` so init-complete triggers are immediate.

### Background work

- **Heavy nonisolated scans off MainActor**: `Task.detached(priority: .userInitiated) { let result = Matcher.scan(...); await MainActor.run { self.baseline = result; self.applyFilters() } }` for O(N_transactions) filters on view open. SwiftUI `View` structs are auto-Sendable — capture is safe.

### Build & profiling

- **`CompileAssetCatalogVariant` failure can be transient** — if `grep -E "error:"` returns nothing, just retry.
- **Don't profile under attached Xcode debugger** — `os.Logger.debug` flooding alone inflated a real <1s launch into a measured 4–6s. Use Instruments Time Profiler or detach debugger before measuring.
- **`PerformanceProfiler.start/end` uses `CACurrentMediaTime()` synchronously** — measurements reflect actual elapsed time at the call site. Older logs that captured time via queued `Task { @MainActor }` are not comparable.

## Code Hygiene

- **Dead code deletion — orphaned call sites**: When deleting a class, grep all `.swift` sources for the class name AND all method names it implemented.
- **`Group {}` in `@ViewBuilder` computed var is unnecessary** — add `@ViewBuilder` and remove `Group`.
- **New `.swift` files auto-register**: Xcode synchronized folders pick up any new file in `Tenra/` subdirectories on next build. Do NOT edit `project.pbxproj` manually for adding files.
- **Don't flag `#Preview` block inconsistencies as production drifts in audits** — distinguish preview-only from production usage when grep'ing.

## Common Cross-Domain Pitfalls

- **PreAggregatedData "piggyback" pattern**: Add fields to `PreAggregatedData.build()` O(N) loop — never add separate O(N) loops when one already exists. See [domains/insights.md](domains/insights.md).
- **`filterService.filterByTimeRange` is expensive** (~16μs/tx due to DateFormatter): use `txDateMap` inline filter when available. See [domains/insights.md](domains/insights.md).
- **Subcategory CoreData relationship**: `Transaction.subcategory: String?` is legacy; real subcats live via `categoriesViewModel.linkSubcategoriesToTransaction(transactionId:subcategoryIds:)`. Generated recurring txs need explicit linking after creation. See [domains/recurring.md](domains/recurring.md).
- **Reconciliation callback pattern**: Never spawn `Task {}` inside synchronous `onTransactionCreated` callbacks — collect into array, batch-persist after reconciliation completes. Applies to both deposits and loans. See [domains/deposits.md](domains/deposits.md) / [domains/loans.md](domains/loans.md).

## Localization

- **NEVER delete `.lproj` files** — they're used via `String(localized:)` even without explicit pbxproj refs.
