# Packed Circle Icons — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the overflowing horizontal facepile icon layout in SubscriptionsCardView and LoansCardView with a packed-circle layout where circle size reflects cost.

**Architecture:** Pure geometry algorithm (`CirclePackingLayout`) computes positions once per data change. `PackedCircleIconsView` renders the result as a ZStack with absolute offsets. Breathing animation via GPU-only `scaleEffect`.

**Tech Stack:** SwiftUI, `@State` for layout cache, `IconView` (existing), `AppAnimation` tokens.

---

### Task 1: Add breathing animation token to AppAnimation

**Files:**
- Modify: `Tenra/Utils/AppAnimation.swift` (after line 52, facepile section)

**Step 1: Add the token**

Insert after line 52 (`static let facepileStagger`) in the facepile section:

```swift
/// Breathing animation for packed circle idle state.
/// 3% scale oscillation, Reduce Motion-aware.
static let breathingScale: CGFloat = 1.03

/// Base duration for breathing cycle (each circle offsets by +0.4s per index).
static let breathingBaseDuration: Double = 3.0

/// Per-index duration offset for desynchronized breathing.
static let breathingStagger: Double = 0.4

/// Reduce-Motion-aware breathing animation factory.
static func breathingAnimation(index: Int) -> Animation {
    isReduceMotionEnabled
        ? .linear(duration: 0)
        : .easeInOut(duration: breathingBaseDuration + Double(index) * breathingStagger)
            .repeatForever(autoreverses: true)
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Utils/AppAnimation.swift
git commit -m "feat: add breathing animation tokens to AppAnimation"
```

---

### Task 2: Create CirclePackingLayout (pure geometry, no SwiftUI)

**Files:**
- Create: `Tenra/Views/Components/Icons/CirclePackingLayout.swift`

**Step 1: Write CirclePackingLayout**

