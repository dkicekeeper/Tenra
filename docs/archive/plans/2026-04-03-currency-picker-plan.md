# Currency Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace hardcoded 7-currency Menu with a full-screen searchable currency list (~150 ISO currencies) for base currency selection in Settings and account/deposit/loan creation.

**Architecture:** New `CurrencyInfo` model generates currency data from Foundation's `Locale.Currency.isoCurrencies`. New `CurrencyPickerView` renders a searchable `List` with "Popular" (regional + USD + EUR) and "All" sections. Settings and account edit views navigate to it via `NavigationLink` / `.navigationDestination`. `CurrencySelectorView` (compact Menu in transaction forms) remains unchanged.

**Tech Stack:** SwiftUI, Foundation (Locale.Currency, NumberFormatter)

---

### Task 1: Create CurrencyInfo model

**Files:**
- Create: `Tenra/Models/CurrencyInfo.swift`

**Step 1: Create the CurrencyInfo struct and static builder**

```swift
//
//  CurrencyInfo.swift
//  Tenra
//

import Foundation

/// Lightweight currency descriptor built from iOS Locale APIs.
/// Name and symbol are localized automatically via Foundation.
struct CurrencyInfo: Identifiable, Sendable, Equatable {
    let code: String   // "USD"
    let name: String   // "Доллар США" / "US Dollar"
    let symbol: String // "$"

    var id: String { code }

    // MARK: - Static Builders

    /// All ISO currencies sorted A-Z by localized name.
    /// Computed once per app launch (locale doesn't change at runtime).
    nonisolated static let allCurrencies: [CurrencyInfo] = {
        let locale = Locale.current
        // Use a USD-based locale to reliably extract pure currency symbols
        let symbolExtractor = NumberFormatter()
        symbolExtractor.numberStyle = .currency
        symbolExtractor.maximumFractionDigits = 0
        symbolExtractor.minimumFractionDigits = 0

        var seen = Set<String>()
        var result: [CurrencyInfo] = []

        for isoCurrency in Locale.Currency.isoCurrencies {
            let code = isoCurrency.identifier
            guard !seen.contains(code) else { continue }
            seen.insert(code)

            let name = locale.localizedString(forCurrencyCode: code) ?? code
            // Skip currencies with no proper localized name
            guard name != code || code.count == 3 else { continue }

            // Extract symbol via NumberFormatter
            symbolExtractor.currencyCode = code
            let formatted = symbolExtractor.string(from: 0) ?? code
            // Strip the "0" and whitespace to get just the symbol
            let symbol = formatted
                .replacingOccurrences(of: "0", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: "")  // non-breaking space
                .trimmingCharacters(in: .whitespaces)

            let finalSymbol = symbol.isEmpty ? code : symbol

            result.append(CurrencyInfo(code: code, name: name, symbol: finalSymbol))
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Top-3 "popular" currencies: device regional + USD + EUR (deduplicated).
    nonisolated static let popularCurrencies: [CurrencyInfo] = {
        let regionalCode = Locale.current.currency?.identifier ?? "KZT"
        var codes: [String] = [regionalCode]
        if regionalCode != "USD" { codes.append("USD") }
        if regionalCode != "EUR" { codes.append("EUR") }

        let lookup = Dictionary(uniqueKeysWithValues: allCurrencies.map { ($0.code, $0) })
        return codes.compactMap { lookup[$0] }
    }()

    /// Look up a single CurrencyInfo by code. O(1) after first access.
    nonisolated static func find(_ code: String) -> CurrencyInfo? {
        lookupTable[code]
    }

    private nonisolated static let lookupTable: [String: CurrencyInfo] = {
        Dictionary(uniqueKeysWithValues: allCurrencies.map { ($0.code, $0) })
    }()
}
```

**Step 2: Build and verify no compile errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors (or only pre-existing ones)

**Step 3: Commit**

```
feat: add CurrencyInfo model with ISO currency list from Locale API
```

---

### Task 2: Create CurrencyPickerView

**Files:**
- Create: `Tenra/Views/Settings/CurrencyPickerView.swift`

