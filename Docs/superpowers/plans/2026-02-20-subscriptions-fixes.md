# Subscriptions: Localization, SwiftUI Patterns & Performance Fixes

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 17 issues across 7 subscription files — 4 critical localization bugs, 5 SwiftUI pattern violations, 5 performance issues, 3 cleanup items.

**Architecture:** No new files, only editing existing Swift source and Localizable.strings. All changes are backwards-compatible. Sheet dismiss moved into SubscriptionEditView itself (owns its own lifecycle). Expensive computations moved out of `body` into `.task`/`.onAppear`.

**Tech Stack:** SwiftUI (iOS 26+), Swift 6, Localizable.strings (en/ru), DateFormatter, @Observable + @MainActor

---

## Task 1: Add missing localization keys to both Localizable.strings

**Files:**
- Modify: `AIFinanceManager/AIFinanceManager/en.lproj/Localizable.strings` (around line 392)
- Modify: `AIFinanceManager/AIFinanceManager/ru.lproj/Localizable.strings` (around line 392)

**Step 1: Append to EN strings — after `"subscriptions.status.unknown"` (line ~415)**

Add the following block in `en.lproj/Localizable.strings` right after the existing subscriptions section:

```
// Notification Permission
"notification.permission.title" = "Enable Reminders?";
"notification.permission.description" = "Get notified about upcoming subscription charges so you never miss an important payment";
"notification.permission.allow" = "Allow Notifications";
"notification.permission.skip" = "Not Now";

// Active count (EmptyState)
"emptyState.noActiveSubscriptions" = "No active subscriptions";
"subscriptions.activeCount" = "%lld active";

// Next charge inline text (format string for SubscriptionCard)
"subscriptions.nextChargeOn" = "Next charge: %@";

// Frequency display names
"frequency.daily" = "Daily";
"frequency.weekly" = "Weekly";
"frequency.monthly" = "Monthly";
"frequency.yearly" = "Yearly";
```

**Step 2: Append to RU strings — after `"subscriptions.status.unknown"` (line ~415)**

Add the following block in `ru.lproj/Localizable.strings` right after the existing subscriptions section:

```
// Notification Permission
"notification.permission.title" = "Включить напоминания?";
"notification.permission.description" = "Получайте уведомления о предстоящих списаниях по подпискам, чтобы не пропустить важные платежи";
"notification.permission.allow" = "Разрешить уведомления";
"notification.permission.skip" = "Не сейчас";

// Active count (EmptyState)
"emptyState.noActiveSubscriptions" = "Нет активных подписок";
"subscriptions.activeCount" = "Активных %lld";

// Next charge inline text (format string for SubscriptionCard)
"subscriptions.nextChargeOn" = "Следующее: %@";

// Frequency display names
"frequency.daily" = "Ежедневно";
"frequency.weekly" = "Еженедельно";
"frequency.monthly" = "Ежемесячно";
"frequency.yearly" = "Ежегодно";
```

**Step 3: Build to verify no string compile errors**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 4: Commit**

```bash
git add AIFinanceManager/AIFinanceManager/en.lproj/Localizable.strings \
        AIFinanceManager/AIFinanceManager/ru.lproj/Localizable.strings
git commit -m "i18n: add missing localization keys for subscriptions, notifications, frequency"
```

---

## Task 2: Fix `RecurringFrequency.displayName` — use proper localization keys

**Files:**
- Modify: `AIFinanceManager/Models/RecurringTransaction.swift` (lines 200-207)

**Context:** Currently uses `NSLocalizedString("Daily", ...)` — those string keys don't exist in Localizable.strings, so Russian locale always shows English. Task 1 added the proper keys.

**Step 1: Replace the displayName computed property (lines 200–207)**

Replace:
```swift
var displayName: String {
    switch self {
    case .daily: return NSLocalizedString("Daily", comment: "")
    case .weekly: return NSLocalizedString("Weekly", comment: "")
    case .monthly: return NSLocalizedString("Monthly", comment: "")
    case .yearly: return NSLocalizedString("Yearly", comment: "")
    }
}
```

