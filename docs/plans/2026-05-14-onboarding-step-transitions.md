# Onboarding Step Transitions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the onboarding flow's two built-in transitions (`TabView` page-swipe + `NavigationStack` push) with one unified spring-overshoot transition across all six onboarding screens.

**Architecture:** A single `OnboardingScreen` enum drives navigation. `OnboardingFlowView` renders one screen at a time inside a `ZStack`, using `.id()` + a custom asymmetric `AnyTransition` so SwiftUI runs an insert/remove transition on every screen change. A bouncy `AppAnimation` token supplies the overshoot. The welcome carousel becomes button-only; back navigation is reimplemented with explicit chevron affordances since `NavigationStack` is gone.

**Tech Stack:** SwiftUI (iOS 26), Swift Testing, `@Observable` view model, Xcode 26.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Tenra/ViewModels/OnboardingViewModel.swift` | Owns `currentScreen` + `transitionDirection`; `goForward`/`goBack` helpers; advance methods set screen instead of `path` |
| `Tenra/Utils/AppAnimation.swift` | New `onboardingTransition` bouncy-spring token (reduce-motion-aware) |
| `Tenra/Views/Onboarding/OnboardingTransition.swift` | **New** — `AnyTransition.onboardingStep(direction:)` asymmetric transition |
| `Tenra/Views/Components/OnboardingDotsIndicator.swift` | **New** — current-dot-highlighted indicator for the welcome carousel |
| `Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift` | Gains optional `onBack` leading-chevron affordance |
| `Tenra/Views/Onboarding/OnboardingWelcomePage.swift` | Self-contained welcome screen: back chevron, content, dots, primary button |
| `Tenra/Views/Onboarding/OnboardingFlowView.swift` | Single `switch` over `currentScreen` + `.transition` in a `ZStack` |
| `Tenra/Views/Onboarding/OnboardingCurrencyStep.swift` | Pass `onBack` to container; drop `.navigationBarBackButtonHidden` |
| `Tenra/Views/Onboarding/OnboardingAccountStep.swift` | Pass `onBack` to container |
| `Tenra/Views/Onboarding/OnboardingCategoriesStep.swift` | Pass `onBack` to container |
| `TenraTests/Onboarding/OnboardingViewModelTests.swift` | New tests for `currentScreen` / `goForward` / `goBack` |

**New-file note:** This project targets Xcode 26. If a newly created `.swift` file is not picked up by the build automatically, add it to the **Tenra** target (for `Tenra/...` files) or **TenraTests** target via Xcode's file inspector. Each task that creates a file includes a build check that will surface this.

**Build check command** (used throughout):
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected when clean: no output.

---

## Task 1: Add unified screen state + navigation helpers to OnboardingViewModel

This task is **purely additive** — the old `welcomePage`, `path`, and `OnboardingStep` stay in place so the module keeps compiling. They are removed in Task 6.

**Files:**
- Modify: `Tenra/ViewModels/OnboardingViewModel.swift`
- Test: `TenraTests/Onboarding/OnboardingViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these three tests to `TenraTests/Onboarding/OnboardingViewModelTests.swift`, inside the existing `struct OnboardingViewModelTests` (after the last `@Test`):

```swift
    @Test func currentScreenStartsAtWelcome1() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.currentScreen == .welcome1)
        #expect(vm.transitionDirection == .forward)
    }

    @Test func goForwardSetsForwardDirectionAndScreen() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.goForward(to: .welcome2)
        #expect(vm.currentScreen == .welcome2)
        #expect(vm.transitionDirection == .forward)
    }

    @Test func goBackSetsBackDirectionAndScreen() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.goForward(to: .currency)
        vm.goBack(to: .welcome3)
        #expect(vm.currentScreen == .welcome3)
        #expect(vm.transitionDirection == .back)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingViewModelTests 2>&1 | grep -E "error:|Compiling failed|has no member" | head -20
```
Expected: compile errors — `value of type 'OnboardingViewModel' has no member 'currentScreen'` (and `goForward`, `goBack`, `transitionDirection`).

- [ ] **Step 3: Add the enums**

In `Tenra/ViewModels/OnboardingViewModel.swift`, **add** these two enums just below the existing `enum OnboardingStep` declaration (do NOT remove `OnboardingStep` yet):

```swift
/// Every screen in the onboarding flow — welcome carousel + data-collection steps.
enum OnboardingScreen: Int, CaseIterable {
    case welcome1, welcome2, welcome3, currency, account, categories
}

/// Direction of a screen change — drives which way the transition slides.
enum TransitionDirection {
    case forward, back
}
```