**Step 1: Create the full-screen currency picker view**

```swift
//
//  CurrencyPickerView.swift
//  Tenra
//
//  Full-screen searchable currency list with "Popular" and "All" sections.
//

import SwiftUI

struct CurrencyPickerView: View {
    let selectedCurrency: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
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

    private var showPopularSection: Bool {
        searchText.isEmpty
    }

    // MARK: - Body

    var body: some View {
        List {
            if showPopularSection {
                Section(header: Text(String(localized: "currency.popular"))) {
                    ForEach(CurrencyInfo.popularCurrencies) { currency in
                        currencyRow(currency)
                    }
                }
            }

            Section(header: Text(String(localized: "currency.all"))) {
                ForEach(filteredCurrencies) { currency in
                    currencyRow(currency)
                }
            }
        }
        .navigationTitle(String(localized: "currency.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: String(localized: "currency.searchPrompt")
        )
    }

    // MARK: - Row

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            onSelect(currency.code)
            HapticManager.selection()
            dismiss()
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
    NavigationStack {
        CurrencyPickerView(selectedCurrency: "KZT") { code in
            print("Selected: \(code)")
        }
    }
}
```

**Step 2: Build and verify no compile errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```
feat: add CurrencyPickerView with search and popular section
```

---

### Task 3: Add localization keys

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

**Step 1: Add English keys after line 86 (after `settings.baseCurrency`)**

```strings
"currency.title" = "Currency";
"currency.popular" = "Popular";
"currency.all" = "All Currencies";
"currency.searchPrompt" = "Search currency";
```

**Step 2: Add Russian keys after line 86 (after `settings.baseCurrency`)**

```strings
"currency.title" = "Валюта";
"currency.popular" = "Популярные";
"currency.all" = "Все валюты";
"currency.searchPrompt" = "Поиск валюты";
```

**Step 3: Commit**

```
feat: add currency picker localization keys (en + ru)
```

---

### Task 4: Wire up SettingsGeneralSection

**Files:**
- Modify: `Tenra/Views/Settings/SettingsGeneralSection.swift`

**Step 1: Replace Menu-based currency picker with NavigationLink**

Replace the `currencyMenu` computed property and the row that uses it. The `UniversalRow` with currency becomes a `NavigationLink` to `CurrencyPickerView`.

In `body`, replace the entire currency UniversalRow block (lines 42-53) with:

```swift
NavigationLink {
    CurrencyPickerView(
        selectedCurrency: selectedCurrency,
        onSelect: onCurrencyChange
    )
} label: {
    UniversalRow(
        config: .settings,
        leadingIcon: .sfSymbol("dollarsign.circle",
                               color: AppColors.accent,
                               size: AppIconSize.md)
    ) {
        Text(String(localized: "settings.baseCurrency"))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textPrimary)
    } trailing: {
        HStack(spacing: AppSpacing.sm) {
            Text(Formatting.currencySymbol(for: selectedCurrency))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
            Text(selectedCurrency)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
```

Delete the `currencyMenu` computed property (lines 67-91) — it's no longer used.

Remove `availableCurrencies` from the struct's props and initializer (no longer needed — `CurrencyPickerView` gets its own data from `CurrencyInfo`).

**Step 2: Update SettingsView.swift call site (line 137)**

Remove `availableCurrencies: AppSettings.availableCurrencies,` from the `SettingsGeneralSection(...)` initializer call.

**Step 3: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```
feat: settings base currency uses full-screen CurrencyPickerView
```

---

### Task 5: Wire up EditableHeroSection for accounts

**Files:**
- Modify: `Tenra/Views/Components/Forms/EditableHeroSection.swift`
- Modify: `Tenra/Views/Accounts/AccountEditView.swift`
- Modify: `Tenra/Views/Deposits/DepositEditView.swift`
- Modify: `Tenra/Views/Loans/LoanEditView.swift`

**Step 1: Replace CurrencySelectorView with NavigationLink in EditableHeroSection**

In `balanceView` (lines 150-167), replace the `CurrencySelectorView` block (lines 159-165) with a NavigationLink-based currency button:

