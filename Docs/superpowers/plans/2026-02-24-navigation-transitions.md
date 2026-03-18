# Navigation Transitions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Modernise all navigation in the app — value-based `NavigationLink(value:)`, `@Namespace`, `matchedTransitionSource`, `navigationTransition(.zoom)`, `NavigationPath`, and iOS 26 `glassEffectID` morphing for AccountCard → AccountActionView.

**Architecture (Approach B — layered):**
Layer 1: model Hashable conformance + value-based navigation everywhere.
Layer 2: `@Namespace` + zoom transitions on top (Insights, Subscriptions).
Layer 3: AccountCard sheet → navigation push + Liquid Glass glassEffectID morphing.

**Tech Stack:** SwiftUI iOS 26+, `@Namespace`, `matchedTransitionSource(id:in:)`, `navigationTransition(.zoom(sourceID:in:))`, `glassEffectID(_:in:)`, `NavigationStack(path:)`, `navigationDestination(for:)`.

---

## Task 1 — Hashable conformance for 3 models

**Files:**
- Modify: `AIFinanceManager/Models/InsightModels.swift` (line 14)
- Modify: `AIFinanceManager/Models/Transaction.swift` (line 238)
- Modify: `AIFinanceManager/Models/RecurringTransaction.swift` (line 21)

**Why:** `NavigationLink(value:)` requires the value type to conform to `Hashable`.

**Step 1: Add `Hashable` to `Insight`**

In `InsightModels.swift` line 14, change:
```swift
struct Insight: Identifiable {
```
to:
```swift
struct Insight: Identifiable, Hashable {
```
`Insight` has all `String`, `Double`, `Bool`, and enum/struct fields. Verify all nested types (`InsightMetric`, `InsightTrend`, `InsightType`, `InsightCategory`, `InsightSeverity`) also get `Hashable` added where missing. They are all simple structs/enums — adding `Hashable` to each is a one-line change.

**Step 2: Add `Hashable` to `Account`**

In `Transaction.swift` line 238, change:
```swift
struct Account: Identifiable, Codable, Equatable {
```
to:
```swift
struct Account: Identifiable, Codable, Equatable, Hashable {
```

**Step 3: Add `Hashable` to `RecurringSeries`**

In `RecurringTransaction.swift` line 21, change:
```swift
struct RecurringSeries: Identifiable, Codable, Equatable {
```
to:
```swift
struct RecurringSeries: Identifiable, Codable, Equatable, Hashable {
```

**Step 4: Build the project**

```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`. If Hashable synthesis fails on a nested type, add `Hashable` to that type too.

**Step 5: Commit**
```bash
git add AIFinanceManager/Models/InsightModels.swift \
        AIFinanceManager/Models/Transaction.swift \
        AIFinanceManager/Models/RecurringTransaction.swift
git commit -m "feat(models): add Hashable conformance to Insight, Account, RecurringSeries"
```

---

## Task 2 — InsightsView: @Namespace + navigationDestination + zoom transitions

**Files:**
- Modify: `AIFinanceManager/Views/Insights/InsightsView.swift`
- Modify: `AIFinanceManager/Views/Insights/Components/InsightsSectionView.swift`

**Goal:** Convert all `NavigationLink(destination: InsightDetailView(...))` calls to value-based navigation with a zoom transition. There are TWO sites: inside `InsightsSectionView`'s ForEach, and inside `InsightsView.insightSections`'s filtered ForEach.

### Step 1: Add `@Namespace` and `navigationDestination` to `InsightsView`

In `InsightsView.swift`, add `@Namespace`:
```swift
struct InsightsView: View {
    let insightsViewModel: InsightsViewModel
    @State private var selectedGranularity: InsightGranularity = .month
    @Namespace private var insightNamespace  // ← ADD
```

In the `ScrollView` body, add `navigationDestination` after the existing modifiers:
```swift
.navigationTitle(String(localized: "insights.title"))
.navigationBarTitleDisplayMode(.inline)
.navigationDestination(for: Insight.self) { insight in  // ← ADD
    InsightDetailView(
        insight: insight,
        currency: insightsViewModel.baseCurrency,
        onCategoryTap: insight.category == .spending ? spendingCategoryTap : nil
    )
    .navigationTransition(.zoom(sourceID: insight.id, in: insightNamespace))
}
```

