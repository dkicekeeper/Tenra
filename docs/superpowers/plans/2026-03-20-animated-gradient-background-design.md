# Animated CategoryGradientBackground Design

**Date**: 2026-03-20
**Scope**: Evolve `CategoryGradientBackground.swift` — add breathing animation, drift movement, blend modes, and 2-layer depth system.

## Context

Current `CategoryGradientBackground` renders up to 5 static blurred ellipses representing top expense categories. No animation, no layering, no amount-based visual modulation.

## Requirements

1. Multiple "orbs" (Circle + radial gradient + blur) instead of flat Ellipse
2. Smooth breathing animation (scale) + slow drift (position movement)
3. `blendMode(.plusLighter)` or `.screen` for colour mixing (try both, pick best)
4. Orb size and brightness proportional to category weight (0.0–1.0)
5. 2 layers with different blur radii for depth effect
6. Performant — no body re-renders, GPU-driven animations

## Approach

Single file modification (`CategoryGradientBackground.swift`). API unchanged — `ContentView` not modified.

## Architecture

```
CategoryGradientBackground (API unchanged)
├── BackLayer (first 2 orbs — highest weight)
│   ├── blur: ~60
│   ├── breathing: 5-7s cycle (weight-dependent)
│   ├── drift: ±15pt, 8-12s cycle
│   └── blendMode: .screen or .plusLighter
├── FrontLayer (orbs 3-5)
│   ├── blur: ~35
│   ├── breathing: 3-5s cycle
│   ├── drift: ±25pt, 6-9s cycle
│   └── blendMode: same
└── Reduce Motion fallback: current static orbs (no change)
```

### Orb Parameters (weight-dependent)

| Parameter | weight=1.0 | weight=0.4 | Layer dependency |
|-----------|-----------|-----------|-----------------|
| breathScale | 1.0→1.15 | 1.0→1.05 | — |
| breathDuration | 4s | 7s | — |
| driftRadius | 15pt (back) / 25pt (front) | same | layer only |
| driftDuration | 8-12s (randomised per orb) | same | — |
| opacity | 0.45 | 0.25 | — |
| blurRadius | 60 (back) / 35 (front) | same | layer only |

### Animation Strategy

- **Breathing**: `scaleEffect` + `.easeInOut(duration:).repeatForever(autoreverses: true)`
- **Drift**: `offset(x:y:)` + `.easeInOut(duration:).repeatForever(autoreverses: true)`
- Each orb is a separate sub-view with its own `@State appeared` trigger
- Different durations per orb prevent synchronisation (lava lamp effect)
- No `TimelineView` or `Canvas` — standard declarative SwiftUI animations, GPU-driven

### Performance

- `drawingGroup()` on outer ZStack — composites into single Metal layer
- `allowsHitTesting(false)` — no touch interception
- No `@State` arrays — each orb sub-view manages its own animation state
- Body never re-invoked during animation (declarative `.repeatForever`)

### Reduce Motion

`AppAnimation.isReduceMotionEnabled` → render current static orbs without any animation (full backward compatibility).

## Files Modified

- `Tenra/Views/Components/Cards/CategoryGradientBackground.swift` — sole change

## Files NOT Modified

- `ContentView.swift` — API unchanged
- `AppAnimation.swift` — no new tokens needed (using standard `.easeInOut`)
- `AppModifiers.swift` — no new modifiers
