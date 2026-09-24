# Plan 012: Russian voice keywords map to the categories onboarding actually creates

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Services/Voice/VoiceInputParser.swift TenraTests/Services/Voice/VoiceInputParserTests.swift Tenra/Services/Onboarding/CategoryPreset.swift`
> Plan 013 may have added income presets to `CategoryPreset.swift`; that is expected.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (changes map VALUES only; keys untouched)
- **Depends on**: 013 for the "Зарплата" part only (see Step 1); the rest is independent
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

Voice input (a Pro feature) maps spoken keywords to a category NAME, which is then matched
against the user's categories (`TransactionDraftService.resolveCategory`: exact,
case-insensitive, substring, then the localized "Other"). The Russian keywords for the most
common spending point to names onboarding never creates:
- 15 keys → `"Еда"` (кафе, кофе, ресторан, обед, ужин, завтрак, еда, столовая, доставка,
  доставку, доставки, доставке, курьер, курьера, еда доставка);
- 5 keys → `"Покупки"` (магазин, покупка, шопинг, одежда, обувь);
- 4 keys → `"Зарплата"` (зарплата, зарплату, оклад, премия; income; no income preset exists yet).

Russian onboarding presets are `Продукты`, `Кафе и рестораны`, `Одежда`, ... (see
`Tenra/ru.lproj/Localizable.strings` keys `onboarding.preset.*`). So "кофе 500" lands in
"Прочее" for every Russian user who kept the presets. The voice test fixture seeds a fake
`"Еда"` category (`TenraTests/Services/Voice/VoiceInputParserTests.swift:48-53`), which is why
tests never caught it. Every other target (86 of 89) already equals a preset name in some locale.

## Current state

- `Tenra/Services/Voice/VoiceInputParser.swift`, `private lazy var categoryMap: [String: (category: String, subcategory: String?)]`
  (starts line 84). The affected lines at planning time:
  ```swift
  "кафе": ("Еда", nil),                 // line 99
  "кофе": ("Еда", "Кофе"),
  "ресторан": ("Еда", nil),
  "обед": ("Еда", nil),
  "ужин": ("Еда", nil),
  "завтрак": ("Еда", nil),
  "еда": ("Еда", nil),
  "столовая": ("Еда", nil),
  "доставка": ("Еда", "Доставка"),
  "доставку": ("Еда", "Доставка"),
  "доставки": ("Еда", "Доставка"),
  "доставке": ("Еда", "Доставка"),
  "курьер": ("Еда", "Доставка"),
  "курьера": ("Еда", "Доставка"),
  "еда доставка": ("Еда", "Доставка"), // line 113
  ...
  "магазин": ("Покупки", nil),          // line 118
  ...
  "покупка": ("Покупки", nil),          // line 125
  "шопинг": ("Покупки", nil),
  "одежда": ("Покупки", "Одежда"),
  "обувь": ("Покупки", "Одежда"),       // line 128
  ...
  "зарплата": ("Зарплата", nil),        // line 159
  "зарплату": ("Зарплата", nil),
  "оклад": ("Зарплата", nil),
  "премия": ("Зарплата", nil),          // line 162
  ```
- ⚠️ CLAUDE.md Red Flag 16: `categoryMap` is a dictionary LITERAL; a duplicate KEY compiles but
  crashes at runtime. This plan changes VALUES only and adds no keys. Do not add, rename, or move keys.
- Russian preset names: `onboarding.preset.dining` = "Кафе и рестораны", `onboarding.preset.groceries` =
  "Продукты", `onboarding.preset.clothing` = "Одежда" (`Tenra/ru.lproj/Localizable.strings:1499-1505`).
- The keyword `покупка` is also an EXPENSE type keyword (`expenseKeywords`, line ~756); as a category
  keyword it is too generic.
- Plan 002 added `func keywordCategory(in:)` which iterates `sortedCategoryKeys` and returns
  `categoryMap[keyword]?.category`. Keep it working.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/VoiceInputParserTests -only-testing:TenraTests/VoiceCategoryTargetsTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| All tests | `-only-testing:TenraTests`; count `' failed on'` | 0 |

## Scope

**In scope**: `Tenra/Services/Voice/VoiceInputParser.swift` (values of the listed entries, plus one
internal accessor for tests), `TenraTests/Services/Voice/VoiceInputParserTests.swift` (fixture only),
`TenraTests/Services/Voice/VoiceCategoryTargetsTests.swift` (create).

**Out of scope**: any other language's entries; `parseCategory` logic; the income presets themselves (plan 013).

## Git workflow

Commit directly on `main`; do not push. Message:
`fix(voice): Russian keywords target the categories onboarding creates`.

## Steps

### Step 1: Retarget values

Change ONLY the values:
- кафе, кофе, ресторан, обед, ужин, завтрак, еда, столовая, доставка, доставку, доставки, доставке,
  курьер, курьера, еда доставка → category `"Кафе и рестораны"` (keep each entry's subcategory as is).
- магазин → `("Продукты", nil)`.
- шопинг → `("Одежда", nil)`; одежда → `("Одежда", nil)`; обувь → `("Одежда", "Обувь")`.
- покупка → leave the entry but point it at `("Продукты", nil)` only if plan review agrees; otherwise
  DELETE the entry `"покупка": ("Покупки", nil)` (deleting a key cannot create a duplicate). Default: delete.
- зарплата, зарплату, оклад, премия → keep `"Зарплата"` (plan 013 adds an income preset named exactly
  "Зарплата" in Russian). If plan 013 chose a different Russian name, use that name here.

**Verify**: `grep -c '("Еда"' Tenra/Services/Voice/VoiceInputParser.swift` → `0`;
`grep -c '("Покупки"' Tenra/Services/Voice/VoiceInputParser.swift` → `0`; build SUCCEEDED.

### Step 2: Test accessor

Add to `VoiceInputParser`, next to `keywordCategory(in:)`:
```swift
/// Every category name the keyword map can produce. Tests pin these to real
/// onboarding presets so a map value can never again point at a category nobody has.
var categoryMapTargets: Set<String> { Set(categoryMap.values.map(\.category)) }
```

### Step 3: Regression test

Create `TenraTests/Services/Voice/VoiceCategoryTargetsTests.swift`, `@MainActor struct`. Build the set of
preset names across ALL 11 locales by loading each `Localizable.strings` from the app bundle:
`Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: loc)`
→ `NSDictionary(contentsOfFile:)`, collecting values whose key starts with `onboarding.preset.`
(locales: en ru de es fr tr pt-BR it uk ja ko; if `Bundle.main` does not contain them in the test host,
try `Bundle(for: CategoriesViewModel.self)`). Test: every element of `parser.categoryMapTargets` is in that
set. Build the parser like `VoiceInputParserTests.makeParser()`.
Until plan 013 lands, "Зарплата" will fail this test: if 013 is not merged, add a clearly commented
temporary allow-list `["Зарплата"]` and note it in your report.

### Step 4: Realistic fixture

In `VoiceInputParserTests.makeParser()`, replace the seeded `"Еда"` category with `"Кафе и рестораны"`
(same icon/color). Update the comment above it ("кофе" → "Кафе и рестораны"). Add one test:
`parse("кофе 500")` → `categoryName == "Кафе и рестораны"`, and one: `parse("магазин 3000")` → `"Продукты"`.
Keep the test at line ~634-645 ("Unknown category phrase") passing; update its `!= "Еда"` to `!= "Кафе и рестораны"`.

**Verify**: Suite → SUCCEEDED; All tests → 0 failed.

## Done criteria

- [ ] No `("Еда"` / `("Покупки"` values remain; no key added
- [ ] VoiceCategoryTargetsTests passes (with the documented temporary allow-list only if 013 is not merged)
- [ ] Full TenraTests 0 failed; `git status --short` only in-scope files (+ `UserInterfaceState.xcuserstate`)
- [ ] `plans/README.md` row 012 updated

## STOP conditions

- The app crashes on first voice parse in tests (duplicate key): you added or duplicated a key; revert.
- Preset names in `ru.lproj` differ from the ones quoted above (use the file's actual values; if unclear, stop).

## Maintenance notes

- Device check: say "кофе пятьсот" with preset categories: lands in "Кафе и рестораны".
- Longer term, map keywords to preset IDs (like `CategorySuggestionService.brandPresets`) instead of
  per-language names; the regression test from Step 3 keeps the current design honest meanwhile.
