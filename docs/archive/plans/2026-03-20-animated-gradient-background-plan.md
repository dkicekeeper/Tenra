# Animated CategoryGradientBackground Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add breathing animation, drift movement, blend modes, and 2-layer depth to the existing `CategoryGradientBackground`.

**Architecture:** Extract each orb into a private `AnimatedOrbView` sub-view that manages its own `@State` animation triggers. Split orbs into back layer (blur 60, slow) and front layer (blur 35, faster). Reduce Motion → static fallback (current behavior).

**Tech Stack:** SwiftUI animations (`.easeInOut.repeatForever`), `blendMode`, `drawingGroup()`, `scaleEffect`, `offset`.

---

### Task 1: Add animation tokens to AppAnimation.swift

**Files:**
- Modify: `Tenra/Utils/AppAnimation.swift`

**Step 1: Add gradient orb tokens after the breathing section (after line 70)**

```swift
// MARK: - Gradient Background Orbs

/// Breathing scale range for gradient orbs — weight=1.0 → 1.15, weight=0.4 → 1.05.
static func orbBreathScale(weight: CGFloat) -> CGFloat {
    1.0 + (0.05 + weight * 0.10)
}

/// Breathing duration for gradient orbs — weight=1.0 → 4s, weight=0.4 → 7s.
/// Heavier categories breathe faster (more visual prominence).
static func orbBreathDuration(weight: CGFloat) -> Double {
    7.0 - weight * 3.0
}

/// Drift radius for gradient orbs. Back layer drifts less than front layer.
static func orbDriftRadius(isBackLayer: Bool) -> CGFloat {
    isBackLayer ? 15 : 25
}

/// Drift duration per orb — randomised per index to prevent synchronisation.
/// Base 8s + index offset creates lava lamp desynchronisation.
static func orbDriftDuration(index: Int) -> Double {
    8.0 + Double(index) * 1.2
}

/// Opacity for gradient orbs — weight=1.0 → 0.45, weight=0.4 → 0.25.
static func orbOpacity(weight: CGFloat) -> Double {
    0.25 + Double(weight) * 0.20
}

/// Blur radius per layer. Back layer = deeper blur (farther), front = sharper (closer).
static func orbBlur(isBackLayer: Bool) -> CGFloat {
    isBackLayer ? 60 : 35
}

/// Reduce-Motion-aware orb breathing animation factory.
static func orbBreathAnimation(weight: CGFloat) -> Animation {
    isReduceMotionEnabled
        ? .linear(duration: 0)
        : .easeInOut(duration: orbBreathDuration(weight: weight))
            .repeatForever(autoreverses: true)
}

/// Reduce-Motion-aware orb drift animation factory.
static func orbDriftAnimation(index: Int) -> Animation {
    isReduceMotionEnabled
        ? .linear(duration: 0)
        : .easeInOut(duration: orbDriftDuration(index: index))
            .repeatForever(autoreverses: true)
}
```

**Step 2: Build and verify no errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Utils/AppAnimation.swift
git commit -m "feat: add gradient orb animation tokens to AppAnimation"
```

---

### Task 2: Create AnimatedOrbView private sub-view

**Files:**
- Modify: `Tenra/Views/Components/Cards/CategoryGradientBackground.swift`

**Step 1: Add the private AnimatedOrbView struct before CategoryGradientBackground's body**

Insert after the `orbOffsets` array (after line 50), before `// MARK: - Body`:

