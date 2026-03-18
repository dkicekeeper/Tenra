# Skeleton Loading Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `ProgressView()` spinners in ContentView and InsightsView with shape-accurate shimmer skeleton screens that mirror the real layout.

**Architecture:** Three-layer approach — `SkeletonShimmerModifier` (animation engine) → `SkeletonView` (base block) → `ContentViewSkeleton` / `InsightsSkeleton` (composed layouts). Shimmer uses a `LinearGradient` overlay with `phase` animation for a left-to-right Liquid Glass blick effect. Integration replaces existing `loadingOverlay` and `loadingView` computed properties in-place — minimal diff.

**Tech Stack:** SwiftUI (iOS 26+), `@State` animation, `ViewModifier`, `AppSpacing` / `AppRadius` / `AppTypography` design system constants.

**Design doc:** `docs/plans/2026-02-23-skeleton-loading-design.md`

---

## Task 1: Rewrite SkeletonView.swift

**Files:**
- Modify: `AIFinanceManager/Views/Components/SkeletonView.swift` (full rewrite)

### Step 1: Replace file content

Replace the entire file with:

```swift
//
//  SkeletonView.swift
//  AIFinanceManager
//
//  Skeleton loading base component with shimmer animation (Phase 29)

import SwiftUI

// MARK: - Shimmer Modifier

/// Overlays a left-to-right shimmer blick on any view — Liquid Glass style.
struct SkeletonShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.3), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: UnitPoint(x: phase, y: 0.5),
                    endPoint: UnitPoint(x: phase + 1, y: 0.5)
                )
                .blendMode(.plusLighter)
            }
            .clipped()
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
                ) {
                    phase = 2.0
                }
            }
    }
}

extension View {
    /// Adds a left-to-right shimmer animation (Liquid Glass style).
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmerModifier())
    }
}

// MARK: - SkeletonView

/// Base skeleton block. Use width: nil to fill available horizontal space.
struct SkeletonView: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemFill))
            .frame(width: width, height: height)
            .skeletonShimmer()
    }
}

// MARK: - Preview

#Preview("Shimmer") {
    VStack(spacing: 16) {
        SkeletonView(height: 16)
        SkeletonView(width: 200, height: 16)
        SkeletonView(height: 80, cornerRadius: 20)
        SkeletonView(width: 44, height: 44, cornerRadius: 22)
    }
    .padding()
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` — no errors.

### Step 3: Commit

```bash
git add AIFinanceManager/Views/Components/SkeletonView.swift
git commit -m "feat(skeleton): SkeletonShimmerModifier + rewritten SkeletonView (Phase 29)"
```

---

## Task 2: Create ContentViewSkeleton.swift

**Files:**
- Create: `AIFinanceManager/Views/Components/ContentViewSkeleton.swift`

### Step 1: Create the file

```swift
//
//  ContentViewSkeleton.swift
//  AIFinanceManager
//
//  Skeleton loading screen for ContentView — mirrors home screen layout (Phase 29)

import SwiftUI

// MARK: - ContentViewSkeleton

/// Full-screen skeleton that mirrors the home tab layout:
/// filter chip → account cards carousel → 3 section cards.
struct ContentViewSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {

                // MARK: Filter chip
                SkeletonView(width: 110, height: 32, cornerRadius: 16)
                    .padding(.horizontal, AppSpacing.lg)

                // MARK: Account cards carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonView(height: 120, cornerRadius: 20)
                                .frame(width: 200)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.xs)
                }

                // MARK: Section cards (История / Подписки / Категории)
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        ContentSectionCardSkeleton()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDisabled(true)
    }
}

// MARK: - ContentSectionCardSkeleton

/// Single section card skeleton (icon circle + two text lines).
private struct ContentSectionCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon circle
            SkeletonView(width: 36, height: 36, cornerRadius: 18)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Title line
                SkeletonView(width: 140, height: 14)
                // Subtitle line
                SkeletonView(width: 100, height: 12, cornerRadius: 6)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - Preview

#Preview {
    ContentViewSkeleton()
        .background(Color(.systemGroupedBackground))
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

### Step 3: Commit

```bash
git add AIFinanceManager/Views/Components/ContentViewSkeleton.swift
git commit -m "feat(skeleton): ContentViewSkeleton — home screen layout (Phase 29)"
```

---

## Task 3: Create InsightsSkeleton.swift

**Files:**
- Create: `AIFinanceManager/Views/Components/InsightsSkeleton.swift`

### Step 1: Create the file

```swift
//
//  InsightsSkeleton.swift
//  AIFinanceManager
//
//  Skeleton loading screen for InsightsView — mirrors analytics layout (Phase 29)