- [ ] **Step 4: Add the state properties**

In `OnboardingViewModel`, in the `// MARK: - Welcome carousel` section, **add** below `var welcomePage: Int = 0` (keep `welcomePage` for now):

```swift
    /// The currently displayed onboarding screen. Single source of navigation truth.
    var currentScreen: OnboardingScreen = .welcome1

    /// Direction of the most recent screen change — read by the transition.
    var transitionDirection: TransitionDirection = .forward
```

- [ ] **Step 5: Add the navigation helpers**

In `OnboardingViewModel`, in the `// MARK: - Step navigation` section, **add** these two methods (above `startDataCollection()`):

```swift
    /// Advance to `screen` with a forward (slide-in-from-trailing) transition.
    func goForward(to screen: OnboardingScreen) {
        transitionDirection = .forward
        withAnimation(AppAnimation.onboardingTransition) {
            currentScreen = screen
        }
    }

    /// Return to `screen` with a back (slide-in-from-leading) transition.
    func goBack(to screen: OnboardingScreen) {
        transitionDirection = .back
        withAnimation(AppAnimation.onboardingTransition) {
            currentScreen = screen
        }
    }
```

> Note: `AppAnimation.onboardingTransition` does not exist yet — it is added in Task 2. The VM file will not compile until Task 2 is done. That is expected; complete Task 2 before running the Task 1 verification in Step 6.

- [ ] **Step 6: Run tests to verify they pass**

(Run **after** Task 2 is complete.)
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingViewModelTests 2>&1 | tail -15
```
Expected: all `OnboardingViewModelTests` pass (9 tests).

- [ ] **Step 7: Commit**

```bash
git add Tenra/ViewModels/OnboardingViewModel.swift TenraTests/Onboarding/OnboardingViewModelTests.swift
git commit -m "feat: add unified OnboardingScreen state + navigation helpers"
```

---

## Task 2: Add the `onboardingTransition` animation token

**Files:**
- Modify: `Tenra/Utils/AppAnimation.swift`

- [ ] **Step 1: Add the token**

In `Tenra/Utils/AppAnimation.swift`, inside `enum AppAnimation`, add this in the `// MARK: - Reduce Motion Aware Animations` section (just after `adaptiveSpring`):

```swift
    /// Onboarding step transition — bouncy spring with a dramatic, visible settle.
    /// Reduce-Motion-aware: collapses to an instant transition.
    static var onboardingTransition: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: 0.5, dampingFraction: 0.68)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run the build check command. Expected: no output. (This also makes the Task 1 VM changes compile — run Task 1 Step 6 now and confirm tests pass.)

- [ ] **Step 3: Commit**

```bash
git add Tenra/Utils/AppAnimation.swift
git commit -m "feat: add onboardingTransition animation token"
```

---

## Task 3: Create the custom step transition

**Files:**
- Create: `Tenra/Views/Onboarding/OnboardingTransition.swift`

- [ ] **Step 1: Create the file**

Create `Tenra/Views/Onboarding/OnboardingTransition.swift`:

```swift
//
//  OnboardingTransition.swift
//  Tenra
//
//  Custom asymmetric transition for onboarding screen changes. The incoming
//  screen slides + scales in from one edge; the outgoing screen slides + scales
//  out the opposite edge. Edge direction is driven by `TransitionDirection`.
//  The spring overshoot comes from `AppAnimation.onboardingTransition`, applied
//  by the caller via `withAnimation`.
//

import SwiftUI

extension AnyTransition {
    static func onboardingStep(direction: TransitionDirection) -> AnyTransition {
        let insertionEdge: Edge = direction == .forward ? .trailing : .leading
        let removalEdge: Edge = direction == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge)
                .combined(with: .scale(scale: 0.88))
                .combined(with: .opacity),
            removal: .move(edge: removalEdge)
                .combined(with: .scale(scale: 0.88))
                .combined(with: .opacity)
        )
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build check command. Expected: no output. (If the new file is not picked up, add it to the Tenra target — see New-file note.)

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Onboarding/OnboardingTransition.swift
git commit -m "feat: add custom onboarding step transition"
```

---

## Task 4: Create the welcome-carousel dots indicator

**Files:**
- Create: `Tenra/Views/Components/OnboardingDotsIndicator.swift`

- [ ] **Step 1: Create the file**

Create `Tenra/Views/Components/OnboardingDotsIndicator.swift`:

```swift
//
//  OnboardingDotsIndicator.swift
//  Tenra
//
//  Page-dots indicator for the onboarding welcome carousel. Highlights the
//  CURRENT dot only — distinct from OnboardingProgressBar, which fills
//  cumulatively for the data-collection steps.
//

