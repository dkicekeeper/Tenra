# Per-Element Skeleton Loading — Implementation Plan (Phase 30)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the broken full-screen skeleton (invisible background, shimmer never visible, dismissed too early) with per-element skeleton loading — each section shows its own skeleton independently until its specific data is ready.

**Architecture:** Universal `.skeletonLoading(isLoading:skeleton:)` ViewModifier replaces the `isInitializing` flag and full-screen overlay in ContentView. AppCoordinator gains two new observable output properties (`fastPathDone`, `fullyInitialized`) that ContentView and InsightsView bind to. SkeletonView shimmer is fixed for light-mode visibility.

**Tech Stack:** SwiftUI ViewModifier, `@Observable` AppCoordinator, existing SkeletonView/AppColors/AppRadius Design System tokens.

---

## Task 1: Fix SkeletonView.swift shimmer

**Files:**
- Modify: `AIFinanceManager/Views/Components/SkeletonView.swift`

**Step 1: Apply the three shimmer fixes**

Edit lines 13, 21, 27, 35 of `SkeletonView.swift`:

Change 1 — phase starts at -0.5 (shimmer enters view immediately on appear, not after 107ms):
```
// Before (line 13):
@State private var phase: CGFloat = -1.0

// After:
@State private var phase: CGFloat = -0.5
```

Change 2 — shimmer highlight more visible on light backgrounds (0.3 → 0.5):
```
// Before (line 21):
.init(color: .white.opacity(0.3), location: 0.5),

// After:
.init(color: .white.opacity(0.5), location: 0.5),
```

Change 3 — remove `.blendMode(.screen)` entirely (on systemGray5 it gives ~0.03 luminance delta, imperceptible):
Delete line 27: `.blendMode(.screen)`

Change 4 — end phase matches new start (1.5 instead of 2.0 keeps sweep duration consistent):
```
// Before (line 35):
phase = 2.0

// After:
phase = 1.5
```

**Step 2: Verify the diff looks correct**

Run: `grep -n "phase\|opacity\|blendMode" AIFinanceManager/Views/Components/SkeletonView.swift`

Expected output — should show `phase: CGFloat = -0.5`, `white.opacity(0.5)`, `phase = 1.5`, NO `blendMode` line:
```
13:    @State private var phase: CGFloat = -0.5
21:        .init(color: .white.opacity(0.5), location: 0.5),
35:                    phase = 1.5
```

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Components/SkeletonView.swift
git commit -m "fix(skeleton): fix shimmer visibility — phase -0.5→1.5, opacity 0.5, remove blendMode"
```

---

## Task 2: Create SkeletonLoadingModifier.swift

**Files:**
- Create: `AIFinanceManager/Views/Components/SkeletonLoadingModifier.swift`

**Step 1: Create the file**

```swift
//
//  SkeletonLoadingModifier.swift
//  AIFinanceManager
//
//  Universal per-element skeleton loading modifier (Phase 30)

import SwiftUI

// MARK: - SkeletonLoadingModifier

/// Universal ViewModifier — shows skeleton when isLoading, transitions to real content when ready.
/// Usage: anyView.skeletonLoading(isLoading: flag) { SkeletonShape() }
struct SkeletonLoadingModifier<S: View>: ViewModifier {
    let isLoading: Bool
    @ViewBuilder let skeleton: () -> S

    func body(content: Content) -> some View {
        Group {
            if isLoading {
                skeleton()
                    .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
            } else {
                content
                    .transition(.opacity.combined(with: .scale(1.02, anchor: .center)))
            }
        }
        .animation(.spring(response: 0.4), value: isLoading)
    }
}

extension View {
    /// Replaces this view with `skeleton()` while `isLoading` is true.
    /// Transitions smoothly to real content once loading completes.
    func skeletonLoading<S: View>(
        isLoading: Bool,
        @ViewBuilder skeleton: () -> S
    ) -> some View {
        modifier(SkeletonLoadingModifier(isLoading: isLoading, skeleton: skeleton))
    }
}
```

**Step 2: Verify it builds**

Run: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Components/SkeletonLoadingModifier.swift
git commit -m "feat(skeleton): add universal SkeletonLoadingModifier for per-element skeleton loading"
```

---

## Task 3: AppCoordinator — add fastPathDone + fullyInitialized

**Files:**
- Modify: `AIFinanceManager/ViewModels/AppCoordinator.swift`

**Step 1: Add two new observable output properties after line 51**

