# AmountInputView Refactor — Design Doc
**Date:** 2026-02-24
**Phase:** 31

---

## Problem

`AmountInputView` + `AnimatedAmountInput` share several critical bugs and an outdated
animation architecture. The audit found:

| # | Issue | Severity |
|---|-------|----------|
| 1 | `displayFormatter` is instance `let` → new `NumberFormatter` on every struct init | High |
| 2 | `DispatchQueue.main.asyncAfter` x4 for wobble — non-cancellable | High |
| 3 | `@State var conversionTask` + manual cancel → use `.task(id:)` | High |
| 4 | `convertedAmountView` transition has no `.animation(_:value:)` outside conditional | High |
| 5 | `GeometryReader` in `.background` + `PreferenceKey` — outdated pattern | Medium |
| 6 | `previousCharacter: Character?` @State — never read (dead code) | Medium |
| 7 | `AnimatedDigit` / `AnimatedTitleChar` — identical wobble logic duplicated | Medium |
| 8 | `UIFont(name: "Overpass-Bold")` — font removed; new font not set | Medium |
| 9 | `onChange(of: character)` has redundant `if oldValue != newValue` | Low |
| 10 | `formatLargeNumber` in `AnimatedAmountInput` creates `NumberFormatter` inline | Medium |

---

## Solution: `.contentTransition(.numericText())`

Replace the entire per-character `ForEach(animatedCharacters) { AnimatedDigit }` system
with a single `Text + .contentTransition(.numericText())` (iOS 17+).
`AnimatedTitleChar` (used for text input) keeps its wobble animation but is fixed with
`keyframeAnimator` instead of `DispatchQueue`.

---

## Scope — 3 files

### 1. `Views/Transactions/Components/AmountInputView.swift`

**State delta (−4 properties):**

| Property | Action |
|----------|--------|
| `@State var animatedCharacters: [AnimatedChar]` | REMOVE |
| `@State var previousAmount: String` | REMOVE |
| `@State var previousRawAmount: String` | REMOVE |
| `@State private var conversionTask: Task<Void, Never>?` | REMOVE |
| `private let displayFormatter` | → `private static let` |

**Body — display section:**

```swift
// BEFORE: ForEach(animatedCharacters) { AnimatedDigit(...) }

// AFTER:
Text(displayAmount)
    .font(.custom("Inter", size: currentFontSize).weight(.bold))
    .contentTransition(.numericText())
    .foregroundStyle(errorMessage != nil ? AppColors.destructive : AppColors.textPrimary)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayAmount)
    .lineLimit(1)
    .minimumScaleFactor(0.3)
```

Cursor stays as `BlinkingCursor()` inside same `HStack` — no changes.

**Conversion debounce — `.task(id:)` replaces manual Task:**

```swift
// Add private struct
private struct ConversionKey: Equatable {
    let amount: String
    let currency: String
}

// In body — replaces @State conversionTask + updateConvertedAmountDebounced()
.task(id: ConversionKey(amount: amount, currency: selectedCurrency)) {
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    await updateConvertedAmount()
}
```

Also remove `.onChange(of: selectedCurrency)` for conversion (now covered by `.task(id:)`).

**Geometry — `.onGeometryChange` (iOS 17+) replaces GeometryReader:**

```swift
// BEFORE
.background(
    GeometryReader { geometry in
        Color.clear.preference(key: ContainerWidthKey.self, value: geometry.size.width)
    }
)
.onPreferenceChange(ContainerWidthKey.self) { width in ... }

// AFTER
.onGeometryChange(for: CGFloat.self) { proxy in
    proxy.size.width
} action: { newWidth in
    guard containerWidth != newWidth else { return }
    containerWidth = newWidth
    updateFontSize(for: newWidth)
}
```

**Font measurement — static cache:**

```swift
private static let measureFont: UIFont =
    UIFont(name: "Inter", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .bold)
private static let measureAttributes: [NSAttributedString.Key: Any] = [.font: measureFont]

// In updateFontSize:
let textWidth = (testText as NSString).size(withAttributes: Self.measureAttributes).width
```

**Transition fix:**

```swift
// In body — wrap convertedAmountView call:
convertedAmountView
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowConversion)
```