With:
```swift
var displayName: String {
    switch self {
    case .daily:   return String(localized: "frequency.daily")
    case .weekly:  return String(localized: "frequency.weekly")
    case .monthly: return String(localized: "frequency.monthly")
    case .yearly:  return String(localized: "frequency.yearly")
    }
}
```

**Step 2: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
git add AIFinanceManager/Models/RecurringTransaction.swift
git commit -m "fix: use localization keys in RecurringFrequency.displayName"
```

---

## Task 3: Fix `NotificationPermissionView` — localize all hardcoded Russian strings

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/Components/NotificationPermissionView.swift`

**Context:** 4 Text literals are hardcoded in Russian. Replace with `String(localized:)` using keys added in Task 1.

**Step 1: Replace the entire body of `NotificationPermissionView`**

Replace the body (lines 17–73) with:

```swift
var body: some View {
    VStack(spacing: AppSpacing.xl) {
        Spacer()

        // Icon
        Image(systemName: "bell.badge.fill")
            .font(.system(size: 64))
            .foregroundStyle(.blue)
            .padding(.bottom, AppSpacing.md)

        // Title
        Text(String(localized: "notification.permission.title"))
            .font(AppTypography.h2)
            .multilineTextAlignment(.center)

        // Description
        Text(String(localized: "notification.permission.description"))
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.xl)

        Spacer()

        // Buttons
        VStack(spacing: AppSpacing.md) {
            Button {
                HapticManager.light()
                Task {
                    await onAllow()
                    dismiss()
                }
            } label: {
                Text(String(localized: "notification.permission.allow"))
                    .font(AppTypography.body)
                    .bold()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(.blue)
                    .clipShape(.rect(cornerRadius: AppRadius.md))
            }

            Button {
                HapticManager.light()
                onSkip()
                dismiss()
            } label: {
                Text(String(localized: "notification.permission.skip"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xl)
    }
    .padding(.top, AppSpacing.xl)
}
```

**Step 2: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/Components/NotificationPermissionView.swift
git commit -m "fix: localize NotificationPermissionView strings"
```

---

## Task 4: Fix `SubscriptionsCardView` — hardcoded Russian counter + missing key

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/SubscriptionsCardView.swift` (lines 28, 33, 49)

**Context:**
- Line 28: `defaultValue:` is redundant when key exists in strings file
- Line 33: `"emptyState.noActiveSubscriptions"` key added in Task 1 — `defaultValue:` redundant
- Line 49: `Text("Активных \(subscriptions.count)")` — completely hardcoded Russian

**Step 1: Fix line 28 — remove redundant defaultValue:**

Replace:
```swift
Text(String(localized: "subscriptions.title", defaultValue: "Подписки"))
```
With:
```swift
Text(String(localized: "subscriptions.title"))
```

**Step 2: Fix line 33 — remove redundant defaultValue:**

Replace:
```swift
EmptyStateView(title: String(localized: "emptyState.noActiveSubscriptions", defaultValue: "Нет активных подписок"), style: .compact)
```
With:
```swift
EmptyStateView(title: String(localized: "emptyState.noActiveSubscriptions"), style: .compact)
```

**Step 3: Fix line 49 — localize the active count:**

Replace:
```swift
Text("Активных \(subscriptions.count)")
    .font(AppTypography.bodySecondary)
    .foregroundStyle(AppColors.textPrimary)
```
With:
```swift
Text(String(format: String(localized: "subscriptions.activeCount"), subscriptions.count))
    .font(AppTypography.bodySecondary)
    .foregroundStyle(AppColors.textPrimary)
```

**Step 4: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 5: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/SubscriptionsCardView.swift
git commit -m "fix: localize subscription active count, remove redundant defaultValue"
```

---

## Task 5: Fix `DateFormatters` — hardcoded `ru_RU` locale

**Files:**
- Modify: `AIFinanceManager/Utils/DateFormatters.swift` (lines 34, 44)

**Context:** `displayDateFormatter` and `displayDateWithYearFormatter` both hardcode `Locale(identifier: "ru_RU")`. English users see Russian month names everywhere (subscription cards, detail view, etc.).

**Step 1: Fix displayDateFormatter locale (line 34)**

Replace:
```swift
formatter.locale = Locale(identifier: "ru_RU")
```
With:
```swift
formatter.locale = .current
```
(First occurrence — in the `displayDateFormatter` block)

**Step 2: Fix displayDateWithYearFormatter locale (line 44)**

Replace the second occurrence:
```swift
formatter.locale = Locale(identifier: "ru_RU")
```
With:
```swift
formatter.locale = .current
```

**Step 3: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 4: Commit**

```bash
git add AIFinanceManager/Utils/DateFormatters.swift
git commit -m "fix: use Locale.current in date formatters instead of hardcoded ru_RU"
```

---

## Task 6: Refactor `SubscriptionEditView` — sheet owns dismiss, fix force unwrap, cache categories

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/SubscriptionEditView.swift`