Current code (lines 50–51):
```swift
private var isInitialized = false
private var isFastPathStarted = false
```

New code:
```swift
private var isInitialized = false
private var isFastPathStarted = false

// Observable loading stage outputs — views bind to these for per-element skeletons
private(set) var fastPathDone = false      // accounts + categories ready (~50ms)
private(set) var fullyInitialized = false  // transactions + all data ready (~1-3s)
```

**Step 2: Set fastPathDone = true at end of initializeFastPath()**

Current end of `initializeFastPath()` (line 217 closing brace, after `await settingsViewModel.loadInitialData()`):
```swift
    // Load settings (UserDefaults read — instant)
    await settingsViewModel.loadInitialData()
}
```

New:
```swift
    // Load settings (UserDefaults read — instant)
    await settingsViewModel.loadInitialData()
    fastPathDone = true
}
```

**Step 3: Set fullyInitialized = true after balance registration in initialize()**

Current code around lines 242–246:
```swift
        await balanceCoordinator.registerAccounts(
            transactionStore.accounts,
            transactions: transactionStore.transactions
        )

        // 4. Generate recurring transactions in background (non-blocking)
```

New:
```swift
        await balanceCoordinator.registerAccounts(
            transactionStore.accounts,
            transactions: transactionStore.transactions
        )
        fullyInitialized = true

        // 4. Generate recurring transactions in background (non-blocking)
```

**Step 4: Verify build**

Run: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add AIFinanceManager/ViewModels/AppCoordinator.swift
git commit -m "feat(coordinator): add fastPathDone + fullyInitialized observable loading stage outputs"
```

---

## Task 4: Update ContentView — per-section skeleton loading

**Files:**
- Modify: `AIFinanceManager/Views/Home/ContentView.swift`

This task has 4 sub-steps: (a) remove `isInitializing`, (b) update `body` ZStack → direct, (c) update `mainContent`, (d) replace `initializeIfNeeded`, (e) remove `loadingOverlay`, (f) add private skeleton structs.

**Step 1: Remove @State private var isInitializing = true (line 21)**

Delete line:
```swift
@State private var isInitializing = true
```

**Step 2: Update body — remove ZStack, keep mainContent directly**

Current (lines 47–49):
```swift
ZStack {
    mainContent
    loadingOverlay
}
```

New (remove ZStack, use mainContent directly):
```swift
mainContent
```

**Step 3: Update mainContent — add .skeletonLoading on 4 sections**

Current `mainContent`:
```swift
private var mainContent: some View {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            accountsSection
            historyNavigationLink
            subscriptionsNavigationLink
            categoriesSection
            errorSection
        }
        .padding(.vertical, AppSpacing.md)
    }
    // No opacity modifier — content visible immediately
}
```

New `mainContent`:
```swift
private var mainContent: some View {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            accountsSection
                .skeletonLoading(isLoading: !coordinator.fastPathDone) {
                    AccountsCarouselSkeleton()
                }
            historyNavigationLink
                .skeletonLoading(isLoading: !coordinator.fullyInitialized) {
                    SectionCardSkeleton()
                        .screenPadding()
                }
            subscriptionsNavigationLink
                .skeletonLoading(isLoading: !coordinator.fullyInitialized) {
                    SectionCardSkeleton()
                        .screenPadding()
                }
            categoriesSection
                .skeletonLoading(isLoading: !coordinator.fastPathDone) {
                    SectionCardSkeleton()
                        .screenPadding()
                }
            errorSection
        }
        .padding(.vertical, AppSpacing.md)
    }
}
```

**Step 4: Replace .task modifier and remove initializeIfNeeded()**

Current `.task` modifier (line 57):
```swift
.task { await initializeIfNeeded() }
```

New `.task` modifier (AppCoordinator guards prevent double-init):
```swift
.task {
    await coordinator.initializeFastPath()
    await coordinator.initialize()
}
```

Delete the entire `initializeIfNeeded()` function:
```swift
private func initializeIfNeeded() async {
    guard isInitializing else { return }
    // Phase 28-A: Fast path — show UI with account cards immediately (~50ms)
    await coordinator.initializeFastPath()
    withAnimation(.easeOut(duration: 0.2)) {
        isInitializing = false
    }
    // Full load continues in background — @Observable updates UI when ready
    await coordinator.initialize()
}
```

**Step 5: Remove loadingOverlay computed property**

Delete the entire `loadingOverlay` property:
```swift
@ViewBuilder
private var loadingOverlay: some View {
    if isInitializing {
        ContentViewSkeleton()
//                .background(Color(.systemGroupedBackground))
            .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
//                .ignoresSafeArea()
    }
}
```

**Step 6: Add private skeleton structs at the bottom of the file (before #Preview)**

Add before the `#Preview` block:

