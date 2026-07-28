# Bulk Deletion for Accounts, Categories & Subcategories

**Date:** 2026-04-07
**Status:** Approved

## Problem

Management views (AccountsManagementView, CategoriesManagementView, SubcategoriesManagementView) only support single-item deletion via swipe-to-delete. Users managing many items need bulk deletion.

## Solution

Add a multi-select mode to all 3 management views using native `List` `EditMode` with `selection: Binding<Set<UUID>>`. Entry via long press on element OR toolbar "Select" button. Floating destructive "Delete (N)" button at the bottom when items are selected.

## UX Flow

### Toolbar States (3 modes)

| Mode | Toolbar Leading | Toolbar Trailing | Row Tap Action |
|------|----------------|-----------------|----------------|
| **Normal** (default) | `[+ Add]` | `[Reorder]` | Open edit sheet |
| **Selecting** (new) | `[Select All / Deselect All]` | `[Done]` | Toggle selection |
| **Reordering** (existing) | — | `[Done]` | Drag to move |

### Entry into Select Mode
- **Long press** on any row: activates select mode + selects that row
- **Toolbar button** "Select": activates select mode with empty selection

### Exit from Select Mode
- **Done** button in toolbar
- All items deselected manually

### Floating Delete Button
- Appears at bottom center when `selection.count > 0`
- Shows count: "Delete (3)"
- Destructive red style using `AppColors.destructive`
- Spring animation on appear/disappear (`AppAnimation.contentSpring`)

### Confirmation Alerts

**Accounts & Categories** (have related transactions):
```
Title: "Delete N items?"
Message: "What to do with related transactions?"

Actions:
  [Delete only items]           — default
  [Delete with transactions]    — destructive
  [Cancel]
```

**Subcategories** (no transaction cascade):
```
Title: "Delete N subcategories?"

Actions:
  [Delete]    — destructive
  [Cancel]
```

## Architecture

### Shared Component: `BulkSelectionModifier<ID: Hashable>`

ViewModifier encapsulating:
- `@State var isSelecting: Bool`
- `@State var selection: Set<ID>`
- Toolbar items (Select/Done, Select All/Deselect All)
- Floating delete button overlay
- Long press gesture configuration

Parameters:
- `allItemIDs: [ID]` — for Select All
- `onDelete: (Set<ID>) -> Void` — callback when delete confirmed
- `deleteButtonLabel: (Int) -> String` — localized label

Location: `Views/Components/Input/BulkSelectionModifier.swift`

### View Changes

**AccountsManagementView:**
- Replace single `isReordering` state with `ManagementMode` enum: `.normal`, `.selecting`, `.reordering`
- Add `@State var selection: Set<UUID>`
- Apply `BulkSelectionModifier`
- Long press on `AccountRow` → enter select mode

**CategoriesManagementView:**
- Same pattern as accounts
- Category type filter (expense/income) preserved in select mode — only visible items selectable
- Select All only selects visible (filtered) categories

**SubcategoriesManagementView:**
- Simplified — no transaction cascade question
- Same `BulkSelectionModifier` with simpler delete confirmation

### ViewModel Methods

```swift
// AccountsViewModel
func deleteAccounts(_ ids: Set<UUID>, deleteTransactions: Bool) async

// CategoriesViewModel
func deleteCategories(_ ids: Set<UUID>, deleteTransactions: Bool) async
func deleteSubcategories(_ ids: Set<UUID>) async
```

Each method iterates through IDs calling existing single-delete logic, with ONE cache rebuild at the end (not per-item).

### Enum: ManagementMode

```swift
enum ManagementMode {
    case normal
    case selecting
    case reordering
}
```

Shared across all 3 management views. Replaces `isReordering: Bool`.

## Design System Usage

| Element | Token |
|---------|-------|
| Delete button background | `AppColors.destructive` |
| Delete button style | `PrimaryButtonStyle` variant with red |
| Button appear/disappear | `AppAnimation.contentSpring` |
| Selection checkmarks | Native `EditMode` styling |
| Floating button padding | `AppSpacing.lg` from bottom |
| Haptic on enter select mode | `.selectionChanged` |
| Haptic on delete | `.notificationOccurred(.warning)` |

## Localization Keys

### Shared (bulk.)
| Key | EN | RU |
|-----|----|----|
| `bulk.select` | Select | Выбрать |
| `bulk.selectAll` | Select All | Выбрать все |
| `bulk.deselectAll` | Deselect All | Снять выбор |
| `bulk.done` | Done | Готово |
| `bulk.deleteCount` | Delete (%d) | Удалить (%d) |

### Accounts (bulk.deleteAccounts.)
| Key | EN | RU |
|-----|----|----|
| `bulk.deleteAccounts.title` | Delete %d accounts? | Удалить %d счетов? |
| `bulk.deleteAccounts.message` | What to do with related transactions? | Что делать со связанными транзакциями? |
| `bulk.deleteAccounts.onlyAccounts` | Delete only accounts | Удалить только счета |
| `bulk.deleteAccounts.withTransactions` | Delete with all transactions | Удалить с транзакциями |

### Categories (bulk.deleteCategories.)
| Key | EN | RU |
|-----|----|----|
| `bulk.deleteCategories.title` | Delete %d categories? | Удалить %d категорий? |
| `bulk.deleteCategories.message` | What to do with related transactions? | Что делать со связанными транзакциями? |
| `bulk.deleteCategories.onlyCategories` | Delete only categories | Удалить только категории |
| `bulk.deleteCategories.withTransactions` | Delete with all transactions | Удалить с транзакциями |

### Subcategories (bulk.deleteSubcategories.)
| Key | EN | RU |
|-----|----|----|
| `bulk.deleteSubcategories.title` | Delete %d subcategories? | Удалить %d подкатегорий? |
| `bulk.deleteSubcategories.confirm` | Delete | Удалить |

## Edge Cases

- **Default categories**: Cannot be selected for deletion (skip in Select All, disable checkbox)
- **Deposits/Loans**: Accounts with `isDeposit` or `isLoan` can be selected — use respective delete methods
- **Empty selection + Done**: Exit select mode, no action
- **All items selected**: Show "Deselect All" instead of "Select All"
- **Reorder mode active → long press**: No-op (reorder takes priority)
- **Single item selected**: Same flow as bulk (consistent UX)

## Files to Create/Modify

### New Files
1. `Views/Components/Input/BulkSelectionModifier.swift` — shared selection modifier

### Modified Files
2. `Views/Accounts/AccountsManagementView.swift` — add select mode
3. `Views/Categories/CategoriesManagementView.swift` — add select mode
4. `Views/Categories/SubcategoriesManagementView.swift` — add select mode
5. `ViewModels/AccountsViewModel.swift` — `deleteAccounts(_:deleteTransactions:)`
6. `ViewModels/CategoriesViewModel.swift` — `deleteCategories(_:deleteTransactions:)`, `deleteSubcategories(_:)`
7. `en.lproj/Localizable.strings` — EN keys
8. `ru.lproj/Localizable.strings` — RU keys
