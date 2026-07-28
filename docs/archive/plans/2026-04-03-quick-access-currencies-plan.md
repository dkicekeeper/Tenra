# Quick-Access Currencies Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the transaction currency Menu configurable — user picks which currencies appear, account currencies always included automatically.

**Architecture:** `AppSettings` stores `quickAccessCurrencies: [String]`. `CurrencySelectorView` merges account currencies + user picks + "Customize..." item. "Customize..." opens a sheet with `QuickAccessCurrencyPickerView` (fullscreen multiselect with search).

**Tech Stack:** SwiftUI, Foundation, UserDefaults (via AppSettings Codable persistence)

---

### Task 1: Add quickAccessCurrencies to AppSettings

**Files:**
- Modify: `Tenra/Models/AppSettings.swift`

**Step 1: Add the property and update Codable**

Add `quickAccessCurrencies` property after `blurWallpaper`:

```swift
/// Currencies shown in the quick-access transaction currency Menu.
/// Account currencies are always included automatically (not stored here).
var quickAccessCurrencies: [String]
```

Add to `CodingKeys`:
```swift
case quickAccessCurrencies
```

Update `init(...)` — add parameter with default:
```swift
init(
    baseCurrency: String = defaultCurrency,
    wallpaperImageName: String? = nil,
    homeBackgroundMode: HomeBackgroundMode = .none,
    blurWallpaper: Bool = false,
    quickAccessCurrencies: [String] = ["USD", "EUR"]
) {
    ...
    self.quickAccessCurrencies = quickAccessCurrencies
}
```

Update `init(from decoder:)` — backward-compatible:
```swift
quickAccessCurrencies = (try? container.decodeIfPresent([String].self, forKey: .quickAccessCurrencies)) ?? ["USD", "EUR"]
```

Update `encode(to:)`:
```swift
try container.encode(quickAccessCurrencies, forKey: .quickAccessCurrencies)
```

Update `update(from:)`:
```swift
quickAccessCurrencies = other.quickAccessCurrencies
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

**Step 3: Commit**

```
feat: add quickAccessCurrencies to AppSettings
```

---

### Task 2: Create QuickAccessCurrencyPickerView

**Files:**
- Create: `Tenra/Views/Settings/QuickAccessCurrencyPickerView.swift`

**Step 1: Create the multiselect currency picker**

```swift
//
//  QuickAccessCurrencyPickerView.swift
//  Tenra
//
//  Fullscreen multiselect currency list for configuring which currencies
//  appear in the transaction currency Menu.
//

import SwiftUI

struct QuickAccessCurrencyPickerView: View {
    @Binding var selectedCurrencyCodes: Set<String>
    let accountCurrencies: Set<String>

    @State private var searchText = ""

    // MARK: - Filtered Data

