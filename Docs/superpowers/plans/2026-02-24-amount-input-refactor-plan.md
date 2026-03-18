# AmountInputView Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the broken per-character `AnimatedDigit` / `ForEach` animation system with native `.contentTransition(.numericText())`, fix 4 critical bugs, and align everything with the Inter-based design system.

**Architecture:** Three files touched in order of dependency — `AnimatedInputComponents.swift` first (shared types), then `AmountInputView.swift` (primary target), then `AnimatedAmountInput.swift` (sibling component). Each task is self-contained and buildable.

**Tech Stack:** SwiftUI, iOS 26+, `keyframeAnimator` (iOS 17+), `.contentTransition(.numericText())` (iOS 17+), `.onGeometryChange` (iOS 17+), `.task(id:)`.

**Design doc:** `docs/plans/2026-02-24-amount-input-refactor-design.md`

---

## Task 1: Clean up `AnimatedInputComponents.swift` — remove `AnimatedDigit`, fix `AnimatedTitleChar`

**Files:**
- Modify: `AIFinanceManager/Views/Components/AnimatedInputComponents.swift`

This file is shared. We clean it first so Tasks 2 and 3 can remove their `AnimatedDigit` usage without compile errors.

---

**Step 1: Remove `AnimatedDigit` struct**

Delete lines 30–95 (the entire `// MARK: - AnimatedDigit` section + struct body).
The struct is replaced by native `.contentTransition(.numericText())` — no replacement needed here.

---

**Step 2: Remove `ContainerWidthKey` struct**

Delete lines 192–200 (the entire `// MARK: - ContainerWidthKey` section).
Replaced by `.onGeometryChange(for:)` at the call sites.

---

**Step 3: Add `CharAnimState` value type** (needed by the fixed `AnimatedTitleChar`)

Add this **before** `// MARK: - AnimatedTitleChar`:

```swift
// MARK: - CharAnimState

/// Keyframe animation state for AnimatedTitleChar.
struct CharAnimState {
    var offsetY: CGFloat = 0
    var scale: CGFloat = 1.0
    var rotation: Double = 0
}
```

---

**Step 4: Replace `AnimatedTitleChar` body**

Replace the entire `AnimatedTitleChar` struct (lines 101–166) with:

```swift
// MARK: - AnimatedTitleChar

/// Renders a single text character with spring entrance + wobble effect.
/// Uses keyframeAnimator (iOS 17+) instead of DispatchQueue.asyncAfter.
struct AnimatedTitleChar: View {
    let character: Character
    let isNew: Bool
    let font: Font
    let color: Color

    @State private var animTrigger = false

    var body: some View {
        Text(String(character))
            .font(font)
            .foregroundStyle(color)
            .keyframeAnimator(
                initialValue: CharAnimState(),
                trigger: animTrigger
            ) { content, value in
                content
                    .offset(y: value.offsetY)
                    .scaleEffect(value.scale)
                    .rotationEffect(.degrees(value.rotation))
            } keyframes: { _ in
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
                    SpringKeyframe(8,  duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
                    SpringKeyframe(-8, duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
                    SpringKeyframe(4,  duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
                    SpringKeyframe(0,  duration: 0.15, spring: .init(response: 0.15, dampingFraction: 0.3))
                }
            }
            .onAppear {
                if isNew { animTrigger.toggle() }
            }
            .onChange(of: isNew) { _, new in
                if new { animTrigger.toggle() }
            }
            .onChange(of: character) { _, _ in
                animTrigger.toggle()
            }
    }
}
```

**What changed vs old code:**
- Removed `@State private var offset/scale/rotation/previousCharacter` (4 dead properties)
- Removed 4× `DispatchQueue.main.asyncAfter` blocks
- Added `@State private var animTrigger`
- Added `keyframeAnimator` with identical wobble sequence (declarative)
- Removed redundant `if oldValue != newValue` check in `onChange(of:character)` (always true)

---

**Step 5: Verify file compiles**

Build target `AIFinanceManager`:
```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded` — `AnimatedDigit` was only used in files we touch in Tasks 2–3, so there will be compile errors for those files. That is expected — proceed.

Actually, at this point Tasks 2 and 3 haven't removed their `AnimatedDigit` calls yet → build will fail for those two files. That is fine. Proceed to Task 2.

---

**Step 6: Commit**