```swift
//
//  CirclePackingLayout.swift
//  Tenra
//
//  Pure geometry: packs circles into a rectangular container.
//  No SwiftUI dependency — input diameters, output (x, y) positions.
//

import Foundation

struct PackedCircle: Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
    let diameter: CGFloat
}

enum CirclePackingLayout {

    /// Min/max circle diameters.
    static let minDiameter: CGFloat = 28
    static let maxDiameter: CGFloat = 56

    // MARK: - Public

    /// Compute diameters from amounts using linear interpolation.
    /// Returns diameters in the same order as input.
    static func diameters(for amounts: [Double]) -> [CGFloat] {
        guard !amounts.isEmpty else { return [] }
        let minAmt = amounts.min()!
        let maxAmt = amounts.max()!
        let range = maxAmt - minAmt
        if range < 0.01 {
            // All amounts equal → uniform middle size
            let mid = (minDiameter + maxDiameter) / 2
            return amounts.map { _ in mid }
        }
        return amounts.map { amt in
            let ratio = CGFloat((amt - minAmt) / range)
            return minDiameter + ratio * (maxDiameter - minDiameter)
        }
    }

    /// Pack circles into a container. Returns positions relative to container center (0,0).
    /// - Parameters:
    ///   - ids: Stable identifiers for each circle.
    ///   - diameters: Pre-computed diameters (sorted largest-first recommended).
    ///   - containerWidth: Available width.
    ///   - containerHeight: Available height.
    /// - Returns: Array of `PackedCircle` with (x, y) offsets from container center.
    static func pack(
        ids: [String],
        diameters: [CGFloat],
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> [PackedCircle] {
        guard !ids.isEmpty else { return [] }

        // Sort by diameter descending (pack large circles first)
        let indexed = zip(ids, diameters)
            .enumerated()
            .sorted { $0.element.1 > $1.element.1 }

        let halfW = containerWidth / 2
        let halfH = containerHeight / 2
        var placed: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []
        var result: [(index: Int, circle: PackedCircle)] = []

        for (originalIndex, (id, diameter)) in indexed {
            let r = diameter / 2
            if placed.isEmpty {
                // First circle at center
                placed.append((0, 0, r))
                result.append((originalIndex, PackedCircle(id: id, x: 0, y: 0, diameter: diameter)))
                continue
            }

            // Generate candidate positions: tangent to each placed circle
            var bestPos: (x: CGFloat, y: CGFloat)? = nil
            var bestDist: CGFloat = .greatestFiniteMagnitude

            // Candidates: tangent to one placed circle at 12 angles
            let angleSteps = 24
            for p in placed {
                let touchDist = p.r + r
                for step in 0..<angleSteps {
                    let angle = CGFloat(step) * (2 * .pi / CGFloat(angleSteps))
                    let cx = p.x + touchDist * cos(angle)
                    let cy = p.y + touchDist * sin(angle)

                    // Check bounds
                    guard cx - r >= -halfW, cx + r <= halfW,
                          cy - r >= -halfH, cy + r <= halfH else { continue }

                    // Check no overlap with any placed circle
                    let overlaps = placed.contains { other in
                        let dx = cx - other.x
                        let dy = cy - other.y
                        let minDist = other.r + r
                        return dx * dx + dy * dy < minDist * minDist - 0.01
                    }
                    guard !overlaps else { continue }

                    // Prefer position closest to center
                    let dist = cx * cx + cy * cy
                    if dist < bestDist {
                        bestDist = dist
                        bestPos = (cx, cy)
                    }
                }
            }

            // Tangent to two placed circles (tighter packing)
            for i in 0..<placed.count {
                for j in (i + 1)..<placed.count {
                    let positions = tangentToTwo(
                        c1: placed[i], c2: placed[j], r: r,
                        halfW: halfW, halfH: halfH, placed: placed
                    )
                    for pos in positions {
                        let dist = pos.x * pos.x + pos.y * pos.y
                        if dist < bestDist {
                            bestDist = dist
                            bestPos = pos
                        }
                    }
                }
            }

            if let pos = bestPos {
                placed.append((pos.x, pos.y, r))
                result.append((originalIndex, PackedCircle(id: id, x: pos.x, y: pos.y, diameter: diameter)))
            }
            // If no valid position found, skip this circle (shouldn't happen with 6 circles in 120×100)
        }

        // Restore original order
        return result.sorted { $0.index < $1.index }.map(\.circle)
    }

    // MARK: - Private

    /// Find positions tangent to two existing circles simultaneously.
    private static func tangentToTwo(
        c1: (x: CGFloat, y: CGFloat, r: CGFloat),
        c2: (x: CGFloat, y: CGFloat, r: CGFloat),
        r: CGFloat,
        halfW: CGFloat,
        halfH: CGFloat,
        placed: [(x: CGFloat, y: CGFloat, r: CGFloat)]
    ) -> [(x: CGFloat, y: CGFloat)] {
        let d1 = c1.r + r
        let d2 = c2.r + r
        let dx = c2.x - c1.x
        let dy = c2.y - c1.y
        let d = sqrt(dx * dx + dy * dy)

        guard d > 0.01, d <= d1 + d2 else { return [] }

        let a = (d1 * d1 - d2 * d2 + d * d) / (2 * d)
        let hSq = d1 * d1 - a * a
        guard hSq >= 0 else { return [] }
        let h = sqrt(hSq)

        let mx = c1.x + a * dx / d
        let my = c1.y + a * dy / d
        let px = -dy / d * h
        let py = dx / d * h

        let candidates = [(mx + px, my + py), (mx - px, my - py)]
        return candidates.compactMap { (cx, cy) in
            // Bounds check
            guard cx - r >= -halfW, cx + r <= halfW,
                  cy - r >= -halfH, cy + r <= halfH else { return nil }
            // Overlap check (skip c1, c2 — we know we're tangent to them)
            let overlaps = placed.contains { other in
                let odx = cx - other.x
                let ody = cy - other.y
                let minDist = other.r + r
                return odx * odx + ody * ody < minDist * minDist - 0.01
            }
            return overlaps ? nil : (cx, cy)
        }
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Views/Components/Icons/CirclePackingLayout.swift
git commit -m "feat: add circle packing layout algorithm"
```

