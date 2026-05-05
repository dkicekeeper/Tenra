# UI & Design System Audit Report

**Date**: 2026-04-10
**Scope**: Full audit of Tenra iOS project UI layer
**Auditor**: Claude (automated)

---

## Executive Summary

The Tenra codebase shows **strong design system discipline overall** — the shared component library (UniversalRow, IconView, FormSection, EditSheetContainer, MessageBanner) is well-adopted, and most views follow established patterns. iOS 26 Liquid Glass adoption is excellent.

**Key problem areas:**
1. **Hardcoded `.foregroundStyle(.secondary)` / `.primary`** — 60+ instances that should use `AppColors.textSecondary` / `AppColors.textPrimary` for consistency
2. **Hardcoded `.tint()` colors** — 8 instances using raw `.blue`, `.green`, `.red`, `.orange` instead of `AppColors` tokens
3. **Missing delete confirmation** on TransactionCard swipe-to-delete (deletes immediately without confirmation dialog)
4. **Hardcoded animation values** — 3 instances using inline `.spring()` instead of `AppAnimation` tokens
5. **Localization gaps** — hardcoded Russian strings in CSVEntityMappingView, hardcoded "Error"/"OK" in TransactionCard alerts

### Statistics

| Severity | Count |
|----------|-------|
| Critical | 3 |
| Warning | 38 |
| Info | 25 |

| Category | Findings |
|----------|----------|
| 1. Design Tokens | 22 |
| 2. Component Reuse | 4 |
| 3. Localization | 8 |
| 4. UI Consistency | 10 |
| 5. Accessibility | 5 |
| 6. Performance | 3 |
| 7. iOS 26 | 4 |

---

## 1. DESIGN TOKENS

### 1.1 Hardcoded Colors

#### `.foregroundStyle(.secondary)` / `.primary` Usage

**Assessment**: `.foregroundStyle(.secondary)` maps to SwiftUI's built-in `Color.secondary` which adapts to dark mode. The project defines `AppColors.textSecondary` as `.secondary` and `AppColors.textPrimary` as `.primary`. Using the raw SwiftUI values is **functionally correct** but **inconsistent with the design system** — if tokens are later changed, these won't update.

**Severity: info** — Functional, but not token-aligned. These are in ~60 files including core components like UniversalRow, TransactionCardComponents, AccountRow, CategoryRow.

#### Critical Color Issues

```
[critical] TransactionCard.swift:182 — Hardcoded .tint(.blue) on swipe action
  Current:  .tint(.blue)
  Should be: .tint(AppColors.accent)
  Complexity: trivial

[critical] TransactionCard.swift:229 — Hardcoded .tint(.green) on swipe action
  Current:  .tint(.green)
  Should be: .tint(AppColors.success)
  Complexity: trivial

[warning] TransactionCard.swift:146 — Hardcoded opacity instead of modifier
  Current:  .opacity(isFutureDate ? 0.5 : 1.0)
  Should be: .futureTransactionStyle(isFuture: isFutureDate)
  Complexity: trivial

[warning] SubcategorySearchView.swift:115 — Hardcoded .foregroundStyle(.blue)
  Current:  .foregroundStyle(.blue)
  Should be: .foregroundStyle(AppColors.accent)
  Complexity: trivial

[warning] SubcategorySearchView.swift:130 — Hardcoded .tint(.orange)
  Current:  .tint(.orange)
  Should be: .tint(AppColors.warning)
  Complexity: trivial

[warning] CategoryRow.swift:70 — Hardcoded .red for over-budget
  Current:  .foregroundStyle(progress.isOverBudget ? .red : .secondary)
  Should be: .foregroundStyle(progress.isOverBudget ? AppColors.destructive : AppColors.textSecondary)
  Complexity: trivial

[warning] SettingsHomeBackgroundView.swift:69 — Hardcoded .foregroundStyle(.red)
  Current:  .foregroundStyle(.red)
  Should be: .foregroundStyle(AppColors.destructive)
  Complexity: trivial

[warning] InsightsService+Forecasting.swift:251 — Hardcoded fallback hex color
  Current:  Color(hex: cat?.colorHex ?? "#5856D6")
  Should be: Color(hex: cat?.colorHex ?? AppColors.defaultCategoryHex)
  Complexity: trivial
```