import SwiftUI

// MARK: - InsightsSkeleton

/// Full-body skeleton that mirrors the analytics tab layout:
/// summary header → filter carousel → section label → 3 insight cards.
struct InsightsSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {

                // MARK: Summary header card
                InsightsSummaryHeaderSkeleton()
                    .padding(.horizontal, AppSpacing.lg)

                // MARK: Filter carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonView(width: 70, height: 30, cornerRadius: 15)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                // MARK: Section header label
                SkeletonView(width: 100, height: 16)
                    .padding(.horizontal, AppSpacing.lg)

                // MARK: Insight cards
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        InsightCardSkeleton()
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDisabled(true)
    }
}

// MARK: - InsightsSummaryHeaderSkeleton

/// Summary header card: 3 metric columns + health score row.
private struct InsightsSummaryHeaderSkeleton: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // 3 metric columns (Доходы / Расходы / Чистый поток)
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: AppSpacing.xs) {
                        SkeletonView(height: 11, cornerRadius: 5)
                        SkeletonView(height: 20, cornerRadius: 7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
                .opacity(0.3)

            // Health score row
            HStack {
                SkeletonView(width: 150, height: 13, cornerRadius: 6)
                Spacer()
                SkeletonView(width: 64, height: 22, cornerRadius: 11)
            }
        }
        .padding(AppSpacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - InsightCardSkeleton

/// Single insight card: icon circle + 3 text lines + trailing chart rect.
private struct InsightCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon circle
            SkeletonView(width: 40, height: 40, cornerRadius: 20)

            // Text content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 160, height: 13)
                SkeletonView(width: 100, height: 11, cornerRadius: 5)
                SkeletonView(width: 120, height: 19, cornerRadius: 8)
            }

            Spacer()

            // Chart placeholder
            SkeletonView(width: 72, height: 48, cornerRadius: 8)
        }
        .padding(AppSpacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: AppRadius.md))
    }
}

// MARK: - Preview

#Preview {
    InsightsSkeleton()
        .background(Color(.systemGroupedBackground))
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

### Step 3: Commit

```bash
git add AIFinanceManager/Views/Components/InsightsSkeleton.swift
git commit -m "feat(skeleton): InsightsSkeleton — analytics screen layout (Phase 29)"
```

---

## Task 4: Integrate ContentViewSkeleton into ContentView

**Files:**
- Modify: `AIFinanceManager/Views/Home/ContentView.swift` — replace `loadingOverlay` body

**Context:** `loadingOverlay` is a `@ViewBuilder private var` at lines 173-192. It currently shows a small top-aligned capsule with `ProgressView`. Replace it with a full-screen skeleton. The existing `.overlay { loadingOverlay }` call site stays unchanged.

### Step 1: Replace loadingOverlay

Find this block in ContentView.swift (lines 173-192):

```swift
@ViewBuilder
private var loadingOverlay: some View {
    if isInitializing {
        VStack {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(String(localized: "progress.loadingData", defaultValue: "Loading data..."))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, AppSpacing.sm)
            Spacer()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
```

Replace with:

```swift
@ViewBuilder
private var loadingOverlay: some View {
    if isInitializing {
        ContentViewSkeleton()
            .background(Color(.systemGroupedBackground))
            .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
            .ignoresSafeArea()
    }
}
```

### Step 2: Build to verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

### Step 3: Commit

