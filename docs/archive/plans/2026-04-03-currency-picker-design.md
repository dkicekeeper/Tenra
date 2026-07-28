# Currency Picker — Full-Screen List with Search

**Date:** 2026-04-03
**Scope:** Settings (base currency) + Account creation/edit

## Problem

Currency selection uses a hardcoded 7-item Menu dropdown with symbols only. No search, no currency names, no way to pick currencies outside the fixed list.

## Solution

Full-screen `CurrencyPickerView` via NavigationLink with:
- `.searchable` for filtering by code or localized name
- "Popular" section: regional currency (via `Locale.current.currency`) + USD + EUR
- "All currencies" section: full ISO list via `Locale.Currency.isoCurrencies`, sorted A-Z by localized name

## UI Structure

```
NavigationLink -> CurrencyPickerView
+-- .searchable(text:prompt:) -- "currency.searchPrompt"
+-- Section "currency.popular"
|   +-- Row: [regional] -- localized name, symbol, checkmark if selected
|   +-- Row: USD -- localized name, $
|   +-- Row: EUR -- localized name, euro sign
+-- Section "currency.all" (A-Z by localized name)
    +-- Row: AED -- localized name, symbol
    +-- ...
```

Each row: `[Code]  [Localized name]  [Symbol]  [checkmark if selected]`

## Data Model

```swift
struct CurrencyInfo: Identifiable, Sendable {
    let code: String        // "USD"
    let name: String        // "Доллар США" (localized via Locale)
    let symbol: String      // "$"
    var id: String { code }
}
```

- Currency list: `Locale.Currency.isoCurrencies`
- Name: `Locale.current.localizedString(forCurrencyCode:)`
- Symbol: derived from NumberFormatter with locale
- Regional default: `Locale.current.currency?.identifier ?? "KZT"`
- Top-3 deduplication: if regional == USD or EUR, don't duplicate

## Search

Case-insensitive filter on code and localized name.

## Files Changed

| File | Change |
|------|--------|
| **New:** `Views/Settings/CurrencyPickerView.swift` | Full-screen list with search |
| **New:** `Models/CurrencyInfo.swift` | CurrencyInfo model + static list builder |
| `SettingsGeneralSection.swift` | Menu -> NavigationLink to CurrencyPickerView |
| `SettingsView.swift` | Pass callback through |
| `EditableHeroSection.swift` | Add .navigationDestination for account currency |
| `AppSettings.swift` | Remove hardcoded `availableCurrencies` |
| `SettingsValidationService.swift` | Validate via Locale.Currency.isoCurrencies |
| `Formatting.swift` | Extend currencySymbol(for:) with Locale fallback |
| `Localizable.strings` (ru + en) | Add: currency.popular, currency.all, currency.searchPrompt |

## Unchanged

- `CurrencySelectorView` (compact Menu in transaction forms)
- `CurrencyConverter` (works with any code, conversion only for NBK-supported)
- `TransactionStore`, `BalanceCoordinator`
