# Packed Circle Icons — Design Doc

**Date**: 2026-03-20
**Status**: Approved
**Replaces**: `StaticSubscriptionIconsView` (facepile) and `LoanFacepileIconsView`

## Problem

Current facepile layout (HStack with -12pt overlap) renders 5×48pt icons at ~192pt natural width inside a 120pt container. Icons overflow and clip beyond card boundaries.

## Solution

Replace the overlapping horizontal stack with a **packed circle layout** where:
- Circle sizes reflect subscription/loan cost (bigger = more expensive)
- Circles are tightly packed without overlapping (touching edges)
- Max 5 visible + "+N" overflow badge
- Entrance animation + subtle idle breathing

## Design Decisions

### Circle Sizing

Linear interpolation by amount:
- **Min size**: 28pt (cheapest item)
- **Max size**: 56pt (most expensive item)
- Formula: `diameter = 28 + (amount - min) / (max - min) * 28`
- Equal amounts → all circles at 42pt
- Overflow badge "+N" always 28pt (minimum size)

### Circle Packing Algorithm

Greedy placement into rectangular container (120 × ~100pt):

1. Sort circles by diameter descending (largest first)
2. Place first circle at container center
3. For each subsequent circle: evaluate candidate positions (tangent points to already-placed circles), pick the one closest to center that fits within bounds
4. If no valid position: shrink circle by 10% and retry

**Properties**:
- Deterministic: same data → same layout (no randomness)
- O(n²) at n≤6 — instant
- Result: array of `(x, y, diameter)` stored in `@State`

### Recalculation Trigger

Via `.task(id:)` when count or amounts change. No per-frame computation.

### SwiftUI Layout

```swift
ZStack {
    ForEach(packedCircles) { circle in
        IconView(source: circle.iconSource, style: .circle(size: circle.diameter))
            .overlay(Circle().stroke(.background, lineWidth: 2))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .offset(x: circle.x, y: circle.y)
            .scaleEffect(breathingScale)
            .staggeredEntrance(delay: index * facepileStagger)
    }
    if overflowCount > 0 {
        OverflowBadge(count: overflowCount)
            .offset(x: badge.x, y: badge.y)
    }
}
.frame(width: 120, height: containerHeight)
```

### Animation

**Entrance**: Existing `.staggeredEntrance(delay:)` — scale 0.5→1.0 + opacity, 0.06s stagger.

**Idle breathing**:
- `scaleEffect` oscillating 1.0↔1.03 (3% amplitude, barely visible)
- Period: 3–5s per circle, desynchronized via `duration: 3.0 + index * 0.4`
- `.easeInOut.repeatForever(autoreverses: true)`
- GPU-only operation (no layout recalc)
- Disabled when Reduce Motion is enabled

### Component API

One shared component replaces both `StaticSubscriptionIconsView` and `LoanFacepileIconsView`:

```swift
struct PackedCircleIconsView: View {
    let items: [PackedCircleItem]  // iconSource + amount
    var maxVisible: Int = 5
    var containerWidth: CGFloat = 120
}

struct PackedCircleItem: Identifiable {
    let id: String
    let iconSource: IconSource
    let amount: Double
}
```

### Icon Styling

Preserved from current implementation:
- **SF Symbols**: `.circle(size:, tint: .accentMonochrome, backgroundColor: AppColors.surface)`
- **Brand logos**: `.circle(size:, tint: .original)`
- **Border**: 2pt white circle stroke
- **Shadow**: 4pt radius, 15% black opacity, 2pt y-offset

## Files Changed

| File | Action |
|------|--------|
| `Views/Components/Icons/PackedCircleIconsView.swift` | Create — new packed circle component |
| `Views/Components/Icons/CirclePackingLayout.swift` | Create — packing algorithm (pure geometry, no SwiftUI) |
| `Views/Components/Icons/StaticSubscriptionIconsView.swift` | Delete — replaced |
| `Views/Components/Cards/SubscriptionsCardView.swift` | Modify — use PackedCircleIconsView |
| `Views/Components/Cards/LoansCardView.swift` | Modify — use PackedCircleIconsView, delete LoanFacepileIconsView |
| `Utils/AppAnimation.swift` | Modify — add breathing animation token |