Add a private computed property for the spending drill-down closure (replaces the inline closure that was inside `InsightsSectionView`):
```swift
private var spendingCategoryTap: (CategoryBreakdownItem) -> AnyView {
    { [insightsViewModel] item in
        AnyView(
            CategoryDeepDiveView(
                categoryName: item.categoryName,
                color: item.color,
                iconSource: item.iconSource,
                currency: insightsViewModel.baseCurrency,
                viewModel: insightsViewModel
            )
        )
    }
}
```

### Step 2: Convert the filtered ForEach in `insightSections`

Find this block (line ~258–263):
```swift
} else {
    // Show filtered insights without section headers
    ForEach(filtered) { insight in
        NavigationLink(destination: InsightDetailView(insight: insight, currency: insightsViewModel.baseCurrency)) {
            InsightsCardView(insight: insight)
        }
        .buttonStyle(.plain)
    }
    .screenPadding()
}
```

Replace with:
```swift
} else {
    ForEach(filtered) { insight in
        NavigationLink(value: insight) {
            InsightsCardView(insight: insight)
                .matchedTransitionSource(id: insight.id, in: insightNamespace)
        }
        .buttonStyle(.plain)
    }
    .screenPadding()
}
```

### Step 3: Update all `InsightsSectionView` call sites in `InsightsView`

`InsightsSectionView` will gain a `namespace` parameter (Step 4 below).
All 8 call sites in `insightSections` change from:
```swift
InsightsSectionView(
    category: .spending,
    insights: insightsViewModel.spendingInsights,
    currency: insightsViewModel.baseCurrency,
    onCategoryTap: { ... },   // ← REMOVE this param (handled in navigationDestination)
    granularity: insightsViewModel.currentGranularity
)
```
to:
```swift
InsightsSectionView(
    category: .spending,
    insights: insightsViewModel.spendingInsights,
    currency: insightsViewModel.baseCurrency,
    namespace: insightNamespace,   // ← ADD
    granularity: insightsViewModel.currentGranularity
)
```
Apply same change to all other 7 `InsightsSectionView` instances (income, budget, recurring, cashFlow, wealth, savings, forecasting). None of the others had `onCategoryTap`, so they only need `namespace:` added.

### Step 4: Refactor `InsightsSectionView`

In `InsightsSectionView.swift`:

**Remove** `onCategoryTap` property:
```swift
// DELETE this line:
var onCategoryTap: ((CategoryBreakdownItem) -> AnyView)? = nil
```

**Add** `namespace` property:
```swift
var namespace: Namespace.ID  // ← ADD
```

**Convert** the ForEach NavigationLink:
```swift
// BEFORE:
NavigationLink(
    destination: InsightDetailView(
        insight: insight,
        currency: currency,
        onCategoryTap: onCategoryTap
    )
) {
    InsightsCardView(insight: insight)
}
.buttonStyle(.plain)

// AFTER:
NavigationLink(value: insight) {
    InsightsCardView(insight: insight)
        .matchedTransitionSource(id: insight.id, in: namespace)
}
.buttonStyle(.plain)
```

**Update Previews** in `InsightsSectionView.swift` — add a dummy `@Namespace` to each `#Preview`:
```swift
#Preview("Simple — Income") {
    @Namespace var ns
    return NavigationStack {
        ScrollView {
            InsightsSectionView(
                category: .income,
                insights: [.mockIncomeGrowth()],
                currency: "KZT",
                namespace: ns
            )
        }
    }
}
```

### Step 5: Build
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`.

### Step 6: Commit
```bash
git add AIFinanceManager/Views/Insights/InsightsView.swift \
        AIFinanceManager/Views/Insights/Components/InsightsSectionView.swift
