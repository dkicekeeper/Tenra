# Bulk Deletion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add multi-select bulk deletion to AccountsManagementView, CategoriesManagementView, and SubcategoriesManagementView.

**Architecture:** Shared `ManagementMode` enum replaces `isReordering: Bool`. Each management view adds `@State var selection: Set<String>` and native `List(selection:)`. A shared `BulkDeleteButton` overlay appears when selection is non-empty. ViewModel batch-delete methods iterate existing single-delete logic with one cache rebuild at the end.

**Tech Stack:** SwiftUI (iOS 26+), native `EditMode` with `List(selection:)`, existing design system tokens.

**Design doc:** `docs/plans/2026-04-07-bulk-deletion-design.md`

---

### Task 1: Add localization keys

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

**Step 1: Add EN keys to Localizable.strings**

Add at the end of the file, before any closing comments:

```strings
// MARK: - Bulk Selection
"bulk.select" = "Select";
"bulk.selectAll" = "Select All";
"bulk.deselectAll" = "Deselect All";
"bulk.done" = "Done";
"bulk.deleteCount" = "Delete (%d)";

// MARK: - Bulk Delete Accounts
"bulk.deleteAccounts.title" = "Delete %d accounts?";
"bulk.deleteAccounts.message" = "What to do with related transactions?";
"bulk.deleteAccounts.onlyAccounts" = "Delete only accounts";
"bulk.deleteAccounts.withTransactions" = "Delete with all transactions";

// MARK: - Bulk Delete Categories
"bulk.deleteCategories.title" = "Delete %d categories?";
"bulk.deleteCategories.message" = "What to do with related transactions?";
"bulk.deleteCategories.onlyCategories" = "Delete only categories";
"bulk.deleteCategories.withTransactions" = "Delete with all transactions";

// MARK: - Bulk Delete Subcategories
"bulk.deleteSubcategories.title" = "Delete %d subcategories?";
"bulk.deleteSubcategories.confirm" = "Delete";
```

**Step 2: Add RU keys to Localizable.strings**

```strings
// MARK: - Bulk Selection
"bulk.select" = "Выбрать";
"bulk.selectAll" = "Выбрать все";
"bulk.deselectAll" = "Снять выбор";
"bulk.done" = "Готово";
"bulk.deleteCount" = "Удалить (%d)";

// MARK: - Bulk Delete Accounts
"bulk.deleteAccounts.title" = "Удалить счетов: %d?";
"bulk.deleteAccounts.message" = "Что делать со связанными транзакциями?";
"bulk.deleteAccounts.onlyAccounts" = "Удалить только счета";
"bulk.deleteAccounts.withTransactions" = "Удалить с транзакциями";

// MARK: - Bulk Delete Categories
"bulk.deleteCategories.title" = "Удалить категорий: %d?";
"bulk.deleteCategories.message" = "Что делать со связанными транзакциями?";
"bulk.deleteCategories.onlyCategories" = "Удалить только категории";
"bulk.deleteCategories.withTransactions" = "Удалить с транзакциями";

// MARK: - Bulk Delete Subcategories
"bulk.deleteSubcategories.title" = "Удалить подкатегорий: %d?";
"bulk.deleteSubcategories.confirm" = "Удалить";
```

**Step 3: Build to verify no typos**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 4: Commit**

```bash
git add Tenra/en.lproj/Localizable.strings Tenra/ru.lproj/Localizable.strings
git commit -m "feat: add bulk deletion localization keys (EN + RU)"
```

---

### Task 2: Create ManagementMode enum and BulkDeleteButton

**Files:**
- Create: `Tenra/Views/Components/Input/ManagementMode.swift`
- Create: `Tenra/Views/Components/Input/BulkDeleteButton.swift`

**Step 1: Create ManagementMode enum**

Create `Tenra/Views/Components/Input/ManagementMode.swift`:

```swift
//
//  ManagementMode.swift
//  Tenra
//

import SwiftUI

enum ManagementMode: Equatable {
    case normal
    case selecting
    case reordering

    var editMode: EditMode {
        switch self {
        case .normal: return .inactive
        case .selecting, .reordering: return .active
        }
    }

    var isSelecting: Bool { self == .selecting }
    var isReordering: Bool { self == .reordering }
}
```

