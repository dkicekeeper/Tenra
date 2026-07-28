# Subscription Transaction Linking — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to retroactively link existing expense transactions to a subscription via a multi-select UI, reusing the loan link-payments pattern.

**Architecture:** Create `SubscriptionTransactionMatcher` (mirrors `LoanTransactionMatcher`) for auto-matching. Add `SubscriptionLinkPaymentsView` (mirrors `LoanLinkPaymentsView`) for selection UI. Add `linkTransactionsToSubscription()` on `TransactionStore+Recurring`. Wire into `SubscriptionDetailView` toolbar menu.

**Tech Stack:** SwiftUI, Swift Testing, @Observable, TransactionStore

---

### Task 1: Create `SubscriptionTransactionMatcher`

**Files:**
- Create: `Tenra/Services/Recurring/SubscriptionTransactionMatcher.swift`

**Step 1: Create the matcher**

```swift
//
//  SubscriptionTransactionMatcher.swift
//  Tenra
//
//  Finds existing transactions that match a subscription's payment pattern.
//  Used to retroactively link manually entered transactions to a subscription.
//

import Foundation

/// Finds existing transactions that match a subscription's payment pattern.
nonisolated enum SubscriptionTransactionMatcher {

    /// Default tolerance: +/-10% of subscription amount.
    static let defaultTolerance: Double = 0.10

    /// Returns expense transactions whose amount falls within `tolerance` of
    /// the subscription's amount, dated after the subscription start, matching
    /// the subscription currency, and not already linked to any recurring series.
    /// Results are sorted chronologically.
    static func findCandidates(
        for subscription: RecurringSeries,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance
    ) -> [Transaction] {
        let amount = NSDecimalNumber(decimal: subscription.amount).doubleValue
        let lowerBound = amount * (1.0 - tolerance)
        let upperBound = amount * (1.0 + tolerance)
        let startDate = subscription.startDate
        let currency = subscription.currency

        return transactions
            .filter { tx in
                guard tx.type == .expense else { return false }
                guard tx.currency == currency else { return false }
                guard tx.amount >= lowerBound && tx.amount <= upperBound else { return false }
                guard tx.date >= startDate else { return false }
                guard tx.recurringSeriesId == nil else { return false }
                return true
            }
            .sorted { $0.date < $1.date }
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors (or only pre-existing ones)

**Step 3: Commit**

```
feat: add SubscriptionTransactionMatcher for auto-matching
```

---

### Task 2: Write tests for `SubscriptionTransactionMatcher`

**Files:**
- Create: `TenraTests/Services/SubscriptionTransactionMatcherTests.swift`

**Step 1: Write the tests**

Mirror the structure of `TenraTests/Services/LoanTransactionMatcherTests.swift`. Use Swift Testing (`import Testing`, `@Test`, `#expect`).