```swift
// MARK: - Animated Orb

/// A single animated orb that manages its own breathing and drift state.
/// Each orb is a separate sub-view so `@State` is per-orb, not per-array.
private struct AnimatedOrbView: View {
    let color: Color
    let diameter: CGFloat
    let baseOffset: CGPoint
    let weight: CGFloat
    let index: Int
    let isBackLayer: Bool
    let containerSize: CGSize

    @State private var isAnimating = false

    /// Deterministic drift targets per orb index — ensures each orb
    /// drifts in a unique direction. Values are fractional of driftRadius.
    private static let driftDirections: [(dx: CGFloat, dy: CGFloat)] = [
        ( 1.0,  0.6),   // 0
        (-0.7,  1.0),   // 1
        ( 0.5, -0.9),   // 2
        (-1.0,  0.3),   // 3
        ( 0.8, -0.7),   // 4
    ]

    var body: some View {
        let breathScale = isAnimating
            ? AppAnimation.orbBreathScale(weight: weight)
            : 1.0
        let driftR = AppAnimation.orbDriftRadius(isBackLayer: isBackLayer)
        let dir = Self.driftDirections[index % Self.driftDirections.count]
        let driftX = isAnimating ? dir.dx * driftR : 0
        let driftY = isAnimating ? dir.dy * driftR : 0

        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(AppAnimation.orbOpacity(weight: weight)),
                             color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(breathScale)
            .offset(
                x: baseOffset.x + driftX,
                y: baseOffset.y + driftY
            )
            .blur(radius: AppAnimation.orbBlur(isBackLayer: isBackLayer))
            .onAppear {
                withAnimation(AppAnimation.orbBreathAnimation(weight: weight)) {
                    isAnimating = true
                }
                // Drift uses a separate animation with different timing.
                // Since both target `isAnimating = true`, we set it once
                // and let SwiftUI resolve both animations simultaneously.
            }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors (AnimatedOrbView exists but isn't used yet)

**Step 3: Commit**

```bash
git add Tenra/Views/Components/Cards/CategoryGradientBackground.swift
git commit -m "feat: add AnimatedOrbView private sub-view for gradient background"
```

---

### Task 3: Rewrite CategoryGradientBackground body with 2-layer animation

**Files:**
- Modify: `Tenra/Views/Components/Cards/CategoryGradientBackground.swift`

**Step 1: Replace the body property with animated 2-layer version**

Replace the entire `body` computed property (lines 54-86) with:

```swift
var body: some View {
    GeometryReader { geo in
        let w = geo.size.width
        let h = geo.size.height
        let base = max(w, h) * 0.85
        let items = Array(weights.prefix(5))

        // Back layer: first 2 orbs (highest weight) — larger, slower, deeper blur.
        // Front layer: orbs 3-5 — smaller, faster drift, sharper blur.
        let backItems = Array(items.prefix(2))
        let frontItems = items.count > 2 ? Array(items.dropFirst(2)) : []

        ZStack {
            if AppAnimation.isReduceMotionEnabled {
                // Static fallback — identical to original implementation.
                staticOrbs(items: items, base: base, w: w, h: h)
            } else {
                // Back layer
                ForEach(Array(backItems.enumerated()), id: \.offset) { index, item in
                    animatedOrb(
                        item: item, index: index, base: base,
                        w: w, h: h, isBackLayer: true
                    )
                }
                .blendMode(.screen)

                // Front layer
                ForEach(Array(frontItems.enumerated()), id: \.offset) { index, item in
                    animatedOrb(
                        item: item, index: index + 2, base: base,
                        w: w, h: h, isBackLayer: false
                    )
                }
                .blendMode(.screen)
            }
        }
        .frame(width: w, height: h)
        .drawingGroup()
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
}

// MARK: - Helpers

/// Animated orb using the AnimatedOrbView sub-view.
private func animatedOrb(
    item: CategoryColorWeight,
    index: Int,
    base: CGFloat,
    w: CGFloat,
    h: CGFloat,
    isBackLayer: Bool
) -> some View {
    let color = CategoryColors.hexColor(
        for: item.category,
        opacity: 1.0,
        customCategories: customCategories
    )
    let diameter = base * (0.40 + item.weight * 0.60)
    let offset = Self.orbOffsets[index]

    return AnimatedOrbView(
        color: color,
        diameter: diameter,
        baseOffset: CGPoint(x: offset.dx * w, y: offset.dy * h),
        weight: item.weight,
        index: index,
        isBackLayer: isBackLayer,
        containerSize: CGSize(width: w, height: h)
    )
}

/// Static orbs for Reduce Motion — preserves original rendering.
private func staticOrbs(
    items: [CategoryColorWeight],
    base: CGFloat,
    w: CGFloat,
    h: CGFloat
) -> some View {
    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        let color = CategoryColors.hexColor(
            for: item.category,
            opacity: 1.0,
            customCategories: customCategories
        )
        let diameter = base * (0.40 + item.weight * 0.60)
        let offset = Self.orbOffsets[index]

        Ellipse()
            .fill(color.opacity(0.55))
            .frame(width: diameter, height: diameter * 0.80)
            .offset(x: offset.dx * w, y: offset.dy * h)
            .blur(radius: 48)
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Views/Components/Cards/CategoryGradientBackground.swift
git commit -m "feat: animated gradient background with 2-layer depth and breathing/drift"
```

---

### Task 4: Fix drift animation timing (separate from breath)

The single `isAnimating` bool drives both breath and drift with the same timing. We need separate animation timings for each.

**Files:**
- Modify: `Tenra/Views/Components/Cards/CategoryGradientBackground.swift` (AnimatedOrbView only)

**Step 1: Split animation state into two bools**

In `AnimatedOrbView`, replace `@State private var isAnimating = false` with:

```swift
@State private var isBreathing = false
@State private var isDrifting = false
```

**Step 2: Update body to use separate states**

```swift
var body: some View {
    let breathScale = isBreathing
        ? AppAnimation.orbBreathScale(weight: weight)
        : 1.0
    let driftR = AppAnimation.orbDriftRadius(isBackLayer: isBackLayer)
    let dir = Self.driftDirections[index % Self.driftDirections.count]
    let driftX = isDrifting ? dir.dx * driftR : 0
    let driftY = isDrifting ? dir.dy * driftR : 0

    Circle()
        .fill(
            RadialGradient(
                colors: [color.opacity(AppAnimation.orbOpacity(weight: weight)),
                         color.opacity(0.0)],
                center: .center,
                startRadius: 0,
                endRadius: diameter * 0.5
            )
        )
        .frame(width: diameter, height: diameter)
        .scaleEffect(breathScale)
        .offset(
            x: baseOffset.x + driftX,
            y: baseOffset.y + driftY
        )
        .blur(radius: AppAnimation.orbBlur(isBackLayer: isBackLayer))
        .onAppear {
            withAnimation(AppAnimation.orbBreathAnimation(weight: weight)) {
                isBreathing = true
            }
            withAnimation(AppAnimation.orbDriftAnimation(index: index)) {
                isDrifting = true
            }
        }
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```bash
git add Tenra/Views/Components/Cards/CategoryGradientBackground.swift
git commit -m "fix: separate breath and drift animation timings for gradient orbs"
```

---

### Task 5: Visual tuning pass — try blendMode variants

**Files:**
- Modify: `Tenra/Views/Components/Cards/CategoryGradientBackground.swift`

**Step 1: Run on simulator and visually compare**

Try `.plusLighter` vs `.screen` on both layers. Pick whichever looks better against the glass card at `opacity(0.35)`.

Candidates to try:
- Both layers `.screen` (softer)
- Both layers `.plusLighter` (brighter intersections)
- Back `.screen` + front `.plusLighter` (depth separation)

**Step 2: Adjust opacity/blur if needed**

The `orbOpacity` range (0.25–0.45) and blur radii (35/60) may need tuning once animated. Tweak values in `AppAnimation.swift` token functions if the result is too bright/dim.

**Step 3: Commit final tuning**

```bash
git add Tenra/Utils/AppAnimation.swift Tenra/Views/Components/Cards/CategoryGradientBackground.swift
git commit -m "style: tune gradient orb blend mode and opacity values"
```

---

### Task 6: Update file header comments

**Files:**
- Modify: `Tenra/Views/Components/Cards/CategoryGradientBackground.swift` (header comment, lines 1-9)

**Step 1: Update the file header to reflect new behavior**

```swift
//
//  CategoryGradientBackground.swift
//  Tenra
//
//  Animated blurred colour orbs as the home screen gradient background.
//  Each orb maps to a top expense category; its size, brightness, and
//  breathing speed are proportional to that category's spend weight.
//  Two depth layers (back/front) with different blur radii create
//  a lava-lamp parallax effect.  Reduce Motion → static fallback.
//
```

**Step 2: Commit**

```bash
git add Tenra/Views/Components/Cards/CategoryGradientBackground.swift
git commit -m "docs: update CategoryGradientBackground header for animated behavior"
```