---

### Task 3: Create PackedCircleIconsView

**Files:**
- Create: `Tenra/Views/Components/Icons/PackedCircleIconsView.swift`

**Step 1: Write PackedCircleIconsView**

```swift
//
//  PackedCircleIconsView.swift
//  Tenra
//
//  Packed circle layout for subscription/loan icon display.
//  Circle size reflects item cost; circles are tightly packed without overlap.
//

import SwiftUI

// MARK: - Data Model

struct PackedCircleItem: Identifiable {
    let id: String
    let iconSource: IconSource?
    let amount: Double
}

// MARK: - Main View

struct PackedCircleIconsView: View {
    let items: [PackedCircleItem]
    var maxVisible: Int = 5
    var containerWidth: CGFloat = AppSize.subscriptionCardWidth

    @State private var packedCircles: [PackedCircle] = []
    @State private var isBreathing = false

    private let containerHeight: CGFloat = 100
    private let borderWidth: CGFloat = 2

    private var visible: [PackedCircleItem] {
        Array(items.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, items.count - maxVisible)
    }

    /// Key for recalculation when items change.
    private var layoutKey: String {
        visible.map { "\($0.id):\($0.amount)" }.joined(separator: ",")
        + (overflowCount > 0 ? ",+\(overflowCount)" : "")
    }

    var body: some View {
        ZStack {
            ForEach(Array(packedCircles.enumerated()), id: \.element.id) { index, circle in
                if index < visible.count {
                    PackedCircleIcon(
                        iconSource: visible[index].iconSource,
                        diameter: circle.diameter,
                        borderWidth: borderWidth,
                        isBreathing: isBreathing,
                        breathingIndex: index,
                        animationDelay: Double(index) * AppAnimation.facepileStagger
                    )
                    .offset(x: circle.x, y: circle.y)
                } else {
                    // Overflow badge
                    PackedOverflowBadge(
                        count: overflowCount,
                        diameter: circle.diameter,
                        borderWidth: borderWidth,
                        animationDelay: Double(index) * AppAnimation.facepileStagger
                    )
                    .offset(x: circle.x, y: circle.y)
                }
            }
        }
        .frame(width: containerWidth, height: containerHeight)
        .task(id: layoutKey) {
            recalculateLayout()
            // Start breathing after entrance animations settle
            if !AppAnimation.isReduceMotionEnabled {
                try? await Task.sleep(for: .milliseconds(
                    Int(Double(packedCircles.count) * AppAnimation.facepileStagger * 1000 + 400)
                ))
                isBreathing = true
            }
        }
    }

    // MARK: - Layout

    private func recalculateLayout() {
        var amounts = visible.map(\.amount)
        var ids = visible.map(\.id)

        // Add overflow badge as smallest circle
        if overflowCount > 0 {
            amounts.append(0) // Will get minDiameter
            ids.append("__overflow__")
        }

        let diameters: [CGFloat]
        if overflowCount > 0 {
            // Compute diameters for visible items, force badge to minDiameter
            var d = CirclePackingLayout.diameters(for: Array(amounts.dropLast()))
            d.append(CirclePackingLayout.minDiameter)
            diameters = d
        } else {
            diameters = CirclePackingLayout.diameters(for: amounts)
        }

        packedCircles = CirclePackingLayout.pack(
            ids: ids,
            diameters: diameters,
            containerWidth: containerWidth,
            containerHeight: containerHeight
        )
        isBreathing = false
    }
}

// MARK: - Packed Circle Icon

private struct PackedCircleIcon: View {
    let iconSource: IconSource?
    let diameter: CGFloat
    let borderWidth: CGFloat
    let isBreathing: Bool
    let breathingIndex: Int
    let animationDelay: Double

    private var iconStyle: IconStyle {
        switch iconSource {
        case .sfSymbol:
            return .circle(size: diameter, tint: .accentMonochrome, backgroundColor: AppColors.surface)
        case .brandService, .none:
            return .circle(size: diameter, tint: .original)
        }
    }

    var body: some View {
        IconView(source: iconSource, style: iconStyle)
            .overlay(Circle().stroke(.background, lineWidth: borderWidth))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .scaleEffect(isBreathing ? AppAnimation.breathingScale : 1.0)
            .animation(
                isBreathing
                    ? AppAnimation.breathingAnimation(index: breathingIndex)
                    : .default,
                value: isBreathing
            )
            .staggeredEntrance(delay: animationDelay)
    }
}

// MARK: - Overflow Badge

private struct PackedOverflowBadge: View {
    let count: Int
    let diameter: CGFloat
    let borderWidth: CGFloat
    let animationDelay: Double

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Text("+\(count)")
                .font(.system(size: diameter * 0.35, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().stroke(.background, lineWidth: borderWidth))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .staggeredEntrance(delay: animationDelay)
    }
}

// MARK: - Previews

#Preview("5 items, varying amounts") {
    let items: [PackedCircleItem] = [
        .init(id: "1", iconSource: .brandService("netflix.com"), amount: 15000),
        .init(id: "2", iconSource: .brandService("spotify.com"), amount: 4990),
        .init(id: "3", iconSource: .sfSymbol("cloud.fill"), amount: 2990),
        .init(id: "4", iconSource: .sfSymbol("gamecontroller.fill"), amount: 1500),
        .init(id: "5", iconSource: .sfSymbol("dumbbell.fill"), amount: 800),
    ]

    VStack(spacing: 20) {
        Text("5 items").font(.caption).foregroundStyle(.secondary)
        PackedCircleIconsView(items: items)
            .border(Color.red.opacity(0.3)) // Debug container bounds
    }
    .padding()
}

#Preview("8 items with overflow") {
    let items: [PackedCircleItem] = (1...8).map { i in
        PackedCircleItem(
            id: "s\(i)",
            iconSource: .sfSymbol(["star.fill","heart.fill","flame.fill","bolt.fill","leaf.fill","music.note","camera.fill","globe"][i - 1]),
            amount: Double(i) * 1000
        )
    }

    VStack(spacing: 20) {
        Text("8 items (+3 overflow)").font(.caption).foregroundStyle(.secondary)
        PackedCircleIconsView(items: items)
            .border(Color.red.opacity(0.3))
    }
    .padding()
}

#Preview("Equal amounts") {
    let items: [PackedCircleItem] = (1...4).map { i in
        PackedCircleItem(id: "e\(i)", iconSource: .sfSymbol("star.fill"), amount: 5000)
    }

    VStack(spacing: 20) {
        Text("Equal amounts (uniform size)").font(.caption).foregroundStyle(.secondary)
        PackedCircleIconsView(items: items)
            .border(Color.red.opacity(0.3))
    }
    .padding()
}

#Preview("Single item") {
    PackedCircleIconsView(items: [
        .init(id: "solo", iconSource: .brandService("netflix.com"), amount: 9990)
    ])
    .border(Color.red.opacity(0.3))
    .padding()
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Views/Components/Icons/PackedCircleIconsView.swift
git commit -m "feat: add PackedCircleIconsView with packed circle layout"
```

