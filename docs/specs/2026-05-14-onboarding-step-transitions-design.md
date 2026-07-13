# Onboarding Step Transitions — Design

**Date:** 2026-05-14
**Status:** Approved

## Goal

Replace the onboarding flow's two separate, built-in navigation transitions
(`TabView` page-swipe for the welcome carousel, `NavigationStack` push for the
3-step data collection) with a single unified, custom **spring-overshoot**
transition that choreographs the outgoing screen out and the incoming screen in.

Inspired by the SwiftUI "KeyFramed OnBoarding Setup Animation" technique, but
implemented with a bouncy spring rather than an explicit `KeyframeAnimator` —
the spring's natural overshoot/settle *is* the bounce, in far less code.

## Decisions

- **Approach A** — custom `.transition()` + bouncy spring. Not an explicit
  `KeyframeAnimator` container (Approach B) — the described effect (spring
  bounce/overshoot) is exactly what a `.bouncy` spring produces.
- **Scope** — both the welcome carousel *and* the 3-step data-collection flow,
  unified under one transition style.
- **Welcome carousel becomes button-only.** Swipe-between-pages gestures are
  dropped along with `TabView`.

## Architecture

### 1. State model & navigation

`OnboardingViewModel` currently drives navigation through two mechanisms:
`welcomePage: Int` (carousel) and `path: [OnboardingStep]` (NavigationStack).
Both are replaced by one driver:

```swift
enum OnboardingScreen: Int, CaseIterable {
    case welcome1, welcome2, welcome3, currency, account, categories
}

enum TransitionDirection { case forward, back }
```

VM additions:
- `var currentScreen: OnboardingScreen = .welcome1`
- `var transitionDirection: TransitionDirection = .forward`

VM changes:
- `advanceToAccountStep()` / `advanceToCategoriesStep()` keep their async commit
  logic (currency persistence, account create/update) — they set
  `transitionDirection = .forward` and `currentScreen = .account` / `.categories`
  instead of appending to `path`.
- New `goForward()` / `goBack()` helpers set direction then screen; used for
  welcome→welcome moves and all *back* moves.
- `startDataCollection()` becomes a forward move from `.welcome3` to `.currency`.
- `welcomePage` and `path` are removed.
- `OnboardingStep` enum is removed **if** nothing outside onboarding references
  it. `Services/Onboarding/OnboardingState.swift` is flagged to check during
  planning; if it depends on `OnboardingStep`, reconcile there.

### 2. The transition

`OnboardingFlowView` collapses from a `TabView` + `NavigationStack` into a
single `switch` over `currentScreen`, rendered inside a `ZStack`:

```swift
ZStack {
    screenContent(for: vm.currentScreen)
        .id(vm.currentScreen)
        .transition(.onboardingStep(direction: vm.transitionDirection))
}
```

The `.id(currentScreen)` makes SwiftUI treat each screen as a discrete
insert/remove, triggering the transition. All screen changes are wrapped in
`withAnimation(AppAnimation.onboardingTransition)`.

- **New `AppAnimation` token** — `onboardingTransition`, a bouncy spring
  (`.spring` with overshoot). Added per the design-system convention of no
  hardcoded animation literals in views. See `docs/design-system.md`.
- **New file `OnboardingTransition.swift`** (in `Views/Onboarding/`) — an
  `AnyTransition` extension `.onboardingStep(direction:)`. Asymmetric:
  - insertion: `.move(edge:)` + `.scale(0.88)` + `.opacity`
  - removal: `.move(edge:)` + `.scale(0.88)` + `.opacity`
  - edges flip on `direction`: forward = incoming from `.trailing`, outgoing to
    `.leading`; back = mirrored.

  Driven by the bouncy spring, the incoming screen slides + scales in past its
  resting point and settles.

### 3. Supporting UI

- **Back navigation.** `NavigationStack` previously gave account/categories a
  system back chevron — now gone. `OnboardingPageContainer` gains an optional
  `onBack: (() -> Void)?`; when non-nil it renders a leading chevron button at
  the top. Welcome pages 2–3 get the same affordance for parity. The first
  screen (`welcome1`) has no back.
- **Welcome page dots.** `TabView`'s `.page` index dots are gone. New
  `OnboardingDotsIndicator` component (in `Views/Components/`) — highlights the
  *current* dot. Semantically distinct from the existing
  `OnboardingProgressBar`, which fills *cumulatively* (`index < currentStep`),
  so it is a separate small component, not a reuse.

## Files

| File | Change |
|------|--------|
| `ViewModels/OnboardingViewModel.swift` | Replace `welcomePage` + `path` with `currentScreen` + `transitionDirection`; add `goForward()`/`goBack()`; adjust advance methods; remove `OnboardingStep` (pending external-ref check) |
| `Views/Onboarding/OnboardingFlowView.swift` | Remove `TabView` + `NavigationStack`; single `switch` + `.transition` in a `ZStack` |
| `Views/Onboarding/Components/OnboardingPageContainer.swift` | Add optional `onBack` + leading chevron |
| `Views/Onboarding/OnboardingWelcomePage.swift` | Support optional back affordance + dots indicator placement |
| `Views/Onboarding/OnboardingTransition.swift` | **New** — `AnyTransition` extension + `TransitionDirection` usage |
| `Views/Components/OnboardingDotsIndicator.swift` | **New** — current-dot-highlighted indicator for welcome carousel |
| `Utils/` (AppAnimation) | Add `onboardingTransition` bouncy-spring token |
| `Services/Onboarding/OnboardingState.swift` | Check for `OnboardingStep` dependency; reconcile if present |

## Testing

- `OnboardingViewModel` tests referencing `welcomePage` / `path` are updated to
  assert on `currentScreen` and `transitionDirection`.
- Existing draft/commit-pipeline tests (currency persistence, account
  create/update, category commit) are unaffected — that logic is unchanged.
- Manual verification on a real device / simulator: forward and back through
  all six screens, confirm the spring overshoot reads correctly in both
  directions and the progress bar / dots stay in sync.

## Out of scope

- Explicit `KeyframeAnimator` choreography (Approach B).
- Swipe gestures on the welcome carousel.
- Any change to the onboarding's data model, commit pipeline, or the content of
  individual steps.
