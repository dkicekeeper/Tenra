# Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hard-flow first-launch onboarding for Tenra (welcome carousel → currency → first account → preset categories) that gates `MainTabView` until the user supplies the minimum data needed for the app to be useful.

**Architecture:** Routing branch lives at `TenraApp.swift` root, driven by `AppCoordinator.needsOnboarding`. A dedicated `OnboardingViewModel` owns ephemeral state (drafts, navigation path), commits each step's data into existing ViewModels (`SettingsViewModel`, `AccountsViewModel`, `CategoriesViewModel`) as the user advances, then flips a `UserDefaults` flag on completion. iCloud-restore on a fresh device skips onboarding automatically when accounts already exist.

**Tech Stack:** SwiftUI (iOS 26+), Swift Testing (`import Testing`, `@Test`, `#expect`), `@Observable`, `@MainActor`, existing `AppColors`/`AppSpacing`/`AppTypography`/`AppAnimation` design tokens, `os.Logger`.

**Spec reference:** [docs/superpowers/specs/2026-04-27-onboarding-design.md](../specs/2026-04-27-onboarding-design.md)

---

## Build & test commands (use these throughout)

Build:
```bash
xcodebuild build \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: empty output (no errors).

Run a specific test:
```bash
xcodebuild test \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/<SuiteName>/<testName>
```
Expected: `Test Suite 'All tests' passed`.

Run the whole onboarding test bucket:
```bash
xcodebuild test \
  -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/Onboarding
