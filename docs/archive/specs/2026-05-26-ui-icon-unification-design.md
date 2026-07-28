# UI Icon Unification + "Транзакция" → "Операция" Rename + Picker Scroll Fix

**Date:** 2026-05-26
**Scope:** Visual consistency pass + Russian terminology change + one navigation bug fix
**Owner:** Daulet

## Goals

1. Replace user-visible Russian word "транзакция" with "операция" across the app.
2. Fix non-scrollable category picker pushed from `AccountDetailView`.
3. Unify icon/logo sizes across account cards, loan cards, subscription cards, and rows (accounts, categories, loans, subscriptions) to 44pt.
4. Make all icons and logos circular for shape consistency.
5. SF Symbol containers gain background colors: `AppColors.bgCard` for generic, soft-tinted category color for category icons.

## Non-Goals

- Renaming Swift identifiers (`Transaction`, `TransactionStore`, etc.).
- Translating English (`en.lproj`) — only Russian is in scope.
- Updating DocC comments / inline code comments containing "транзакц" (user opted to defer).
- Touching hero icons (`glassHero`, `categoryCoin`) — they live on detail views, not in cards/rows.
- Touching `CategoryChip` picker grid coins (custom 64pt glass coin layout — independent system).
- Touching `AccountsCardView` packed circles (auto-sized by container layout, not by IconStyle preset).
- Inline indicator icons in `TransactionCardComponents` at `sm`/`md` sizes (badges, not primary icons).

## Decisions (locked by user)

