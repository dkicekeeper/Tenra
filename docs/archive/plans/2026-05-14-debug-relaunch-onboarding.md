# Debug "Relaunch Onboarding" Row Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `#if DEBUG`-only Settings row that immediately resets the onboarding flag and relaunches the onboarding flow.

**Architecture:** Three additive changes — a one-line `#if DEBUG` delegation method on `SettingsViewModel` that calls the existing `coordinator?.resetOnboarding()`, an `ActionSettingsRow` added to the already-`#if DEBUG` `experimentsSection` of `SettingsView`, and one new localized string in each of the en/ru strings files. No new types, no tests (see Testing note).

**Tech Stack:** SwiftUI (iOS 26), `@Observable` view model, Xcode 26.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Tenra/ViewModels/SettingsViewModel.swift` | Add `#if DEBUG debugRelaunchOnboarding()` — delegates to `coordinator?.resetOnboarding()` |
| `Tenra/Views/Settings/SettingsView.swift` | Add `ActionSettingsRow` to the `#if DEBUG experimentsSection` |
| `Tenra/en.lproj/Localizable.strings` | Add `settings.debug.relaunchOnboarding` (English) |
| `Tenra/ru.lproj/Localizable.strings` | Add `settings.debug.relaunchOnboarding` (Russian) |

All four changes are interdependent (the row references both the VM method and the localized key), so they land in **one task / one commit** to keep the module compiling.

**Build check command** (used throughout):
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD" | head -10
```
Expected when clean: `** BUILD SUCCEEDED **` and no `error:` lines.

**Testing note:** No unit test. `SettingsViewModelTests` does not exist, and `SettingsViewModel.init` requires five protocol-mock dependencies (`storageService`, `wallpaperService`, `resetCoordinator`, `validationService`, `exportCoordinator`) — building a bespoke harness for a one-line `#if DEBUG` delegation is disproportionate. The spec made the unit test explicitly conditional on an existing harness; there is none. Verification is manual (Task 2).

---

## Task 1: Add the debug relaunch-onboarding row

**Files:**
- Modify: `Tenra/ViewModels/SettingsViewModel.swift`
- Modify: `Tenra/Views/Settings/SettingsView.swift`
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 1: Add the localized strings**

In `Tenra/en.lproj/Localizable.strings`, find the line `"settings.experiments" = ...` (the existing key for the Experiments section). Add this new key on the line immediately after it:

```
"settings.debug.relaunchOnboarding" = "Relaunch Onboarding";
```

In `Tenra/ru.lproj/Localizable.strings`, find the same `"settings.experiments" = ...` line and add immediately after it:

```
"settings.debug.relaunchOnboarding" = "Перезапустить онбординг";
```

(If `"settings.experiments"` is not found in one of the files, place the new key adjacent to `"settings.notificationDebug"` instead — the goal is just to keep debug-settings keys grouped. Do not create a new section comment.)

- [ ] **Step 2: Add the `debugRelaunchOnboarding()` method to SettingsViewModel**

In `Tenra/ViewModels/SettingsViewModel.swift`, in the `// MARK: - Dangerous Operations` section, immediately after the closing brace of `resetAllData()`, add:

```swift
    #if DEBUG
    /// Debug-only: reset the onboarding flag and relaunch the onboarding flow.
    /// Swaps the whole app to `OnboardingFlowView` at the root via the coordinator.
    func debugRelaunchOnboarding() {
        coordinator?.resetOnboarding()
    }
    #endif
```

`coordinator` is the existing `@ObservationIgnored weak var coordinator: AppCoordinator?` property. `resetOnboarding()` is an existing method on `AppCoordinator` (it calls `OnboardingState.reset()` and sets `needsOnboarding = true`).

- [ ] **Step 3: Add the ActionSettingsRow to experimentsSection**

In `Tenra/Views/Settings/SettingsView.swift`, find the `#if DEBUG private var experimentsSection: some View` computed property. It currently contains a `Section { ... }` with two `NavigationSettingsRow` entries (Experiments, Notification Debug). Add a third row — an `ActionSettingsRow` — as the last child of that `Section`, immediately after the `NotificationDebugView` `NavigationSettingsRow` block:

```swift
            ActionSettingsRow(
                icon: "arrow.counterclockwise",
                title: String(localized: "settings.debug.relaunchOnboarding"),
                isDestructive: false,
                action: { settingsViewModel.debugRelaunchOnboarding() }
            )
```

`ActionSettingsRow` is an existing component (`Tenra/Views/Components/Rows/ActionSettingsRow.swift`) with initializer `init(icon:title:iconColor:titleColor:isDestructive:action:)` — `iconColor` and `titleColor` default to `nil`, `isDestructive` defaults to `false`. `settingsViewModel` is an existing stored property on `SettingsView`.

- [ ] **Step 4: Build to verify it compiles**

Run the build check command. Expected: `** BUILD SUCCEEDED **`, no `error:` lines.

If you see an error that `debugRelaunchOnboarding` is unavailable from `SettingsView`: confirm Step 2's method is NOT nested inside another `#if DEBUG` that's already open, and that the call site in Step 3 is inside the `#if DEBUG experimentsSection` (it is — `experimentsSection` itself is `#if DEBUG`, so the `#if DEBUG` method is always visible to it in a debug build).

- [ ] **Step 5: Commit**

```bash
git add Tenra/ViewModels/SettingsViewModel.swift Tenra/Views/Settings/SettingsView.swift Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat: add debug Settings row to relaunch onboarding"
```

---

## Task 2: Manual verification

**Files:** none (verification only)

- [ ] **Step 1: Full build (debug configuration)**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD" | head -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Manual check on the simulator**

Run the app on the iPhone 17 Pro simulator (debug build — the Experiments section only appears in `#if DEBUG`). Then:
1. Open **Settings**.
2. Scroll to the **Experiments** section — confirm a new row "Relaunch Onboarding" with a counterclockwise-arrow icon appears below "Notification Debug".
3. Tap it.
4. Confirm the app immediately swaps to the onboarding flow (`OnboardingFlowView`) at the root — the welcome carousel's first page.
5. Confirm you can navigate forward through onboarding normally.

> Note: completing the relaunched onboarding will create another account + categories (duplicates) — this is the expected, in-scope behavior per the design spec, not a bug.

---

## Self-Review

**Spec coverage:**
- `SettingsViewModel.debugRelaunchOnboarding()` `#if DEBUG` method → Task 1 Step 2 ✅
- `ActionSettingsRow` in `experimentsSection` → Task 1 Step 3 ✅
- `settings.debug.relaunchOnboarding` in en + ru → Task 1 Step 1 ✅
- Data flow (tap → VM → `resetOnboarding()` → `TenraApp` re-render) → exercised by Task 2 manual check ✅
- Testing: unit test was conditional on an existing harness; none exists → manual verification (Task 2), documented in the Testing note ✅
- Out-of-scope items (sheet preview, confirmation, dedupe) → not in any task, correct ✅

**Placeholder scan:** No TBD/TODO/vague steps — every code step shows complete code; the one fallback instruction in Step 1 ("if `settings.experiments` not found...") is a concrete contingency, not a placeholder.

**Type consistency:** `debugRelaunchOnboarding()` (defined Task 1 Step 2, called Task 1 Step 3) — name matches. `ActionSettingsRow(icon:title:isDestructive:action:)` matches the verified initializer. `settings.debug.relaunchOnboarding` key string identical across Steps 1 and 3.