**Context:**
- Remove `onSave`/`onCancel` callbacks — sheet manages its own lifecycle via `@Environment(\.dismiss)`
- `balanceCoordinator!` force unwrap → safe optional binding
- `availableCategories` computed property in body → `@State` + lazy computation

**Step 1: Remove callback parameters, add `@Environment(\.dismiss)`, add `@State private var availableCategories`**

Replace the property declarations block (lines 11–29):
```swift
// ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
let transactionStore: TransactionStore
let transactionsViewModel: TransactionsViewModel
let subscription: RecurringSeries?
let onSave: (RecurringSeries) -> Void
let onCancel: () -> Void

@State private var description: String = ""
@State private var amountText: String = ""
@State private var currency: String = "USD"
@State private var selectedCategory: String? = nil
@State private var selectedAccountId: String? = nil
@State private var selectedFrequency: RecurringFrequency = .monthly
@State private var startDate: Date = Date()
@State private var selectedIconSource: IconSource? = nil
@State private var reminder: ReminderOption = .none
@State private var showingNotificationPermission = false
@State private var validationError: String? = nil
```

With:
```swift
// ✨ Phase 9: Use TransactionStore directly (Single Source of Truth)
let transactionStore: TransactionStore
let transactionsViewModel: TransactionsViewModel
let subscription: RecurringSeries?

@Environment(\.dismiss) private var dismiss

@State private var description: String = ""
@State private var amountText: String = ""
@State private var currency: String = "USD"
@State private var selectedCategory: String? = nil
@State private var selectedAccountId: String? = nil
@State private var selectedFrequency: RecurringFrequency = .monthly
@State private var startDate: Date = Date()
@State private var selectedIconSource: IconSource? = nil
@State private var reminder: ReminderOption = .none
@State private var showingNotificationPermission = false
@State private var validationError: String? = nil
@State private var availableCategories: [String] = []
```

**Step 2: Remove the `availableCategories` computed property (lines 31–45)**

Delete the entire block:
```swift
private var availableCategories: [String] {
    var categories: Set<String> = []
    for customCategory in transactionsViewModel.customCategories where customCategory.type == .expense {
        categories.insert(customCategory.name)
    }
    for tx in transactionsViewModel.allTransactions where tx.type == .expense {
        if !tx.category.isEmpty && tx.category != "Uncategorized" {
            categories.insert(tx.category)
        }
    }
    if categories.isEmpty {
        categories.insert("Uncategorized")
    }
    return Array(categories).sortedByCustomOrder(customCategories: transactionsViewModel.customCategories, type: .expense)
}
```

Add a private method instead (place after the `validationError` state):
```swift
private func computeAvailableCategories() -> [String] {
    var categories: Set<String> = []
    for customCategory in transactionsViewModel.customCategories where customCategory.type == .expense {
        categories.insert(customCategory.name)
    }
    for tx in transactionsViewModel.allTransactions where tx.type == .expense {
        if !tx.category.isEmpty && tx.category != "Uncategorized" {
            categories.insert(tx.category)
        }
    }
    if categories.isEmpty {
        categories.insert("Uncategorized")
    }
    return Array(categories).sortedByCustomOrder(
        customCategories: transactionsViewModel.customCategories,
        type: .expense
    )
}
```

**Step 3: Fix EditSheetContainer — remove onCancel reference**

