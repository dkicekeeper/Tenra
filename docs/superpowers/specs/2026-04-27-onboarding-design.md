# Onboarding — Design Spec

**Date:** 2026-04-27
**Status:** Design approved, awaiting implementation plan
**Languages:** RU + EN (existing `en.lproj` / `ru.lproj`)

## 1. Goal & Scope

### 1.1 Goal
Make the app immediately useful on first launch by collecting the **minimum required data**:
- Base currency (`AppSettings.baseCurrency`)
- One real account (`Account` via `AccountsViewModel.addAccount`)
- A starter set of expense categories (`CustomCategory` via `CategoriesViewModel.add`)

Without these three, `MainTabView` shows empty/non-functional states (no balance, can't create transactions). Onboarding closes that gap.

### 1.2 Non-goals
- Feature tour / tooltips inside the main app.
- CSV/PDF statement import during onboarding.
- Creating deposits, loans, or recurring transactions during onboarding.
- Income categories (added later via the regular Categories screen).
- External analytics / SDKs.

### 1.3 Flow overview
```
Welcome carousel (3 pages)
    → Currency picker
        → First account form
            → Categories preset grid
                → MainTabView
```
Hard flow: every data-collection step is required, no skip buttons.

## 2. Architecture

### 2.1 Routing — gate at `TenraApp.swift`

`TenraApp.swift` already creates `AppCoordinator` after CoreData pre-warm. We extend that root branch to choose between onboarding and the main app:

```swift
if let coordinator {
    if coordinator.needsOnboarding {
        OnboardingFlowView(coordinator: coordinator)
            .environment(coordinator)
    } else {
        MainTabView()
            .environment(timeFilterManager)
            .environment(coordinator)
            .environment(coordinator.transactionStore)
    }
}
```

`AppCoordinator.needsOnboarding: Bool` is computed: `!OnboardingState.isCompleted`. After completion, the coordinator triggers a re-render (`@Observable` will pick up the underlying flag change via a published property mirror — see §3.3).

**Why this option (vs `.fullScreenCover` over MainTabView, vs sheet inside ContentView):**
- `MainTabView` is heavy: it triggers full transaction load (~19k rows), FRC setup, balance recalculations. Building it under a cover wastes startup time on a first launch where there's nothing to show anyway.
- A sheet over `ContentView` is dismissible (swipe-down) — incompatible with the "hard flow" decision.
- A dedicated branch matches the existing `AppCoordinator` pattern (a coordinator per lifecycle phase) and makes re-running onboarding (after `Reset all data`) trivially symmetric.

### 2.2 File layout

```
Tenra/
├── Views/Onboarding/
│   ├── OnboardingFlowView.swift          # root container (welcome carousel + NavigationStack)
│   ├── OnboardingWelcomePage.swift       # one welcome carousel page
│   ├── OnboardingCurrencyStep.swift
│   ├── OnboardingAccountStep.swift
│   ├── OnboardingCategoriesStep.swift
│   └── Components/
│       ├── OnboardingPageContainer.swift # shared layout: title + content + bottom CTA
│       └── OnboardingProgressBar.swift   # 3-dot progress for data steps
├── ViewModels/
│   └── OnboardingViewModel.swift         # @Observable @MainActor
├── Services/Onboarding/
│   ├── OnboardingState.swift             # UserDefaults read/write (isCompleted)
│   └── CategoryPreset.swift              # static catalog of preset categories
└── (tests)
    └── TenraTests/Onboarding/
        ├── OnboardingViewModelTests.swift
        └── OnboardingStateTests.swift
```

### 2.3 Internal flow

- **Welcome carousel** uses `TabView(selection:)` with `.tabViewStyle(.page(indexDisplayMode: .always))` for 3 pages. CTA on the last page transitions into the data-collection `NavigationStack`.
- **Data-collection steps** (Currency / Account / Categories) live in a `NavigationStack` with programmatic `path` binding. This gives:
  - Native back gesture and animations.
  - Explicit `push` / `pop` (no accidental swipe between unrelated steps).
  - A clean target for the progress bar (3 dots tied to `path.count`).

## 3. State management

### 3.1 `OnboardingViewModel`

```swift
@Observable
@MainActor
final class OnboardingViewModel {
    @ObservationIgnored let coordinator: AppCoordinator

    // Welcome carousel
    var welcomePage: Int = 0

    // Step 1 — currency
    var draftCurrency: String = AppSettings.defaultCurrency  // "KZT"

    // Step 2 — first account
    var draftAccount: AccountDraft = AccountDraft()
    var createdAccountId: UUID?  // nil until step 2 commits

    // Step 3 — categories
    var draftCategories: [CategoryPreset] = CategoryPreset.defaultExpense
        .map { $0.makeSelectable(isSelected: true) }

    // Navigation
    var path: [OnboardingStep] = []  // pushed steps after welcome

    var isFinishing: Bool = false
}

struct AccountDraft {
    var name: String = ""
    var iconSource: IconSource = .sfSymbol("creditcard.fill")
    var type: AccountType = .card
    var colorHex: String = "#3b82f6"  // first hex from CategoryColors palette
    var balance: Double = 0
}
```

Per CLAUDE.md `@Observable` rules:
- `coordinator` is a dependency → `@ObservationIgnored`.
- Mutable form state is plain `var` so SwiftUI tracks it.

### 3.2 `OnboardingState`

```swift
enum OnboardingState {
    private static let key = "hasCompletedOnboarding"

    static var isCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
```

### 3.3 Hooking `needsOnboarding` into `@Observable`

`AppCoordinator` exposes a tracked mirror:

```swift
@Observable @MainActor
final class AppCoordinator {
    private(set) var needsOnboarding: Bool

    init(...) {
        // ... existing init ...

        // iCloud-restore mitigation (see §6): if accounts already exist after
        // store load (e.g. user restored from iCloud backup on a new device),
        // mark onboarding completed and skip the flow.
        if !OnboardingState.isCompleted && !accountsVM.accounts.isEmpty {
            OnboardingState.markCompleted()
        }
        self.needsOnboarding = !OnboardingState.isCompleted
    }

    func completeOnboarding() {
        OnboardingState.markCompleted()
        needsOnboarding = false
    }

    func resetOnboarding() {
        OnboardingState.reset()
        needsOnboarding = true
    }
}
```

`needsOnboarding` is a stored `var` (not computed) so SwiftUI's observation correctly diffs the root view. The fast-path account load (`initializeFastPath()` in existing code) must complete before this check runs — implementer should place the iCloud-restore check after the fast path, not before.

## 4. Step-by-step UI spec

### 4.1 Welcome carousel — 3 pages

Container: `TabView` with `.page(indexDisplayMode: .always)`. Bottom button:
- Pages 1, 2 → "Далее" / "Next" (advances `welcomePage += 1`).
- Page 3 → "Начать" / "Get started" (pushes `.currency` onto `path`).

Each page (`OnboardingWelcomePage`):
```
[Large SF Symbol, ~120pt, AppColors.accentPrimary]
[AppTypography.title]
[AppTypography.body, multi-line, .center]
```

| # | SF Symbol | RU Title | RU Subtitle | EN Title | EN Subtitle |
|---|---|---|---|---|---|
| 1 | `chart.pie.fill` | Все финансы в одном месте | Счета, депозиты, кредиты, подписки и категории трат — всё в одном приложении с понятной аналитикой. | All your finances in one place | Accounts, deposits, loans, subscriptions and spending categories — together with clear analytics. |
| 2 | `mic.fill` | Добавляйте транзакции голосом | Скажите «Кофе 800 тенге» — Tenra поймёт сумму, валюту и категорию. Или импортируйте выписку из PDF/CSV. | Add transactions by voice | Say "Coffee 800 tenge" — Tenra parses amount, currency, and category. Or import statements from PDF/CSV. |
| 3 | `lock.shield.fill` | Ваши данные — только ваши | Всё хранится локально на устройстве. iCloud-бэкап опциональный. Никаких аккаунтов и регистраций. | Your data stays yours | Everything is stored on-device. iCloud backup is optional. No accounts, no signup. |

Animations: `staggeredEntrance` for icon + title + subtitle on first appear of each page. Uses `AppAnimation.contentSpring`.

### 4.2 Step 1 — Currency

- Top: `OnboardingProgressBar` (3 dots, dot 1 active).
- Title: "Выберите основную валюту" / "Choose your base currency".
- Subtitle: "В этой валюте Tenra будет показывать общий баланс и аналитику. Валюту можно сменить позже в Настройках." / "Tenra will show your total balance and analytics in this currency. You can change it later in Settings."
- Body: reuse the inner list of `CurrencyPickerView` (`Views/Settings/CurrencyPickerView.swift`). If it's not extractable as a binding-driven component, factor out `CurrencyListView(selection: Binding<String>)` and use it in both places.
- `.searchable(...)` over the list (existing pattern).
- Default selection: `AppSettings.defaultCurrency` ("KZT") — pre-selected, so "Next" is always enabled.
- Bottom CTA: "Далее" / "Next" (`PrimaryButtonStyle`).

**On Next:**
- `coordinator.appSettings.baseCurrency = vm.draftCurrency` (commits immediately so the next step's account form picks it up).
- `path.append(.account)`.

### 4.3 Step 2 — First account

- Top: progress bar (dot 2 active).
- Title: "Добавьте первый счёт" / "Add your first account".
- Subtitle: "Это может быть карта, наличные или счёт в банке. Позже добавите остальные." / "It can be a card, cash, or a bank account. You can add more later."
- Body — `FormSection(.card)` containing:
  - `TextField` "Название" — bound to `draftAccount.name`. Required.
  - `IconPickerView` row — bound to `draftAccount.iconSource`. Default icon depends on `draftAccount.type`.
  - `MenuPickerRow` "Тип" — `card | cash | bank | other`. Default `.card`.
  - Color row — horizontal picker over `CategoryColors` palette. Default first entry.
  - `AmountInput` "Стартовый баланс" — bound to `draftAccount.balance`. Currency label = `vm.draftCurrency` (display-only).
- Bottom CTA: "Далее" / "Next". Disabled while `draftAccount.name.isEmpty`.

**On Next:**
- If `vm.createdAccountId == nil`:
  - Build `Account` from `draftAccount` + `currency: vm.draftCurrency`.
  - `await coordinator.accountsVM.addAccount(account)` (or whatever the existing API is).
  - Store `vm.createdAccountId = account.id`.
- Else (user came back to this step):
  - `await coordinator.accountsVM.update(...)` with the same id.
- `path.append(.categories)`.

**On Back from Categories → Account:**
- Form is pre-filled from `draftAccount`. User can edit, "Next" hits the `update` branch.

**On Back from Account → Currency:**
- If `vm.createdAccountId != nil` and `vm.draftCurrency` changes on Currency step:
  - Show an info banner on the next push back to Account: "Валюта приложения изменена. Валюта счёта останется прежней. Изменить можно в редакторе счёта." / "App currency changed. Account currency stays the same. You can change it in the account editor."
- We do not auto-rewrite the account's currency (would surprise the user).

**Reuse:** if existing `AccountAddView` / `AccountEditView` are tightly coupled to sheet presentation, extract a pure `AccountFormView(draft: Binding<AccountDraft>)` and reuse here and in the existing flows.

### 4.4 Step 3 — Categories preset grid

- Top: progress bar (dot 3 active).
- Title: "Выберите категории трат" / "Choose spending categories".
- Subtitle: "Отметьте те, которыми будете пользоваться. Остальные сможете добавить позже." / "Pick the ones you'll use. You can add more later."
- Body: `LazyVGrid` — 3 columns on iPhone, 4 on iPad.
- Each cell:
  - Round icon (SF Symbol on a `colorHex` background, sized via `AppIconSize`).
  - Localized name below.
  - When `isSelected`: 2pt `AppColors.accentPrimary` ring + checkmark badge in top-right corner.
  - Tap → toggle. `.sensoryFeedback(.selection, trigger: ...)`.
  - Animation on `value: isSelected` → `AppAnimation.contentSpring`.
- All 15 presets default to `isSelected = true`.
- Bottom CTA: "Готово • выбрано N" / "Done • N selected" (`PrimaryButtonStyle`). Disabled when `selectedCount == 0`.

**Preset catalog** (`CategoryPreset.defaultExpense`, all `type = .expense`):

Hex values are concrete `colorHex` strings stored on each created `CustomCategory`. The first 13 are taken from the existing palette in `Utils/AppColors.swift::CategoryColors` (14 vibrant tones, no brown/gray). For "Pets" and "Services" we fall back to neutral browns/grays not in the palette — `CustomCategory.colorHex` accepts arbitrary hex, and the hash-based palette is only used as a default when no `colorHex` is set.

| SFSymbol | RU | EN | colorHex |
|---|---|---|---|
| `cart.fill` | Продукты | Groceries | `#22c55e` (green) |
| `fork.knife` | Кафе и рестораны | Dining out | `#f97316` (orange) |
| `car.fill` | Транспорт | Transport | `#3b82f6` (blue) |
| `house.fill` | Жильё | Housing | `#a855f7` (violet) |
| `bolt.fill` | Коммунальные | Utilities | `#eab308` (yellow) |
| `pills.fill` | Здоровье | Health | `#f43f5e` (red) |
| `tshirt.fill` | Одежда | Clothing | `#ec4899` (pink) |
| `gamecontroller.fill` | Развлечения | Entertainment | `#8b5cf6` (purple) |
| `airplane` | Путешествия | Travel | `#06b6d4` (cyan) |
| `book.fill` | Образование | Education | `#6366f1` (indigo) |
| `gift.fill` | Подарки | Gifts | `#10b981` (mint) |
| `creditcard.fill` | Подписки | Subscriptions | `#14b8a6` (teal) |
| `pawprint.fill` | Питомцы | Pets | `#92400e` (brown — outside palette) |
| `wrench.and.screwdriver.fill` | Услуги | Services | `#64748b` (slate gray — outside palette) |
| `ellipsis.circle.fill` | Прочее | Other | `#9ca3af` (light gray — outside palette) |

**On Done:**
- For each `preset` with `isSelected == true`:
  - Build a `CustomCategory` (name from `String(localized: preset.nameKey)`, icon, color, type `.expense`).
  - `await coordinator.categoriesVM.add(category)`.
- `coordinator.completeOnboarding()` (sets the flag, flips `needsOnboarding`).
- Root view re-renders into `MainTabView`, wrapped in `withAnimation(AppAnimation.contentSpring) { ... }`.

## 5. Persistence rules

- `appSettings.baseCurrency` — committed at step 1's Next.
- `Account` — committed at step 2's Next (or updated if back-and-forth).
- `CustomCategory[]` — committed at step 3's Done (atomic for the user even if not for the DB; per-row failures are logged, not rolled back).
- `OnboardingState.markCompleted()` runs **only after** all category writes return.

## 6. Edge cases

| Situation | Behavior |
|---|---|
| User kills the app mid-flow | `hasCompletedOnboarding == false` → onboarding restarts on next launch. Account created mid-flow stays in CoreData; user will create another, may delete the orphan manually. Acceptable. |
| Back from Categories → Account, user edits | `accountsVM.update(...)` path (no duplicate create). |
| Back from Account → Currency, user changes currency | App `baseCurrency` updates; existing account currency stays. Info banner explains. |
| `Settings → Reset all data` | `resetAllData()` calls `coordinator.resetOnboarding()` → flag cleared → next launch (or restart) starts onboarding again. |
| iCloud restore on a new device | `UserDefaults` is not iCloud-synced by default. New device would re-show onboarding even though data exists. **Mitigation:** before showing onboarding, `AppCoordinator.init` checks: if `accountsVM.accounts.count > 0` after store load → call `OnboardingState.markCompleted()` and set `needsOnboarding = false` automatically. |
| OS locale change after onboarding | Created categories keep their original language strings (stored as flat `String`). Documented as accepted trade-off. |

## 7. Animations & design tokens

- All animations use `AppAnimation` constants (no inline springs):
  - Welcome carousel page transitions — built-in `TabView`.
  - Step transitions in `NavigationStack` — system default.
  - Cell selection toggle — `AppAnimation.contentSpring`.
  - Icon + title appearance — `staggeredEntrance` modifier.
  - Final transition into `MainTabView` — `AppAnimation.contentSpring` wrapped around `completeOnboarding()`.
- All colors: `AppColors.*`.
- All spacing: `AppSpacing.*`.
- All typography: `AppTypography.*`.
- Buttons: `PrimaryButtonStyle` for primary CTA on each step.
- Reduce Motion: standard project pattern (`AppAnimation.isReduceMotionEnabled` already covered by tokens).

## 8. Localization

- All visible strings via `Text(String(localized: "onboarding.<screen>.<element>"))`.
- New keys added to both `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`.
- Naming: `onboarding.welcome.page1.title`, `onboarding.currency.title`, `onboarding.categories.preset.groceries.name`, etc.
- Preset category names use stable keys like `onboarding.preset.groceries`, resolved once at category creation time and stored as a flat string in CoreData.

## 9. Tests

### Unit tests
- `OnboardingViewModelTests`:
  - Default preset list has 15 entries, all `isSelected == true`.
  - `complete()` creates exactly `selectedCount` categories.
  - `complete()` writes `baseCurrency` to `appSettings`.
  - Coming back to step 2 after a created account triggers `update`, not `addAccount`.
  - `complete()` flips `OnboardingState.isCompleted` to `true` only after all writes return.
- `OnboardingStateTests`:
  - `isCompleted` reflects UserDefaults state.
  - `markCompleted()` / `reset()` round-trip.

### Integration / smoke
- Build runs cleanly.
- Manual: fresh sim → 3-step flow → MainTabView shows the new account, balance, categories.
- Manual: `Settings → Danger Zone → Reset all data` → restart → onboarding shown again.

### Out of scope for this spec
- Snapshot tests on each step (RU/EN × light/dark) — nice-to-have, can be added later.

## 10. Logging

`os.Logger` (project-standard), category `"Onboarding"`:
- `onboarding_started` — first render of `OnboardingFlowView`.
- `onboarding_step_completed` with step name — on each Next/Done.
- `onboarding_finished` — after `completeOnboarding()` returns.
- `onboarding_reset` — when `resetOnboarding()` is called.

No external analytics.

## 11. Reuse / refactor opportunities (in scope)

- Extract `CurrencyListView(selection:)` from `CurrencyPickerView` if it's currently coupled to `appSettings`.
- Extract `AccountFormView(draft:)` from `AccountAddView` / `AccountEditView` for shared use.
- These are targeted improvements — no broader refactor.

## 12. Open items

None blocking. Possible follow-ups (not in this spec):
- Add an income-categories mini-section to step 3 (e.g., "Зарплата", "Прочее") if first-week analytics show users struggle to log income.
- Optional CSV/PDF "import path" branch from a fork on the welcome screen — would convert the flow to a hybrid (data + import).