```

---

## File map

**New files:**

| Path | Purpose |
|---|---|
| `Tenra/Services/Onboarding/OnboardingState.swift` | UserDefaults read/write for `hasCompletedOnboarding` flag |
| `Tenra/Services/Onboarding/CategoryPreset.swift` | Static catalog of 15 expense-category presets + `Selectable` wrapper |
| `Tenra/ViewModels/OnboardingViewModel.swift` | `@Observable @MainActor` ephemeral onboarding state + commit pipeline |
| `Tenra/Views/Onboarding/OnboardingFlowView.swift` | Root: welcome carousel + `NavigationStack` for data steps |
| `Tenra/Views/Onboarding/OnboardingWelcomePage.swift` | One welcome carousel page |
| `Tenra/Views/Onboarding/OnboardingCurrencyStep.swift` | Step 1 — currency picker |
| `Tenra/Views/Onboarding/OnboardingAccountStep.swift` | Step 2 — first account form |
| `Tenra/Views/Onboarding/OnboardingCategoriesStep.swift` | Step 3 — preset category grid |
| `Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift` | Shared layout: title + content + bottom CTA |
| `Tenra/Views/Onboarding/Components/OnboardingProgressBar.swift` | 3-dot progress indicator for data steps |
| `Tenra/Views/Onboarding/Components/CategoryPresetCell.swift` | Single grid cell with toggle state |
| `Tenra/Views/Settings/CurrencyListContent.swift` | Extracted reusable list (selection-binding driven) |
| `TenraTests/Onboarding/OnboardingStateTests.swift` | Round-trip tests |
| `TenraTests/Onboarding/CategoryPresetTests.swift` | Catalog invariants |
| `TenraTests/Onboarding/OnboardingViewModelTests.swift` | Commit logic, navigation, draft round-trips |

**Modified files:**

| Path | Change |
|---|---|
| `Tenra/TenraApp.swift` | Branch on `coordinator.needsOnboarding` between `OnboardingFlowView` and `MainTabView` |
| `Tenra/ViewModels/AppCoordinator.swift` | Add `needsOnboarding` stored prop, `completeOnboarding()`, `resetOnboarding()`, iCloud-restore check after fast path |
| `Tenra/ViewModels/SettingsViewModel.swift` | After `resetCoordinator.resetAllData()` succeeds, also call `coordinator.resetOnboarding()` |
| `Tenra/Views/Settings/CurrencyPickerView.swift` | Refactor to wrap the new `CurrencyListContent` |
| `Tenra/en.lproj/Localizable.strings` | Add `onboarding.*` keys |
| `Tenra/ru.lproj/Localizable.strings` | Add `onboarding.*` keys |

**Deviations from spec (recorded here so the implementer doesn't get confused):**

1. The spec's `AccountDraft.type: AccountType` is **dropped** — `Account` model has no `type` field. The icon picker (already part of the form) covers visual differentiation. `AccountDraft` keeps name, iconSource, colorHex, balance only.
2. `CategoriesViewModel.addCategory(_:)` is **synchronous** (not async as the spec sketched). The commit pipeline awaits nothing for category writes.
3. `AccountsViewModel.addAccount(...)` is async, no throws. `SettingsViewModel.updateBaseCurrency(_:)` is async, no throws. We `await` both but don't `try`.
4. The "Color row" inside the account form is **dropped** — `Account` model has no `colorHex` field; the field exists on `CustomCategory` only. Color is implied by the chosen icon.
5. The `SettingsViewModel.resetAllData()` wrapper is the right hook point (not `DataResetCoordinator.resetAllData` directly), because `SettingsViewModel` already owns the `coordinator` reference. We add the onboarding reset there, after the underlying reset succeeds.

---

## Task 1: `OnboardingState` (UserDefaults wrapper) + tests

**Files:**
- Create: `Tenra/Services/Onboarding/OnboardingState.swift`
- Test: `TenraTests/Onboarding/OnboardingStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Onboarding/OnboardingStateTests.swift`:

```swift
//
//  OnboardingStateTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct OnboardingStateTests {
    private let testKey = "hasCompletedOnboarding"

    @Test func defaultsToNotCompleted() {
        UserDefaults.standard.removeObject(forKey: testKey)
        #expect(OnboardingState.isCompleted == false)
    }

    @Test func markCompletedFlipsTheFlag() {
        UserDefaults.standard.removeObject(forKey: testKey)
        OnboardingState.markCompleted()
        #expect(OnboardingState.isCompleted == true)
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    @Test func resetClearsTheFlag() {
        OnboardingState.markCompleted()
        #expect(OnboardingState.isCompleted == true)
        OnboardingState.reset()
        #expect(OnboardingState.isCompleted == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingStateTests 2>&1 | grep -E "error:|FAIL" | head -10
```
Expected: build error "cannot find 'OnboardingState' in scope".

- [ ] **Step 3: Implement `OnboardingState`**

Create `Tenra/Services/Onboarding/OnboardingState.swift`:

```swift
//
//  OnboardingState.swift
//  Tenra
//
//  UserDefaults-backed flag for first-launch onboarding completion.
//

import Foundation

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

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingStateTests
```
Expected: `Test Suite 'OnboardingStateTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Onboarding/OnboardingState.swift TenraTests/Onboarding/OnboardingStateTests.swift
git commit -m "feat(onboarding): add OnboardingState UserDefaults wrapper"
```

---

## Task 2: `CategoryPreset` catalog + tests

**Files:**
- Create: `Tenra/Services/Onboarding/CategoryPreset.swift`
- Test: `TenraTests/Onboarding/CategoryPresetTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Onboarding/CategoryPresetTests.swift`:

```swift
//
//  CategoryPresetTests.swift
//  TenraTests
//

import Testing
@testable import Tenra

@MainActor
struct CategoryPresetTests {
    @Test func defaultExpenseHas15Entries() {
        #expect(CategoryPreset.defaultExpense.count == 15)
    }

    @Test func allPresetsAreExpenseType() {
        for preset in CategoryPreset.defaultExpense {
            #expect(preset.type == .expense)
        }
    }

    @Test func allPresetsHaveSFSymbol() {
        for preset in CategoryPreset.defaultExpense {
            if case .sfSymbol = preset.iconSource {
                continue
            }
            Issue.record("Preset \(preset.id) is not an SF symbol")
        }
    }

    @Test func allPresetsHaveValidHexColor() {
        for preset in CategoryPreset.defaultExpense {
            #expect(preset.colorHex.hasPrefix("#"))
            #expect(preset.colorHex.count == 7)
        }
    }

    @Test func presetIDsAreUnique() {
        let ids = CategoryPreset.defaultExpense.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test func makeSelectableTogglesIsSelected() {
        let preset = CategoryPreset.defaultExpense[0]
        let selected = preset.makeSelectable(isSelected: true)
        #expect(selected.preset.id == preset.id)
        #expect(selected.isSelected == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/CategoryPresetTests 2>&1 | grep -E "error:" | head -10
```
Expected: build error "cannot find 'CategoryPreset' in scope".

- [ ] **Step 3: Implement `CategoryPreset`**

Create `Tenra/Services/Onboarding/CategoryPreset.swift`:

```swift
//
//  CategoryPreset.swift
//  Tenra
//
//  Static catalog of preset expense categories offered during onboarding.
//

import Foundation

struct CategoryPreset: Identifiable, Hashable {
    let id: String
    let nameKey: String      // localization key, resolved at commit time
    let iconSource: IconSource
    let colorHex: String
    let type: TransactionType

    func makeSelectable(isSelected: Bool) -> SelectablePreset {
        SelectablePreset(preset: self, isSelected: isSelected)
    }
}

struct SelectablePreset: Identifiable, Hashable {
    var preset: CategoryPreset
    var isSelected: Bool

    var id: String { preset.id }
}

extension CategoryPreset {
    /// 15 expense-category presets. Names resolved via `String(localized:)` at commit time.
    /// Hex colours: first 12 from `CategoryColors` palette; last 3 are neutrals chosen
    /// outside the palette (brown / slate / light grey) — see spec §4.4.
    static let defaultExpense: [CategoryPreset] = [
        .init(id: "groceries",     nameKey: "onboarding.preset.groceries",     iconSource: .sfSymbol("cart.fill"),                     colorHex: "#22c55e", type: .expense),
        .init(id: "dining",        nameKey: "onboarding.preset.dining",        iconSource: .sfSymbol("fork.knife"),                    colorHex: "#f97316", type: .expense),
        .init(id: "transport",     nameKey: "onboarding.preset.transport",     iconSource: .sfSymbol("car.fill"),                      colorHex: "#3b82f6", type: .expense),
        .init(id: "housing",       nameKey: "onboarding.preset.housing",       iconSource: .sfSymbol("house.fill"),                    colorHex: "#a855f7", type: .expense),
        .init(id: "utilities",     nameKey: "onboarding.preset.utilities",     iconSource: .sfSymbol("bolt.fill"),                     colorHex: "#eab308", type: .expense),
        .init(id: "health",        nameKey: "onboarding.preset.health",        iconSource: .sfSymbol("pills.fill"),                    colorHex: "#f43f5e", type: .expense),
        .init(id: "clothing",      nameKey: "onboarding.preset.clothing",      iconSource: .sfSymbol("tshirt.fill"),                   colorHex: "#ec4899", type: .expense),
        .init(id: "entertainment", nameKey: "onboarding.preset.entertainment", iconSource: .sfSymbol("gamecontroller.fill"),           colorHex: "#8b5cf6", type: .expense),
        .init(id: "travel",        nameKey: "onboarding.preset.travel",        iconSource: .sfSymbol("airplane"),                      colorHex: "#06b6d4", type: .expense),
        .init(id: "education",     nameKey: "onboarding.preset.education",     iconSource: .sfSymbol("book.fill"),                     colorHex: "#6366f1", type: .expense),
        .init(id: "gifts",         nameKey: "onboarding.preset.gifts",         iconSource: .sfSymbol("gift.fill"),                     colorHex: "#10b981", type: .expense),
        .init(id: "subscriptions", nameKey: "onboarding.preset.subscriptions", iconSource: .sfSymbol("creditcard.fill"),               colorHex: "#14b8a6", type: .expense),
        .init(id: "pets",          nameKey: "onboarding.preset.pets",          iconSource: .sfSymbol("pawprint.fill"),                 colorHex: "#92400e", type: .expense),
        .init(id: "services",      nameKey: "onboarding.preset.services",      iconSource: .sfSymbol("wrench.and.screwdriver.fill"),   colorHex: "#64748b", type: .expense),
        .init(id: "other",         nameKey: "onboarding.preset.other",         iconSource: .sfSymbol("ellipsis.circle.fill"),          colorHex: "#9ca3af", type: .expense)
    ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/CategoryPresetTests
```
Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Onboarding/CategoryPreset.swift TenraTests/Onboarding/CategoryPresetTests.swift
git commit -m "feat(onboarding): add CategoryPreset catalog with 15 expense presets"
```

---

## Task 3: Localization keys

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

- [ ] **Step 1: Append onboarding keys to `en.lproj/Localizable.strings`**

Append at the end of the file:

```
/* MARK: - Onboarding */

"onboarding.welcome.page1.title" = "All your finances in one place";
"onboarding.welcome.page1.subtitle" = "Accounts, deposits, loans, subscriptions and spending categories — together with clear analytics.";
"onboarding.welcome.page2.title" = "Add transactions by voice";
"onboarding.welcome.page2.subtitle" = "Say \"Coffee 800 tenge\" — Tenra parses amount, currency, and category. Or import statements from PDF/CSV.";
"onboarding.welcome.page3.title" = "Your data stays yours";
"onboarding.welcome.page3.subtitle" = "Everything is stored on-device. iCloud backup is optional. No accounts, no signup.";

"onboarding.cta.next" = "Next";
"onboarding.cta.start" = "Get started";
"onboarding.cta.done" = "Done";
"onboarding.cta.doneWithCount" = "Done • %d selected";

"onboarding.currency.title" = "Choose your base currency";
"onboarding.currency.subtitle" = "Tenra will show your total balance and analytics in this currency. You can change it later in Settings.";

"onboarding.account.title" = "Add your first account";
"onboarding.account.subtitle" = "It can be a card, cash, or a bank account. You can add more later.";
"onboarding.account.namePlaceholder" = "e.g., Chase";
"onboarding.account.nameLabel" = "Name";
"onboarding.account.iconLabel" = "Icon";
"onboarding.account.balanceLabel" = "Starting balance";
"onboarding.account.currencyChangedBanner" = "App currency changed. Account currency stays the same. You can change it in the account editor.";

"onboarding.categories.title" = "Choose spending categories";
"onboarding.categories.subtitle" = "Pick the ones you'll use. You can add more later.";

"onboarding.preset.groceries" = "Groceries";
"onboarding.preset.dining" = "Dining out";
"onboarding.preset.transport" = "Transport";
"onboarding.preset.housing" = "Housing";
"onboarding.preset.utilities" = "Utilities";
"onboarding.preset.health" = "Health";
"onboarding.preset.clothing" = "Clothing";
"onboarding.preset.entertainment" = "Entertainment";
"onboarding.preset.travel" = "Travel";
"onboarding.preset.education" = "Education";
"onboarding.preset.gifts" = "Gifts";
"onboarding.preset.subscriptions" = "Subscriptions";
"onboarding.preset.pets" = "Pets";
"onboarding.preset.services" = "Services";
"onboarding.preset.other" = "Other";
```

- [ ] **Step 2: Append onboarding keys to `ru.lproj/Localizable.strings`**

Append at the end of the file:

```
/* MARK: - Onboarding */

"onboarding.welcome.page1.title" = "Все финансы в одном месте";
"onboarding.welcome.page1.subtitle" = "Счета, депозиты, кредиты, подписки и категории трат — всё в одном приложении с понятной аналитикой.";
"onboarding.welcome.page2.title" = "Добавляйте транзакции голосом";
"onboarding.welcome.page2.subtitle" = "Скажите «Кофе 800 тенге» — Tenra поймёт сумму, валюту и категорию. Или импортируйте выписку из PDF/CSV.";
"onboarding.welcome.page3.title" = "Ваши данные — только ваши";
"onboarding.welcome.page3.subtitle" = "Всё хранится локально на устройстве. iCloud-бэкап опциональный. Никаких аккаунтов и регистраций.";

"onboarding.cta.next" = "Далее";
"onboarding.cta.start" = "Начать";
"onboarding.cta.done" = "Готово";
"onboarding.cta.doneWithCount" = "Готово • выбрано %d";

"onboarding.currency.title" = "Выберите основную валюту";
"onboarding.currency.subtitle" = "В этой валюте Tenra будет показывать общий баланс и аналитику. Валюту можно сменить позже в Настройках.";

"onboarding.account.title" = "Добавьте первый счёт";
"onboarding.account.subtitle" = "Это может быть карта, наличные или счёт в банке. Позже добавите остальные.";
"onboarding.account.namePlaceholder" = "Например, Kaspi";
"onboarding.account.nameLabel" = "Название";
"onboarding.account.iconLabel" = "Иконка";
"onboarding.account.balanceLabel" = "Стартовый баланс";
"onboarding.account.currencyChangedBanner" = "Валюта приложения изменена. Валюта счёта останется прежней. Изменить можно в редакторе счёта.";

"onboarding.categories.title" = "Выберите категории трат";
"onboarding.categories.subtitle" = "Отметьте те, которыми будете пользоваться. Остальные сможете добавить позже.";

"onboarding.preset.groceries" = "Продукты";
"onboarding.preset.dining" = "Кафе и рестораны";
"onboarding.preset.transport" = "Транспорт";
"onboarding.preset.housing" = "Жильё";
"onboarding.preset.utilities" = "Коммунальные";
"onboarding.preset.health" = "Здоровье";
"onboarding.preset.clothing" = "Одежда";
"onboarding.preset.entertainment" = "Развлечения";
"onboarding.preset.travel" = "Путешествия";
"onboarding.preset.education" = "Образование";
"onboarding.preset.gifts" = "Подарки";
"onboarding.preset.subscriptions" = "Подписки";
"onboarding.preset.pets" = "Питомцы";
"onboarding.preset.services" = "Услуги";
"onboarding.preset.other" = "Прочее";
```

- [ ] **Step 3: Build to verify .strings parses**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty output.

- [ ] **Step 4: Commit**

```bash
git add Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat(onboarding): add localization keys for welcome carousel and 3 steps"
```

---

## Task 4: `OnboardingViewModel` + tests

**Files:**
- Create: `Tenra/ViewModels/OnboardingViewModel.swift`
- Test: `TenraTests/Onboarding/OnboardingViewModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Onboarding/OnboardingViewModelTests.swift`:

```swift
//
//  OnboardingViewModelTests.swift
//  TenraTests
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct OnboardingViewModelTests {
    @Test func draftCurrencyDefaultsToKZT() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftCurrency == "KZT")
    }

    @Test func draftCategoriesAreAllSelectedByDefault() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftCategories.count == 15)
        #expect(vm.draftCategories.allSatisfy { $0.isSelected })
    }

    @Test func selectedCountReflectsToggles() {
        let vm = OnboardingViewModel.makeForTesting()
        vm.draftCategories[0].isSelected = false
        vm.draftCategories[1].isSelected = false
        #expect(vm.selectedPresetCount == 13)
    }

    @Test func draftAccountStartsEmpty() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.draftAccount.name == "")
        #expect(vm.draftAccount.balance == 0)
    }

    @Test func canCompleteAccountStepRequiresName() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.canAdvanceFromAccountStep == false)
        vm.draftAccount.name = "Kaspi"
        #expect(vm.canAdvanceFromAccountStep == true)
    }

    @Test func canCompleteCategoriesRequiresAtLeastOneSelected() {
        let vm = OnboardingViewModel.makeForTesting()
        #expect(vm.canFinish == true)
        for index in vm.draftCategories.indices {
            vm.draftCategories[index].isSelected = false
        }
        #expect(vm.canFinish == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingViewModelTests 2>&1 | grep -E "error:" | head -10
```
Expected: build error "cannot find 'OnboardingViewModel'".

- [ ] **Step 3: Implement `OnboardingViewModel`**

Create `Tenra/ViewModels/OnboardingViewModel.swift`:

```swift
//
//  OnboardingViewModel.swift
//  Tenra
//
//  Ephemeral state and commit pipeline for the first-launch onboarding flow.
//

import Foundation
import SwiftUI
import Observation
import os

/// One step in the data-collection portion of onboarding.
enum OnboardingStep: Hashable {
    case currency
    case account
    case categories
}

/// Draft for the first account being created during onboarding.
struct AccountDraft: Equatable {
    var name: String = ""
    var iconSource: IconSource = .sfSymbol("creditcard.fill")
    var balance: Double = 0
}

@Observable
@MainActor
final class OnboardingViewModel {
    // MARK: - Dependencies

    @ObservationIgnored private weak var coordinator: AppCoordinator?
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "Onboarding")

    // MARK: - Welcome carousel

    var welcomePage: Int = 0

    // MARK: - Step state

    var path: [OnboardingStep] = []

    /// Step 1: chosen base currency. Default `KZT` (matches `AppSettings.defaultCurrency`).
    var draftCurrency: String = AppSettings.defaultCurrency

    /// Step 2: account form draft.
    var draftAccount: AccountDraft = AccountDraft()

    /// Set to the created account's id once Step 2 is committed for the first time.
    /// Subsequent re-entries update the existing account in place.
    var createdAccountId: String?

    /// Step 3: preset list with toggle state. All selected by default.
    var draftCategories: [SelectablePreset] = CategoryPreset.defaultExpense.map {
        $0.makeSelectable(isSelected: true)
    }

    /// True while the final commit pipeline is running (disables the Done button).
    var isFinishing: Bool = false

    // MARK: - Init

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Test-only convenience: builds a VM with no coordinator. The commit pipeline
    /// is a no-op in this mode (just toggles state). All draft logic still works.
    static func makeForTesting() -> OnboardingViewModel {
        let vm = OnboardingViewModel.__forTesting()
        return vm
    }

    private init() {
        self.coordinator = nil
    }

    private static func __forTesting() -> OnboardingViewModel {
        OnboardingViewModel()
    }

    // MARK: - Derived UI helpers

    var selectedPresetCount: Int {
        draftCategories.lazy.filter { $0.isSelected }.count
    }

    var canAdvanceFromAccountStep: Bool {
        !draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFinish: Bool {
        selectedPresetCount > 0 && !isFinishing
    }

    // MARK: - Step navigation

    func startDataCollection() {
        // Root of the NavigationStack is OnboardingCurrencyStep already; path stays empty.
        path = []
        logger.info("onboarding_started")
    }

    func advanceToAccountStep() async {
        guard let coordinator else { return }
        await coordinator.settingsViewModel.updateBaseCurrency(draftCurrency)
        path.append(.account)
        logger.info("onboarding_step_completed step=currency currency=\(self.draftCurrency, privacy: .public)")
    }

    func advanceToCategoriesStep() async {
        guard let coordinator else { return }
        let trimmedName = draftAccount.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existingId = createdAccountId,
           let existing = coordinator.accountsViewModel.accounts.first(where: { $0.id == existingId }) {
            // Update branch — user came back to this step.
            var updated = existing
            updated.name = trimmedName
            updated.iconSource = draftAccount.iconSource
            updated.initialBalance = draftAccount.balance
            updated.balance = draftAccount.balance
            coordinator.accountsViewModel.updateAccount(updated)
        } else {
            await coordinator.accountsViewModel.addAccount(
                name: trimmedName,
                initialBalance: draftAccount.balance,
                currency: draftCurrency,
                iconSource: draftAccount.iconSource,
                shouldCalculateFromTransactions: false
            )
            // Last-added account id (AccountsViewModel appends to the end of the array).
            createdAccountId = coordinator.accountsViewModel.accounts.last?.id
        }
        path.append(.categories)
        logger.info("onboarding_step_completed step=account")
    }

    // MARK: - Final commit

    func finish() async {
        guard let coordinator, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

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
        logger.info("onboarding_finished selectedCount=\(self.selectedPresetCount, privacy: .public)")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingViewModelTests
```
Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tenra/ViewModels/OnboardingViewModel.swift TenraTests/Onboarding/OnboardingViewModelTests.swift
git commit -m "feat(onboarding): add OnboardingViewModel with draft state and commit pipeline"
```

---

## Task 5: Wire `needsOnboarding` into `AppCoordinator`

**Files:**
- Modify: `Tenra/ViewModels/AppCoordinator.swift`

- [ ] **Step 1: Add stored property and methods**

Open `Tenra/ViewModels/AppCoordinator.swift`. After the existing `private(set) var isFullyInitialized = false` line (near the top of the class, around line 60), add:

```swift
    // Onboarding gate — true on first launch. Mutated by completeOnboarding/resetOnboarding.
    private(set) var needsOnboarding: Bool = !OnboardingState.isCompleted
```

Then anywhere inside the class body (e.g. just after `init(...)` closes, before `// MARK: - Initialization Methods` or wherever utility methods live), add:

```swift
    // MARK: - Onboarding gate

    func completeOnboarding() {
        OnboardingState.markCompleted()
        needsOnboarding = false
        logger.info("onboarding_finished")
    }

    func resetOnboarding() {
        OnboardingState.reset()
        needsOnboarding = true
        logger.info("onboarding_reset")
    }

    /// iCloud-restore mitigation: if accounts already exist after the fast path
    /// finishes (e.g. user restored from an iCloud backup on a new device),
    /// auto-mark onboarding as completed and skip the flow.
    func reconcileOnboardingAfterFastPath() {
        guard !OnboardingState.isCompleted else { return }
        guard !accountsViewModel.accounts.isEmpty else { return }
        OnboardingState.markCompleted()
        needsOnboarding = false
        logger.info("onboarding_skipped_due_to_existing_data accountsCount=\(self.accountsViewModel.accounts.count, privacy: .public)")
    }
```

- [ ] **Step 2: Hook the iCloud-restore reconciliation into the existing fast-path**

Find the spot in `AppCoordinator` where `isFastPathDone = true` is set (search for `isFastPathDone = true`). Immediately before that line, add:

```swift
        reconcileOnboardingAfterFastPath()
```

If `isFastPathDone` is set inside an async function, the reconcile call belongs at the same indentation. The point: as soon as accounts are loaded into memory, decide whether to skip onboarding.

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```
Expected: empty.

- [ ] **Step 4: Commit**

```bash
git add Tenra/ViewModels/AppCoordinator.swift
git commit -m "feat(onboarding): add needsOnboarding gate and iCloud-restore reconciliation to AppCoordinator"
```

---

## Task 6: Hook reset-all-data to clear onboarding flag

**Files:**
- Modify: `Tenra/ViewModels/SettingsViewModel.swift`

- [ ] **Step 1: Find the reset call site**

Open `Tenra/ViewModels/SettingsViewModel.swift`, jump to line ~287 (`func resetAllData() async`). The body looks similar to:

```swift
func resetAllData() async {
    do {
        try await resetCoordinator.resetAllData()
        // ...
    } catch {
        // ...
    }
}
```

- [ ] **Step 2: Add coordinator reference and reset call**

The simplest hook: this VM doesn't currently hold an `AppCoordinator` reference; instead it's owned by the coordinator. Two options:

**Option A (preferred)**: Pass an optional `(@MainActor () -> Void)?` callback into `SettingsViewModel.init` that the coordinator wires up.

**Option B (simpler, used here)**: Reset the flag directly without coordinator coupling.

Use Option B. Locate the `try await resetCoordinator.resetAllData()` line, and on the line immediately after a successful reset, add:

```swift
        OnboardingState.reset()
```

The full method should look like:

```swift
func resetAllData() async {
    do {
        try await resetCoordinator.resetAllData()
        OnboardingState.reset()
        // ... existing post-reset code, if any ...
    } catch {
        // ... existing error handling ...
    }
}
```

The `needsOnboarding` flag will pick up the change on next launch. (If the user is mid-session after a reset, the app is already in the "all data wiped" state — they need to relaunch anyway for a clean start; this matches existing reset-all-data UX.)

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 4: Commit**

```bash
git add Tenra/ViewModels/SettingsViewModel.swift
git commit -m "feat(onboarding): clear onboarding flag on reset-all-data"
```

---

## Task 7: Extract `CurrencyListContent` for reuse

**Files:**
- Create: `Tenra/Views/Settings/CurrencyListContent.swift`
- Modify: `Tenra/Views/Settings/CurrencyPickerView.swift`

- [ ] **Step 1: Create the extracted view**

Create `Tenra/Views/Settings/CurrencyListContent.swift`:

```swift
//
//  CurrencyListContent.swift
//  Tenra
//
//  Reusable currency list (List + searchable + popular/all sections).
//  Owners: CurrencyPickerView (legacy callback flow), OnboardingCurrencyStep (binding flow).
//

import SwiftUI

struct CurrencyListContent: View {
    let selectedCurrency: String
    let onTap: (String) -> Void

    @State private var searchText = ""

    private var filteredCurrencies: [CurrencyInfo] {
        guard !searchText.isEmpty else { return CurrencyInfo.allCurrencies }
        let query = searchText.lowercased()
        return CurrencyInfo.allCurrencies.filter {
            $0.code.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    private var showPopularSection: Bool { searchText.isEmpty }

    var body: some View {
        List {
            if showPopularSection {
                Section(header: Text(String(localized: "currency.popular"))) {
                    ForEach(CurrencyInfo.popularCurrencies) { currencyRow($0) }
                }
            }
            Section(header: Text(String(localized: "currency.all"))) {
                ForEach(filteredCurrencies) { currencyRow($0) }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "currency.searchPrompt"))
    }

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            onTap(currency.code)
            HapticManager.selection()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.code)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(currency.name)
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text(currency.symbol)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                if currency.code == selectedCurrency {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.accentPrimary)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Refactor `CurrencyPickerView` to wrap it**

Replace the body of `CurrencyPickerView` (`Tenra/Views/Settings/CurrencyPickerView.swift`) so it uses `CurrencyListContent` and keeps the `dismiss()` behavior in its own `onTap` closure:

```swift
struct CurrencyPickerView: View {
    let selectedCurrency: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CurrencyListContent(selectedCurrency: selectedCurrency) { code in
            onSelect(code)
            dismiss()
        }
        .navigationTitle(String(localized: "currency.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

Delete the now-unused `searchText` state, `filteredCurrencies` / `showPopularSection` / `currencyRow` from `CurrencyPickerView` (they migrated into `CurrencyListContent`).

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Views/Settings/CurrencyListContent.swift Tenra/Views/Settings/CurrencyPickerView.swift
git commit -m "refactor(settings): extract CurrencyListContent for reuse in onboarding"
```

---

## Task 8: `OnboardingProgressBar` and `OnboardingPageContainer`

**Files:**
- Create: `Tenra/Views/Onboarding/Components/OnboardingProgressBar.swift`
- Create: `Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift`

- [ ] **Step 1: Create the progress bar**

Create `Tenra/Views/Onboarding/Components/OnboardingProgressBar.swift`:

```swift
//
//  OnboardingProgressBar.swift
//  Tenra
//
//  3-dot progress indicator for the data-collection portion of onboarding.
//

import SwiftUI

struct OnboardingProgressBar: View {
    let totalSteps: Int
    let currentStep: Int  // 1-based

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index < currentStep ? AppColors.accentPrimary : AppColors.textSecondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .animation(AppAnimation.contentSpring, value: currentStep)
    }
}
```

- [ ] **Step 2: Create the page container**

Create `Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift`:

```swift
//
//  OnboardingPageContainer.swift
//  Tenra
//
//  Shared layout for onboarding data-collection steps:
//  progress bar (top), title + subtitle, body content, primary CTA pinned at the bottom.
//

import SwiftUI

struct OnboardingPageContainer<Content: View>: View {
    let progressStep: Int            // 1, 2, or 3
    let title: String
    let subtitle: String?
    let primaryButtonTitle: String
    let primaryButtonEnabled: Bool
    let onPrimaryTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressBar(totalSteps: 3, currentStep: progressStep)
                .padding(.top, AppSpacing.lg)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.title)
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

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Views/Onboarding/Components/OnboardingProgressBar.swift Tenra/Views/Onboarding/Components/OnboardingPageContainer.swift
git commit -m "feat(onboarding): add progress bar and page container components"
```

---

## Task 9: `OnboardingWelcomePage`

**Files:**
- Create: `Tenra/Views/Onboarding/OnboardingWelcomePage.swift`

- [ ] **Step 1: Create the page**

Create `Tenra/Views/Onboarding/OnboardingWelcomePage.swift`:

```swift
//
//  OnboardingWelcomePage.swift
//  Tenra
//

import SwiftUI

struct OnboardingWelcomePage: View {
    let sfSymbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: sfSymbol)
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(AppColors.accentPrimary)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Onboarding/OnboardingWelcomePage.swift
git commit -m "feat(onboarding): add OnboardingWelcomePage view"
```

---

## Task 10: `OnboardingCurrencyStep`

**Files:**
- Create: `Tenra/Views/Onboarding/OnboardingCurrencyStep.swift`

- [ ] **Step 1: Create the step view**

Create `Tenra/Views/Onboarding/OnboardingCurrencyStep.swift`:

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
            }
        ) {
            CurrencyListContent(selectedCurrency: vm.draftCurrency) { code in
                vm.draftCurrency = code
            }
            .padding(.top, AppSpacing.md)
        }
        .navigationBarBackButtonHidden(false)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Onboarding/OnboardingCurrencyStep.swift
git commit -m "feat(onboarding): add Currency step view"
```

---

## Task 11: `OnboardingAccountStep`

**Files:**
- Create: `Tenra/Views/Onboarding/OnboardingAccountStep.swift`

- [ ] **Step 1: Create the step view**

Create `Tenra/Views/Onboarding/OnboardingAccountStep.swift`:

```swift
//
//  OnboardingAccountStep.swift
//  Tenra
//

import SwiftUI

struct OnboardingAccountStep: View {
    @Bindable var vm: OnboardingViewModel
    @State private var showIconPicker = false

    var body: some View {
        OnboardingPageContainer(
            progressStep: 2,
            title: String(localized: "onboarding.account.title"),
            subtitle: String(localized: "onboarding.account.subtitle"),
            primaryButtonTitle: String(localized: "onboarding.cta.next"),
            primaryButtonEnabled: vm.canAdvanceFromAccountStep,
            onPrimaryTap: {
                Task { await vm.advanceToCategoriesStep() }
            }
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    formSection
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            NavigationStack {
                IconPickerView(selection: $vm.draftAccount.iconSource)
            }
        }
    }

    @ViewBuilder
    private var formSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "onboarding.account.nameLabel"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                TextField(String(localized: "onboarding.account.namePlaceholder"), text: $vm.draftAccount.name)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            Divider().padding(.leading, AppSpacing.lg)

            Button {
                showIconPicker = true
            } label: {
                HStack {
                    Text(String(localized: "onboarding.account.iconLabel"))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    IconView(source: vm.draftAccount.iconSource, style: .compact)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.caption)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, AppSpacing.lg)

            HStack {
                Text(String(localized: "onboarding.account.balanceLabel"))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                AmountInput(
                    value: $vm.draftAccount.balance,
                    baseFontSize: 17,
                    color: AppColors.textPrimary,
                    placeholderColor: AppColors.textSecondary,
                    autoFocus: false,
                    showContextMenu: false,
                    onAmountChange: nil
                )
                .frame(maxWidth: 160)
                Text(vm.draftCurrency)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .cardStyle()
    }
}
```

> **Note for the implementer:** `IconView`'s exact init and `IconPickerView`'s exact API may differ. If the build fails on the `IconView(source: style:)` or `IconPickerView(selection:)` line, grep for an existing call site (e.g. `grep -rn "IconPickerView(" Tenra/Views/`) and copy the parameter shape. The `AmountInput` init shape used here matches its definition in `Tenra/Views/Components/Input/AnimatedInputComponents.swift`.

- [ ] **Step 2: Build and adjust to match real `IconView` / `IconPickerView` APIs**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

If errors mention `IconView` or `IconPickerView`, run:

```bash
grep -rn "IconPickerView(" /Users/dauletkydrali/Documents/GitHub/Tenra/Tenra/Views | head -5
grep -rn "IconView(source:" /Users/dauletkydrali/Documents/GitHub/Tenra/Tenra/Views/Components/Icons | head -5
```

Match the parameter shape from a known good call site. The intent is unchanged: an icon row that opens the existing icon picker bound to `vm.draftAccount.iconSource`.

After fixing, rebuild — expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Onboarding/OnboardingAccountStep.swift
git commit -m "feat(onboarding): add Account step view with name + icon + balance form"
```

---

## Task 12: `CategoryPresetCell` + `OnboardingCategoriesStep`

**Files:**
- Create: `Tenra/Views/Onboarding/Components/CategoryPresetCell.swift`
- Create: `Tenra/Views/Onboarding/OnboardingCategoriesStep.swift`

- [ ] **Step 1: Create the cell**

Create `Tenra/Views/Onboarding/Components/CategoryPresetCell.swift`:

```swift
//
//  CategoryPresetCell.swift
//  Tenra
//

import SwiftUI

struct CategoryPresetCell: View {
    let preset: CategoryPreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(Color(hex: preset.colorHex))
                        .frame(width: 56, height: 56)
                        .overlay(
                            iconImage
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(AppColors.accentPrimary, lineWidth: isSelected ? 2 : 0)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.accentPrimary, AppColors.backgroundPrimary)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(String(localized: String.LocalizationValue(preset.nameKey)))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .opacity(isSelected ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(AppAnimation.contentSpring, value: isSelected)
    }

    @ViewBuilder
    private var iconImage: some View {
        switch preset.iconSource {
        case .sfSymbol(let name):
            Image(systemName: name)
        case .brandService:
            Image(systemName: "questionmark.circle")  // not expected for presets
        }
    }
}
```

> **Note:** `Color(hex:)` is a convenience init that may live in `Extensions/Color+Hex.swift` or similar. If the build fails, grep `grep -rn "extension Color" /Users/dauletkydrali/Documents/GitHub/Tenra/Tenra/Extensions | head -5` and adjust. If no such init exists, parse the hex inline:
>
> ```swift
> private func parseHex(_ hex: String) -> Color {
>     var s = hex
>     if s.hasPrefix("#") { s.removeFirst() }
>     var v: UInt64 = 0
>     Scanner(string: s).scanHexInt64(&v)
>     return Color(red: Double((v >> 16) & 0xFF)/255, green: Double((v >> 8) & 0xFF)/255, blue: Double(v & 0xFF)/255)
> }
> ```

- [ ] **Step 2: Create the step view**

Create `Tenra/Views/Onboarding/OnboardingCategoriesStep.swift`:

```swift
//
//  OnboardingCategoriesStep.swift
//  Tenra
//

import SwiftUI

struct OnboardingCategoriesStep: View {
    @Bindable var vm: OnboardingViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 3
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.md), count: count)
    }

    private var doneTitle: String {
        let count = vm.selectedPresetCount
        return String(format: String(localized: "onboarding.cta.doneWithCount"), count)
    }

    var body: some View {
        OnboardingPageContainer(
            progressStep: 3,
            title: String(localized: "onboarding.categories.title"),
            subtitle: String(localized: "onboarding.categories.subtitle"),
            primaryButtonTitle: doneTitle,
            primaryButtonEnabled: vm.canFinish,
            onPrimaryTap: {
                Task { await vm.finish() }
            }
        ) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                    ForEach(vm.draftCategories.indices, id: \.self) { idx in
                        let preset = vm.draftCategories[idx].preset
                        let isSelected = vm.draftCategories[idx].isSelected
                        CategoryPresetCell(preset: preset, isSelected: isSelected) {
                            vm.draftCategories[idx].isSelected.toggle()
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```
Expected: empty (after `Color(hex:)` adjustment if needed).

- [ ] **Step 4: Commit**

```bash
git add Tenra/Views/Onboarding/Components/CategoryPresetCell.swift Tenra/Views/Onboarding/OnboardingCategoriesStep.swift
git commit -m "feat(onboarding): add Categories step grid with preset cells"
```

---

## Task 13: `OnboardingFlowView` (root container)

**Files:**
- Create: `Tenra/Views/Onboarding/OnboardingFlowView.swift`

- [ ] **Step 1: Create the root**

Create `Tenra/Views/Onboarding/OnboardingFlowView.swift`:

```swift
//
//  OnboardingFlowView.swift
//  Tenra
//
//  Root view of the onboarding experience: welcome carousel followed by a
//  NavigationStack-driven 3-step data collection flow.
//

import SwiftUI

struct OnboardingFlowView: View {
    @State private var vm: OnboardingViewModel
    @State private var hasStartedDataCollection = false

    init(coordinator: AppCoordinator) {
        _vm = State(wrappedValue: OnboardingViewModel(coordinator: coordinator))
    }

    var body: some View {
        if hasStartedDataCollection {
            NavigationStack(path: $vm.path) {
                OnboardingCurrencyStep(vm: vm)
                    .navigationDestination(for: OnboardingStep.self) { step in
                        switch step {
                        case .currency:
                            OnboardingCurrencyStep(vm: vm)
                        case .account:
                            OnboardingAccountStep(vm: vm)
                        case .categories:
                            OnboardingCategoriesStep(vm: vm)
                        }
                    }
            }
        } else {
            welcomeCarousel
        }
    }

    @ViewBuilder
    private var welcomeCarousel: some View {
        VStack(spacing: 0) {
            TabView(selection: $vm.welcomePage) {
                OnboardingWelcomePage(
                    sfSymbol: "chart.pie.fill",
                    title: String(localized: "onboarding.welcome.page1.title"),
                    subtitle: String(localized: "onboarding.welcome.page1.subtitle")
                )
                .tag(0)

                OnboardingWelcomePage(
                    sfSymbol: "mic.fill",
                    title: String(localized: "onboarding.welcome.page2.title"),
                    subtitle: String(localized: "onboarding.welcome.page2.subtitle")
                )
                .tag(1)

                OnboardingWelcomePage(
                    sfSymbol: "lock.shield.fill",
                    title: String(localized: "onboarding.welcome.page3.title"),
                    subtitle: String(localized: "onboarding.welcome.page3.subtitle")
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: handlePrimaryTap) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(AppColors.backgroundPrimary.ignoresSafeArea())
    }

    private var primaryTitle: String {
        vm.welcomePage == 2
            ? String(localized: "onboarding.cta.start")
            : String(localized: "onboarding.cta.next")
    }

    private func handlePrimaryTap() {
        if vm.welcomePage < 2 {
            withAnimation(AppAnimation.contentSpring) {
                vm.welcomePage += 1
            }
        } else {
            vm.startDataCollection()
            withAnimation(AppAnimation.contentSpring) {
                hasStartedDataCollection = true
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Views/Onboarding/OnboardingFlowView.swift
git commit -m "feat(onboarding): add OnboardingFlowView root with welcome carousel + NavigationStack"
```

---

## Task 14: Wire `OnboardingFlowView` into `TenraApp`

**Files:**
- Modify: `Tenra/TenraApp.swift`

- [ ] **Step 1: Branch on `needsOnboarding`**

Replace the `Group` body inside `WindowGroup` with:

```swift
            Group {
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
                } else {
                    AppColors.backgroundPrimary.ignoresSafeArea()
                }
            }
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -10
```
Expected: empty.

- [ ] **Step 3: Manual smoke test**

Boot a fresh simulator (or `xcrun simctl erase all`), then run from Xcode:

1. Launch app → welcome page 1 visible.
2. Tap "Next" → welcome page 2.
3. Tap "Next" → welcome page 3.
4. Tap "Get started" → currency picker, KZT pre-selected.
5. Tap a different currency (e.g. USD) → "Next" button.
6. Account step appears. Type "Kaspi", balance 1000, tap "Next".
7. Categories step appears, all 15 selected. Tap a few to deselect (e.g. Pets), CTA shows "Done • 14 selected".
8. Tap "Done" → MainTabView appears.
9. Verify: account "Kaspi" with 1000 USD shows on Home; deselected categories are NOT in Categories list; selected ones ARE present.
10. Background app, kill, relaunch → MainTabView appears immediately (onboarding flag is set).
11. Settings → Danger Zone → Reset all data → kill & relaunch → onboarding shows again.

Document any issues that come up during smoke as follow-up commits before moving on.

- [ ] **Step 4: Commit**

```bash
git add Tenra/TenraApp.swift
git commit -m "feat(onboarding): gate MainTabView behind onboarding flow on first launch"
```

---

## Task 15: Run the full test suite

- [ ] **Step 1: Run all onboarding tests**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/OnboardingStateTests -only-testing:TenraTests/CategoryPresetTests -only-testing:TenraTests/OnboardingViewModelTests
```
Expected: all green.

- [ ] **Step 2: Run the broader unit test bucket to verify no regressions**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | tail -30
```
Expected: `** TEST SUCCEEDED **` and no test count regression vs baseline.

- [ ] **Step 3: If anything fails**

Address the regression as a focused fix commit before declaring done. Do not push if tests are red.

---

## Out-of-scope (do not implement here)

- Snapshot tests for each step (RU/EN × light/dark) — nice-to-have, follow-up.
- An income-categories mini-section on Step 3 — explicitly cut in spec §1.2.
- CSV/PDF import branching from welcome — explicitly cut in spec §1.2.
- Deposits/loans creation in onboarding — explicitly cut in spec §1.2.
- Re-styling existing Account form components beyond what's needed for onboarding reuse.

---

## Self-review notes

Spec coverage map:
- §1.3 flow (welcome → currency → account → categories → MainTabView): Tasks 13, 14
- §2.1 routing at TenraApp: Task 14
- §2.2 file layout: matches plan file map
- §3.1 OnboardingViewModel: Task 4
- §3.2 OnboardingState: Task 1
- §3.3 needsOnboarding mirror + iCloud-restore: Task 5
- §4.1 welcome carousel: Tasks 9, 13
- §4.2 currency step: Tasks 7, 10
- §4.3 account step: Task 11 (with documented spec deviation: no `type`/`colorHex` fields)
- §4.4 categories step: Tasks 2, 12
- §5 persistence rules: encoded in Task 4 (`advanceToAccountStep` early-commit, `finish()` final commit)
- §6 edge cases: covered (kill mid-flow → flag stays false; back-and-forth account update path; iCloud restore reconcile in Task 5; reset-all-data in Task 6)
- §7 animations & tokens: applied throughout view tasks
- §8 localization: Task 3
- §9 tests: Tasks 1, 2, 4 + Task 15. **Coverage gap (intentional):** spec listed 5 unit test cases. Tasks 1, 2, 4 cover the draft-state and validation predicates directly. The three commit-pipeline assertions ("complete() creates exactly selectedCount categories", "complete() writes baseCurrency to appSettings", "back-to-step-2 triggers update not addAccount") would require introducing a coordinator protocol + fakes, which is a larger refactor than this plan justifies. They are covered by the manual smoke checklist in Task 14, Step 3 — bullets 6, 7, 8, 9. Document this explicitly so the implementer doesn't try to bolt on mocks mid-task.
- §10 logging: hooks added in Tasks 4 and 5
- §11 reuse: Task 7 extracts `CurrencyListContent`. Spec also suggested extracting `AccountFormView` from `AccountAddView` — we built a slim inline form in Task 11 instead, which is simpler and matches the trimmed `AccountDraft` (no `type`/`colorHex`). If a future task wants to unify, that's a follow-up refactor outside this plan.
- §12 open items: not in scope.

No placeholders. All code blocks are concrete. The two `// note for implementer` callouts (in Tasks 11 and 12) are acceptable: they tell the implementer how to verify a real API surface against existing code rather than asking them to invent something.
