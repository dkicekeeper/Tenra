# Debug "Relaunch Onboarding" Row — Design

**Date:** 2026-05-14
**Status:** Approved

## Goal

Add a `#if DEBUG`-only Settings row that immediately resets the onboarding
completion flag and relaunches the onboarding flow — for testing the onboarding
experience (notably the new step transitions) without reinstalling the app.

## Decisions

- **Behavior:** reset the flag and relaunch the *real* flow (not a sheet
  preview). Tapping the row swaps the whole app to `OnboardingFlowView` at the
  root.
- **No confirmation:** tapping the row acts immediately. It lives in a
  DEBUG-only section, optimized for fast repeated testing.
- **Side effect accepted:** completing the relaunched onboarding runs the real
  commit pipeline, creating another account + categories (duplicates against
  existing data). Expected for a debug tool — not in scope to dedupe.

## Architecture

The plumbing already exists:
- `AppCoordinator.resetOnboarding()` resets `OnboardingState` and sets
  `needsOnboarding = true`.
- `TenraApp.swift` reads `needsOnboarding` to choose `OnboardingFlowView` vs the
  main app.
- `SettingsViewModel` already holds `@ObservationIgnored weak var coordinator:
  AppCoordinator?` and already calls `coordinator?.resetOnboarding()` inside
  `resetAllData()`.
- `SettingsView` already has a `#if DEBUG` `experimentsSection`.
- `ActionSettingsRow` (icon / title / isDestructive / action) is the existing
  component for action rows.

So this is three small additive changes.

### 1. `SettingsViewModel` — `debugRelaunchOnboarding()`

Add a `#if DEBUG`-guarded method:

```swift
#if DEBUG
/// Debug-only: reset the onboarding flag and relaunch the onboarding flow.
func debugRelaunchOnboarding() {
    coordinator?.resetOnboarding()
}
#endif
```

One-line delegation to the coordinator.

### 2. `SettingsView.experimentsSection` — new row

`experimentsSection` is already wrapped in `#if DEBUG`. Add a third row after the
existing `NotificationDebugView` row:

```swift
ActionSettingsRow(
    icon: "arrow.counterclockwise",
    title: String(localized: "settings.debug.relaunchOnboarding"),
    isDestructive: false,
    action: { settingsViewModel.debugRelaunchOnboarding() }
)
```

### 3. Localization

Add `settings.debug.relaunchOnboarding` to both strings files:
- `en.lproj/Localizable.strings`: `"Relaunch Onboarding"`
- `ru.lproj/Localizable.strings`: `"Перезапустить онбординг"`

## Data Flow

```
tap row
  → settingsViewModel.debugRelaunchOnboarding()
  → coordinator.resetOnboarding()
  → OnboardingState.reset() + needsOnboarding = true
  → TenraApp re-renders
  → OnboardingFlowView shown at root
```

## Files

| File | Change |
|------|--------|
| `Tenra/ViewModels/SettingsViewModel.swift` | Add `#if DEBUG debugRelaunchOnboarding()` method |
| `Tenra/Views/Settings/SettingsView.swift` | Add `ActionSettingsRow` to `experimentsSection` |
| `Tenra/en.lproj/Localizable.strings` | Add `settings.debug.relaunchOnboarding` |
| `Tenra/ru.lproj/Localizable.strings` | Add `settings.debug.relaunchOnboarding` |

## Testing

- **Manual (primary):** DEBUG build → Settings → Experiments section → tap
  "Relaunch Onboarding" → onboarding flow appears at the app root.
- **Unit test (conditional):** add a `SettingsViewModel` test asserting
  `debugRelaunchOnboarding()` triggers `resetOnboarding()` *only if* the existing
  test harness already builds a `SettingsViewModel` wired to an `AppCoordinator`.
  If it does not, skip it — the method is a one-line `#if DEBUG` delegation and a
  bespoke coordinator mock is disproportionate. Decision deferred to the
  implementation plan after inspecting `SettingsViewModelTests`.

## Out of Scope

- Sheet-preview mode (no-side-effect onboarding preview).
- Confirmation alert.
- Deduping accounts/categories created by re-running onboarding.
- Any change to the onboarding flow itself.