git commit -m "feat(insights): value-based NavigationLink + zoom transition from insight cards"
```

---

## Task 3 — SubscriptionsListView: @Namespace + value-based nav + zoom

**Files:**
- Modify: `AIFinanceManager/Views/Subscriptions/SubscriptionsListView.swift`

**Goal:** Convert the `NavigationLink(destination:)` inside the subscriptions ForEach to value-based with a zoom transition.

### Step 1: Add `@Namespace` and `navigationDestination`

In `SubscriptionsListView.swift`, add namespace:
```swift
struct SubscriptionsListView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @Namespace private var subscriptionNamespace  // ← ADD
    // ...
```

Add `navigationDestination` to the `body`'s `ScrollView` (after existing toolbar modifier):
```swift
.navigationDestination(for: RecurringSeries.self) { subscription in
    SubscriptionDetailView(
        transactionStore: transactionStore,
        transactionsViewModel: transactionsViewModel,
        subscription: subscription
    )
    .environment(timeFilterManager)
    .navigationTransition(.zoom(sourceID: subscription.id, in: subscriptionNamespace))
}
```

### Step 2: Convert ForEach NavigationLink

Find `subscriptionsList` computed property:
```swift
// BEFORE:
NavigationLink(destination: SubscriptionDetailView(
    transactionStore: transactionStore,
    transactionsViewModel: transactionsViewModel,
    subscription: subscription
)
    .environment(timeFilterManager)) {
    SubscriptionCard(
        subscription: subscription,
        nextChargeDate: nextChargeDate
    )
}
.buttonStyle(PlainButtonStyle())

// AFTER:
NavigationLink(value: subscription) {
    SubscriptionCard(
        subscription: subscription,
        nextChargeDate: nextChargeDate
    )
    .matchedTransitionSource(id: subscription.id, in: subscriptionNamespace)
}
.buttonStyle(PlainButtonStyle())
```

### Step 3: Build and commit
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

```bash
git add AIFinanceManager/Views/Subscriptions/SubscriptionsListView.swift
git commit -m "feat(subscriptions): value-based NavigationLink + zoom transition from subscription cards"
```

---

## Task 4 — ContentView: NavigationStack(path:) + HomeDestination

**Files:**
- Modify: `AIFinanceManager/Views/Home/ContentView.swift`

**Goal:** Replace `NavigationStack` with `NavigationStack(path:)`, convert the two `NavigationLink(destination:)` to value-based, and add `navigationDestination(for: HomeDestination.self)`.

### Step 1: Add `HomeDestination` enum

Add this enum at the top of `ContentView.swift`, before `struct ContentView`:
```swift
enum HomeDestination: Hashable {
    case history
    case subscriptions
}
```

### Step 2: Add `@State private var navigationPath`

In `ContentView`, add:
```swift
@State private var navigationPath = NavigationPath()
```

### Step 3: Change `NavigationStack` to `NavigationStack(path:)`

```swift
// BEFORE:
NavigationStack {
    mainContent
    // ...
}

// AFTER:
NavigationStack(path: $navigationPath) {
    mainContent
    .navigationDestination(for: HomeDestination.self) { dest in
        switch dest {
        case .history:
            historyDestination
        case .subscriptions:
            subscriptionsDestination
        }
    }
    // ... all other modifiers unchanged
}
```

### Step 4: Convert `historyNavigationLink`

```swift
// BEFORE:
private var historyNavigationLink: some View {
    NavigationLink(destination: historyDestination) {
        TransactionsSummaryCard(...)
    }
    .buttonStyle(.bounce)
    .screenPadding()
}

// AFTER:
private var historyNavigationLink: some View {
    NavigationLink(value: HomeDestination.history) {
        TransactionsSummaryCard(...)
    }
    .buttonStyle(.bounce)
    .screenPadding()
}
```

### Step 5: Convert `subscriptionsNavigationLink`

```swift
// BEFORE:
private var subscriptionsNavigationLink: some View {
    NavigationLink(destination: subscriptionsDestination) {
        SubscriptionsCardView(...)
    }
    .buttonStyle(.bounce)
    .screenPadding()
}