---

### Task 4: Wire up SubscriptionsCardView

**Files:**
- Modify: `Tenra/Views/Components/Cards/SubscriptionsCardView.swift` (lines 72-74)

**Step 1: Replace StaticSubscriptionIconsView with PackedCircleIconsView**

Replace lines 72-74:
```swift
            if !subscriptions.isEmpty {
                StaticSubscriptionIconsView(subscriptions: subscriptions)
                    .frame(width: AppSize.subscriptionCardWidth, alignment: .top)
            }
```

With:
```swift
            if !subscriptions.isEmpty {
                PackedCircleIconsView(
                    items: subscriptions.map { sub in
                        PackedCircleItem(
                            id: sub.id,
                            iconSource: sub.iconSource,
                            amount: (sub.amount as NSDecimalNumber).doubleValue
                        )
                    }
                )
            }
```

Note: Remove the `.frame(width:)` — `PackedCircleIconsView` manages its own frame internally.

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```bash
git add Tenra/Views/Components/Cards/SubscriptionsCardView.swift
git commit -m "feat: use PackedCircleIconsView in SubscriptionsCardView"
```

---

### Task 5: Wire up LoansCardView and delete old facepile

**Files:**
- Modify: `Tenra/Views/Components/Cards/LoansCardView.swift`