import SwiftUI

struct OnboardingDotsIndicator: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<totalCount, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex
                          ? AppColors.accent
                          : AppColors.textSecondary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(AppAnimation.contentSpring, value: currentIndex)
    }
}

#Preview {
    OnboardingDotsIndicator(currentIndex: 1, totalCount: 3)
        .padding()
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build check command. Expected: no output. (If the new file is not picked up, add it to the Tenra target.)

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Components/OnboardingDotsIndicator.swift
git commit -m "feat: add OnboardingDotsIndicator component"
```

---

## Task 5: Add optional back affordance to OnboardingPageContainer

The `onBack` parameter defaults to `nil`, so the existing three step-view callers stay compiling unchanged until Task 6.

**Files:**
- Modify: `Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift`

- [ ] **Step 1: Add the parameter and back chevron**

Replace the entire body of `Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift` with:

```swift
//
//  OnboardingPageContainer.swift
//  Tenra
//
//  Shared layout for onboarding data-collection steps:
//  optional back chevron, progress bar, title + subtitle, body content,
//  primary CTA pinned at the bottom.
//

import SwiftUI

struct OnboardingPageContainer<Content: View>: View {
    let progressStep: Int            // 1, 2, or 3
    let title: String
    let subtitle: String?
    let primaryButtonTitle: String
    let primaryButtonEnabled: Bool
    let onPrimaryTap: () -> Void
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }

            OnboardingProgressBar(totalSteps: 3, currentStep: progressStep)
                .padding(.top, onBack == nil ? AppSpacing.lg : AppSpacing.md)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.lg)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Button(action: onPrimaryTap) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!primaryButtonEnabled)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build check command. Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift
git commit -m "feat: add optional back affordance to OnboardingPageContainer"
```

---

## Task 6: Cut over to the unified flow

This is the atomic cutover: `OnboardingFlowView`, `OnboardingWelcomePage`, the three step views, and the VM's advance methods all switch to `currentScreen` together, and the old `welcomePage` / `path` / `OnboardingStep` are removed. All edits land in one commit because Swift compiles the module as a unit.

**Files:**
- Modify: `Tenra/Views/Onboarding/OnboardingWelcomePage.swift`
- Modify: `Tenra/Views/Onboarding/OnboardingFlowView.swift`
- Modify: `Tenra/Views/Onboarding/OnboardingCurrencyStep.swift`
- Modify: `Tenra/Views/Onboarding/OnboardingAccountStep.swift`
- Modify: `Tenra/Views/Onboarding/OnboardingCategoriesStep.swift`
- Modify: `Tenra/ViewModels/OnboardingViewModel.swift`

- [ ] **Step 1: Rewrite OnboardingWelcomePage as a self-contained screen**

Replace the entire contents of `Tenra/Views/Onboarding/OnboardingWelcomePage.swift` with:

```swift
//
//  OnboardingWelcomePage.swift
//  Tenra
//
//  One self-contained welcome-carousel screen: optional back chevron, hero
//  icon + copy, page dots, and the primary CTA.
//

import SwiftUI

struct OnboardingWelcomePage: View {
    let pageIndex: Int
    let sfSymbol: String
    let title: String
    let subtitle: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                Spacer()
            }
            .frame(height: 24)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)

            Spacer()

            Image(systemName: sfSymbol)
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(AppColors.accent)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.top, AppSpacing.lg)

            Spacer()

            OnboardingDotsIndicator(currentIndex: pageIndex, totalCount: 3)
                .padding(.bottom, AppSpacing.lg)

            Button(action: onPrimary) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
    }
}
```

- [ ] **Step 2: Rewrite OnboardingFlowView**

Replace the entire contents of `Tenra/Views/Onboarding/OnboardingFlowView.swift` with:

```swift
//
//  OnboardingFlowView.swift
//  Tenra
//
//  Root view of the onboarding experience. Renders one OnboardingScreen at a
//  time inside a ZStack, with a custom spring-overshoot transition on every
//  screen change.
//

import SwiftUI

struct OnboardingFlowView: View {
    @State private var vm: OnboardingViewModel