// AFTER:
private var subscriptionsNavigationLink: some View {
    NavigationLink(value: HomeDestination.subscriptions) {
        SubscriptionsCardView(...)
    }
    .buttonStyle(.bounce)
    .screenPadding()
}
```

### Step 6: Build and commit
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

```bash
git add AIFinanceManager/Views/Home/ContentView.swift
git commit -m "feat(home): NavigationStack(path:) + HomeDestination enum for programmatic navigation"
```

---

## Task 5 — AccountCard: sheet → navigation + glassEffectID morphing

This is the largest change. Four files modified.

**Files:**
- Modify: `AIFinanceManager/Views/Accounts/Components/AccountCard.swift`
- Modify: `AIFinanceManager/Views/Accounts/Components/AccountsCarousel.swift`
- Modify: `AIFinanceManager/Views/Home/ContentView.swift`
- Modify: `AIFinanceManager/Views/Accounts/AccountActionView.swift`

**Goal:**
- Remove `.sheet(item: $selectedAccount)` from ContentView
- Remove outer `NavigationStack` from `AccountActionView`
- Convert `AccountCard` from `Button` to `NavigationLink(value:)` with `matchedTransitionSource` + `glassEffectID`
- Add `navigationDestination(for: Account.self)` to ContentView with zoom transition + `glassEffectID` on the destination header

### Step 1: Modify `AccountCard` — Button → NavigationLink + transitions

```swift
// BEFORE:
struct AccountCard: View {
    let account: Account
    let onTap: () -> Void
    let balanceCoordinator: BalanceCoordinator

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.sm) {
                IconView(source: account.iconSource, size: AppIconSize.xl)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                        .foregroundStyle(.primary)
                    FormattedAmountText(...)
                }
            }
            .glassCardStyle()
        }
        .buttonStyle(.bounce)
        .accessibilityLabel(...)
        .accessibilityHint(...)
    }
}

// AFTER:
struct AccountCard: View {
    let account: Account
    let balanceCoordinator: BalanceCoordinator
    var namespace: Namespace.ID   // ← ADD (replaces onTap)

    private var balance: Double {
        balanceCoordinator.balances[account.id] ?? 0
    }

    var body: some View {
        NavigationLink(value: account) {    // ← was Button(action: onTap)
            HStack(spacing: AppSpacing.sm) {
                IconView(source: account.iconSource, size: AppIconSize.xl)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(account.name)
                        .font(AppTypography.h4)
                        .foregroundStyle(.primary)
                    FormattedAmountText(
                        amount: balance,
                        currency: account.currency,
                        fontSize: AppTypography.bodySmall,
                        fontWeight: .semibold,
                        color: .primary
                    )
                }
            }
            .glassCardStyle()
            .glassEffectID("account-card-\(account.id)", in: namespace)  // ← ADD
        }
        .buttonStyle(.bounce)
        .matchedTransitionSource(id: account.id, in: namespace)  // ← ADD
        .accessibilityLabel(String(format: String(localized: "accessibility.accountCard.label"), account.name, Formatting.formatCurrency(balance, currency: account.currency)))
        .accessibilityHint(String(localized: "accessibility.accountCard.hint"))
    }
}
```

**Update the Preview** at the bottom of `AccountCard.swift` — remove `onTap:` and add a `@Namespace`:
```swift
#Preview("Account Card") {
    @Namespace var ns
    let coordinator = AppCoordinator()
    return NavigationStack {
        AccountCard(
            account: Account(name: "Main Account", currency: "USD", iconSource: nil, initialBalance: 1000),
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!,
            namespace: ns
        )
        .padding()
    }
}
```

### Step 2: Modify `AccountsCarousel` — remove `onAccountTap`, add `namespace`

```swift
// BEFORE:
struct AccountsCarousel: View {
    let accounts: [Account]
    let onAccountTap: (Account) -> Void
    let balanceCoordinator: BalanceCoordinator