```bash
git add AIFinanceManager/Views/Home/ContentView.swift
git commit -m "feat(skeleton): integrate ContentViewSkeleton into ContentView (Phase 29)"
```

---

## Task 5: Integrate InsightsSkeleton into InsightsView

**Files:**
- Modify: `AIFinanceManager/Views/Insights/InsightsView.swift` (or wherever InsightsView.swift lives — find with Glob) — replace `loadingView` body

**Context:** `loadingView` is a `private var` at lines 238-248. It's referenced conditionally at lines 27-28 via `if insightsViewModel.isLoading { loadingView }`. Replace the property body only.

### Step 1: Replace loadingView

Find this block in InsightsView.swift (lines 238-248):

```swift
private var loadingView: some View {
    VStack(spacing: AppSpacing.lg) {
        ProgressView()
            .scaleEffect(1.5)
        Text(String(localized: "insights.loading"))
            .font(AppTypography.body)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, AppSpacing.xxxl)
}
```

Replace with:

```swift
private var loadingView: some View {
    InsightsSkeleton()
        .transition(.opacity.combined(with: .scale(0.98, anchor: .center)))
}
```

### Step 2: Add animation to the isLoading condition

Find the call site (lines 27-28 area):

```swift
if insightsViewModel.isLoading {
    loadingView
}
```

Ensure it's inside a container that has animation. If not already wrapped, add `.animation(.spring(response: 0.4), value: insightsViewModel.isLoading)` to the parent `VStack` or `ScrollView`. Look at the existing parent structure — if it uses `withAnimation` on state change, no modification needed. Otherwise add:

```swift
// On the VStack/Group that contains the if insightsViewModel.isLoading check:
.animation(.spring(response: 0.4), value: insightsViewModel.isLoading)
```

### Step 3: Build to verify

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

### Step 4: Commit

```bash
git add AIFinanceManager/Views/Insights/InsightsView.swift
git commit -m "feat(skeleton): integrate InsightsSkeleton into InsightsView (Phase 29)"
```

---

## Task 6: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` — add Phase 29 section

### Step 1: Add Phase 29 entry

In the "Recent Refactoring Phases" section, add before Phase 28:

```markdown
**Phase 29** (2026-02-23): Skeleton Loading — ContentView & InsightsView
- **SkeletonShimmerModifier**: `ViewModifier` with `@State phase: CGFloat` animation — `LinearGradient` blick sweeps left-to-right in 1.4s, `easeInOut`, `repeatForever`. `.blendMode(.plusLighter)` for Liquid Glass character.
- **SkeletonView**: Base block — `RoundedRectangle` with `Color(.systemFill)` + `.skeletonShimmer()`. `width: nil` fills available space.
- **ContentViewSkeleton**: Mirrors home screen — filter chip + 3 account cards carousel + 3 section cards. Replaces capsule `ProgressView` in `loadingOverlay` (ContentView.swift).
- **InsightsSkeleton**: Mirrors analytics screen — summary header (3 columns + health row) + filter carousel + 3 insight cards with trailing chart rects. Replaces `loadingView` property (InsightsView.swift).
- Transition: `.opacity.combined(with: .scale(0.98))` — subtle zoom-out on content appear.
- New files: `ContentViewSkeleton.swift`, `InsightsSkeleton.swift`. Updated: `SkeletonView.swift`.
```

### Step 2: Commit

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md Phase 29 skeleton loading"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `BUILD SUCCEEDED` with no errors
- [ ] Preview for `ContentViewSkeleton` shows filter chip + 3 cards + 3 sections with shimmer
- [ ] Preview for `InsightsSkeleton` shows header + filter chips + 3 insight cards with shimmer
- [ ] Simulator: launch app → skeleton appears for ~100ms during fast-path init → smooth fade to real content
- [ ] Simulator: tap Insights tab → skeleton appears while `isLoading` → fades to real insights
- [ ] Dark mode: `Color(.systemFill)` is appropriately dark, shimmer still visible
- [ ] No `error:` or `warning:` regressions in build output