    init(coordinator: AppCoordinator) {
        _vm = State(wrappedValue: OnboardingViewModel(coordinator: coordinator))
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()
            screenContent
                .id(vm.currentScreen)
                .transition(.onboardingStep(direction: vm.transitionDirection))
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch vm.currentScreen {
        case .welcome1:
            OnboardingWelcomePage(
                pageIndex: 0,
                sfSymbol: "chart.pie.fill",
                title: String(localized: "onboarding.welcome.page1.title"),
                subtitle: String(localized: "onboarding.welcome.page1.subtitle"),
                primaryTitle: String(localized: "onboarding.cta.next"),
                onPrimary: { vm.goForward(to: .welcome2) },
                onBack: nil
            )
        case .welcome2:
            OnboardingWelcomePage(
                pageIndex: 1,
                sfSymbol: "mic.fill",
                title: String(localized: "onboarding.welcome.page2.title"),
                subtitle: String(localized: "onboarding.welcome.page2.subtitle"),
                primaryTitle: String(localized: "onboarding.cta.next"),
                onPrimary: { vm.goForward(to: .welcome3) },
                onBack: { vm.goBack(to: .welcome1) }
            )
        case .welcome3:
            OnboardingWelcomePage(
                pageIndex: 2,
                sfSymbol: "lock.shield.fill",
                title: String(localized: "onboarding.welcome.page3.title"),
                subtitle: String(localized: "onboarding.welcome.page3.subtitle"),
                primaryTitle: String(localized: "onboarding.cta.start"),
                onPrimary: { vm.startDataCollection() },
                onBack: { vm.goBack(to: .welcome2) }
            )
        case .currency:
            OnboardingCurrencyStep(vm: vm)
        case .account:
            OnboardingAccountStep(vm: vm)
        case .categories:
            OnboardingCategoriesStep(vm: vm)
        }
    }
}
```

- [ ] **Step 3: Update OnboardingCurrencyStep**

Replace the entire contents of `Tenra/Views/Onboarding/OnboardingCurrencyStep.swift` with:

```swift
//
//  OnboardingCurrencyStep.swift
//  Tenra
//

import SwiftUI