    var body: some View {
        UniversalCarousel(config: .cards) {
            ForEach(accounts.sortedByOrder()) { account in
                AccountCard(
                    account: account,
                    onTap: {
                        HapticManager.light()
                        onAccountTap(account)
                    },
                    balanceCoordinator: balanceCoordinator
                )
                .id("\(account.id)-\(balanceCoordinator.balances[account.id] ?? 0)")
            }
        }
        .screenPadding()
    }
}

// AFTER:
struct AccountsCarousel: View {
    let accounts: [Account]
    let balanceCoordinator: BalanceCoordinator
    var namespace: Namespace.ID   // ← ADD

    var body: some View {
        UniversalCarousel(config: .cards) {
            ForEach(accounts.sortedByOrder()) { account in
                AccountCard(
                    account: account,
                    balanceCoordinator: balanceCoordinator,
                    namespace: namespace   // ← pass through
                )
                .id("\(account.id)-\(balanceCoordinator.balances[account.id] ?? 0)")
            }
        }
        .screenPadding()
    }
}
```

**Update the Preview** in `AccountsCarousel.swift` — add `@Namespace` and remove `onAccountTap:`:
```swift
#Preview {
    @Namespace var ns
    let coordinator = AppCoordinator()
    return NavigationStack {
        AccountsCarousel(
            accounts: [...],
            balanceCoordinator: coordinator.accountsViewModel.balanceCoordinator!,
            namespace: ns
        )
    }
}
```

### Step 3: Modify `ContentView` — remove sheet, add namespace + navigationDestination

**3a.** Add `@Namespace`:
```swift
@Namespace private var accountNamespace  // ← ADD
```

**3b.** Remove `selectedAccount` state and sheet:
```swift
// DELETE:
@State private var selectedAccount: Account?
// DELETE:
.sheet(item: $selectedAccount) { accountSheet(for: $0) }
```

**3c.** In `accountsSection`, pass `namespace` to `AccountsCarousel` and remove `onAccountTap`:
```swift
// BEFORE:
AccountsCarousel(
    accounts: accountsViewModel.accounts,
    onAccountTap: { account in
        selectedAccount = account
    },
    balanceCoordinator: accountsViewModel.balanceCoordinator!
)

// AFTER:
AccountsCarousel(
    accounts: accountsViewModel.accounts,
    balanceCoordinator: accountsViewModel.balanceCoordinator!,
    namespace: accountNamespace
)
```

**3d.** Add `navigationDestination(for: Account.self)` inside the `NavigationStack(path: $navigationPath)` body, alongside the existing `HomeDestination` destination:
```swift
.navigationDestination(for: Account.self) { account in
    AccountActionView(
        transactionsViewModel: viewModel,
        accountsViewModel: accountsViewModel,
        account: account,
        namespace: accountNamespace
    )
    .navigationTransition(.zoom(sourceID: account.id, in: accountNamespace))
}
```

**3e.** Remove the `accountSheet(for:)` helper method (it's no longer used).

Also remove the private helper if it exists (search for `func accountSheet` in ContentView and delete it).

### Step 4: Modify `AccountActionView` — remove NavigationStack wrapper, add namespace + glassEffectID

**4a.** Add `namespace` parameter:
```swift
struct AccountActionView: View {
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TransactionStore.self) private var transactionStore
    @Environment(AppCoordinator.self) private var appCoordinator
    let account: Account
    var namespace: Namespace.ID   // ← ADD
    @Environment(\.dismiss) var dismiss
    // ...
```

Also update `init` to include `namespace`:
```swift
init(
    transactionsViewModel: TransactionsViewModel,
    accountsViewModel: AccountsViewModel,
    account: Account,
    namespace: Namespace.ID,         // ← ADD
    transferDirection: DepositTransferDirection? = nil
) {
    self.transactionsViewModel = transactionsViewModel
    self.accountsViewModel = accountsViewModel
    self.account = account
    self.namespace = namespace       // ← ADD
    self.transferDirection = transferDirection
    _selectedCurrency = State(initialValue: account.currency)
    _selectedAction = State(initialValue: account.isDeposit ? .transfer : .transfer)
}
```

**4b.** Remove the outer `NavigationStack` wrapper in `body`:
```swift
// BEFORE:
var body: some View {
    NavigationStack {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // ... content
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ... }
        // ... other modifiers
    }
}

