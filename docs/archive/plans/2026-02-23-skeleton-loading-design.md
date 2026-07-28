# Skeleton Loading — ContentView & InsightsView

**Date:** 2026-02-23
**Status:** Approved
**Approach:** Shape-accurate skeleton + Shimmer modifier (Variant A)

---

## Problem

Both ContentView and InsightsView currently show a generic `ProgressView()` spinner during loading. This creates:
- A jarring visual jump when real content loads (layout shift)
- No spatial context for the user — they can't predict what's coming
- Inconsistency with modern iOS loading patterns (shimmer is standard)

---

## Solution Overview

Three new files + integration into two existing views:

```
Views/Components/SkeletonView.swift         — rewritten: base block + shimmer modifier
Views/Components/ContentViewSkeleton.swift  — home screen skeleton
Views/Components/InsightsSkeleton.swift     — analytics screen skeleton
```

---

## Architecture

### 1. SkeletonShimmerModifier (`SkeletonView.swift`)

A `ViewModifier` that overlays a moving shimmer gradient on any view.

**Implementation:**
- `@State private var phase: CGFloat = -1.0` — horizontal position of the shimmer
- On `onAppear`: animates phase from `-1.0` to `2.0` with `.easeInOut(duration: 1.4).repeatForever(autoreverses: false)`
- Overlay: `LinearGradient` with stops `[clear, white.opacity(0.3), clear]`
- Direction: `UnitPoint(x: phase, y: 0)` → `UnitPoint(x: phase + 1, y: 0)`
- Liquid Glass character: white shimmer at low opacity simulates glass reflection

**Public API:**
```swift
extension View {
    func skeletonShimmer() -> some View
}
```

### 2. SkeletonView (`SkeletonView.swift`)

Base building block for all skeleton layouts.

```swift
struct SkeletonView: View {
    var width: CGFloat? = nil        // nil = fill available width
    var height: CGFloat
    var cornerRadius: CGFloat = 8
}
```

Fill color: `Color(.systemFill)` — adaptive for dark/light mode.
Shimmer applied internally.

### 3. ContentViewSkeleton (`Views/Components/ContentViewSkeleton.swift`)

Mirrors the home screen layout:

| Element | Skeleton |
|---------|----------|
| Filter chip "Всё время" | `SkeletonView(width: 100, height: 32, cornerRadius: 16)` |
| Account cards carousel | 3× `SkeletonView(width: 200, height: 120, cornerRadius: 20)` in HStack |
| Section cards (История, Подписки, Категории) | 3× tall card with icon circle + 2 text lines |

**Integration in ContentView:**
- Replaces `ProgressView()` + "Loading data..." overlay
- Shown while `isInitializing == true`
- Full-screen overlay matching the actual screen padding/spacing
- Transition: `.opacity.combined(with: .scale(0.98))` — subtle zoom-out when content appears

### 4. InsightsSkeleton (`Views/Components/InsightsSkeleton.swift`)

Mirrors the analytics screen layout:

| Element | Skeleton |
|---------|----------|
| Summary header card | Card with 3 column blocks + health score row |
| Category filter carousel | 4× chip `SkeletonView(width: 70, height: 30, cornerRadius: 15)` |
| Section header label | `SkeletonView(width: 120, height: 16)` |
| Insight cards (×3) | Card: circle icon + 3 text lines + trailing chart rect |

**Integration in InsightsView:**
- Replaces `ProgressView()` block in `if insightsViewModel.isLoading` branch
- Occupies full scroll body — no layout shift
- Same `.opacity.combined(with: .scale(0.98))` transition

---

## Animation Details

| Property | Value |
|----------|-------|
| Duration | 1.4s |
| Curve | `.easeInOut` |
| Repeat | `autoreverses: false` (one-direction sweep) |
| Shimmer color | `white.opacity(0.3)` |
| Base fill | `Color(.systemFill)` |
| Transition out | `.opacity` + `.scale(0.98)` with `.spring(response: 0.4)` |

---

## Files Changed

| File | Change |
|------|--------|
| `Views/Components/SkeletonView.swift` | **Rewrite** — add `SkeletonShimmerModifier`, clean API |
| `Views/Components/ContentViewSkeleton.swift` | **New** |
| `Views/Components/InsightsSkeleton.swift` | **New** |
| `Views/Home/ContentView.swift` | **Update** — replace ProgressView with `ContentViewSkeleton` |
| `Views/Insights/InsightsView.swift` | **Update** — replace ProgressView with `InsightsSkeleton` |

---

## Non-Goals

- No changes to AppCoordinator loading state (ContentView's local `isInitializing` is sufficient)
- No skeleton for other tabs (Settings, Transactions) — out of scope
- No animated transition between skeleton rows — YAGNI