```swift
// MARK: - Skeleton Components

/// Accounts carousel skeleton: 3 cards (200×120) in horizontal scroll.
private struct AccountsCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView(height: 120, cornerRadius: AppRadius.md)
                        .frame(width: 200)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xs)
        }
    }
}

/// Generic section card skeleton: icon circle + 2 text lines.
/// Used for TransactionsSummaryCard, SubscriptionsCard, and QuickAdd skeletons.
private struct SectionCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            SkeletonView(width: 36, height: 36, cornerRadius: AppRadius.circle)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 140, height: 14)
                SkeletonView(width: 100, height: 12, cornerRadius: AppRadius.xs)
            }
            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}
```

**Step 7: Verify build**

Run: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 8: Commit**

```bash
git add AIFinanceManager/Views/Home/ContentView.swift
git commit -m "feat(content): per-element skeleton loading — remove isInitializing, add skeletonLoading on 4 sections"
```

---

## Task 5: Delete ContentViewSkeleton.swift

**Files:**
- Delete: `AIFinanceManager/Views/Components/ContentViewSkeleton.swift`

**Step 1: Remove the file from Xcode project and disk**

Run: `rm AIFinanceManager/Views/Components/ContentViewSkeleton.swift`

Then open Xcode and remove the reference (or use xcodebuild to verify it's no longer referenced):

Run: `grep -r "ContentViewSkeleton" AIFinanceManager/`

Expected: **no output** (no remaining references)

**Step 2: Verify build still succeeds**

Run: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

Note: If build fails with "file not found in project", you need to remove the file reference from the `.xcodeproj`. Run:
```bash
# Check if file is still referenced in pbxproj
grep -n "ContentViewSkeleton" AIFinanceManager.xcodeproj/project.pbxproj
```
If referenced, remove those lines from `project.pbxproj`. The file has one `/* ContentViewSkeleton.swift */` line in the Build Sources section and one in the file references section — both need removal.

**Step 3: Commit**

```bash
git add -A
git commit -m "feat(skeleton): delete ContentViewSkeleton.swift — replaced by per-element SectionCardSkeleton in ContentView"
```

---

## Task 6: Rename InsightsSkeleton.swift → InsightsSkeletonComponents.swift

**Files:**
- Delete: `AIFinanceManager/Views/Components/InsightsSkeleton.swift`
- Create: `AIFinanceManager/Views/Components/InsightsSkeletonComponents.swift`

**Step 1: Create InsightsSkeletonComponents.swift**

Write the new file — key changes vs InsightsSkeleton.swift:
- Remove `InsightsSkeleton` struct (full-screen wrapper — no longer needed)
- Remove `InsightsSkeleton` preview
- Change `InsightsSummaryHeaderSkeleton` from `private struct` → `struct` (internal — used by InsightsView)
- Change `InsightCardSkeleton` from `private struct` → `struct` (internal — used by InsightsView)
- Add new `InsightsFilterCarouselSkeleton` struct (extracted from InsightsSkeleton inline code)

```swift
//
//  InsightsSkeletonComponents.swift
//  AIFinanceManager
//
//  Per-element skeleton components for InsightsView (Phase 30)
//  Replaces InsightsSkeleton.swift — components are now used independently via .skeletonLoading

import SwiftUI

// MARK: - InsightsSummaryHeaderSkeleton

/// Summary header skeleton: 3 metric columns + health score row.
struct InsightsSummaryHeaderSkeleton: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // 3 metric columns (Income / Expenses / Net Flow)
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: AppSpacing.xs) {
                        SkeletonView(height: 11, cornerRadius: AppRadius.xs)
                        SkeletonView(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
                .opacity(0.3)

            // Health score row
            HStack {
                SkeletonView(width: 150, height: 13, cornerRadius: AppRadius.compact)
                Spacer()
                SkeletonView(width: 64, height: 22, cornerRadius: AppRadius.md)
            }
        }
        .padding(AppSpacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - InsightsFilterCarouselSkeleton

/// Filter carousel skeleton: 4 chip placeholders.
struct InsightsFilterCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonView(width: 70, height: 30, cornerRadius: AppRadius.pill)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

// MARK: - InsightCardSkeleton

/// Single insight card skeleton: icon circle + 3 text lines + trailing chart rect.
struct InsightCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon circle
            SkeletonView(width: 40, height: 40, cornerRadius: AppRadius.circle)

            // Text content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 160, height: 13)
                SkeletonView(width: 100, height: 11, cornerRadius: AppRadius.xs)
                SkeletonView(width: 120, height: 19, cornerRadius: AppRadius.sm)
            }

            Spacer()

            // Chart placeholder
            SkeletonView(width: AppIconSize.budgetRing, height: AppIconSize.xxxl, cornerRadius: AppRadius.sm)
        }
        .padding(AppSpacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - Preview

#Preview("Skeleton Components") {
    VStack(spacing: AppSpacing.lg) {
        InsightsSummaryHeaderSkeleton()
        InsightsFilterCarouselSkeleton()
        InsightCardSkeleton()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
```

**Step 2: Delete InsightsSkeleton.swift**

Run: `rm AIFinanceManager/Views/Components/InsightsSkeleton.swift`

**Step 3: Check for any remaining InsightsSkeleton references**

Run: `grep -r "InsightsSkeleton\b" AIFinanceManager/`

Expected output: only the `InsightsSkeleton()` reference in `InsightsView.swift:loadingView` — which will be removed in Task 7.

**Step 4: Update Xcode project**

If needed, remove `InsightsSkeleton.swift` reference and add `InsightsSkeletonComponents.swift` to the project. Verify:
```bash
grep -n "InsightsSkeleton" AIFinanceManager.xcodeproj/project.pbxproj
```

**Step 5: Verify build (expect 1 error for InsightsSkeleton() in InsightsView — ok, fixed in Task 7)**

Run: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | grep -E "error:|BUILD"`

Expected: Build error about `InsightsSkeleton` in InsightsView (expected — fixed next task). `InsightsSummaryHeaderSkeleton`, `InsightCardSkeleton`, `InsightsFilterCarouselSkeleton` should resolve fine.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat(skeleton): rename InsightsSkeleton→InsightsSkeletonComponents, make structs internal, add InsightsFilterCarouselSkeleton"
```

---

## Task 7: Update InsightsView — per-section skeleton loading

**Files:**
- Modify: `AIFinanceManager/Views/Insights/InsightsView.swift`

**Step 1: Restructure the body VStack**

Current body (lines 26–63):
```swift
VStack(spacing: AppSpacing.xl) {
    if insightsViewModel.isLoading {
        loadingView
    } else if !insightsViewModel.hasData {
        emptyState
    } else {
        NavigationLink(destination: ...) { InsightsSummaryHeader(...) ... }
        .buttonStyle(.plain)
        categoryFilterCarousel
        insightSections
    }
}
.padding(.vertical, AppSpacing.md)
.animation(.spring(response: 0.4), value: insightsViewModel.isLoading)
```

New body VStack:
```swift
VStack(spacing: AppSpacing.xl) {
    if !insightsViewModel.isLoading && !insightsViewModel.hasData {
        emptyState
    } else {
        insightsSummaryHeaderSection
        insightsFilterSection
        insightsSectionsSection
    }
}
.padding(.vertical, AppSpacing.md)
.animation(.spring(response: 0.4), value: insightsViewModel.isLoading)
```

**Step 2: Add insightsSummaryHeaderSection computed property**

Add after the existing `categoryFilterCarousel` property (after line 128):

```swift
// MARK: - Summary Header Section

private var insightsSummaryHeaderSection: some View {
    NavigationLink(destination: InsightsSummaryDetailView(
        totalIncome: insightsViewModel.totalIncome,
        totalExpenses: insightsViewModel.totalExpenses,
        netFlow: insightsViewModel.netFlow,
        currency: insightsViewModel.baseCurrency,
        periodDataPoints: insightsViewModel.periodDataPoints,
        granularity: insightsViewModel.currentGranularity
    )) {
        InsightsSummaryHeader(
            totalIncome: insightsViewModel.totalIncome,
            totalExpenses: insightsViewModel.totalExpenses,
            netFlow: insightsViewModel.netFlow,
            currency: insightsViewModel.baseCurrency,
            periodDataPoints: insightsViewModel.periodDataPoints,
            healthScore: insightsViewModel.healthScore
        )
        .screenPadding()
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .skeletonLoading(isLoading: insightsViewModel.isLoading) {
        InsightsSummaryHeaderSkeleton()
            .padding(.horizontal, AppSpacing.lg)
    }
}
```

**Step 3: Add insightsFilterSection computed property**

```swift
// MARK: - Filter Section

private var insightsFilterSection: some View {
    categoryFilterCarousel
        .skeletonLoading(isLoading: insightsViewModel.isLoading) {
            InsightsFilterCarouselSkeleton()
        }
}
```

**Step 4: Add insightsSectionsSection computed property**

```swift
// MARK: - Content Sections

private var insightsSectionsSection: some View {
    insightSections
        .skeletonLoading(isLoading: insightsViewModel.isLoading) {
            VStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    InsightCardSkeleton()
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
}
```

**Step 5: Remove loadingView property**

Delete:
```swift
// MARK: - Loading View

private var loadingView: some View {
    InsightsSkeleton()
        .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
}
```

**Step 6: Verify build**

Run: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

**Step 7: Commit**

```bash
git add AIFinanceManager/Views/Insights/InsightsView.swift
git commit -m "feat(insights): per-element skeleton loading — insightsSummaryHeaderSection + insightsFilterSection + insightsSectionsSection"
```

---

## Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Phase 30 entry**

In the "Recent Refactoring Phases" section, add Phase 30 entry BEFORE Phase 29:

```markdown
**Phase 30** (2026-02-23): Per-Element Skeleton Loading
- **Root cause fixed**: Phase 29 skeleton had 3 bugs — background commented out (skeleton transparent), shimmer dismissed after ~50ms (fast-path duration = shimmer never visible), `.blendMode(.screen)` on light gray imperceptible
- **SkeletonLoadingModifier**: New `Views/Components/SkeletonLoadingModifier.swift` — `View.skeletonLoading(isLoading:skeleton:)` universal per-element modifier. `Group { if isLoading { skeleton() } else { content } }` with `.spring(response: 0.4)` animation.
- **AppCoordinator**: `private(set) var fastPathDone = false` (set after initializeFastPath) + `private(set) var fullyInitialized = false` (set after balance registration in initialize). Observable outputs for UI binding.
- **ContentView**: Removed `isInitializing`/`loadingOverlay`/`initializeIfNeeded`. ZStack → direct mainContent. 4 sections use `.skeletonLoading`: accountsSection(`!fastPathDone`) + historyNavigationLink(`!fullyInitialized`) + subscriptionsNavigationLink(`!fullyInitialized`) + categoriesSection(`!fastPathDone`). Private `AccountsCarouselSkeleton` + `SectionCardSkeleton` structs.
- **ContentViewSkeleton.swift**: Deleted (full-screen approach replaced)
- **InsightsView**: Restructured if/else → `insightsSummaryHeaderSection` + `insightsFilterSection` + `insightsSectionsSection` computed properties each using `.skeletonLoading(isLoading: insightsViewModel.isLoading)`
- **InsightsSkeleton.swift → InsightsSkeletonComponents.swift**: Renamed; `InsightsSkeleton` full-screen struct deleted; `InsightsSummaryHeaderSkeleton`/`InsightCardSkeleton` made internal; new `InsightsFilterCarouselSkeleton` extracted
- **Shimmer fixes**: phase -1.0→-0.5 (immediate visibility), end 2.0→1.5, opacity 0.3→0.5, removed `.blendMode(.screen)`
- Design doc: `docs/plans/2026-02-23-per-element-skeleton-design.md`
```

**Step 2: Update "Last Updated" line at bottom of CLAUDE.md**

Change phase note to mention Phase 30.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Phase 30 per-element skeleton loading"
```

---

## Verification

After all 8 tasks are complete:

1. Run full build: `xcodebuild build -scheme AIFinanceManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' 2>&1 | tail -3`
   - Expected: `** BUILD SUCCEEDED **`

2. Check no old references remain:
   ```bash
   grep -r "ContentViewSkeleton\|InsightsSkeleton()\|isInitializing\|loadingOverlay\|initializeIfNeeded" AIFinanceManager/
   ```
   Expected: **no output**

3. Check new components exist:
   ```bash
   grep -r "skeletonLoading\|fastPathDone\|fullyInitialized" AIFinanceManager/ | grep -v ".xcodeproj"
   ```
   Expected: multiple matches in ContentView.swift, InsightsView.swift, AppCoordinator.swift