// AFTER:
var body: some View {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            // ... content unchanged
        }
    }
    .navigationTitle(navigationTitleText)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ... }
    // ... other modifiers unchanged
}
```

Note: `dismiss()` in the cancel toolbar button continues to work correctly — when the view is a navigation destination, `dismiss()` pops back to the previous screen.

**4c.** Add `glassEffectID` to the account header area. Find the top of the `body` VStack content (the first section with account info/icon) and add:

After the leading icon/header view, add `glassEffectID` to the navigation bar area. The simplest approach is to add it to the `navigationTitle` modifier chain, but since `glassEffectID` requires a View, apply it to the ScrollView's background or a hero header view.

Add a hero header view at the top of the ScrollView's VStack:
```swift
// At the very top of the ScrollView VStack, before the action picker:
Color.clear
    .frame(height: 0)
    .glassEffectID("account-card-\(account.id)", in: namespace)  // ← ADD (matches AccountCard's ID)
```

This invisible anchor creates the glass morphing connection between the source card and the destination screen.

### Step 5: Build
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

### Step 6: Commit
```bash
git add AIFinanceManager/Views/Accounts/Components/AccountCard.swift \
        AIFinanceManager/Views/Accounts/Components/AccountsCarousel.swift \
        AIFinanceManager/Views/Home/ContentView.swift \
        AIFinanceManager/Views/Accounts/AccountActionView.swift
git commit -m "feat(accounts): sheet → navigation + zoom transition + glassEffectID morphing"
```

---

## Task 6 — CSVEntityMappingView: value-based NavigationLink

**Files:**
- Modify: `AIFinanceManager/Views/CSV/CSVEntityMappingView.swift`

**Goal:** Replace 3 inline `NavigationLink(destination:)` with a typed enum + `navigationDestination(for:)`.

### Step 1: Add `CSVMappingDestination` enum

Add before `struct CSVEntityMappingView`:
```swift
private enum CSVMappingDestination: Hashable {
    case account(String)                  // csvValue
    case incomeCategory(String)           // csvValue
    case expenseCategory(String)          // csvValue
}
```

### Step 2: Add `navigationDestination` to the existing `NavigationStack`

Inside the `NavigationStack { Form { ... } }` but after the Form closing brace:
```swift
.navigationDestination(for: CSVMappingDestination.self) { dest in
    switch dest {
    case .account(let csvValue):
        AccountMappingDetailView(
            csvValue: csvValue,
            accounts: accountsViewModel.accounts,
            selectedAccountId: Binding(
                get: { accountMappings[csvValue] },
                set: { accountMappings[csvValue] = $0 }
            ),
            onCreateNew: {
                Task { await createAccount(name: csvValue) }
            }
        )
    case .incomeCategory(let csvValue):
        CategoryMappingDetailView(
            csvValue: csvValue,
            categories: categoriesViewModel.incomeCategories,
            selectedCategory: Binding(
                get: { categoryMappings[csvValue] },
                set: { categoryMappings[csvValue] = $0 }
            ),
            onCreateNew: {
                Task { await createCategory(name: csvValue, isIncome: true) }
            }
        )
    case .expenseCategory(let csvValue):
        CategoryMappingDetailView(
            csvValue: csvValue,
            categories: categoriesViewModel.customCategories,
            selectedCategory: Binding(
                get: { categoryMappings[csvValue] },
                set: { categoryMappings[csvValue] = $0 }
            ),
            onCreateNew: {
                Task { await createCategory(name: csvValue, isIncome: false) }
            }
        )
    }
}
```

### Step 3: Convert all 3 NavigationLink(destination:) to NavigationLink(value:)

**Account mapping (line ~37):**
```swift
// BEFORE:
NavigationLink(destination: AccountMappingDetailView(
    csvValue: accountValue,
    accounts: accountsViewModel.accounts,
    selectedAccountId: Binding(...),
    onCreateNew: { ... }
)) {
    HStack { ... }
}