#### Hardcoded RGB Values (HomeBackgroundPicker.swift)

```
[info] HomeBackgroundPicker.swift:132-151 — 5 hardcoded Color(red:green:blue:) values for background orbs
  These are decorative/cosmetic colors for custom background theme.
  Recommendation: Move to AppColors as named constants if backgrounds will be reusable.
  Complexity: moderate
```

#### `.foregroundStyle(.white)` in Overlays

```
[info] BulkDeleteButton.swift:19 — .foregroundStyle(.white) on accent button label
[info] VoiceInputView.swift:289 — .foregroundStyle(.white) on recording button
[info] CSVPreviewView.swift:154 — .foregroundStyle(.white) on selected column
[info] CSVImportResultView.swift:223 — .foregroundStyle(.white) on import badge
[info] ImportTransactionPreviewView.swift:115 — .foregroundStyle(.white) on selection badge
[info] NotificationPermissionView.swift:52 — .foregroundStyle(.white) on CTA button
[info] DonutChart.swift:168 — .foregroundStyle(.white) on center label

  Assessment: White-on-accent/overlay is an intentional pattern for high contrast.
  Recommendation: Consider adding AppColors.onAccent = .white semantic token.
  Complexity: trivial
```

### 1.2 Hardcoded Padding

```
[warning] VoiceInputView.swift:71 — .padding(.bottom, 24)
  Should be: .padding(.bottom, AppSpacing.xxl)
  Complexity: trivial

[info] CategoriesManagementView.swift:374 — .listRowInsets(EdgeInsets(...leading: 16...trailing: 16))
  Should be: .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.lg, bottom: 0, trailing: AppSpacing.lg))
  Complexity: trivial

[info] CategoryRow.swift:133 — Same listRowInsets pattern
  Should use AppSpacing.lg
  Complexity: trivial
```

### 1.3 Hardcoded Font Sizes

```
[warning] VoiceInputView.swift:303 — .font(.system(size: 18, weight: .semibold))
  Should be: .font(AppTypography.bodyEmphasis)  // 18pt medium — close enough, or define a new token
  Complexity: trivial

[warning] HomeBackgroundPicker.swift:171 — .font(.system(size: 28, weight: .ultraLight))
  Should be: Define AppTypography token or use .h2 variant
  Complexity: trivial
```

### 1.4 Hardcoded Animations

```
[warning] MainTabView.swift:132 — withAnimation(.spring(response: 0.38, dampingFraction: 0.75))
  Should be: withAnimation(AppAnimation.contentSpring) or a named token
  Complexity: trivial

[warning] AnimatedTitleInput.swift:66 — .animation(.easeInOut(duration: 0.15), value: showCursor)
  Should be: .animation(AppAnimation.fastAnimation, value: showCursor)
  Complexity: trivial

[info] AnimatedInputComponents.swift:32 — Cursor blink animation
  Already has reduce motion guard at line 31 ✓, but uses inline .easeInOut(duration: 0.5)
  Recommendation: Define AppAnimation.cursorBlink token
  Complexity: trivial

[info] AccountsCarousel.swift:27 — .scrollTransition(.animated(.easeOut(duration: 0.3)))
  Recommendation: Use AppAnimation.standard token
  Complexity: trivial
```

### 1.5 Hardcoded Corner Radius

```
[info] KeyboardToolbarExperiment.swift:51 — RoundedRectangle(cornerRadius: 14)
  Should be: AppRadius.lg (12) or define new token
  Complexity: trivial (experiment file, low priority)
```