```swift
//
//  SubscriptionTransactionMatcherTests.swift
//  TenraTests
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct SubscriptionTransactionMatcherTests {

    // MARK: - Helpers

    private func makeSubscription(
        amount: Decimal = 9.99,
        startDate: String = "2024-01-01",
        currency: String = "USD"
    ) -> RecurringSeries {
        RecurringSeries(
            id: "sub-1",
            amount: amount,
            currency: currency,
            category: "Entertainment",
            description: "Netflix",
            frequency: .monthly,
            startDate: startDate,
            kind: .subscription,
            status: .active
        )
    }

    private func makeTransaction(
        id: String = UUID().uuidString,
        date: String,
        amount: Double,
        type: TransactionType = .expense,
        currency: String = "USD",
        recurringSeriesId: String? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "Payment",
            amount: amount,
            currency: currency,
            type: type,
            category: "Entertainment",
            recurringSeriesId: recurringSeriesId
        )
    }

    // MARK: - findCandidates

    @Test func findCandidates_matchesExpensesWithinTolerance() {
        let sub = makeSubscription(amount: 9.99, startDate: "2024-01-01")
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99),
            makeTransaction(date: "2024-03-01", amount: 9.50),  // within 10%
            makeTransaction(date: "2024-04-01", amount: 5.00),  // outside 10%
            makeTransaction(date: "2024-05-01", amount: 15.00), // outside 10%
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(
            for: sub,
            in: transactions
        )

        #expect(candidates.count == 2)
        #expect(candidates[0].amount == 9.99)
        #expect(candidates[1].amount == 9.50)
    }

    @Test func findCandidates_excludesNonExpenses() {
        let sub = makeSubscription()
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99, type: .income),
            makeTransaction(date: "2024-02-02", amount: 9.99, type: .internalTransfer),
            makeTransaction(date: "2024-02-03", amount: 9.99, type: .expense),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].type == .expense)
    }

    @Test func findCandidates_excludesBeforeStartDate() {
        let sub = makeSubscription(startDate: "2024-06-01")
        let transactions = [
            makeTransaction(date: "2024-05-01", amount: 9.99),
            makeTransaction(date: "2024-07-01", amount: 9.99),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].date == "2024-07-01")
    }

    @Test func findCandidates_excludesDifferentCurrency() {
        let sub = makeSubscription(currency: "USD")
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99, currency: "USD"),
            makeTransaction(date: "2024-02-02", amount: 9.99, currency: "KZT"),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].currency == "USD")
    }

    @Test func findCandidates_excludesAlreadyLinked() {
        let sub = makeSubscription()
        let transactions = [
            makeTransaction(date: "2024-02-01", amount: 9.99, recurringSeriesId: nil),
            makeTransaction(date: "2024-03-01", amount: 9.99, recurringSeriesId: "other-series"),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].recurringSeriesId == nil)
    }

    @Test func findCandidates_sortsByDate() {
        let sub = makeSubscription()
        let transactions = [
            makeTransaction(date: "2024-04-01", amount: 9.99),
            makeTransaction(date: "2024-02-01", amount: 9.99),
            makeTransaction(date: "2024-03-01", amount: 9.99),
        ]

        let candidates = SubscriptionTransactionMatcher.findCandidates(for: sub, in: transactions)

        #expect(candidates[0].date == "2024-02-01")
        #expect(candidates[1].date == "2024-03-01")
        #expect(candidates[2].date == "2024-04-01")
    }
}
```

**Step 2: Run tests to verify they pass**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/SubscriptionTransactionMatcherTests 2>&1 | tail -20`
Expected: All 6 tests PASS

**Step 3: Commit**

```
test: add SubscriptionTransactionMatcher tests
```

---

### Task 3: Add `linkTransactionsToSubscription` to `TransactionStore+Recurring`

**Files:**
- Modify: `Tenra/ViewModels/TransactionStore+Recurring.swift` (add method at end of extension)

**Step 1: Add the linking method**

Add the following at the end of the `TransactionStore` extension, before the closing `}`:

```swift
// MARK: - Link Existing Transactions to Subscription

