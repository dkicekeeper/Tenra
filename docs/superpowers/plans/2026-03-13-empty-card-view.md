# EmptyCardView Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 3 duplicate "card with header + compact empty state" implementations with a single `EmptyCardView` component.

**Architecture:** New `EmptyCardView` in `Views/Components/Cards/` encapsulates the pattern: section title (h3) + `EmptyStateView(.compact)` + card chrome (`.padding(.lg).cardStyle()`), with an optional `action` closure that wraps the card in a tappable `Button`. `EmptyAccountsPrompt.swift` is deleted; `TransactionsSummaryCard` and `CategoryGridView` migrate their inline empty state vars to `EmptyCardView`.

**Tech Stack:** SwiftUI, existing design tokens (`AppSpacing`, `AppTypography`, `AppRadius`, `AppAnimation`)

---

### Task 1: Create `EmptyCardView.swift`

**Files:**
- Create: `Tenra/Views/Components/Cards/EmptyCardView.swift`

**Step 1: Create the file**

```swift
//
//  EmptyCardView.swift
//  Tenra
//
//  Universal card component for section empty states.
//  Shows a section title + compact empty message, optionally tappable.
//

import SwiftUI

/// Card with a section header and compact empty state.
///
/// Use when a home-screen section has no data yet.
/// Pass `action` to make the entire card tappable (adds account, category, etc.).
///
/// ```swift
/// EmptyCardView(
///     sectionTitle: String(localized: "accounts.title"),
///     emptyTitle: String(localized: "emptyState.noAccounts"),
///     action: { showingAddAccount = true }
/// )
/// .screenPadding()
/// ```
struct EmptyCardView: View {

    let sectionTitle: String
    let emptyTitle: String
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: {
                HapticManager.light()
                action()
            }) {
                cardContent
            }
            .buttonStyle(.bounce)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text(sectionTitle)
                .font(AppTypography.h3)
                .foregroundStyle(.primary)

            EmptyStateView(
                title: emptyTitle,
                style: .compact
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

// MARK: - Preview

#Preview("Tappable") {
    EmptyCardView(
        sectionTitle: String(localized: "accounts.title"),
        emptyTitle: String(localized: "emptyState.noAccounts"),
        action: {}
    )
    .screenPadding()
}

#Preview("Non-tappable") {
    EmptyCardView(
        sectionTitle: String(localized: "analytics.history"),
        emptyTitle: String(localized: "emptyState.noTransactions")
    )
    .screenPadding()
}
```

**Step 2: Build to verify**

```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no errors.

---

### Task 2: Migrate `ContentView.swift` — replace `EmptyAccountsPrompt`

**Files:**
- Modify: `Tenra/Views/Home/ContentView.swift:244`

**Step 1: Replace the call site**

Find (line ~244 in `accountsSection`):
```swift
EmptyAccountsPrompt(onAddAccount: { showingAddAccount = true })
```

Replace with:
```swift
EmptyCardView(
    sectionTitle: String(localized: "accounts.title"),
    emptyTitle: String(localized: "emptyState.noAccounts"),
    action: { showingAddAccount = true }
)
.screenPadding()
```

**Step 2: Build**

```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no errors.

---

### Task 3: Delete `EmptyAccountsPrompt.swift`

**Files:**
- Delete: `Tenra/Views/Components/Feedback/EmptyAccountsPrompt.swift`

**Step 1: Verify no remaining call sites**

```bash
grep -r "EmptyAccountsPrompt" Tenra/ --include="*.swift"
```

Expected: no output (zero matches).

**Step 2: Delete the file**

```bash
rm Tenra/Views/Components/Feedback/EmptyAccountsPrompt.swift
```

**Step 3: Build**

```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no errors.

---

### Task 4: Migrate `TransactionsSummaryCard.swift` — replace `emptyState` var

**Files:**
- Modify: `Tenra/Views/Components/Cards/TransactionsSummaryCard.swift`

**Step 1: Replace the `emptyState` private var**

Find (lines 46–62):
```swift
// MARK: - Empty State
private var emptyState: some View {
    VStack(alignment: .leading, spacing: AppSpacing.lg) {
        HStack {
            Text(String(localized: "analytics.history"))
                .font(AppTypography.h3)
                .foregroundStyle(.primary)
        }

        EmptyStateView(
            title: String(localized: "emptyState.noTransactions"),
            style: .compact
        )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppSpacing.lg)
    .cardStyle()
}
```

Replace with:
```swift
// MARK: - Empty State
private var emptyState: some View {
    EmptyCardView(
        sectionTitle: String(localized: "analytics.history"),
        emptyTitle: String(localized: "emptyState.noTransactions")
    )
}
```

**Step 2: Build**

```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no errors.

---

### Task 5: Migrate `CategoryGridView.swift` — replace action variant

**Files:**
- Modify: `Tenra/Views/Components/Input/CategoryGridView.swift`

**Step 1: Replace the action variant in `emptyState` var**

Find (lines 33–64), the entire `emptyState` var:
```swift
private var emptyState: some View {
    Group {
        if let action = emptyStateAction {
            Button(action: {
                HapticManager.light()
                action()
            }) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack {
                        Text(String(localized: "categories.expenseCategories", defaultValue: "Expense Categories"))
                            .font(AppTypography.h3)
                            .foregroundStyle(.primary)
                    }

                    EmptyStateView(
                        title: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                        style: .compact
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.lg)
                .cardStyle()
            }
            .buttonStyle(.bounce)
        } else {
            EmptyStateView(
                title: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
                style: .compact
            )
        }
    }
}
```

Replace with:
```swift
private var emptyState: some View {
    EmptyCardView(
        sectionTitle: String(localized: "categories.expenseCategories", defaultValue: "Expense Categories"),
        emptyTitle: String(localized: "emptyState.noCategories", defaultValue: "No categories"),
        action: emptyStateAction
    )
}
```

**Step 2: Build**

```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no errors.

---

### Task 6: Final build check + commit

**Step 1: Full build, zero errors**

```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

Expected: no output.

**Step 2: Verify no leftover references**

```bash
grep -r "EmptyAccountsPrompt" Tenra/ --include="*.swift"
```

Expected: no output.

**Step 3: Commit**

```bash
git add \
  Tenra/Views/Components/Cards/EmptyCardView.swift \
  Tenra/Views/Home/ContentView.swift \
  Tenra/Views/Components/Cards/TransactionsSummaryCard.swift \
  Tenra/Views/Components/Input/CategoryGridView.swift
git rm Tenra/Views/Components/Feedback/EmptyAccountsPrompt.swift
git commit -m "refactor: replace duplicate card empty states with EmptyCardView

- Add EmptyCardView to Views/Components/Cards/ — section title + compact
  empty state + card chrome, optionally tappable via action closure
- Delete EmptyAccountsPrompt (1 call site, migrated to EmptyCardView)
- Migrate TransactionsSummaryCard.emptyState var
- Migrate CategoryGridView action-variant emptyState var

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