Replace:
```swift
EditSheetContainer(
    title: subscription == nil ?
        String(localized: "subscription.newTitle") :
        String(localized: "subscription.editTitle"),
    isSaveDisabled: description.isEmpty || amountText.isEmpty,
    useScrollView: true,
    onSave: saveSubscription,
    onCancel: onCancel
)
```
With:
```swift
EditSheetContainer(
    title: subscription == nil ?
        String(localized: "subscription.newTitle") :
        String(localized: "subscription.editTitle"),
    isSaveDisabled: description.isEmpty || amountText.isEmpty,
    useScrollView: true,
    onSave: saveSubscription,
    onCancel: { dismiss() }
)
```

**Step 4: Fix AccountSelectorView force unwrap (line ~85)**

Replace:
```swift
AccountSelectorView(
    accounts: transactionsViewModel.accounts,
    selectedAccountId: $selectedAccountId,
    emptyStateMessage: transactionsViewModel.accounts.isEmpty ?
    String(localized: "account.noAccountsAvailable") : nil,
    warningMessage: selectedAccountId == nil ?
    String(localized: "account.selectAccount") : nil,
    balanceCoordinator: transactionsViewModel.balanceCoordinator!
)
```
With:
```swift
if let balanceCoordinator = transactionsViewModel.balanceCoordinator {
    AccountSelectorView(
        accounts: transactionsViewModel.accounts,
        selectedAccountId: $selectedAccountId,
        emptyStateMessage: transactionsViewModel.accounts.isEmpty ?
            String(localized: "account.noAccountsAvailable") : nil,
        warningMessage: selectedAccountId == nil ?
            String(localized: "account.selectAccount") : nil,
        balanceCoordinator: balanceCoordinator
    )
}
```

**Step 5: Update `.onAppear` — add `availableCategories` computation**

In the `.onAppear` block, the else branch currently is:
```swift
} else {
    currency = transactionsViewModel.appSettings.baseCurrency
    if !availableCategories.isEmpty {
        selectedCategory = availableCategories[0]
    }
    // Set first account as default
    if !transactionsViewModel.accounts.isEmpty {
        selectedAccountId = transactionsViewModel.accounts[0].id
    }
}
```

Add category computation at the TOP of `.onAppear` closure (before the if/else), and fix reference to use the state variable:
```swift
.onAppear {
    availableCategories = computeAvailableCategories()  // ← add this line at top
    if let subscription = subscription {
        // ... existing code unchanged ...
    } else {
        currency = transactionsViewModel.appSettings.baseCurrency
        if !availableCategories.isEmpty {
            selectedCategory = availableCategories[0]
        }
        if !transactionsViewModel.accounts.isEmpty {
            selectedAccountId = transactionsViewModel.accounts[0].id
        }
    }
}
```

**Step 6: Update `saveSubscription()` — move async save into Task, call `dismiss()`**

Replace the last 3 lines of `saveSubscription()`:
```swift
HapticManager.success()
onSave(series)
```
With:
```swift
Task {
    do {
        if subscription == nil {
            try await transactionStore.createSeries(series)
        } else {
            try await transactionStore.updateSeries(series)
        }
        HapticManager.success()
        dismiss()
    } catch {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            validationError = error.localizedDescription
        }
        HapticManager.error()
    }
}
```

**Step 7: Update Preview — remove onSave/onCancel params**

Replace:
```swift
SubscriptionEditView(
    transactionStore: coordinator.transactionStore,
    transactionsViewModel: coordinator.transactionsViewModel,
    subscription: nil,
    onSave: { _ in },
    onCancel: {}
)
```
With:
```swift
SubscriptionEditView(
    transactionStore: coordinator.transactionStore,
    transactionsViewModel: coordinator.transactionsViewModel,
    subscription: nil
)
```

**Step 8: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 9: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/SubscriptionEditView.swift
git commit -m "refactor: SubscriptionEditView owns dismiss, remove force unwrap, cache categories"
```

---

## Task 7: Refactor `SubscriptionsListView` — `.sheet(item:)`, topBarTrailing, remove callbacks

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/SubscriptionsListView.swift`

**Context:**
- Task 6 removed `onSave`/`onCancel` from SubscriptionEditView, so callers must be updated
- `.sheet(isPresented:)` with if/else → `.sheet(item:)` with `Identifiable` enum
- `.navigationBarTrailing` deprecated → `.topBarTrailing`

**Step 1: Replace state variables and add `SubscriptionSheetItem` enum**