```swift
if config.showCurrency {
    NavigationLink {
        CurrencyPickerView(
            selectedCurrency: currency,
            onSelect: { newCurrency in
                currency = newCurrency
            }
        )
    } label: {
        HStack(spacing: AppSpacing.sm) {
            Text(Formatting.currencySymbol(for: currency))
            Text(currency)
                .font(AppTypography.bodySmall)
            Image(systemName: "chevron.right")
                .font(.system(size: AppIconSize.sm))
        }
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.secondaryBackground)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
}
```

Remove `currencies` and `baseCurrency` from the struct's properties and initializer — no longer needed (CurrencyPickerView is self-contained).

**Step 2: Update AccountEditView.swift (line 54)**

Remove `currencies: AppSettings.availableCurrencies` from the `EditableHeroSection(...)` call.

**Step 3: Update DepositEditView.swift**

Remove the `private let depositCurrencies = ["KZT", "USD", "EUR"]` (line 25) and `currencies: depositCurrencies` (line 50) from the `EditableHeroSection` call.

**Step 4: Update LoanEditView.swift**

Remove the `private let currencies = ["KZT", "USD", "EUR"]` (line 31) and `currencies: currencies` (line 75) from the `EditableHeroSection` call.

**Step 5: Update SubscriptionEditView.swift**

Remove `baseCurrency: transactionsViewModel.appSettings.baseCurrency` (line 72) from the `EditableHeroSection` call if present.

**Step 6: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 7: Commit**

```
feat: account/deposit/loan edit views use full-screen currency picker
```

---

### Task 6: Update AppSettings, validation, and Formatting

**Files:**
- Modify: `Tenra/Models/AppSettings.swift`
- Modify: `Tenra/Services/Settings/SettingsValidationService.swift`
- Modify: `Tenra/Utils/Formatting.swift`

**Step 1: Update AppSettings.swift**

Remove the hardcoded `availableCurrencies` array (line 43). Replace `isValid` (line 48-50) to use `CurrencyInfo`:

```swift
var isValid: Bool {
    CurrencyInfo.find(baseCurrency) != nil
}
```

Keep `defaultCurrency` as-is.

**Step 2: Update SettingsValidationService.swift**

Replace `AppSettings.availableCurrencies.contains(currency)` (line 29) with:

```swift
guard CurrencyInfo.find(currency) != nil else {
    throw SettingsValidationError.invalidCurrency(currency)
}
```

**Step 3: Update Formatting.swift**

Extend `currencySymbol(for:)` (line 25-27) with a Locale fallback when the code isn't in the hardcoded map:

```swift
static func currencySymbol(for currency: String) -> String {
    if let symbol = currencySymbols[currency.uppercased()] {
        return symbol
    }
    // Fallback: use CurrencyInfo lookup (covers all ISO currencies)
    if let info = CurrencyInfo.find(currency.uppercased()) {
        return info.symbol
    }
    return currency
}
```

**Step 4: Grep for remaining references to `AppSettings.availableCurrencies`**

Run: `grep -rn "availableCurrencies" Tenra/`
Expected: No matches (all references removed in Tasks 4-6). If any remain, update them.

**Step 5: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 6: Commit**

```
refactor: remove hardcoded currency list, use CurrencyInfo for validation and formatting
```

---

### Task 7: Clean up CurrencySelectorView default list

**Files:**
- Modify: `Tenra/Views/Components/Input/CurrencySelectorView.swift`

**Step 1: Update default `availableCurrencies` parameter**

The compact Menu picker in transaction forms keeps its Menu UI but should use a reasonable default list that includes more common currencies. Update the default (line 19):

```swift
availableCurrencies: [String] = CurrencyInfo.popularCurrencies.map(\.code) + ["RUB", "GBP", "CNY", "JPY"],
```

This gives the transaction form a sensible ~7-9 item menu without requiring full-screen navigation.

**Step 2: Build and verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```
refactor: CurrencySelectorView uses CurrencyInfo.popularCurrencies as default
```
