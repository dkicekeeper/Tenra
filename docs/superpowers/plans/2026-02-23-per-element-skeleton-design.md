# Per-Element Skeleton Loading — Design (Phase 30)

**Date:** 2026-02-23
**Status:** Approved
**Supersedes:** Phase 29 (full-screen ContentViewSkeleton / InsightsSkeleton)

---

## Problem

Phase 29 introduced full-screen skeleton screens, but had 3 root-cause bugs:

1. **Background commented out** → skeleton transparent, `mainContent` visible through gaps
2. **Skeleton dismissed after ~50ms** (fast-path only) → shimmer never reaches visible region
3. **Shimmer invisible on light backgrounds** → `.blendMode(.screen)` on `systemGray5` gives ~0.03 luminance delta — imperceptible

Additionally, the full-screen skeleton disappears while content still loads partially (accounts fast, transactions slow), causing a jarring skeleton → empty → content three-phase transition.

## Solution

Replace full-screen skeletons with **per-element skeleton loading** via a universal `.skeletonLoading(isLoading:skeleton:)` ViewModifier. Each UI section shows its own skeleton independently until its specific data is ready — creating smooth, progressive content reveal.

---

## Architecture

### New file: `Views/Components/SkeletonLoadingModifier.swift`

Universal ViewModifier — wraps any view, shows skeleton when `isLoading`, transitions to real content when data arrives:

```swift
extension View {
    func skeletonLoading<S: View>(
        isLoading: Bool,
        @ViewBuilder skeleton: () -> S
    ) -> some View
}

struct SkeletonLoadingModifier<S: View>: ViewModifier {
    let isLoading: Bool
    let skeleton: () -> S

    func body(content: Content) -> some View {
        Group {
            if isLoading {
                skeleton()
                    .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
            } else {
                content
                    .transition(.opacity.combined(with: .scale(1.02, anchor: .center)))
            }
        }
        .animation(.spring(response: 0.4), value: isLoading)
    }
}
```

---

### AppCoordinator — 2 new observable properties

Expose loading stages so views can bind independently:

```swift
// Two internal guards (unchanged):
private var _fastPathStarted = false   // prevents double fast-path start
private var _initializingStarted = false // prevents double full init

// Two new observable outputs:
private(set) var fastPathDone = false      // accounts + categories ready (~50ms)
private(set) var fullyInitialized = false  // transactions + all data ready (~1-3s)
```

`fastPathDone = true` set at end of `initializeFastPath()`.
`fullyInitialized = true` set after `loadData()` + `syncTransactionStoreToViewModels()` complete in `initialize()`.

---

### ContentView — per-section loading thresholds

| Section | Skeleton | Loading condition |
|---------|----------|-------------------|
| AccountsCarousel | `AccountsCarouselSkeleton` | `!coordinator.fastPathDone` |
| TransactionsSummaryCard | `TransactionCardSkeleton` | `!coordinator.fullyInitialized` |
| SubscriptionsCardView | `SubscriptionsCardSkeleton` | `!coordinator.fullyInitialized` |
| QuickAddTransactionView | `CategoriesCardSkeleton` | `!coordinator.fastPathDone` |

Usage pattern:
```swift
accountsSection
    .skeletonLoading(isLoading: !coordinator.fastPathDone) {
        AccountsCarouselSkeleton()
    }

historyNavigationLink
    .skeletonLoading(isLoading: !coordinator.fullyInitialized) {
        TransactionCardSkeleton()
    }
```

`@State private var isInitializing` in ContentView is **removed entirely** — each section manages its own state via `coordinator`.

---

### InsightsView — per-section loading

InsightsViewModel's existing `isLoading: Bool` drives the skeletons.

| Section | Skeleton component |
|---------|--------------------|
| Summary header | `InsightsSummaryHeaderSkeleton` |
| Filter carousel | `InsightsFilterCarouselSkeleton` (4 chips) |
| Insight cards list | `InsightCardSkeleton` × 3 |

---

### Shimmer fixes (SkeletonView.swift)

**Fix 1 — visibility on light backgrounds:**
```swift
// Before: invisible on light gray via screen blend
.init(color: .white.opacity(0.3), location: 0.5)
.blendMode(.screen)

// After: visible normal overlay
.init(color: .white.opacity(0.5), location: 0.5)
// no blendMode
```

**Fix 2 — starts visible immediately:**
```swift
// Before: phase starts off-screen, shimmer enters at ~107ms
@State private var phase: CGFloat = -1.0  // animates to 2.0

// After: shimmer enters from left edge immediately
@State private var phase: CGFloat = -0.5  // animates to 1.5
```

---

## Files Changed

| File | Action |
|------|--------|
| `Views/Components/SkeletonView.swift` | Fix shimmer: opacity 0.3→0.5, remove blendMode, phase -1.0→-0.5, end 2.0→1.5 |
| `Views/Components/SkeletonLoadingModifier.swift` | **New** — universal `.skeletonLoading` modifier |
| `ViewModels/AppCoordinator.swift` | Add `fastPathDone` + `fullyInitialized` observable properties |
| `Views/Home/ContentView.swift` | Remove `isInitializing`, add `.skeletonLoading` on 4 sections, remove `loadingOverlay` |
| `Views/Components/ContentViewSkeleton.swift` | **Delete** |
| `Views/Insights/InsightsView.swift` | Replace `loadingView` with `.skeletonLoading` on header + sections |
| `Views/Components/InsightsSkeleton.swift` | Rename → `InsightsSkeletonComponents.swift`, make sub-structs `internal` |

---

## Skeleton Components (reused from Phase 29)

### ContentView skeletons (from ContentViewSkeleton.swift → inline)
- `AccountsCarouselSkeleton` — 3× card (200×120) in HStack
- `TransactionCardSkeleton` — icon circle + 2 text lines (matches SummaryCard height)
- `SubscriptionsCardSkeleton` — icon circle + 2 text lines
- `CategoriesCardSkeleton` — icon circle + 2 text lines

### InsightsView skeletons (from InsightsSkeletonComponents.swift)
- `InsightsSummaryHeaderSkeleton` — 3 columns + health row (already exists)
- `InsightsFilterCarouselSkeleton` — 4 chips (already exists)
- `InsightCardSkeleton` — icon + 3 lines + chart rect (already exists, ×3)

---

## Non-Goals

- No skeleton for Settings, Transactions history, or other tabs
- No per-card skeleton within InsightsView (cards load as batch)
- No skeleton shimmer speed/color theming