Remove:
```swift
@State private var showingEditView = false
@State private var editingSubscription: RecurringSeries?
```

Add (before `var body`):
```swift
private enum SubscriptionSheetItem: Identifiable {
    case new
    case edit(RecurringSeries)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let sub): return sub.id
        }
    }
}
@State private var sheetItem: SubscriptionSheetItem?
```

**Step 2: Update toolbar button — use new state**

Replace:
```swift
Button {
    editingSubscription = nil
    showingEditView = true
} label: {
    Image(systemName: "plus")
}
```
With:
```swift
Button {
    sheetItem = .new
} label: {
    Image(systemName: "plus")
}
```

**Step 3: Fix deprecated placement**

Replace:
```swift
ToolbarItem(placement: .navigationBarTrailing) {
```
With:
```swift
ToolbarItem(placement: .topBarTrailing) {
```

**Step 4: Replace the `.sheet` modifier**

Replace the entire `.sheet(isPresented: $showingEditView) { ... }` block (lines 51–83) with:
```swift
.sheet(item: $sheetItem) { item in
    switch item {
    case .new:
        SubscriptionEditView(
            transactionStore: transactionStore,
            transactionsViewModel: transactionsViewModel,
            subscription: nil
        )
    case .edit(let subscription):
        SubscriptionEditView(
            transactionStore: transactionStore,
            transactionsViewModel: transactionsViewModel,
            subscription: subscription
        )
    }
}
```

**Step 5: Update `emptyState` — no longer sets two state variables**

Replace:
```swift
action: {
    editingSubscription = nil
    showingEditView = true
}
```
With:
```swift
action: {
    sheetItem = .new
}
```

**Step 6: Update `subscriptionsList` — use new state for navigation links**