// AFTER:
NavigationLink(value: CSVMappingDestination.account(accountValue)) {
    HStack { ... }
}
```

**Income category mapping (~line 70):**
```swift
// BEFORE:
NavigationLink(destination: CategoryMappingDetailView(...income...)) {
    HStack { ... }
}

// AFTER:
NavigationLink(value: CSVMappingDestination.incomeCategory(categoryValue)) {
    HStack { ... }
}
```

**Expense category mapping (~line 101):**
```swift
// BEFORE:
NavigationLink(destination: CategoryMappingDetailView(...expense...)) {
    HStack { ... }
}

// AFTER:
NavigationLink(value: CSVMappingDestination.expenseCategory(categoryValue)) {
    HStack { ... }
}
```

Note: The Bindings for `accountMappings` and `categoryMappings` are captured in the `navigationDestination` closure above. Since these are `@State` dictionaries, the closure captures them by reference correctly.

### Step 4: Build and commit
```bash
xcodebuild build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|Build succeeded"
```

```bash
git add AIFinanceManager/Views/CSV/CSVEntityMappingView.swift
git commit -m "feat(csv): value-based NavigationLink with CSVMappingDestination enum"
```

---

## Task 7 — Final build + smoke test

**Step 1: Full clean build**
```bash
xcodebuild clean build \
  -scheme AIFinanceManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  2>&1 | grep -E "error:|warning:|Build succeeded"
```
Expected: `Build succeeded` with 0 errors.

**Step 2: Manual smoke test checklist**
- [ ] Home → tap TransactionsSummaryCard → History opens (no crash)
- [ ] Home → tap SubscriptionsCardView → Subscriptions opens (no crash)
- [ ] Home → tap AccountCard → AccountActionView opens with zoom animation
- [ ] AccountActionView → tap X → goes back to Home (not crashes)
- [ ] Analytics tab → tap any InsightCard → zoom animation, InsightDetailView opens
- [ ] Analytics tab → Spending insight → drill-down chevron visible in detail
- [ ] Analytics tab → filtered ForEach → cards navigate to InsightDetailView with zoom
- [ ] Subscriptions → tap SubscriptionCard → zoom animation, SubscriptionDetailView opens
- [ ] Settings → CSV Import flow → mapping screens open correctly (NavigationLink works inside sheet)

**Step 3: Final commit**
```bash
git add docs/plans/2026-02-24-navigation-transitions.md
git commit -m "docs: add navigation transitions implementation plan"
```

---

## Summary of changes per file

| File | Change |
|---|---|
| `Models/InsightModels.swift` | Add `Hashable` to `Insight` + nested types |
| `Models/Transaction.swift` | Add `Hashable` to `Account` |
| `Models/RecurringTransaction.swift` | Add `Hashable` to `RecurringSeries` |
| `Views/Insights/InsightsView.swift` | `@Namespace`, `navigationDestination(for: Insight.self)`, zoom, `spendingCategoryTap` property, update 8 InsightsSectionView calls |
| `Views/Insights/Components/InsightsSectionView.swift` | Remove `onCategoryTap`, add `namespace`, value-based link + `matchedTransitionSource` |
| `Views/Subscriptions/SubscriptionsListView.swift` | `@Namespace`, value-based link + `matchedTransitionSource`, `navigationDestination`, zoom |
| `Views/Home/ContentView.swift` | `HomeDestination` enum, `NavigationPath`, 2× value-based links, remove sheet, add account `navigationDestination`, zoom |
| `Views/Accounts/Components/AccountCard.swift` | Remove `onTap`, add `namespace`, Button → NavigationLink, `matchedTransitionSource`, `glassEffectID` |
| `Views/Accounts/Components/AccountsCarousel.swift` | Remove `onAccountTap`, add `namespace`, pass through |
| `Views/Accounts/AccountActionView.swift` | Add `namespace`, remove `NavigationStack` wrapper, `glassEffectID` anchor |
| `Views/CSV/CSVEntityMappingView.swift` | `CSVMappingDestination` enum, value-based links, `navigationDestination` |