```bash
git add AIFinanceManager/Views/Components/AnimatedInputComponents.swift
git commit -m "refactor(animation): replace AnimatedDigit with contentTransition, fix AnimatedTitleChar wobble

- Remove AnimatedDigit (replaced by .contentTransition(.numericText()) at call sites)
- Remove ContainerWidthKey (replaced by .onGeometryChange at call sites)
- Fix AnimatedTitleChar: DispatchQueue.asyncAfter x4 → keyframeAnimator (iOS 17+)
- Fix AnimatedTitleChar: remove dead previousCharacter @State
- Fix AnimatedTitleChar: remove redundant oldValue != newValue check
- Add CharAnimState for keyframe animation value type

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Refactor `AmountInputView.swift`

**Files:**
- Modify: `AIFinanceManager/Views/Transactions/Components/AmountInputView.swift`

This is the primary target. Read the full file before editing.

---

**Step 1: Make `displayFormatter` static**

```swift
// BEFORE (line 31):
private let displayFormatter: NumberFormatter = {

// AFTER:
private static let displayFormatter: NumberFormatter = {
```

---

**Step 2: Remove dead `@State` properties**

Remove these 4 lines from the `@State` declarations block:

```swift
// REMOVE these 3 lines:
@State private var previousAmount: String = ""
@State private var previousRawAmount: String = ""
@State private var animatedCharacters: [AnimatedChar] = []

// REMOVE this 1 line:
@State private var conversionTask: Task<Void, Never>?
```

---

**Step 3: Add `ConversionKey` private struct**

Add after the `// MARK: - Currency Conversion` comment, before `@State private var convertedAmount`:

```swift
private struct ConversionKey: Equatable {
    let amount: String
    let currency: String
}
```

---

**Step 4: Add static font measurement cache**

Add right after `convertedAmountFormatter`:

```swift
// Static UIFont for text-width measurement in updateFontSize.
// Falls back to system bold if "Inter" PostScript name doesn't match.
private static let measureFont: UIFont =
    UIFont(name: "Inter", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .bold)
private static let measureAttributes: [NSAttributedString.Key: Any] = [.font: measureFont]
```

---

**Step 5: Replace the Button label content**

Find the `Button { isFocused = true } label:` block. Replace the inner `HStack` contents (the `ForEach(animatedCharacters)` block) with:

```swift
Button {
    isFocused = true
} label: {
    HStack(spacing: 0) {
        Spacer()
        HStack(spacing: AppSpacing.xs) {
            Text(displayAmount)
                .font(.custom("Inter", size: currentFontSize).weight(.bold))
                .contentTransition(.numericText())
                .foregroundStyle(errorMessage != nil ? AppColors.destructive : AppColors.textPrimary)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayAmount)
                .lineLimit(1)
                .minimumScaleFactor(0.3)

            if isFocused {
                BlinkingCursor()
            }
        }
        Spacer()
    }
}
.buttonStyle(.plain)
```

---

**Step 6: Remove `.onChange(of: selectedCurrency)` for conversion**

Remove this block entirely (conversion is now handled by `.task(id:)`):

```swift
// REMOVE:
CurrencySelectorView(selectedCurrency: $selectedCurrency)
    .onChange(of: selectedCurrency) { _, _ in
        Task { await updateConvertedAmount() }
    }

// REPLACE WITH (no onChange):
CurrencySelectorView(selectedCurrency: $selectedCurrency)
```

---

**Step 7: Add `.task(id:)` for debounced conversion**

Add after the `TextField` block (after the hidden input):

```swift
// Debounced currency conversion — auto-cancels when amount or currency changes
.task(id: ConversionKey(amount: amount, currency: selectedCurrency)) {
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }
    await updateConvertedAmount()
}
```

---

**Step 8: Replace `GeometryReader` background with `.onGeometryChange`**

Remove the entire `.background(GeometryReader { ... })` modifier and the `.onPreferenceChange(ContainerWidthKey.self)` modifier.

Replace with a single modern modifier on the `VStack`:

```swift
.onGeometryChange(for: CGFloat.self) { proxy in
    proxy.size.width
} action: { newWidth in
    guard containerWidth != newWidth else { return }
    containerWidth = newWidth
    updateFontSize(for: newWidth)
}
```

Keep the `.onChange(of: displayAmount)` modifier that calls `updateFontSize` — it's still needed.

---

**Step 9: Fix transition animation on `convertedAmountView`**

In `body`, find where `convertedAmountView` is called and add the animation:

```swift
// BEFORE:
convertedAmountView

// AFTER:
convertedAmountView
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowConversion)
```

---

**Step 10: Fix `updateFontSize` — use static font measurement**

Replace the `UIFont` creation inside `updateFontSize` with the static cache:

```swift
// REMOVE these lines:
let testFont = UIFont(name: "Overpass-Bold", size: baseSize)
    ?? UIFont.systemFont(ofSize: baseSize, weight: .bold)
let textSize = (testText as NSString).size(withAttributes: [.font: testFont])

// REPLACE WITH:
let textSize = (testText as NSString).size(withAttributes: Self.measureAttributes)
```

Also remove the `baseSize` local constant if it's only used for the UIFont creation. The `maxWidth` calc uses `AppSpacing.lg * 2` — keep that.

Also update the font size clamp to use `56` directly (was `baseSize`):
```swift
newFontSize = max(24, min(56, 56 * scaleFactor))
```

---

**Step 11: Clean up `onAppear`**

Remove these 4 lines from `.onAppear`:

```swift
// REMOVE:
previousAmount = displayAmount
let cleaned = Self.cleanAmountString(amount)
previousRawAmount = cleaned.isEmpty ? "0" : cleaned
animatedCharacters = displayAmount.map { char in
    AnimatedChar(id: UUID(), character: char, isNew: false)
}
```

Keep only:
```swift
.onAppear {
    updateDisplayAmount(amount)
    Task {
        try? await Task.sleep(for: .milliseconds(100))
        isFocused = true
    }
}
```

---

**Step 12: Remove dead methods**

Delete these 4 method bodies entirely:

1. `private func updateAnimatedCharacters(newAmount:rawAmount:)` (~50 lines)
2. `private func spacingForFontSize(_:)` (~3 lines)
3. `private func groupDigits(_:)` (~8 lines)
4. `private func updateConvertedAmountDebounced()` (~8 lines)

---

**Step 13: Update bottom comment**

```swift
// BEFORE:
// AnimatedChar, AnimatedDigit, BlinkingCursor, ContainerWidthKey
// are defined in Views/Components/AnimatedInputComponents.swift

// AFTER:
// BlinkingCursor is defined in Views/Components/AnimatedInputComponents.swift
```

---

**Step 14: Build and verify**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded` (AmountInputView compiles; AnimatedAmountInput still fails — expected).

---

**Step 15: Commit**

```bash
git add AIFinanceManager/Views/Transactions/Components/AmountInputView.swift
git commit -m "refactor(AmountInputView): contentTransition + design system font + critical bug fixes

- Replace ForEach/AnimatedDigit with Text + .contentTransition(.numericText())
- Fix: displayFormatter static (was creating new NumberFormatter per struct init)
- Fix: @State Task → .task(id:) for debounced currency conversion
- Fix: GeometryReader+PreferenceKey → .onGeometryChange(for:) (iOS 17+)
- Fix: convertedAmountView transition gets .animation(_:value:) outside conditional
- Fix: UIFont measurement uses static cache (Inter, fallback to system bold)
- Fix: font Overpass-Bold → Inter (design system)
- Fix: error color .red → AppColors.destructive
- Remove dead @State: animatedCharacters, previousAmount, previousRawAmount, conversionTask
- Remove dead methods: updateAnimatedCharacters, spacingForFontSize, groupDigits, updateConvertedAmountDebounced

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Refactor `AnimatedAmountInput.swift`

**Files:**
- Modify: `AIFinanceManager/Views/Components/AnimatedAmountInput.swift`

Same bug patterns as Task 2. Contains two structs: `AnimatedAmountInput` and `AnimatedTitleInput`.
Only `AnimatedAmountInput` uses `AnimatedDigit`. `AnimatedTitleInput` uses `AnimatedTitleChar` (already fixed in Task 1).

---

**Step 1: Make `formatter` static + fix `formatLargeNumber`**

```swift
// BEFORE (line 38):
private let formatter: NumberFormatter = {

// AFTER:
private static let formatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 2
    f.groupingSeparator = " "
    f.usesGroupingSeparator = true
    f.decimalSeparator = "."
    return f
}()

// Add a second static formatter for formatLargeNumber (was creating inline):
private static let largeNumberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    f.usesGroupingSeparator = true
    f.maximumFractionDigits = 2
    return f
}()
```

---

**Step 2: Add static font measurement cache**

Add after the formatters:

```swift
private static let measureFont: UIFont =
    UIFont(name: "Inter", size: 56) ?? UIFont.systemFont(ofSize: 56, weight: .bold)
private static let measureAttributes: [NSAttributedString.Key: Any] = [.font: measureFont]
```

---

**Step 3: Remove dead `@State` properties**

```swift
// REMOVE:
@State private var previousRawAmount: String = "0"
@State private var animatedCharacters: [AnimatedChar] = []
```

---

**Step 4: Replace `AnimatedAmountInput` body — display section**

Replace the outer `HStack` (lines 52–71, the `ForEach` + `AnimatedDigit` block) and change
`onTapGesture` to `Button`:

```swift
var body: some View {
    VStack(spacing: 0) {
        // Amount display — tap to focus
        Button {
            HapticManager.light()
            isFocused = true
        } label: {
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: AppSpacing.xs) {
                    Text(displayAmount)
                        .font(.custom("Inter", size: currentFontSize).weight(.bold))
                        .contentTransition(.numericText())
                        .foregroundStyle(isPlaceholder ? AppColors.textTertiary : color)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayAmount)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)

                    if isFocused {
                        BlinkingCursor(height: cursorHeight)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)

        // Hidden TextField — actual input source
        TextField("", text: $amount)
            .keyboardType(.decimalPad)
            .focused($isFocused)
            .opacity(0)
            .frame(height: 0)
            .onChange(of: amount) { _, newValue in
                updateDisplayAmount(newValue)
            }
    }
```

---

**Step 5: Replace `GeometryReader` with `.onGeometryChange`**

Remove the `.background(GeometryReader { ... })` and `.onPreferenceChange` modifiers.
Replace with:

```swift
.onGeometryChange(for: CGFloat.self) { proxy in
    proxy.size.width
} action: { newWidth in
    guard containerWidth != newWidth else { return }
    containerWidth = newWidth
    updateFontSize(for: newWidth)
}
```

---

**Step 6: Fix `updateDisplayAmount` — use static formatters**

```swift
// In updateDisplayAmount, change:
} else if let formatted = formatter.string(from: number) {

// To use static:
} else if let formatted = Self.formatter.string(from: number) {
```

---

**Step 7: Fix `formatLargeNumber` — use static formatter**

```swift
// BEFORE:
private func formatLargeNumber(_ decimal: Decimal) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    f.usesGroupingSeparator = true
    f.maximumFractionDigits = 2
    if let s = f.string(from: NSDecimalNumber(decimal: decimal)) { return s }
    ...
}

// AFTER:
private func formatLargeNumber(_ decimal: Decimal) -> String {
    if let s = Self.largeNumberFormatter.string(from: NSDecimalNumber(decimal: decimal)) { return s }
    let string = String(describing: decimal)
    guard string.contains(".") else { return groupDigits(string) }
    let parts = string.components(separatedBy: ".")
    return "\(groupDigits(parts[0])).\(parts[1].prefix(2))"
}
```

---

**Step 8: Fix `updateFontSize` — use static measurement + fix font name**

```swift
// REMOVE:
let testFont = UIFont(name: "Overpass-Bold", size: baseFontSize)
    ?? UIFont.systemFont(ofSize: baseFontSize, weight: .bold)
let textSize = (displayAmount as NSString).size(withAttributes: [.font: testFont])

// REPLACE WITH:
let textSize = (displayAmount as NSString).size(withAttributes: Self.measureAttributes)
```

Note: the current scaling is relative to `baseFontSize`, not hardcoded 56. Keep that:
```swift
let newSize: CGFloat
if totalWidth > maxWidth && maxWidth > 0 {
    let scale = maxWidth / totalWidth
    newSize = max(24, min(baseFontSize, baseFontSize * scale))
} else {
    newSize = baseFontSize
}
```

---

**Step 9: Clean up `onAppear` — remove animatedCharacters init**

```swift
// REMOVE:
animatedCharacters = Array(displayAmount).map { char in
    AnimatedChar(id: UUID(), character: char, isNew: false)
}

// Also REMOVE:
previousRawAmount = cleanedRaw(amount)
```

Keep:
```swift
.onAppear {
    currentFontSize = baseFontSize
    updateDisplayAmount(amount)
}
```

---

**Step 10: Remove dead methods from `AnimatedAmountInput`**

Delete these from within the `AnimatedAmountInput` struct:
1. `private func spacingForFontSize(_:)` (~3 lines)
2. `private func groupDigits(_:)` (~8 lines)
3. `private func updateAnimatedCharacters(newDisplay:rawAmount:)` (~45 lines)

⚠️ `groupDigits` is used by `formatLargeNumber` — keep `groupDigits`, only delete `spacingForFontSize` and `updateAnimatedCharacters`.

Actually re-check: `groupDigits` IS still needed in `formatLargeNumber` fallback. Keep it.

Delete only:
1. `private func spacingForFontSize(_:)`
2. `private func updateAnimatedCharacters(newDisplay:rawAmount:)`

---

**Step 11: Build and verify**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded` — all 3 files now compile cleanly, no `AnimatedDigit` or `ContainerWidthKey` usages remain.

---

**Step 12: Final global search — ensure no orphaned references**

```bash
grep -rn "AnimatedDigit\|ContainerWidthKey\|Overpass-Bold\|previousCharacter\|conversionTask\|updateConvertedAmountDebounced\|updateAnimatedCharacters" \
  AIFinanceManager --include="*.swift"
```

Expected: **zero results**. If any remain, fix them before committing.

---

**Step 13: Commit**

```bash
git add AIFinanceManager/Views/Components/AnimatedAmountInput.swift
git commit -m "refactor(AnimatedAmountInput): contentTransition + static formatters + design system font

- Replace ForEach/AnimatedDigit with Text + .contentTransition(.numericText())
- Fix: formatter static (was new NumberFormatter per struct init)
- Fix: formatLargeNumber was creating inline NumberFormatter — now uses static
- Fix: GeometryReader+PreferenceKey → .onGeometryChange(for:)
- Fix: UIFont measurement uses static cache (Inter, fallback to system bold)
- Fix: font Overpass-Bold → Inter (design system)
- Fix: onTapGesture → Button (accessibility, VoiceOver)
- Remove dead @State: animatedCharacters, previousRawAmount
- Remove dead methods: spacingForFontSize, updateAnimatedCharacters

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Final verification

**Step 1: Build release to catch any optimizer issues**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|warning:|Build succeeded"
```

Expected: `Build succeeded`. Warnings for other parts of the codebase are acceptable; errors are not.

**Step 2: Run unit tests**

```
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:AIFinanceManagerTests \
  2>&1 | grep -E "error:|Test Suite.*passed|Test Suite.*failed"
```

Expected: `Test Suite 'AIFinanceManagerTests' passed` — no regressions.

**Step 3: Verify previews compile**

Open Xcode and verify the three `#Preview` blocks in `AmountInputView.swift` and
`AnimatedAmountInput.swift` render without errors. Check:
- "Amount Input - Empty" shows `0` in Inter Bold
- "Amount Input - With Value" shows `1 234.56` formatted with spaces
- "Amount Input - Error" shows red text
- "Animated Amount Input" renders hero balance display
- "Animated Title Input" renders per-character wobble animation (AnimatedTitleChar)

**Step 4: Manual smoke test on simulator**

Run on iPhone 17 Pro simulator. Open Add Transaction sheet. Verify:
1. Amount field shows `0` in Inter Bold at 56pt
2. Typing digits — smooth `contentTransition` animation between numbers
3. Long amounts (9+ digits) — font shrinks smoothly
4. Switching currency to USD — conversion row appears with spring animation
5. Switching back to base currency — conversion row disappears with spring animation
6. Long-press on amount — Copy / Paste context menu appears
7. Paste a numeric value — amount updates correctly

**Step 5: Commit verification tag**

```bash
git tag phase-31-amount-input-refactor
```

---

## Summary of changes

| File | Lines before (est.) | Lines after (est.) | Delta |
|------|--------------------|--------------------|-------|
| `AmountInputComponents.swift` | 200 | 130 | −70 |
| `AmountInputView.swift` | 448 | 290 | −158 |
| `AnimatedAmountInput.swift` | 457 | 310 | −147 |
| **Total** | **1,105** | **730** | **−375 (−34%)** |

| Bug fixed | How |
|-----------|-----|
| `Overpass-Bold` (removed font) | → `Font.custom("Inter", ...)` everywhere |
| `displayFormatter` not static | → `private static let` |
| `DispatchQueue.asyncAfter` x8 | → `keyframeAnimator` in AnimatedTitleChar |
| `@State conversionTask` | → `.task(id: ConversionKey(...))` |
| `GeometryReader + PreferenceKey` x2 | → `.onGeometryChange(for:)` x2 |
| Transition without animation | → `.animation(_:value: shouldShowConversion)` |
| Dead `previousCharacter` @State x2 | → Removed |
| `UIFont` created in hot path x2 | → `static let measureFont` x2 |
| Inline `NumberFormatter` in method | → `static let largeNumberFormatter` |
| `onTapGesture` (accessibility) | → `Button` |