Replace:
```swift
NavigationLink(destination: SubscriptionDetailView(...)) {
    SubscriptionCard(subscription: subscription, nextChargeDate: nextChargeDate)
}
.buttonStyle(PlainButtonStyle())
```
No change needed for navigation links (they don't use sheet state). But update the long-press or tap target if SubscriptionDetailView needs a sheet edit. Look for references to `editingSubscription` and update:

In the current `subscriptionsList`, there's only `NavigationLink` — no sheet trigger needed. The edit is inside `SubscriptionDetailView`. Confirm there are no other `editingSubscription` references and clean them up.

**Step 7: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 8: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/SubscriptionsListView.swift
git commit -m "refactor: SubscriptionsListView uses sheet(item:) and topBarTrailing"
```

---

## Task 8: Refactor `SubscriptionDetailView` — topBarTrailing, dismiss, cache transactions

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/SubscriptionDetailView.swift`

**Context:**
- Remove `onSave`/`onCancel` from sheet (SubscriptionEditView now owns dismiss - Task 6)
- `.navigationBarTrailing` → `.topBarTrailing`
- `subscriptionTransactions` computed each render → cached with `.task` + `onChange`
- Remove commented `.navigationTitle` dead code

**Step 1: Add `@State private var subscriptionTransactions: [Transaction] = []`**

Add after existing `@State` declarations:
```swift
@State private var cachedTransactions: [Transaction] = []
```

**Step 2: Add private refresh function**

Add before `var body`:
```swift
private func refreshTransactions() async {
    let existing = transactionStore.transactions.filter {
        $0.recurringSeriesId == subscription.id
    }
    let planned = transactionStore.getPlannedTransactions(for: subscription.id, horizon: 6)
    cachedTransactions = (existing + planned).sorted { $0.date < $1.date }
}
```

**Step 3: Remove the `subscriptionTransactions` computed property (lines 21–35)**

Delete the entire block:
```swift
private var subscriptionTransactions: [Transaction] {
    let existingTransactions = transactionStore.transactions.filter {
        $0.recurringSeriesId == subscription.id
    }
    let plannedTransactions = transactionStore.getPlannedTransactions(for: subscription.id, horizon: 6)
    let allTransactions = (existingTransactions + plannedTransactions)
        .sorted { $0.date < $1.date }
    return allTransactions
}
```

**Step 4: Update `transactionsSection` — replace reference**

In `transactionsSection`, replace:
```swift
if !subscriptionTransactions.isEmpty {
```
and
```swift
ForEach(subscriptionTransactions) { transaction in
```
With:
```swift
if !cachedTransactions.isEmpty {
```
and:
```swift
ForEach(cachedTransactions) { transaction in
```

**Step 5: Fix toolbar placement**

Replace:
```swift
ToolbarItem(placement: .navigationBarTrailing) {
```
With:
```swift
ToolbarItem(placement: .topBarTrailing) {
```

**Step 6: Update `.sheet` — remove onSave/onCancel (Task 6 handles dismiss)**

Replace:
```swift
.sheet(isPresented: $showingEditView) {
    SubscriptionEditView(
        transactionStore: transactionStore,
        transactionsViewModel: transactionsViewModel,
        subscription: subscription,
        onSave: { updatedSubscription in
            Task {
                try await transactionStore.updateSeries(updatedSubscription)
                showingEditView = false
            }
        },
        onCancel: {
            showingEditView = false
        }
    )
}
```
With:
```swift
.sheet(isPresented: $showingEditView) {
    SubscriptionEditView(
        transactionStore: transactionStore,
        transactionsViewModel: transactionsViewModel,
        subscription: subscription
    )
}
```

**Step 7: Add `.task` and `.onChange` for transaction caching**

Add to the body's modifier chain (after `.alert`):
```swift
.task(id: subscription.id) {
    await refreshTransactions()
}
.onChange(of: transactionStore.transactions.count) { _, _ in
    Task { await refreshTransactions() }
}
```

**Step 8: Remove commented `.navigationTitle` dead code (line 56)**

Delete:
```swift
//        .navigationTitle(subscription.description)
```

**Step 9: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 10: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/SubscriptionDetailView.swift
git commit -m "refactor: SubscriptionDetailView caches transactions, topBarTrailing, removes dead code"
```

---

## Task 9: Fix `SubscriptionCalendarView` — DateFormatter, ForEach identity, force unwrap

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/Components/SubscriptionCalendarView.swift`

**Context:**
- `formatMonthYear()` creates a new `DateFormatter()` on each call → static cached formatter
- `ForEach(0..<days.count, id: \.self)` — index-based id is unstable → `CalendarDay` struct
- `calendar.date(byAdding:...)!` force unwrap in `subscriptionsOnDate`
- Commented `.animation(...)` dead code

**Step 1: Add static `monthYearFormatter` and `CalendarDay` struct**

At the top of the file, before `struct SubscriptionCalendarView`, add:

```swift
private struct CalendarDay: Identifiable {
    let id: String
    let date: Date?
}
```

**Step 2: Add static formatter inside `SubscriptionCalendarView`**

Add as a property (after `private let spacing: CGFloat = 0` or similar):
```swift
private static let monthYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "LLLL yyyy"
    f.locale = .current
    return f
}()
```

**Step 3: Update `formatMonthYear` to use static formatter**

Replace:
```swift
private func formatMonthYear(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "LLLL yyyy"
    formatter.locale = Locale.current
    return formatter.string(from: date).capitalized
}
```
With:
```swift
private func formatMonthYear(_ date: Date) -> String {
    Self.monthYearFormatter.string(from: date).capitalized
}
```

**Step 4: Replace `daysInMonth` with `calendarDays` returning `[CalendarDay]`**

Replace the entire `daysInMonth(for:)` function with:
```swift
private func calendarDays(for monthStart: Date) -> [CalendarDay] {
    guard let range = calendar.range(of: .day, in: .month, for: monthStart),
          let firstDayOfMonth = calendar.date(
              from: calendar.dateComponents([.year, .month], from: monthStart)
          ) else {
        return []
    }

    let weekdayOfFirst = calendar.component(.weekday, from: firstDayOfMonth)
    let firstDayIndex = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

    var days: [CalendarDay] = (0..<firstDayIndex).map { i in
        CalendarDay(id: "empty-\(i)", date: nil)
    }

    for day in 1...range.count {
        if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let id = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            days.append(CalendarDay(id: id, date: date))
        }
    }
    return days
}
```

**Step 5: Update `monthGrid` to use `calendarDays` and `ForEach` with `CalendarDay.id`**

Replace the `monthGrid` function:
```swift
private func monthGrid(for monthStart: Date, availableHeight: CGFloat) -> some View {
    LazyVGrid(columns: columns, spacing: AppSpacing.xs) {
        let days = calendarDays(for: monthStart)
        ForEach(days) { day in
            if let date = day.date {
                dateCell(for: date)
            } else {
                Color.clear
                    .frame(height: 60)
            }
        }
    }
    .padding(.top, AppSpacing.md)
    .frame(maxHeight: .infinity, alignment: .top)
}
```

**Step 6: Update `calculateCalendarHeight` to use `calendarDays`**

Replace:
```swift
let days = daysInMonth(for: currentMonth)
```
With:
```swift
let days = calendarDays(for: currentMonth)
```

**Step 7: Fix force unwrap in `subscriptionsOnDate`**

Replace:
```swift
private func subscriptionsOnDate(_ date: Date) -> [RecurringSeries] {
    let dayInterval = DateInterval(start: date, end: calendar.date(byAdding: .day, value: 1, to: date)!.addingTimeInterval(-1))
    return subscriptions.filter { sub in
        !sub.occurrences(in: dayInterval).isEmpty
    }
}
```
With:
```swift
private func subscriptionsOnDate(_ date: Date) -> [RecurringSeries] {
    guard let endDate = calendar.date(byAdding: .day, value: 1, to: date) else { return [] }
    let dayInterval = DateInterval(start: date, end: endDate.addingTimeInterval(-1))
    return subscriptions.filter { sub in
        !sub.occurrences(in: dayInterval).isEmpty
    }
}
```

**Step 8: Remove commented `.animation(...)` dead code (line ~49)**

Delete:
```swift
//            .animation(.spring(response: 0.5, dampingFraction: 0.65), value: calculateCalendarHeight())
```

**Step 9: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 10: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/Components/SubscriptionCalendarView.swift
git commit -m "perf: fix SubscriptionCalendarView - cached DateFormatter, stable ForEach id, remove force unwrap"
```

---

## Task 10: Fix `SubscriptionCard` — correct `String(format:)` localization key

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/Components/SubscriptionCard.swift` (line 35)

**Context:** `"subscriptions.nextCharge"` = `"Next Charge"` — NOT a format string. Using it with `String(format:)` discards the date argument. Use new `"subscriptions.nextChargeOn"` key (added in Task 1) which contains `%@`.

**Step 1: Fix the format string usage (line 35)**

Replace:
```swift
Text(String(format: String(localized: "subscriptions.nextCharge"), formatDate(nextChargeDate)))
    .font(AppTypography.caption)
    .foregroundStyle(.secondary)
```
With:
```swift
Text(String(format: String(localized: "subscriptions.nextChargeOn"), formatDate(nextChargeDate)))
    .font(AppTypography.caption)
    .foregroundStyle(.secondary)
```

**Step 2: Build**

```
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
git add AIFinanceManager/Views/Subscriptions/Components/SubscriptionCard.swift
git commit -m "fix: use correct format-string localization key in SubscriptionCard"
```

---

## Task 11: Run full build + final verification

**Step 1: Full clean build**

```bash
xcodebuild clean build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  2>&1 | tail -5
```
Expected: `Build succeeded`

**Step 2: Run unit tests**

```bash
xcodebuild test \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:AIFinanceManagerTests \
  2>&1 | grep -E "Test Suite|passed|failed|error:"
```
Expected: All tests passed.

**Step 3: Verify localization — grep for hardcoded Russian strings in subscriptions**

```bash
grep -rn '"[А-Яа-яЁё]' \
  AIFinanceManager/Views/Subscriptions/ \
  AIFinanceManager/Utils/DateFormatters.swift \
  AIFinanceManager/Models/RecurringTransaction.swift
```
Expected: Only preview strings remain (acceptable). No hardcoded strings in production code.

**Step 4: Verify no force unwraps in subscriptions**

```bash
grep -rn '!' \
  AIFinanceManager/Views/Subscriptions/ | \
  grep -v '// ' | grep -v '!=' | grep -v 'important'
```
Expected: No `!` force unwraps in subscriptions views.

**Step 5: Final commit**

```bash
git log --oneline -12
```
Expected: 10 commits from this session visible.