**Methods removed:**
- `updateAnimatedCharacters(newAmount:rawAmount:)`
- `spacingForFontSize(_:)`
- `groupDigits(_:)`
- `updateConvertedAmountDebounced()`

**`onAppear` cleanup** — remove 3 lines that set `previousAmount`, `previousRawAmount`,
and `animatedCharacters`.

---

### 2. `Views/Components/AnimatedAmountInput.swift`

Same pattern as above:

- `formatter: NumberFormatter` → `private static let formatter` + `private static let formatLargeNumberFormatter`
- Remove `animatedCharacters`, `previousRawAmount`
- Replace `ForEach + AnimatedDigit` with `Text + .contentTransition(.numericText())`
- `.onTapGesture` → `Button` (accessibility: tappable area, VoiceOver label)
- `.onGeometryChange` replaces `GeometryReader + ContainerWidthKey`
- Static `measureFont` for `updateFontSize`
- Remove `animatedCharacters`, `spacingForFontSize`, `groupDigits`, `updateAnimatedCharacters`

`cursorHeight` stays (scales cursor proportionally to `baseFontSize`).

---

### 3. `Views/Components/AnimatedInputComponents.swift`

**Remove:**
- `AnimatedDigit` struct (replaced by `contentTransition`)
- `ContainerWidthKey` struct (replaced by `.onGeometryChange`)

**Add:**
- `CharAnimState` — keyframe animation value type for `AnimatedTitleChar`

**Fix `AnimatedTitleChar`:**
- Remove `@State private var previousCharacter: Character?` (dead state — never read)
- Remove `DispatchQueue.main.asyncAfter` x4 wobble
- Add `@State private var animTrigger = false`
- Replace wobble with `keyframeAnimator(initialValue: CharAnimState(), trigger: animTrigger)`
- Remove redundant `if oldValue != newValue` in `onChange(of: character)` (always true)

```swift
struct CharAnimState {
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1.0
    var rotation: Double = 0
}

// keyframes for AnimatedTitleChar:
KeyframeTrack(\.offsetY) {
    LinearKeyframe(20, duration: 0)
    SpringKeyframe(0, duration: 0.4, spring: .init(response: 0.4, dampingFraction: 0.6))
}
KeyframeTrack(\.scale) {
    LinearKeyframe(0.5, duration: 0)
    SpringKeyframe(1.0, duration: 0.4, spring: .init(response: 0.4, dampingFraction: 0.6))
}
KeyframeTrack(\.rotation) {
    LinearKeyframe(0, duration: 0.1)
    SpringKeyframe(8, duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
    SpringKeyframe(-8, duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
    SpringKeyframe(4, duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
    SpringKeyframe(0, duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
}
```

**Keep unchanged:**
- `AnimatedChar` struct (still used by `AnimatedTitleInput`)
- `AnimatedTitleInput` (not in scope — text input, wobble is appropriate)
- `BlinkingCursor` struct

---

## Design System Compliance

| Element | Before | After |
|---------|--------|-------|
| Hero font | `"Overpass-Bold"` (removed) | `Font.custom("Inter", size:).weight(.bold)` |
| Error color | `.red` | `AppColors.destructive` |
| Text primary | `.primary` | `AppColors.textPrimary` |

Localization: all existing keys (`button.copy`, `button.paste`,
`currency.conversion.approximate`) already present in both `en` and `ru`.

---

## Metrics

| Metric | Before | After |
|--------|--------|-------|
| `@State` properties (AmountInputView) | 9 | 5 |
| Methods removed | — | 4 |
| Animated chars system | `AnimatedChar` + `ForEach` + `AnimatedDigit` | Native `contentTransition` |
| Wobble implementation | `DispatchQueue.asyncAfter` x8 (both files) | `keyframeAnimator` declarative |
| Conversion debounce | `@State Task` + manual cancel | `.task(id:)` |
| Geometry reading | `GeometryReader` + `PreferenceKey` | `.onGeometryChange` |
| NumberFormatter instances on hot path | 1 per struct creation | 0 (static) |
| Dead state | `previousCharacter` x2 | Removed |
| Code lines (est.) | ~530 across 3 files | ~330 (-38%) |