**Step 2: Create BulkDeleteButton**

Create `Tenra/Views/Components/Input/BulkDeleteButton.swift`:

```swift
//
//  BulkDeleteButton.swift
//  Tenra
//

import SwiftUI

struct BulkDeleteButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.warning()
            action()
        }) {
            Text(String(format: String(localized: "bulk.deleteCount"), count))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.destructive, in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 4: Commit**

```bash
git add Tenra/Views/Components/Input/ManagementMode.swift Tenra/Views/Components/Input/BulkDeleteButton.swift
git commit -m "feat: add ManagementMode enum and BulkDeleteButton component"
```

---

### Task 3: Add batch delete methods to AccountsViewModel

**Files:**
- Modify: `Tenra/ViewModels/AccountsViewModel.swift:116-126`

**Step 1: Add deleteAccounts batch method**

Add after the existing `deleteAccount(_ account:)` method at line 126:

```swift
func deleteAccounts(_ ids: Set<String>, deleteTransactions: Bool) async {
    let accountsToDelete = accounts.filter { ids.contains($0.id) }

    if deleteTransactions {
        for account in accountsToDelete {
            await transactionStore?.deleteTransactions(forAccountId: account.id)
        }
    }

    for account in accountsToDelete {
        deleteAccount(account)
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 3: Commit**

```bash
git add Tenra/ViewModels/AccountsViewModel.swift
git commit -m "feat: add batch deleteAccounts method to AccountsViewModel"
```

---

### Task 4: Add batch delete methods to CategoriesViewModel

**Files:**
- Modify: `Tenra/ViewModels/CategoriesViewModel.swift:135-177`

**Step 1: Add deleteCategories batch method**

Add after existing `deleteCategory` method at line 138:

```swift
func deleteCategories(_ ids: Set<String>, deleteTransactions: Bool) async {
    let categoriesToDelete = customCategories.filter { ids.contains($0.id) }

    if deleteTransactions {
        for category in categoriesToDelete {
            await transactionStore?.deleteTransactions(forCategoryName: category.name, type: category.type)
        }
    }

    for category in categoriesToDelete {
        deleteCategory(category, deleteTransactions: deleteTransactions)
    }
}
```

**Step 2: Add deleteSubcategories batch method**

Add after existing `deleteSubcategory` method at line 177:

```swift
func deleteSubcategories(_ ids: Set<String>) {
    for id in ids {
        deleteSubcategory(id)
    }
}
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 4: Commit**

```bash
git add Tenra/ViewModels/CategoriesViewModel.swift
git commit -m "feat: add batch delete methods to CategoriesViewModel"
```

---

### Task 5: Add bulk selection to AccountsManagementView

**Files:**
- Modify: `Tenra/Views/Accounts/AccountsManagementView.swift`

**Step 1: Replace state and add selection logic**

Replace `@State private var isReordering = false` (line 23) with:

```swift
@State private var mode: ManagementMode = .normal
@State private var selection: Set<String> = []
@State private var showingBulkDeleteDialog = false
```

**Step 2: Update sortedAccounts usage — replace all `isReordering` references**

In the body:
- Line 101: `.onMove(perform: isReordering ? moveAccount : nil)` → `.onMove(perform: mode.isReordering ? moveAccount : nil)`
- Line 103: `.environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))` → `.environment(\.editMode, .constant(mode.editMode))`
- Add `selection:` to `List`: `List(selection: mode.isSelecting ? $selection : nil) {`

**Step 3: Replace toolbar**

Replace entire toolbar block (lines 133-175) with:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        switch mode {
        case .normal:
            HStack(spacing: 0) {
                Button {
                    HapticManager.light()
                    withAnimation(AppAnimation.contentSpring) { mode = .selecting }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel(String(localized: "bulk.select"))
            }
        case .selecting:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) {
                    mode = .normal
                    selection.removeAll()
                }
            } label: {
                Text(String(localized: "bulk.done"))
            }
            .glassProminentButton()
        case .reordering:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) { mode = .normal }
            } label: {
                Image(systemName: "checkmark")
            }
            .glassProminentButton()
            .accessibilityLabel(String(localized: "accessibility.accounts.doneReordering"))
        }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
        if mode == .normal {
            HStack(spacing: 0) {
                Button {
                    HapticManager.light()
                    withAnimation(AppAnimation.contentSpring) { mode = .reordering }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel(String(localized: "accessibility.accounts.reorder"))
            }
        }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
        if mode == .normal {
            Menu {
                Button(action: {
                    HapticManager.light()
                    showingAddAccount = true
                }) {
                    Label(String(localized: "account.newAccount"), systemImage: "creditcard")
                }
                Button(action: {
                    HapticManager.light()
                    showingAddDeposit = true
                }) {
                    Label(String(localized: "account.newDeposit"), systemImage: "banknote")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "accessibility.accounts.addMenu"))
        } else if mode.isSelecting {
            Button {
                HapticManager.selection()
                if selection.count == sortedAccounts.count {
                    selection.removeAll()
                } else {
                    selection = Set(sortedAccounts.map(\.id))
                }
            } label: {
                Text(selection.count == sortedAccounts.count
                     ? String(localized: "bulk.deselectAll")
                     : String(localized: "bulk.selectAll"))
            }
        }
    }
}
```

**Step 4: Add long press gesture to AccountRow**

On each `AccountRow` inside `ForEach`, add after `.contextMenu { ... }`:

```swift
.onLongPressGesture {
    guard mode == .normal else { return }
    HapticManager.selectionChanged()
    withAnimation(AppAnimation.contentSpring) {
        mode = .selecting
        selection.insert(account.id)
    }
}
```

**Step 5: Add floating delete button and bulk delete alert**

Add before the existing `.alert(...)` (line 269), as an overlay on the Group:

```swift
.overlay(alignment: .bottom) {
    if mode.isSelecting && !selection.isEmpty {
        BulkDeleteButton(count: selection.count) {
            showingBulkDeleteDialog = true
        }
        .animation(AppAnimation.contentSpring, value: selection.count)
    }
}
.alert(
    String(format: String(localized: "bulk.deleteAccounts.title"), selection.count),
    isPresented: $showingBulkDeleteDialog
) {
    Button(String(localized: "button.cancel"), role: .cancel) {}
    Button(String(localized: "bulk.deleteAccounts.onlyAccounts"), role: .destructive) {
        let ids = selection
        Task {
            await accountsViewModel.deleteAccounts(ids, deleteTransactions: false)
            for id in ids {
                transactionsViewModel.cleanupDeletedAccount(id)
            }
            transactionsViewModel.syncAccountsFrom(accountsViewModel)
        }
        withAnimation(AppAnimation.contentSpring) {
            selection.removeAll()
            mode = .normal
        }
    }
    Button(String(localized: "bulk.deleteAccounts.withTransactions"), role: .destructive) {
        let ids = selection
        Task {
            await accountsViewModel.deleteAccounts(ids, deleteTransactions: true)
            for id in ids {
                transactionsViewModel.cleanupDeletedAccount(id)
            }
            transactionsViewModel.clearAndRebuildAggregateCache()
        }
        withAnimation(AppAnimation.contentSpring) {
            selection.removeAll()
            mode = .normal
        }
    }
} message: {
    Text(String(localized: "bulk.deleteAccounts.message"))
}
```

**Step 6: Disable row tap edit in select mode**

In AccountRow's `onEdit` callback, guard against select mode:

```swift
onEdit: {
    guard !mode.isSelecting else { return }
    editingAccount = account
},
```

**Step 7: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 8: Commit**

```bash
git add Tenra/Views/Accounts/AccountsManagementView.swift
git commit -m "feat: add bulk selection and deletion to AccountsManagementView"
```

---

### Task 6: Add bulk selection to CategoriesManagementView

**Files:**
- Modify: `Tenra/Views/Categories/CategoriesManagementView.swift`

**Step 1: Replace state**

Replace `@State private var isReordering = false` (line 22) with:

```swift
@State private var mode: ManagementMode = .normal
@State private var selection: Set<String> = []
@State private var showingBulkDeleteDialog = false
```

**Step 2: Update references**

- Line 105: `.onMove(perform: isReordering ? moveCategory : nil)` → `.onMove(perform: mode.isReordering ? moveCategory : nil)`
- Line 107: `.environment(\.editMode, isReordering ? .constant(.active) : .constant(.inactive))` → `.environment(\.editMode, .constant(mode.editMode))`
- Add `selection:` to `List`: `List(selection: mode.isSelecting ? $selection : nil) {`

**Step 3: Replace toolbar (lines 113-143)**

Same pattern as AccountsManagementView but adapted:
- Select / Reorder / Normal toggle
- Select All / Deselect All uses `filteredCategories` (not all categories — respects expense/income filter)
- Plus button only in normal mode
- No reorder button replacement needed (same icon/behavior)

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        switch mode {
        case .normal:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) { mode = .selecting }
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .accessibilityLabel(String(localized: "bulk.select"))
        case .selecting:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) {
                    mode = .normal
                    selection.removeAll()
                }
            } label: {
                Text(String(localized: "bulk.done"))
            }
            .glassProminentButton()
        case .reordering:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) { mode = .normal }
            } label: {
                Image(systemName: "checkmark")
            }
            .glassProminentButton()
        }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
        if mode == .normal {
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) { mode = .reordering }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
        if mode == .normal {
            Button {
                HapticManager.light()
                showingAddCategory = true
            } label: {
                Image(systemName: "plus")
            }
            .glassProminentButton()
        } else if mode.isSelecting {
            Button {
                HapticManager.selection()
                let filteredIds = Set(filteredCategories.map(\.id))
                if selection == filteredIds {
                    selection.removeAll()
                } else {
                    selection = filteredIds
                }
            } label: {
                Text(selection.count == filteredCategories.count
                     ? String(localized: "bulk.deselectAll")
                     : String(localized: "bulk.selectAll"))
            }
        }
    }
}
```

**Step 4: Add long press to CategoryRow**

After each `CategoryRow(...)` in the ForEach, add:

```swift
.onLongPressGesture {
    guard mode == .normal else { return }
    HapticManager.selectionChanged()
    withAnimation(AppAnimation.contentSpring) {
        mode = .selecting
        selection.insert(category.id)
    }
}
```

**Step 5: Guard row tap in select mode**

```swift
onEdit: {
    guard !mode.isSelecting else { return }
    editingCategory = category
},
```

**Step 6: Add overlay and bulk delete alert**

Add before existing `.alert(...)` (line 195):

```swift
.overlay(alignment: .bottom) {
    if mode.isSelecting && !selection.isEmpty {
        BulkDeleteButton(count: selection.count) {
            showingBulkDeleteDialog = true
        }
        .animation(AppAnimation.contentSpring, value: selection.count)
    }
}
.alert(
    String(format: String(localized: "bulk.deleteCategories.title"), selection.count),
    isPresented: $showingBulkDeleteDialog
) {
    Button(String(localized: "button.cancel"), role: .cancel) {}
    Button(String(localized: "bulk.deleteCategories.onlyCategories"), role: .destructive) {
        let ids = selection
        Task {
            await categoriesViewModel.deleteCategories(ids, deleteTransactions: false)
            transactionsViewModel.clearAndRebuildAggregateCache()
        }
        withAnimation(AppAnimation.contentSpring) {
            selection.removeAll()
            mode = .normal
        }
    }
    Button(String(localized: "bulk.deleteCategories.withTransactions"), role: .destructive) {
        let ids = selection
        Task {
            await categoriesViewModel.deleteCategories(ids, deleteTransactions: true)
            transactionsViewModel.recalculateAccountBalances()
            transactionsViewModel.clearAndRebuildAggregateCache()
        }
        withAnimation(AppAnimation.contentSpring) {
            selection.removeAll()
            mode = .normal
        }
    }
} message: {
    Text(String(localized: "bulk.deleteCategories.message"))
}
```

**Step 7: Clear selection on type filter change**

Add to the existing `.onChange(of: selectedType)` (line 157):

```swift
.onChange(of: selectedType) { _, _ in
    HapticManager.selection()
    selection.removeAll()
}
```

**Step 8: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 9: Commit**

```bash
git add Tenra/Views/Categories/CategoriesManagementView.swift
git commit -m "feat: add bulk selection and deletion to CategoriesManagementView"
```

---

### Task 7: Add bulk selection to SubcategoriesManagementView

**Files:**
- Modify: `Tenra/Views/Categories/SubcategoriesManagementView.swift`

**Step 1: Add state**

Add after existing `@State` declarations (line 14):

```swift
@State private var mode: ManagementMode = .normal
@State private var selection: Set<String> = []
@State private var showingBulkDeleteDialog = false
```

**Step 2: Update List to support selection**

Change `List {` (line 29) to:

```swift
List(selection: mode.isSelecting ? $selection : nil) {
```

**Step 3: Replace toolbar (lines 49-58)**

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        switch mode {
        case .normal:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) { mode = .selecting }
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .accessibilityLabel(String(localized: "bulk.select"))
        case .selecting:
            Button {
                HapticManager.light()
                withAnimation(AppAnimation.contentSpring) {
                    mode = .normal
                    selection.removeAll()
                }
            } label: {
                Text(String(localized: "bulk.done"))
            }
            .glassProminentButton()
        case .reordering:
            EmptyView()
        }
    }
    ToolbarSpacer(.fixed, placement: .topBarTrailing)
    ToolbarItem(placement: .topBarTrailing) {
        if mode == .normal {
            Button(action: {
                HapticManager.light()
                showingAddSubcategory = true
            }) {
                Image(systemName: "plus")
            }
            .glassProminentButton()
        } else if mode.isSelecting {
            Button {
                HapticManager.selection()
                let allIds = Set(categoriesViewModel.subcategories.map(\.id))
                if selection == allIds {
                    selection.removeAll()
                } else {
                    selection = allIds
                }
            } label: {
                Text(selection.count == categoriesViewModel.subcategories.count
                     ? String(localized: "bulk.deselectAll")
                     : String(localized: "bulk.selectAll"))
            }
        }
    }
}
```

**Step 4: Add long press to SubcategoryManagementRow**

After each row in ForEach, add:

```swift
.onLongPressGesture {
    guard mode == .normal else { return }
    HapticManager.selectionChanged()
    withAnimation(AppAnimation.contentSpring) {
        mode = .selecting
        selection.insert(subcategory.id)
    }
}
```

**Step 5: Guard row tap in select mode**

```swift
onEdit: {
    guard !mode.isSelecting else { return }
    editingSubcategory = subcategory
},
```

**Step 6: Add overlay and simple delete alert**

Add after the toolbar:

```swift
.overlay(alignment: .bottom) {
    if mode.isSelecting && !selection.isEmpty {
        BulkDeleteButton(count: selection.count) {
            showingBulkDeleteDialog = true
        }
        .animation(AppAnimation.contentSpring, value: selection.count)
    }
}
.alert(
    String(format: String(localized: "bulk.deleteSubcategories.title"), selection.count),
    isPresented: $showingBulkDeleteDialog
) {
    Button(String(localized: "button.cancel"), role: .cancel) {}
    Button(String(localized: "bulk.deleteSubcategories.confirm"), role: .destructive) {
        HapticManager.warning()
        categoriesViewModel.deleteSubcategories(selection)
        withAnimation(AppAnimation.contentSpring) {
            selection.removeAll()
            mode = .normal
        }
    }
}
```

**Step 7: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors.

**Step 8: Commit**

```bash
git add Tenra/Views/Categories/SubcategoriesManagementView.swift
git commit -m "feat: add bulk selection and deletion to SubcategoriesManagementView"
```

---

### Task 8: Final integration build and manual QA

**Step 1: Full build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: Clean build.

**Step 2: Manual QA checklist**

Test on simulator:
- [ ] Accounts: long press enters select mode, checkboxes appear
- [ ] Accounts: toolbar "Select" button enters select mode
- [ ] Accounts: Select All / Deselect All works
- [ ] Accounts: floating Delete (N) button appears with correct count
- [ ] Accounts: "Delete only accounts" keeps transactions
- [ ] Accounts: "Delete with transactions" removes all
- [ ] Accounts: Done exits select mode, clears selection
- [ ] Accounts: Reorder still works independently
- [ ] Categories: same flow as accounts
- [ ] Categories: switching expense/income clears selection
- [ ] Categories: Select All only selects visible (filtered) categories
- [ ] Subcategories: select mode works
- [ ] Subcategories: simple delete confirm (no transaction question)
- [ ] All: haptic feedback on enter select, delete, select all
- [ ] All: animations smooth (contentSpring)

**Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address QA feedback for bulk deletion"
```