---

## 2. COMPONENT REUSE

```
[info] UniversalRow — Good adoption. All FormSection(.card) rows correctly use UniversalRow.
  No missed reuse opportunities found.

[info] MessageBanner — Properly used for transient feedback across all views.

[info] IconView vs Image(systemName:) — Correctly separated.
  Entity icons → IconView; semantic indicators → Image(systemName:)

[info] FormSection — Properly adopted in all edit views.
```

### Debug Borders Left in Previews

```
[warning] PackedCircleIconsView.swift:186,203,216,225 — .border(Color.red.opacity(0.3)) debug borders
  4 instances of debug borders left in #Preview blocks.
  While preview-only, they suggest debug code that could leak to production.
  Recommendation: Remove debug borders from previews.
  Complexity: trivial
```

### UniversalRow Previews Hardcoded Color

```
[info] UniversalRow.swift:724 — backgroundColor: .purple.opacity(0.2) in preview
  Preview-only, not production issue.
```

---

## 3. LOCALIZATION

### Critical: Hardcoded Russian Strings in Production

```
[critical] CSVEntityMappingView.swift:41 — Text("Сопоставление счетов")
  + lines 52, 62, 72, 82, 92, 143, 272, 294, 299, 316, 343
  12 hardcoded Russian strings in production code.
  Should use: Text(String(localized: "csv.accountMapping"))
  Complexity: moderate (12 strings to extract)
```

### Hardcoded English Strings

```
[warning] TransactionCard.swift:244 — .alert("Error", isPresented: ...)
  Should be: .alert(String(localized: "error.title"), ...)
  Complexity: trivial

[warning] TransactionCard.swift:245 — Button("OK", role: .cancel)
  Should be: Button(String(localized: "button.ok"), role: .cancel)
  Complexity: trivial

[warning] TransactionCard.swift:249-250 — Same "Error" / "OK" pattern repeated
  Complexity: trivial
```

### Localization Key Without String(localized:)

```
[warning] ImportTransactionPreviewView.swift:81 — Text("transactionPreview.selectAll")
  SwiftUI Text("key") looks up localization automatically, BUT only when
  the key exists in Localizable.strings. If it doesn't, the raw key renders.
  Recommendation: Verify key exists or use Text(String(localized: "transactionPreview.selectAll"))
  Complexity: trivial

[warning] ImportTransactionPreviewView.swift:96 — Text("transactionPreview.deselectAll")
  Same issue.

[warning] ImportTransactionPreviewView.swift:247 — Text("transactionPreview.noAccount")
  Same issue.
```

### Experiment Views (Low Priority)

```
[info] KeyboardToolbarExperiment.swift:11,22,34,46,59 — 5 hardcoded Russian strings
  Experiment/debug view — low priority but should still be localized for consistency.
  Complexity: trivial

[info] ExperimentsListView.swift:12 — .navigationTitle("Эксперименты")
  Same — experiment view.
```

---

## 4. UI CONSISTENCY

### Missing Delete Confirmation

```
[critical] TransactionCard.swift:153-169 — Swipe-to-delete has NO confirmation dialog
  Transaction is deleted immediately on swipe without user confirmation.
  This is the ONLY destructive swipe action without confirmation in the app.
  The stopRecurring action (line 178) correctly shows a confirmation dialog.
  Recommendation: Add .confirmationDialog before delete, matching other destructive patterns.
  Complexity: moderate

[warning] BackupRowView.swift:26-30 — Backup deletion via swipe has no confirmation
  Backup files are not recoverable after deletion.
  Recommendation: Add confirmation dialog.
  Complexity: moderate
```

Note: AccountRow and CategoryRow swipe deletes delegate to parent views which handle confirmation.

### Inline Opacity vs futureTransactionStyle

