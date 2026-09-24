# Plan 013: A new user can record income right away (income presets + "add category" in the top-up flow)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat a57d5fe4..HEAD -- Tenra/Services/Onboarding/CategoryPreset.swift Tenra/ViewModels/OnboardingViewModel.swift Tenra/Views/Accounts/AccountActionView.swift Tenra/Views/Components/Input/CategoryCardSelectorView.swift Tenra/*.lproj/Localizable.strings`

## Status

- **Priority**: P1
- **Effort**: S-M
- **Risk**: LOW
- **Depends on**: none (plan 012 relies on the Russian name "Зарплата" chosen here)
- **Category**: bug
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

Onboarding creates expense categories only. Income requires an income category
(`AccountActionViewModel` refuses to save without one), and the top-up screen shows only
"No available categories. Create categories first." with no button, so a new user's first
salary dead-ends and they must find Finances → Categories → Income → Add on their own.
Without income, savings rate, health score and most insights stay empty. Voice "получил
зарплату" also has no income category to land in.

## Current state

- `Tenra/Services/Onboarding/CategoryPreset.swift` — `struct CategoryPreset { id, nameKey, iconSource, colorHex, type }`
  and `static let defaultExpense: [CategoryPreset]` (15 entries, all `.expense`).
- `Tenra/ViewModels/OnboardingViewModel.swift:142-153` (`finish()`):
  ```swift
  for selectable in draftCategories where selectable.isSelected {
      let preset = selectable.preset
      let category = CustomCategory(
          name: String(localized: String.LocalizationValue(preset.nameKey)),
          iconSource: preset.iconSource,
          colorHex: preset.colorHex,
          type: preset.type
      )
      coordinator.categoriesViewModel.addCategory(category)
  }

  coordinator.completeOnboarding()
  ```
- `Tenra/ViewModels/AccountActionViewModel.swift:259-263`:
  ```swift
  guard let category = selectedCategory, !incomeCategories.isEmpty else {
      errorMessage = String(localized: "transactionForm.selectCategoryIncome")
      ...
  ```
- `Tenra/Views/Accounts/AccountActionView.swift:155-165` — income branch:
  ```swift
  case .income:
      CategoryCardSelectorView(
          categories: viewModel.incomeCategories,
          type: .income,
          customCategories: transactionsViewModel.customCategories,
          selectedCategory: $viewModel.selectedCategory,
          onSelectionChange: { _ in viewModel.handleCategorySelectionChange() },
          emptyStateMessage: String(localized: "transactionForm.noCategories")
      )
  ```
  `AccountActionView` has `let categoriesViewModel: CategoriesViewModel` and `transactionsViewModel`.
- `Tenra/Views/Components/Input/CategoryCardSelectorView.swift` — props `categories, type, customCategories,
  selectedCategory (Binding), onSelectionChange, emptyStateMessage`; renders the message when `categories` is empty (~line 45).
- Add-category sheet exemplar: `Tenra/Views/Categories/CategoriesManagementView.swift:335-347`:
  ```swift
  .sheet(isPresented: $showingAddCategory) {
      CategoryEditView(
          categoriesViewModel: categoriesViewModel,
          transactionsViewModel: transactionsViewModel,
          category: nil,
          type: selectedType,
          onSave: { category in
              HapticManager.success()
              categoriesViewModel.addCategory(category)
              transactionsViewModel.invalidateCaches()
              showingAddCategory = false
          },
          onCancel: { showingAddCategory = false }
      )
  ```
- Localization: 11 locales, append keys with `python3` + `io.open(..., encoding="utf-8")`; never `perl -CSD`;
  no em dashes; match each locale's formality (de "Sie", fr "vous", es/it "tú", pt-BR "você").
  An existing key "category.add"/"button.add"-style label may already exist: `grep -n '"category.add\|"categories.add\|"button.add"' Tenra/en.lproj/Localizable.strings`; reuse it for the button if it reads "Add category"/"Add".

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/CategoryPresetIncomeTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Locale parity | `for L in ru de es fr tr pt-BR it uk ja ko; do diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings \| sort) <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings \| sort) >/dev/null && echo "$L ok" \|\| echo "$L MISMATCH"; done` | all ok |

## Scope

**In scope**: `CategoryPreset.swift`, `OnboardingViewModel.swift` (`finish()` only),
`CategoryCardSelectorView.swift` (optional empty-state action), `AccountActionView.swift` (income empty state + sheet),
`Tenra/*.lproj/Localizable.strings`, `TenraTests/Onboarding/CategoryPresetIncomeTests.swift` (create).