struct OnboardingCurrencyStep: View {
    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingPageContainer(
            progressStep: 1,
            title: String(localized: "onboarding.currency.title"),
            subtitle: String(localized: "onboarding.currency.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: true,
            onPrimaryTap: {
                Task { await vm.advanceToAccountStep() }
            },
            onBack: { vm.goBack(to: .welcome3) }
        ) {
            CurrencyListContent(selectedCurrency: vm.draftCurrency) { code in
                vm.draftCurrency = code
            }
            .padding(.top, AppSpacing.md)
        }
    }
}
```

- [ ] **Step 4: Update OnboardingAccountStep**

In `Tenra/Views/Onboarding/OnboardingAccountStep.swift`, in the `OnboardingPageContainer(...)` initializer, add the `onBack` argument immediately after the `onPrimaryTap` closure. The call site becomes:

```swift
        OnboardingPageContainer(
            progressStep: 2,
            title: String(localized: "onboarding.account.title"),
            subtitle: String(localized: "onboarding.account.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: vm.canAdvanceFromAccountStep,
            onPrimaryTap: {
                Task { await vm.advanceToCategoriesStep() }
            },
            onBack: { vm.goBack(to: .currency) }
        ) {
```

(Leave the rest of the file — `ScrollView`, `.onAppear`, `.sheet`, `.onChange`, `formSection` — unchanged.)

- [ ] **Step 5: Update OnboardingCategoriesStep**

In `Tenra/Views/Onboarding/OnboardingCategoriesStep.swift`, in the `OnboardingPageContainer(...)` initializer, add the `onBack` argument immediately after the `onPrimaryTap` closure. The call site becomes:

```swift
        OnboardingPageContainer(
            progressStep: 3,
            title: String(localized: "onboarding.categories.title"),
            subtitle: String(localized: "onboarding.categories.subtitle"),
            primaryButtonTitle: doneTitle,
            primaryButtonEnabled: vm.canFinish,
            onPrimaryTap: {
                vm.finish()    // finish() is sync, NOT async
            },
            onBack: { vm.goBack(to: .account) }
        ) {
```

(Leave the rest of the file unchanged.)

- [ ] **Step 6: Update OnboardingViewModel — advance methods + remove old state**

In `Tenra/ViewModels/OnboardingViewModel.swift`, make these four edits:

1. **Remove** the `enum OnboardingStep { case currency; case account; case categories }` declaration entirely.

2. **Remove** `var welcomePage: Int = 0` and its `// MARK: - Welcome carousel` comment line. Also **remove** `var path: [OnboardingStep] = []` and its doc comment in the `// MARK: - Step state` section. (Keep `currentScreen` and `transitionDirection` — they replace both.)

3. **Replace** `startDataCollection()` with:

```swift
    func startDataCollection() {
        goForward(to: .currency)
        logger.info("onboarding_started")
    }
```

4. **Replace** the `path.append(.account)` line in `advanceToAccountStep()` with `goForward(to: .account)`, and the `path.append(.categories)` line in `advanceToCategoriesStep()` with `goForward(to: .categories)`. The two methods otherwise keep all their existing currency-persistence / account create-update logic and `logger.info(...)` calls.

- [ ] **Step 7: Build to verify the cutover compiles**

Run the build check command. Expected: no output. If there are errors, they will most likely be a missed `path`/`welcomePage`/`OnboardingStep` reference — grep for them:
```bash
grep -rn "welcomePage\|\.path\b\|OnboardingStep" Tenra --include='*.swift'
```
Expected: no matches.

- [ ] **Step 8: Run the onboarding tests**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingViewModelTests 2>&1 | tail -15
```
Expected: all 9 tests pass.

- [ ] **Step 9: Commit**

```bash
git add Tenra/Views/Onboarding/OnboardingWelcomePage.swift Tenra/Views/Onboarding/OnboardingFlowView.swift Tenra/Views/Onboarding/OnboardingCurrencyStep.swift Tenra/Views/Onboarding/OnboardingAccountStep.swift Tenra/Views/Onboarding/OnboardingCategoriesStep.swift Tenra/ViewModels/OnboardingViewModel.swift
git commit -m "feat: unified spring-overshoot onboarding step transitions"
```

---

## Task 7: Full build + test verification

**Files:** none (verification only)

- [ ] **Step 1: Full project build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|warning:.*Onboarding" | head -30
```
Expected: no errors.

- [ ] **Step 2: Full unit-test suite**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | tail -20
```
Expected: all tests pass — confirms nothing else in the app referenced the removed onboarding API.

- [ ] **Step 3: Manual verification on simulator or device**

Launch the app fresh (delete it first so onboarding shows). Verify:
- Welcome 1 → 2 → 3 → currency → account → categories all transition with a visible spring overshoot, sliding in from the trailing edge.
- Back chevron on welcome 2/3 and on currency/account/categories transitions back, sliding in from the leading edge.
- Welcome page dots highlight the current page; data-step progress bar fills cumulatively.
- Completing categories finishes onboarding and lands on the home screen.
- With **Settings → Accessibility → Reduce Motion** ON, screen changes are instant (no slide/scale).

> Note: this is a SwiftUI animation feature — the build + unit tests verify code correctness, not motion feel. The spring tuning (`response: 0.5, dampingFraction: 0.68`) may need adjustment after seeing it on-device; that is a one-line change in `AppAnimation.onboardingTransition`.

---

## Self-Review

**Spec coverage:**
- Unified `OnboardingScreen` + `TransitionDirection` + nav helpers → Task 1 ✅
- `AppAnimation.onboardingTransition` token → Task 2 ✅
- Custom `AnyTransition` (asymmetric move+scale+opacity, direction-flipped) → Task 3 ✅
- `OnboardingDotsIndicator` (current-dot-highlighted) → Task 4 ✅
- `OnboardingPageContainer` optional `onBack` → Task 5 ✅
- `OnboardingFlowView` single switch + ZStack + `.id` + `.transition` → Task 6 Step 2 ✅
- `OnboardingWelcomePage` back affordance + dots → Task 6 Step 1 ✅
- Advance methods set screen instead of `path`; `welcomePage`/`path`/`OnboardingStep` removed → Task 6 Step 6 ✅
- `OnboardingState.swift` `OnboardingStep` dependency check → resolved during planning: confirmed no reference, no task needed ✅
- Tests updated → Task 1 (new tests) + Task 7 Step 2 (full suite catches stragglers) ✅

**Placeholder scan:** No TBD/TODO/"handle edge cases" — every code step shows complete code.

**Type consistency:** `OnboardingScreen`, `TransitionDirection`, `currentScreen`, `transitionDirection`, `goForward(to:)`, `goBack(to:)`, `onboardingStep(direction:)`, `onBack`, `OnboardingDotsIndicator(currentIndex:totalCount:)`, `OnboardingWelcomePage(pageIndex:sfSymbol:title:subtitle:primaryTitle:onPrimary:onBack:)` — names and signatures consistent across Tasks 1, 3, 4, 5, 6.