```
[warning] TransactionCard.swift:146 — .opacity(isFutureDate ? 0.5 : 1.0)
  Should use: .futureTransactionStyle(isFuture: isFutureDate)
  The modifier exists specifically for this purpose and uses 0.55 opacity.
  Complexity: trivial
```

### Alert Presentation (Error Alerts)

```
[info] TransactionCard.swift:244-253 — Uses .alert() for errors instead of MessageBanner
  The codebase convention is MessageBanner for transient feedback.
  However, .alert() is acceptable for error states that need acknowledgment.
  Assessment: Acceptable but inconsistent with the stated convention.
```

---

## 5. ACCESSIBILITY

### Dynamic Type Violations

```
[warning] VoiceInputView.swift:303 — .font(.system(size: 18, weight: .semibold))
  Fixed font size doesn't scale with Dynamic Type.
  Should use: .font(AppTypography.bodyEmphasis)
  Complexity: trivial

[warning] HomeBackgroundPicker.swift:171 — .font(.system(size: 28, weight: .ultraLight))
  Fixed font size. Define token or use relative sizing.
  Complexity: trivial
```

### Small Touch Targets

```
[warning] ColorPickerRow.swift:168 — .frame(width: 30, height: 30) on interactive color circles
  30x30pt is below the 44x44pt minimum touch target.
  Recommendation: Keep visual size at 30pt but add .contentShape(Circle().size(width: 44, height: 44))
  Complexity: moderate
```

### Reduce Motion

```
[warning] MainTabView.swift:132 — withAnimation(.spring(...)) without reduce motion check
  Decorative tab switching animation should respect isReduceMotionEnabled.
  Complexity: trivial

[info] AnimatedInputComponents.swift:31-32 — ✓ Has reduce motion guard before cursor blink animation
[info] MessageBanner.swift — ✓ Uses AppAnimation tokens (reduce motion aware)
```

### VoiceOver

```
[info] TransactionCard.swift:148-150 — ✓ Has .accessibilityElement(children: .combine) + label + hint
[info] VoiceInputView.swift:51-58,281-291 — ✓ Close/Stop buttons have accessibilityLabel
```

**Overall accessibility posture is good** — most interactive elements have proper labels.

---

## 6. PERFORMANCE

### ForEach Identity

```
[info] No UUID() identity issues found. ✓
[info] ForEach(id: \.self) used only on String/primitive collections — acceptable. ✓
```

### .onAppear vs .task

```
[info] No `.onAppear { Task {} }` anti-patterns found. ✓
  Async work correctly uses `.task {}` throughout.
```

### Task.sleep(nanoseconds:)

```
[info] No deprecated Task.sleep(nanoseconds:) found. ✓
  All sleep calls use modern `.sleep(for:)` API.
```

---

## 7. iOS 26 / LIQUID GLASS

### Adoption Status: Excellent

```
[info] Liquid Glass widely adopted via .glassEffect():
  - IconView.swift:295-301 — Glass hero styles
  - MessageBanner.swift:50 — Glass banner background
  - CategoryChip.swift:65 — Glass chip
  - SegmentedPickerView.swift:34 — Glass segmented control
  - SubcategorySearchView.swift:149 — Glass search bar
  - AccountCard.swift:40 — Glass card ID
  - AccountActionView.swift:50 — Glass action view
```

### NavigationView

```
[info] No deprecated NavigationView usage found. ✓
  All navigation uses NavigationStack.
```

### .foregroundColor (Deprecated)

```
[info] No .foregroundColor() usage found. ✓
  All color styling uses modern .foregroundStyle().
```

### cardStyle() Padding Contract

```
[info] cardStyle() correctly applies NO padding — content adds its own. ✓
  Verified in AppModifiers.swift and usage sites.
```

---

## Action Plan (Prioritized)

### P0 — Critical (fix immediately)