**Out of scope**: adding income presets to the onboarding selection grid UI; creating categories for existing
users automatically (they get the empty-state button instead); voice map changes (plan 012).

## Git workflow

Commit directly on `main`; do not push. Message: `feat(onboarding): income categories and an add-category path for first income`.

## Steps

### Step 1: Income presets

In `CategoryPreset`, add:
```swift
/// Created automatically at onboarding finish (not shown in the selection grid), so the
/// first income never dead-ends. Names resolved via String(localized:) at commit time.
static let defaultIncome: [CategoryPreset] = [
    .init(id: "salary",      nameKey: "onboarding.preset.salary",      iconSource: .sfSymbol("briefcase.fill"),    colorHex: "#16a34a", type: .income),
    .init(id: "otherIncome", nameKey: "onboarding.preset.otherIncome", iconSource: .sfSymbol("plus.circle.fill"),  colorHex: "#64748b", type: .income)
]
```

### Step 2: Create them at finish

In `OnboardingViewModel.finish()`, after the expense loop and before `completeOnboarding()`, add the
`defaultIncome` presets the same way (skip one if a category with the same name and type already exists
in `coordinator.categoriesViewModel.customCategories`).

### Step 3: Empty-state action

In `CategoryCardSelectorView` add `let emptyStateAction: (() -> Void)?` and `let emptyStateActionTitle: String?`
(both defaulting to `nil` in `init`, so existing call sites compile unchanged). When `categories` is empty and
both are non-nil, render a `Button(emptyStateActionTitle, action: emptyStateAction)` under the message, styled
`.secondaryButton()` (design system: `Tenra/Utils/AppButton.swift`).

In `AccountActionView`'s income branch pass `emptyStateAction: { showingAddIncomeCategory = true }` and a title;
add `@State private var showingAddIncomeCategory = false` and a `.sheet` modeled on the exemplar with
`type: .income`; in `onSave`, after `categoriesViewModel.addCategory(category)`, set
`viewModel.selectedCategory = category.name`.

### Step 4: Strings

| Key | en | ru |
|---|---|---|
| `onboarding.preset.salary` | Salary | Зарплата |
| `onboarding.preset.otherIncome` | Other income | Прочие доходы |
| `transactionForm.addIncomeCategory` (only if no reusable key exists) | Add income category | Добавить категорию дохода |

Other locales (suggested): de Gehalt / Sonstige Einnahmen / Einnahmekategorie hinzufügen; es Salario / Otros ingresos /
Añadir categoría de ingresos; fr Salaire / Autres revenus / Ajouter une catégorie de revenus; tr Maaş / Diğer gelirler /
Gelir kategorisi ekle; pt-BR Salário / Outras receitas / Adicionar categoria de receita; it Stipendio / Altre entrate /
Aggiungi categoria di entrata; uk Зарплата / Інші доходи / Додати категорію доходу; ja 給与 / その他の収入 / 収入カテゴリを追加;
ko 급여 / 기타 수입 / 수입 카테고리 추가.

### Step 5: Tests

`TenraTests/Onboarding/CategoryPresetIncomeTests.swift` (`@MainActor`):
1. `defaultIncome` has 2 presets, all `.income`, ids unique and disjoint from `defaultExpense` ids.
2. Every preset `nameKey` (expense + income) exists in `en.lproj` (load via `Bundle.main` like plan 012's test).
3. Russian value of `onboarding.preset.salary` is "Зарплата" (keeps plan 012's voice target valid).

**Verify**: Build → SUCCEEDED; Suite → SUCCEEDED; parity all ok; full TenraTests 0 failed.

## Done criteria

- [ ] New onboarding finish creates 2 income categories (verified by the device check below)
- [ ] Top-up screen with no income categories shows a working add button
- [ ] Tests pass; parity ok; only in-scope files changed; `plans/README.md` row 013 updated

## STOP conditions

- `OnboardingFlowView`'s skip path is the common path for most users (then report: skipping creates no categories at all, a separate decision).
- `CategoryEditView` cannot be presented from `AccountActionView` without new dependencies.

## Maintenance notes

- Device check: fresh install (or `OnboardingState.reset()` in DEBUG), finish onboarding, open an account → Top up:
  "Зарплата" is preselected. On an existing profile without income categories: the button opens the editor.
- If income presets are later shown in the onboarding grid, keep them selected by default.