| Decision | Value |
|---|---|
| SF Symbol container background | `AppColors.bgCard` (since `AppColors.surface` doesn't exist) |
| Unified icon size | 44pt (`AppIconSize.xxl`) for all cards + rows |
| Category icon background style | Soft tint: `bg = color.opacity(0.15)`, `fg = full category color` |
| Brand logos under Circle clip | Yes — circular for all sources for consistency |
| Rename scope | UI strings only (Localizable.strings + inline `String(localized:)`), not code comments |

## Architecture

### 1. Icon system changes (single source of truth)

The codebase has an `IconView(source:size:)` convenience init that auto-picks a preset by source type. By updating the **presets**, all auto-styled call sites pick up the change for free.

**File: `Tenra/Models/IconStyle.swift`**

Modify four semantic presets. Their `shape` field is the only structural change; signatures stay backward-compatible.

| Preset | Before | After |
|---|---|---|
| `categoryIcon(size:)` | Circle, accent tint, no bg | Circle, **optional `backgroundColor` param**; default tint stays `.accentMonochrome` |
| `serviceLogo(size:)` | `RoundedSquare(cornerRadius: AppRadius.md)`, original tint | **Circle**, original tint |
| `serviceLogoLarge(size:)` | `RoundedSquare(cornerRadius: AppRadius.lg)`, original tint | **Circle**, original tint |
| `roundedLogo(size:)` | `RoundedSquare(cornerRadius: AppRadius.md)`, original tint | **Circle**, original tint, `backgroundColor: AppColors.bgCard` (for SF Symbol fallback case via auto-init) |
| `roundedLogoLarge(size:)` | RoundedSquare(cornerRadius: AppRadius.lg), original tint | **Circle**, original tint |
| `placeholder(size:)` | RoundedSquare, `backgroundColor: AppColors.bgCard` | **Circle**, `backgroundColor: AppColors.bgCard` |

Note: `categoryIcon` adds new optional `backgroundColor` param. When the caller wants a category-color tint, they pass `backgroundColor: color.opacity(0.15)` and keep `tint: .monochrome(color)`.

The function names retain their "logo"/"square" semantic identity for future flexibility, but their shape is now Circle.

**File: `Tenra/Views/Components/Icons/IconView.swift`**

Change convenience init default size: `AppIconSize.xl` (32) → `AppIconSize.xxl` (44). This is the **only line change** needed to bring all auto-styled cards/rows to 44pt.

```swift
init(source: IconSource?, size: CGFloat = AppIconSize.xxl) { ... }
```

### 2. Per-call-site size bumps

Even with the new default, several call sites pass an explicit `size: AppIconSize.xl`. Bump these to `.xxl`:

| File | Line | Change |
|---|---|---|
| `Views/Components/Cards/AccountCard.swift` | 22 | `.xl` → `.xxl` |
| `Views/Components/Cards/LoanCard.swift` | 23 | `.xl` → `.xxl` |
| `Views/Components/Rows/AccountRow.swift` | 47 | `.xl` → `.xxl` |
| `Views/Components/Input/AccountRadioButton.swift` | 23 | `.xl` → `.xxl` |

Not changed:
- `TransactionCardComponents.swift` lines 113/133/159 — use `.sm` (16pt) as inline transfer-indicator badges. Out of scope.
- `UniversalFilterButton.swift` — uses `.sm`/`.md` for compact filter chips. Out of scope.
- `HistoryFilterSection.swift` — `.sm` for filter chip. Out of scope.
- `SubscriptionCalendarView.swift` — caller-controlled size for calendar cells. Out of scope.
- `InsightDetailView.swift` — `.lg` (24pt) for insight rows. Out of scope.
- `CSVEntityMappingView.swift` — `.lg` for mapping rows. Out of scope.
- `SubscriptionCard.swift` — already `.xxl` (44pt). Unchanged.

### 3. CategoryRow gets a soft-tint background

**File: `Views/Components/Rows/CategoryRow.swift` (lines 64–70)**

Add `backgroundColor: category.color.opacity(0.15)` parameter to the IconView call. Tint stays `.monochrome(category.color)` (full saturation foreground over soft bg).

The 44pt icon + 52pt budget ring spacing is unchanged.

### 4. Category picker scroll fix

**File: `Views/Components/Input/TransactionCategoryPickerView.swift`**

Wrap `CategoryGridView(...)` in `ScrollView`. The view modifiers (`navigationDestination`, `sheet`, `task`) move outside the `ScrollView`. Padding may be needed inside.

`CategoryGridView` is also used by:
- Insights / category-detail flows (each provides its own scroll container) — UNCHANGED, do not add ScrollView there.

So the scroll wrapper is added at the `TransactionCategoryPickerView` body level only.

### 5. Russian rename

**File: `Tenra/ru.lproj/Localizable.strings`**

Stem-level replace: `транзакц` → `операц`. Both nouns share the same 1st-declension feminine paradigm, so all case endings transfer correctly:
- транзакция → операция, транзакции → операции, транзакций → операций, транзакцию → операцию, транзакцией → операцией, транзакциями → операциями, транзакциях → операциях

Also check for capitalized form `Транзакц` → `Операц` if any (it's the same stem, sed catches it as separate).

**File: `Tenra/Services/ML/MLDataExporter.swift` line 98**

Replace one inline user-facing Russian error string: `"Недостаточно транзакций..."` → `"Недостаточно операций..."`.

**Inline Russian string literals in view code (4 hits, found):**

- `Views/Settings/SettingsView.swift:119` — `Text("...не удалит сами транзакции.")` → `операции`
- `Views/VoiceInput/VoiceInputView.swift:444` — `suffix = "транзакцию"` → `"операцию"`
- `Views/VoiceInput/VoiceInputView.swift:446` — `suffix = "транзакции"` → `"операции"`
- `Views/VoiceInput/VoiceInputView.swift:448` — `suffix = "транзакций"` → `"операций"`

Note: VoiceInputView has Russian plural-suffix logic (1, 2-4, 5+); the stem-level rule preserves it.

**Excluded:**
- All `// ...транзакц...` comments
- DocC `/// ...транзакц...` comments
- Swift identifiers
- ML JSON/CSV column headers (not Russian)
- `Tenra/en.lproj/Localizable.strings` (English unchanged)

## Visual / Behavioral Risks

1. **Brand-logo cropping under Circle clip.** Logos like Kaspi/Halyk/Netflix that were designed to fit in a rounded square may show edge-clipping when rendered in a circle. Mitigation: visual inspection after build; if unacceptable, the `serviceLogo` preset can be reverted to `RoundedSquare` (single-line change) without touching call sites.

2. **AccountRow height bump.** Going from 32pt to 44pt icons raises row height by ~12pt. Affects density of the accounts list. Acceptable per user direction ("единый размер").

3. **Soft-tint category background.** New per-row colored background may make CategoryRow look busier. The 15% opacity should be subtle enough; if it competes with the budget progress ring, the chosen `bg = color.opacity(0.15)` can be lowered to `0.10`.

4. **Existing `# Preview` blocks** in `IconView+Previews.swift` reference roundedSquare presets explicitly. Previews will now render circular variants. Not a code error, only a visual difference — left as-is.

## Verification Plan

After implementation:
1. `xcodebuild build` for iPhone 17 Pro Simulator — compile-only check.
2. User builds & runs on Simulator (white-on-white risk on cards is non-issue here since bg = bgCard adapts to dark mode).
3. User verifies:
   - All icons in account list, category list, account cards, loan cards, subscription cards are circular and same visual weight (44pt).
   - Category picker from AccountDetailView ("+ Добавить транзакцию" → category list) scrolls when there are many categories.
   - All Russian "транзакция" labels now read "операция" in proper case.
   - Brand logos (if any in the account list) don't look broken under circle clip.

## Out-of-Scope Future Work

- Centralize size token at the call-site level (e.g., `IconView.row()` / `IconView.card()` factories) — defer until current uniformity proves stable.
- Possible `AppColors.surface` token if a third semantic background level is needed in the future.

## Files Touched (final list)

**Modified (12):**
1. `Tenra/Models/IconStyle.swift`
2. `Tenra/Views/Components/Icons/IconView.swift`
3. `Tenra/Views/Components/Cards/AccountCard.swift`
4. `Tenra/Views/Components/Cards/LoanCard.swift`
5. `Tenra/Views/Components/Rows/AccountRow.swift`
6. `Tenra/Views/Components/Rows/CategoryRow.swift`
7. `Tenra/Views/Components/Input/AccountRadioButton.swift`
8. `Tenra/Views/Components/Input/TransactionCategoryPickerView.swift`
9. `Tenra/ru.lproj/Localizable.strings`
10. `Tenra/Services/ML/MLDataExporter.swift`
11. `Tenra/Views/Settings/SettingsView.swift`
12. `Tenra/Views/VoiceInput/VoiceInputView.swift`