**Step 1: Replace loanIcons computed property**

Replace lines 76-80 (the `loanIcons` computed property):
```swift
    // MARK: - Icons

    private var loanIcons: some View {
        LoanFacepileIconsView(loans: loans)
    }
```

With:
```swift
    // MARK: - Icons

    private var loanIcons: some View {
        PackedCircleIconsView(
            items: loans.map { loan in
                PackedCircleItem(
                    id: loan.id,
                    iconSource: loan.iconSource,
                    amount: loan.loanInfo.map { ($0.remainingPrincipal as NSDecimalNumber).doubleValue } ?? 0
                )
            }
        )
    }
```

**Step 2: Remove the `.frame(width:)` on the caller**

Replace line 60:
```swift
                loanIcons
                    .frame(width: AppSize.subscriptionCardWidth, alignment: .top)
```

With:
```swift
                loanIcons
```

**Step 3: Delete old facepile code**

Delete lines 83-161 entirely — the following private structs:
- `LoanFacepileIconsView`
- `LoanFacepileIcon`
- `LoanOverflowBadge`

Keep the `Decimal.toDouble()` extension (lines 163-169) — it's still used by `totalDebt`.

**Step 4: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 5: Commit**

```bash
git add Tenra/Views/Components/Cards/LoansCardView.swift
git commit -m "feat: use PackedCircleIconsView in LoansCardView, delete old facepile"
```

---

### Task 6: Delete StaticSubscriptionIconsView

**Files:**
- Delete: `Tenra/Views/Components/Icons/StaticSubscriptionIconsView.swift`

**Step 1: Verify no other references exist**

Run: `grep -r "StaticSubscriptionIconsView" Tenra/ --include="*.swift" -l`
Expected: Only `StaticSubscriptionIconsView.swift` itself (already replaced in SubscriptionsCardView)

**Step 2: Delete the file**

```bash
rm Tenra/Views/Components/Icons/StaticSubscriptionIconsView.swift
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete StaticSubscriptionIconsView (replaced by PackedCircleIconsView)"
```

---

### Task 7: Visual QA in Simulator

**Step 1: Run the app**

Run in Xcode on iPhone 17 Pro simulator. Navigate to Home screen.

**Step 2: Verify subscriptions card**

- [ ] Circles appear with staggered entrance animation
- [ ] Largest circle corresponds to most expensive subscription
- [ ] Circles don't overlap or escape card bounds
- [ ] "+N" badge appears if >5 subscriptions
- [ ] Breathing animation starts after entrance settles
- [ ] Breathing is subtle (3% scale, barely visible)

**Step 3: Verify loans card**

- [ ] Same checks as subscriptions
- [ ] Largest circle corresponds to highest remaining principal

**Step 4: Edge cases**

- [ ] 1 subscription → single centered circle
- [ ] All equal amounts → uniform circle sizes
- [ ] Empty state → no icons shown (existing empty state view)
- [ ] Reduce Motion enabled → no breathing animation

**Step 5: Fix any issues found, commit fixes**