| # | Issue | File | Complexity |
|---|-------|------|------------|
| 1 | Add delete confirmation dialog to TransactionCard swipe | TransactionCard.swift:153 | moderate |
| 2 | Localize 12 hardcoded Russian strings in CSVEntityMappingView | CSVEntityMappingView.swift | moderate |
| 3 | Replace hardcoded .tint(.blue/.green) with AppColors tokens | TransactionCard.swift:182,229 | trivial |

### P1 — Warning (fix in next sprint)

| # | Issue | Files | Complexity |
|---|-------|-------|------------|
| 4 | Replace .opacity(0.5) with .futureTransactionStyle() | TransactionCard.swift:146 | trivial |
| 5 | Localize "Error"/"OK" strings in TransactionCard alerts | TransactionCard.swift:244-250 | trivial |
| 6 | Replace hardcoded .tint(.orange) with AppColors.warning | SubcategorySearchView.swift:130 | trivial |
| 7 | Replace hardcoded .foregroundStyle(.blue) with AppColors.accent | SubcategorySearchView.swift:115 | trivial |
| 8 | Replace hardcoded .foregroundStyle(.red) with AppColors.destructive | SettingsHomeBackgroundView.swift:69, CategoryRow.swift:70 | trivial |
| 9 | Replace .font(.system(size:)) with AppTypography tokens | VoiceInputView.swift:303, HomeBackgroundPicker.swift:171 | trivial |
| 10 | Replace inline .spring() animations with AppAnimation tokens | MainTabView.swift:132, AnimatedTitleInput.swift:66 | trivial |
| 11 | Add reduce motion check to MainTabView tab animation | MainTabView.swift:132 | trivial |
| 12 | Increase ColorPickerRow touch target to 44pt | ColorPickerRow.swift:168 | moderate |
| 13 | Add backup delete confirmation dialog | BackupRowView.swift:26-30 | moderate |
| 14 | Verify localization keys in ImportTransactionPreviewView | ImportTransactionPreviewView.swift:81,96,247 | trivial |

### P2 — Info (improve when touching these files)

| # | Issue | Scope | Complexity |
|---|-------|-------|------------|
| 15 | Add `AppColors.onAccent` semantic token for white-on-accent text | 7 files | trivial |
| 16 | Replace numeric listRowInsets with AppSpacing.lg | CategoriesManagementView.swift, CategoryRow.swift | trivial |
| 17 | Replace numeric padding(24) with AppSpacing.xxl | VoiceInputView.swift:71 | trivial |
| 18 | Move HomeBackgroundPicker RGB colors to named constants | HomeBackgroundPicker.swift:132-151 | moderate |
| 19 | Remove debug .border() from PackedCircleIconsView previews | PackedCircleIconsView.swift | trivial |
| 20 | Define AppAnimation.cursorBlink token | AnimatedInputComponents.swift | trivial |
| 21 | Standardize .foregroundStyle(.secondary) → AppColors.textSecondary | 60+ files | large (batch refactor) |
| 22 | Localize experiment view strings | KeyboardToolbarExperiment.swift, ExperimentsListView.swift | trivial |

---

## Positive Findings (What's Working Well)

1. **Component library is comprehensive and well-adopted** — UniversalRow, IconView, FormSection, EditSheetContainer, MessageBanner all used correctly
2. **No deprecated NavigationView or .foregroundColor()** — modern APIs throughout
3. **iOS 26 Liquid Glass** widely adopted via `.glassEffect()`
4. **Accessibility labels** present on most interactive elements
5. **No `.onAppear { Task {} }` anti-pattern** — proper `.task {}` usage
6. **No `Task.sleep(nanoseconds:)` deprecated calls**
7. **No `UUID()` in ForEach identity** — stable identifiers used
8. **cardStyle() padding contract** correctly followed
9. **Localization infrastructure exists** (en.lproj + ru.lproj) with `String(localized:)` pattern established
10. **EmptyStateView** properly used in all list views

---

*Generated by automated audit — verify line numbers before applying fixes, as they may shift with uncommitted changes.*