    private var filteredCurrencies: [CurrencyInfo] {
        guard !searchText.isEmpty else {
            return CurrencyInfo.allCurrencies
        }
        let query = searchText.lowercased()
        return CurrencyInfo.allCurrencies.filter {
            $0.code.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    private var accountCurrencyInfos: [CurrencyInfo] {
        accountCurrencies.compactMap { CurrencyInfo.find($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var showAccountSection: Bool {
        searchText.isEmpty && !accountCurrencies.isEmpty
    }

    // MARK: - Body

    var body: some View {
        List {
            if showAccountSection {
                Section(header: Text(String(localized: "currency.accountCurrencies"))) {
                    ForEach(accountCurrencyInfos) { currency in
                        lockedRow(currency)
                    }
                }
            }

            Section(header: Text(String(localized: "currency.all"))) {
                ForEach(filteredCurrencies) { currency in
                    if !accountCurrencies.contains(currency.code) || !searchText.isEmpty {
                        toggleRow(currency)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "currency.customize"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: String(localized: "currency.searchPrompt")
        )
    }

    // MARK: - Rows

    /// Account currencies — always included, can't be toggled off.
    private func lockedRow(_ currency: CurrencyInfo) -> some View {
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

            Image(systemName: "checkmark")
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    /// User-selectable currencies.
    private func toggleRow(_ currency: CurrencyInfo) -> some View {
        Button {
            if selectedCurrencyCodes.contains(currency.code) {
                selectedCurrencyCodes.remove(currency.code)
            } else {
                selectedCurrencyCodes.insert(currency.code)
            }
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

                if selectedCurrencyCodes.contains(currency.code) {
                    Image(systemName: "checkmark")
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selected: Set<String> = ["USD", "EUR"]
    NavigationStack {
        QuickAccessCurrencyPickerView(
            selectedCurrencyCodes: $selected,
            accountCurrencies: ["KZT", "USD"]
        )
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

**Step 3: Commit**

```
feat: add QuickAccessCurrencyPickerView for transaction currency customization
```

---

### Task 3: Add localization keys

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

**Step 1: Add English keys after existing `currency.*` keys**

```strings
"currency.customize" = "Customize Currencies";
"currency.accountCurrencies" = "Account Currencies";
"currency.customizeAction" = "Customize...";
```

**Step 2: Add Russian keys**

```strings
"currency.customize" = "Настроить валюты";
"currency.accountCurrencies" = "Валюты счетов";
"currency.customizeAction" = "Настроить...";
```

**Step 3: Commit**

```
feat: add quick-access currency localization keys (en + ru)
```

---

### Task 4: Update CurrencySelectorView with configurable Menu

**Files:**
- Modify: `Tenra/Views/Components/Input/CurrencySelectorView.swift`

**Step 1: Rework the component**

The CurrencySelectorView needs to:
1. Accept `accountCurrencies: Set<String>` — currencies from user's accounts
2. Accept `appSettings: AppSettings` — to read/write `quickAccessCurrencies`
3. Compute merged currency list: `accountCurrencies ∪ quickAccessCurrencies`
4. Add "Customize..." menu item that opens a sheet

Replace the entire file:

```swift
//
//  CurrencySelectorView.swift
//  Tenra
//
//  Configurable currency selector using Menu picker.
//  Shows account currencies + user's quick-access picks + "Customize..." action.
//

import SwiftUI

struct CurrencySelectorView: View {
    @Binding var selectedCurrency: String
    let accountCurrencies: Set<String>
    let appSettings: AppSettings

    @State private var showingCustomize = false

    /// Merged, deduplicated, sorted currency list for the Menu.
    private var menuCurrencies: [CurrencyInfo] {
        let quickAccess = Set(appSettings.quickAccessCurrencies)
        let allCodes = accountCurrencies.union(quickAccess)
        return allCodes
            .compactMap { CurrencyInfo.find($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            currencyMenu
        }
        .sheet(isPresented: $showingCustomize) {
            NavigationStack {
                QuickAccessCurrencyPickerView(
                    selectedCurrencyCodes: Binding(
                        get: { Set(appSettings.quickAccessCurrencies) },
                        set: { appSettings.quickAccessCurrencies = Array($0).sorted() }
                    ),
                    accountCurrencies: accountCurrencies
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "button.done")) {
                            showingCustomize = false
                        }
                    }
                }
            }
        }
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(menuCurrencies) { currency in
                Button(action: {
                    selectedCurrency = currency.code
                    HapticManager.selection()
                }) {
                    HStack {
                        Text("\(currency.code) \(currency.symbol)")
                        Spacer()
                        if selectedCurrency == currency.code {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button(action: {
                showingCustomize = true
            }) {
                Label(
                    String(localized: "currency.customizeAction"),
                    systemImage: "slider.horizontal.3"
                )
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(Formatting.currencySymbol(for: selectedCurrency))
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.sm))
            }
            .filterChipStyle(isSelected: false)
        }
    }
}

#Preview("Currency Selector") {
    @Previewable @State var selectedCurrency = "KZT"

    return CurrencySelectorView(
        selectedCurrency: $selectedCurrency,
        accountCurrencies: ["KZT", "USD"],
        appSettings: .makeDefault()
    )
    .padding()
}
```

**Step 2: Build — expect errors in AmountInputView (fixed in Task 5)**

**Step 3: Commit (may need to be combined with Task 5 if build fails)**

---

### Task 5: Update AmountInputView and transaction forms

**Files:**
- Modify: `Tenra/Views/Components/Input/AmountInputView.swift`
- Modify: `Tenra/Views/Transactions/TransactionAddModal.swift`
- Modify: `Tenra/Views/Transactions/TransactionEditView.swift`

**Step 1: Update AmountInputView to pass new props**

Add two new properties:

```swift
let accountCurrencies: Set<String>
let appSettings: AppSettings
```

Update `CurrencySelectorView` call (line 38):

```swift
CurrencySelectorView(
    selectedCurrency: $selectedCurrency,
    accountCurrencies: accountCurrencies,
    appSettings: appSettings
)
```

Update previews to pass the new props.

**Step 2: Update TransactionAddModal.swift**

In `formContent` (line 130-138), add the new props to `AmountInputView`:

```swift
AmountInputView(
    amount: $bindableCoordinator.formData.amountText,
    selectedCurrency: $bindableCoordinator.formData.currency,
    errorMessage: validationError,
    baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
    accountCurrencies: Set(coordinator.accountsViewModel.accounts.map(\.currency)),
    appSettings: coordinator.transactionsViewModel.appSettings,
    onAmountChange: { _ in
        validationError = nil
    }
)
```

**Step 3: Update TransactionEditView.swift**

In the `AmountInputView` call (~line 73-78), add:

```swift
AmountInputView(
    amount: $bindableCoordinator.formData.amountText,
    selectedCurrency: $bindableCoordinator.formData.selectedCurrency,
    errorMessage: nil,
    baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
    accountCurrencies: Set(_accounts.map(\.currency)),
    appSettings: coordinator.transactionsViewModel.appSettings
)
```

**Step 4: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

**Step 5: Commit**

```
feat: wire up configurable currency Menu in transaction forms
```

---

### Task 6: Persist quickAccessCurrencies on change

**Files:**
- Verify: `Tenra/Models/AppSettings.swift` — `save()` already encodes all Codable properties

**Step 1: Verify persistence works**

The existing `AppSettings.save()` method uses `JSONEncoder().encode(self)` which will include `quickAccessCurrencies` since it's in `CodingKeys`. The `update(from:)` method copies it. Both paths already handle the new field.

However, the `CurrencySelectorView` writes to `appSettings.quickAccessCurrencies` directly (via binding). Need to ensure this triggers save.

Add `.onChange(of: appSettings.quickAccessCurrencies)` in `CurrencySelectorView` to call `appSettings.save()`:

In `CurrencySelectorView.body`, add after `.sheet(...)`:

```swift
.onChange(of: appSettings.quickAccessCurrencies) { _, _ in
    appSettings.save()
}
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`

**Step 3: Commit**

```
feat: persist quickAccessCurrencies on change
```
