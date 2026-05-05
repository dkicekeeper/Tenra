# Quick-Access Currencies — Customizable Transaction Currency Menu

**Date:** 2026-04-03

## Problem

The transaction currency Menu shows a fixed list (~7 currencies). Users with accounts in currencies outside this list (TRY, GEL, etc.) can't quickly switch. Account currencies auto-sync on account selection, but manual currency override is limited.

## Solution

Make the Menu configurable: user taps "Customize..." in the Menu → opens fullscreen multiselect list → picks which currencies appear. Account currencies are always included automatically (locked, can't remove).

## UX Flow

1. User opens transaction form → sees compact Menu with currencies
2. Menu contains: account currencies (auto) + user-selected currencies + divider + "Customize..."
3. "Customize..." → `.sheet` wrapping `NavigationStack` → fullscreen `QuickAccessCurrencyPickerView`
4. Picker shows:
   - Section "Account currencies" — locked checkmarks (always included)
   - Section "All currencies" — searchable, toggleable checkmarks
5. User toggles currencies → closes sheet → Menu updates

## Data Model

`AppSettings.quickAccessCurrencies: [String]` — user's manual picks, persisted in UserDefaults.
Default: `["USD", "EUR"]`.

Final Menu list = `Set(accountCurrencies) ∪ Set(quickAccessCurrencies)`, sorted by name.

## Files Changed

| File | Change |
|------|--------|
| **New:** `Views/Settings/QuickAccessCurrencyPickerView.swift` | Fullscreen multiselect with search |
| `Models/AppSettings.swift` | Add `quickAccessCurrencies: [String]` |
| `Views/Components/Input/CurrencySelectorView.swift` | Accept `accountCurrencies`, merge lists, add "Customize..." item |
| `Views/Components/Input/AmountInputView.swift` | Pass `accountCurrencies` through |
| `Views/Transactions/TransactionAddModal.swift` | Pass account currencies to AmountInputView |
| `Views/Transactions/TransactionEditView.swift` | Pass account currencies to AmountInputView |
| `Localizable.strings` (ru + en) | Add keys |