/// Link existing transactions to a subscription by setting their recurringSeriesId.
/// Unlike loan linking, this does NOT change the transaction type or accountId —
/// only the recurringSeriesId is set, making the transaction appear in the
/// subscription's transaction history.
func linkTransactionsToSubscription(
    seriesId: String,
    transactions: [Transaction]
) async throws {
    guard recurringSeries.contains(where: { $0.id == seriesId }) else {
        throw TransactionStoreError.seriesNotFound
    }

    for tx in transactions.sorted(by: { $0.date < $1.date }) {
        let updated = Transaction(
            id: tx.id,
            date: tx.date,
            description: tx.description,
            amount: tx.amount,
            currency: tx.currency,
            convertedAmount: tx.convertedAmount,
            type: tx.type,
            category: tx.category,
            subcategory: tx.subcategory,
            accountId: tx.accountId,
            targetAccountId: tx.targetAccountId,
            accountName: tx.accountName,
            targetAccountName: tx.targetAccountName,
            targetCurrency: tx.targetCurrency,
            targetAmount: tx.targetAmount,
            recurringSeriesId: seriesId,
            recurringOccurrenceId: tx.recurringOccurrenceId,
            createdAt: tx.createdAt
        )
        try await update(updated)
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```
feat: add linkTransactionsToSubscription on TransactionStore
```

---

### Task 4: Create `SubscriptionLinkPaymentsView`

**Files:**
- Create: `Tenra/Views/Subscriptions/SubscriptionLinkPaymentsView.swift`

**Step 1: Create the view**

Mirror `Tenra/Views/Loans/LoanLinkPaymentsView.swift` structure. Key differences:
- Takes `RecurringSeries` instead of `Account`
- Uses `SubscriptionTransactionMatcher` instead of `LoanTransactionMatcher`
- Calls `transactionStore.linkTransactionsToSubscription()` instead of `loansViewModel.linkTransactions()`
- No `loansViewModel` or `balanceCoordinator` dependency needed

```swift
//
//  SubscriptionLinkPaymentsView.swift
//  Tenra
//
//  Full-screen view for selecting existing transactions to link to a subscription.
//  Uses SubscriptionTransactionMatcher for auto-matching and TransactionStore
//  for linking on confirm.
//

import SwiftUI

struct SubscriptionLinkPaymentsView: View {
    let subscription: RecurringSeries
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @Environment(TransactionStore.self) private var transactionStore
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Transaction] = []
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var isLinking = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var filterAccountId: String?

    // MARK: - Computed Properties

    /// When search is empty — show auto-matched candidates.
    /// When search is active — search ALL unlinked expense transactions globally.
    private var filteredCandidates: [Transaction] {
        var result: [Transaction]
        if searchText.isEmpty {
            result = candidates
        } else {
            let query = searchText.lowercased()
            let allTx = transactionStore.transactions.filter { tx in
                tx.type == .expense
                && tx.currency == subscription.currency
                && tx.recurringSeriesId == nil
            }
            result = allTx.filter { tx in
                tx.description.lowercased().contains(query)
                || tx.category.lowercased().contains(query)
                || (tx.subcategory?.lowercased().contains(query) ?? false)
                || String(format: "%.0f", tx.amount).contains(query)
                || tx.date.contains(query)
            }
        }
        if let accountId = filterAccountId {
            result = result.filter { $0.accountId == accountId }
        }
        return result
    }

    private var selectedTransactions: [Transaction] {
        candidates.filter { selectedIds.contains($0.id) }
    }

    private var selectedTotal: Double {
        selectedTransactions.reduce(0) { $0 + $1.amount }
    }

    private var uniqueAccountIds: [String] {
        Array(Set(candidates.compactMap(\.accountId))).sorted()
    }

    // MARK: - Date Sections

    private var dateSections: [(date: String, displayLabel: String, transactions: [Transaction])] {
        let grouped = Dictionary(grouping: filteredCandidates) { $0.date }
        return grouped.sorted { $0.key > $1.key }.map { key, txs in
            (date: key, displayLabel: displayDateKey(from: key), transactions: txs)
        }
    }

    // MARK: - Body

    var body: some View {
        transactionList
            .safeAreaBar(edge: .top) {
                if uniqueAccountIds.count > 1 {
                    accountFilter
                        .padding(.vertical, AppSpacing.sm)
                }
            }
            .safeAreaBar(edge: .bottom) {
                actionBar
            }
            .searchable(text: $searchText, prompt: String(localized: "subscription.linkPayments.search", defaultValue: "Search by description or amount"))
            .navigationTitle(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"))
                            .font(AppTypography.body.weight(.semibold))
                        Text(String(format: String(localized: "subscription.linkPayments.selectedWithAmount", defaultValue: "%d selected · %@"), selectedIds.count, Formatting.formatCurrency(selectedTotal, currency: subscription.currency)))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .task {
                loadCandidates()
            }
    }

    // MARK: - Account Filter

    private var accountFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                UniversalFilterButton(
                    title: String(localized: "subscription.filterAll", defaultValue: "All"),
                    isSelected: filterAccountId == nil,
                    showChevron: false,
                    onTap: { filterAccountId = nil }
                )

                ForEach(uniqueAccountIds, id: \.self) { accountId in
                    let accountName = transactionStore.accounts.first(where: { $0.id == accountId })?.name ?? accountId
                    UniversalFilterButton(
                        title: accountName,
                        isSelected: filterAccountId == accountId,
                        showChevron: false,
                        onTap: { filterAccountId = accountId }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        List {
            ForEach(dateSections, id: \.date) { section in
                Section {
                    ForEach(section.transactions) { transaction in
                        let isSelected = selectedIds.contains(transaction.id)
                        let styleData = CategoryStyleHelper.cached(
                            category: transaction.category,
                            type: transaction.type,
                            customCategories: categoriesViewModel.customCategories
                        )
                        let sourceAccount = accountsViewModel.accounts.first { $0.id == transaction.accountId }
                        let targetAccount = accountsViewModel.accounts.first { $0.id == transaction.targetAccountId }

                        Button {
                            if isSelected {
                                selectedIds.remove(transaction.id)
                            } else {
                                selectedIds.insert(transaction.id)
                            }
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? AppColors.accent : .secondary)
                                    .font(.system(size: AppIconSize.md))

                                TransactionCard(
                                    transaction: transaction,
                                    currency: subscription.currency,
                                    styleData: styleData,
                                    sourceAccount: sourceAccount,
                                    targetAccount: targetAccount
                                )
                                .allowsHitTesting(false)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(
                            top: AppSpacing.sm,
                            leading: AppSpacing.lg,
                            bottom: AppSpacing.sm,
                            trailing: AppSpacing.lg
                        ))
                    }
                } header: {
                    DateSectionHeaderView(dateKey: section.displayLabel)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if candidates.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "subscription.linkPayments.empty", defaultValue: "No matching transactions"), systemImage: "doc.text.magnifyingglass")
                }
            } else if filteredCandidates.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Button {
                linkSelected()
            } label: {
                if isLinking {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(String(format: String(localized: "subscription.linkPayments.link", defaultValue: "Link %d Payments"), selectedIds.count))
                        .frame(maxWidth: .infinity)
                }
            }
            .primaryButton(disabled: selectedIds.isEmpty || isLinking)
            .padding(AppSpacing.lg)
        }
        .overlay(alignment: .top) {
            if showError {
                MessageBanner.error(errorMessage)
                    .padding(.horizontal, AppSpacing.lg)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Helpers

    private func displayDateKey(from isoDate: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: isoDate) else { return isoDate }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sectionDay = calendar.startOfDay(for: date)

        if sectionDay == today {
            return String(localized: "common.today", defaultValue: "Today")
        }
        if let diff = calendar.dateComponents([.day], from: sectionDay, to: today).day, diff == 1 {
            return String(localized: "common.yesterday", defaultValue: "Yesterday")
        }

        let currentYear = calendar.component(.year, from: Date())
        let sectionYear = calendar.component(.year, from: date)
        if sectionYear == currentYear {
            return DateFormatters.displayDateFormatter.string(from: date)
        }
        return DateFormatters.displayDateWithYearFormatter.string(from: date)
    }

    // MARK: - Actions

    private func loadCandidates() {
        let matched = SubscriptionTransactionMatcher.findCandidates(
            for: subscription,
            in: transactionStore.transactions
        )
        candidates = matched
        selectedIds = Set(matched.map(\.id))
    }

    private func linkSelected() {
        guard !selectedIds.isEmpty else { return }
        isLinking = true
        showError = false

        Task {
            do {
                try await transactionStore.linkTransactionsToSubscription(
                    seriesId: subscription.id,
                    transactions: selectedTransactions
                )
                isLinking = false
                dismiss()
            } catch {
                isLinking = false
                errorMessage = error.localizedDescription
                withAnimation(AppAnimation.contentSpring) {
                    showError = true
                }
            }
        }
    }
}
```

**Step 2: Build to verify no compile errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 3: Commit**

```
feat: add SubscriptionLinkPaymentsView
```

---

### Task 5: Wire into `SubscriptionDetailView`

**Files:**
- Modify: `Tenra/Views/Subscriptions/SubscriptionDetailView.swift`
- Modify: `Tenra/Views/Subscriptions/SubscriptionsListView.swift` (pass `accountsViewModel`)

**Step 1: Add `accountsViewModel` parameter and link payments state to `SubscriptionDetailView`**

Add `accountsViewModel` parameter to `SubscriptionDetailView`:

```swift
struct SubscriptionDetailView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel  // ← ADD THIS
    @Environment(TimeFilterManager.self) private var timeFilterManager
    ...
```

Add state variable after `showingDeleteConfirmation`:

```swift
@State private var showingLinkPayments = false
```

**Step 2: Add "Link Payments" button to toolbar menu**

In the `Menu` inside `.toolbar`, add before the Edit button:

```swift
Button {
    showingLinkPayments = true
} label: {
    Label(String(localized: "subscription.linkPayments.title", defaultValue: "Link Payments"), systemImage: "link.badge.plus")
}
```

**Step 3: Add navigation destination**

Add `.navigationDestination(isPresented: $showingLinkPayments)` after the `.alert(...)` modifier:

```swift
.navigationDestination(isPresented: $showingLinkPayments) {
    SubscriptionLinkPaymentsView(
        subscription: subscription,
        categoriesViewModel: categoriesViewModel,
        accountsViewModel: accountsViewModel
    )
}
```

**Step 4: Update `SubscriptionsListView` to pass `accountsViewModel`**

In `SubscriptionsListView.swift`, add `accountsViewModel` parameter:

```swift
struct SubscriptionsListView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel  // ← ADD THIS
    ...
```

Update the `.navigationDestination(for: RecurringSeries.self)` closure (line 52-61) to pass `accountsViewModel`:

```swift
.navigationDestination(for: RecurringSeries.self) { subscription in
    SubscriptionDetailView(
        transactionStore: transactionStore,
        transactionsViewModel: transactionsViewModel,
        categoriesViewModel: categoriesViewModel,
        accountsViewModel: accountsViewModel,  // ← ADD THIS
        subscription: subscription
    )
    .environment(timeFilterManager)
    .navigationTransition(.zoom(sourceID: subscription.id, in: subscriptionNamespace))
}
```

**Step 5: Fix all call sites of `SubscriptionsListView`**

Search for all `SubscriptionsListView(` usages and add `accountsViewModel:` parameter. The main call site is likely in `ContentView` or a navigation coordinator. Use:

Run: `grep -rn "SubscriptionsListView(" Tenra/ --include="*.swift"` to find all call sites.

Pass `accountsViewModel` (available from `AppCoordinator`) at each call site.

**Step 6: Fix preview code in both files**

Update `SubscriptionDetailView` previews to pass `accountsViewModel: coordinator.accountsViewModel`.

Update `SubscriptionsListView` previews to pass `accountsViewModel: coordinator.accountsViewModel`.

**Step 7: Build to verify no compile errors**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 8: Commit**

```
feat: wire subscription link payments into detail view
```

---

### Task 6: Add localization strings

**Files:**
- Modify: `Tenra/en.lproj/Localizable.strings`
- Modify: `Tenra/ru.lproj/Localizable.strings`

**Step 1: Add English strings**

Add after the existing `subscription.*` or `loan.linkPayments.*` section:

```
// Subscription Link Payments
"subscription.linkPayments.title" = "Link Payments";
"subscription.linkPayments.search" = "Search by description or amount";
"subscription.linkPayments.selectedWithAmount" = "%d selected · %@";
"subscription.linkPayments.link" = "Link %d Payments";
"subscription.linkPayments.empty" = "No matching transactions";
"subscription.filterAll" = "All";
```

**Step 2: Add Russian strings**

```
// Привязка платежей к подписке
"subscription.linkPayments.title" = "Привязать платежи";
"subscription.linkPayments.search" = "Поиск по описанию или сумме";
"subscription.linkPayments.selectedWithAmount" = "%d выбрано · %@";
"subscription.linkPayments.link" = "Привязать %d платежей";
"subscription.linkPayments.empty" = "Нет подходящих транзакций";
"subscription.filterAll" = "Все";
```

**Step 3: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: No errors

**Step 4: Commit**

```
feat: add localization for subscription link payments
```

---

### Task 7: Run full test suite and verify

**Step 1: Run all tests**

Run: `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | tail -30`
Expected: All tests pass including new `SubscriptionTransactionMatcherTests`

**Step 2: Run build**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: Clean build

**Step 3: Final commit if any fixes needed**

```
fix: address test/build issues from subscription link payments
```
