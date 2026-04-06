# Loan Link Payments — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to link existing expense transactions to a loan, converting them to loanPayment type and recalculating loan state.

**Architecture:** New `LoanTransactionMatcher` service handles auto-matching logic. New `LoanLinkPaymentsView` presents candidates with checkboxes. `LoansViewModel` gets a `linkTransactions()` method that converts transactions via `TransactionStore.update()` and recalculates LoanInfo.

**Tech Stack:** SwiftUI, CoreData, @Observable, existing TransactionStore/LoanPaymentService

---

### Task 1: LoanTransactionMatcher Service

**Files:**
- Create: `Tenra/Services/Loans/LoanTransactionMatcher.swift`
- Create: `TenraTests/Services/LoanTransactionMatcherTests.swift`

**Step 1: Write tests**

```swift
import Testing
@testable import Tenra

@MainActor
struct LoanTransactionMatcherTests {

    // MARK: - Helpers

    private func makeLoanAccount(
        monthlyPayment: Decimal = 340_000,
        startDate: String = "2021-06-15",
        currency: String = "KZT"
    ) -> Account {
        var account = Account(
            id: "loan-1",
            name: "Car Loan",
            currency: currency,
            balance: 10_000_000,
            icon: .sfSymbol("car.fill"),
            sortOrder: 0
        )
        account.loanInfo = LoanInfo(
            bankName: "Bank",
            loanType: .annuity,
            originalPrincipal: 20_000_000,
            remainingPrincipal: 10_000_000,
            interestRateAnnual: 12,
            termMonths: 60,
            startDate: startDate,
            monthlyPayment: monthlyPayment,
            paymentDay: 15,
            paymentsMade: 0,
            lastReconciliationDate: startDate
        )
        return account
    }

    private func makeTransaction(
        id: String = UUID().uuidString,
        date: String,
        amount: Double,
        type: TransactionType = .expense,
        category: String = "Auto",
        accountId: String = "acc-1",
        currency: String = "KZT"
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: "Payment",
            amount: amount,
            currency: currency,
            type: type,
            category: category,
            accountId: accountId
        )
    }

    // MARK: - findCandidates

    @Test func findCandidates_matchesExpensesWithinTolerance() {
        let loan = makeLoanAccount(monthlyPayment: 340_000, startDate: "2021-06-15")
        let transactions = [
            makeTransaction(date: "2021-07-15", amount: 340_000),   // exact match
            makeTransaction(date: "2021-08-15", amount: 330_000),   // within 10%
            makeTransaction(date: "2021-09-15", amount: 200_000),   // too low
            makeTransaction(date: "2021-10-15", amount: 500_000),   // too high
        ]

        let candidates = LoanTransactionMatcher.findCandidates(
            for: loan,
            in: transactions
        )

        #expect(candidates.count == 2)
        #expect(candidates[0].amount == 340_000)
        #expect(candidates[1].amount == 330_000)
    }

    @Test func findCandidates_excludesNonExpenses() {
        let loan = makeLoanAccount()
        let transactions = [
            makeTransaction(date: "2021-07-15", amount: 340_000, type: .income),
            makeTransaction(date: "2021-07-16", amount: 340_000, type: .loanPayment),
            makeTransaction(date: "2021-07-17", amount: 340_000, type: .expense),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].type == .expense)
    }

    @Test func findCandidates_excludesTransactionsOutsideLoanPeriod() {
        let loan = makeLoanAccount(startDate: "2021-06-15")
        let transactions = [
            makeTransaction(date: "2021-05-15", amount: 340_000), // before start
            makeTransaction(date: "2021-07-15", amount: 340_000), // valid
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].date == "2021-07-15")
    }

    @Test func findCandidates_matchesDifferentCurrencyLoan() {
        let loan = makeLoanAccount(monthlyPayment: 340_000, currency: "KZT")
        let transactions = [
            makeTransaction(date: "2021-07-15", amount: 340_000, currency: "KZT"),
            makeTransaction(date: "2021-07-16", amount: 340_000, currency: "USD"),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates.count == 1)
        #expect(candidates[0].currency == "KZT")
    }

    @Test func findCandidates_sortsByDate() {
        let loan = makeLoanAccount()
        let transactions = [
            makeTransaction(date: "2021-09-15", amount: 340_000),
            makeTransaction(date: "2021-07-15", amount: 340_000),
            makeTransaction(date: "2021-08-15", amount: 340_000),
        ]

        let candidates = LoanTransactionMatcher.findCandidates(for: loan, in: transactions)

        #expect(candidates[0].date == "2021-07-15")
        #expect(candidates[1].date == "2021-08-15")
        #expect(candidates[2].date == "2021-09-15")
    }
}
```

**Step 2: Run tests, verify they fail**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/LoanTransactionMatcherTests 2>&1 | grep -E "error:|Test.*failed|BUILD"
```

Expected: compilation error — `LoanTransactionMatcher` not defined.

**Step 3: Implement LoanTransactionMatcher**

```swift
// Tenra/Services/Loans/LoanTransactionMatcher.swift

import Foundation

/// Finds existing transactions that match a loan's payment pattern.
nonisolated enum LoanTransactionMatcher {

    /// Default tolerance: ±10% of monthly payment.
    static let defaultTolerance: Double = 0.10

    /// Find expense transactions that likely represent payments for the given loan.
    /// - Parameters:
    ///   - loan: The loan account (must have loanInfo)
    ///   - transactions: All transactions to search through
    ///   - tolerance: Fraction of monthlyPayment for amount matching (default 0.10 = ±10%)
    /// - Returns: Matching transactions sorted by date ascending
    static func findCandidates(
        for loan: Account,
        in transactions: [Transaction],
        tolerance: Double = defaultTolerance
    ) -> [Transaction] {
        guard let loanInfo = loan.loanInfo else { return [] }

        let monthlyPayment = NSDecimalNumber(decimal: loanInfo.monthlyPayment).doubleValue
        let lowerBound = monthlyPayment * (1.0 - tolerance)
        let upperBound = monthlyPayment * (1.0 + tolerance)
        let startDate = loanInfo.startDate
        let loanCurrency = loan.currency

        return transactions
            .filter { tx in
                // Only expenses
                guard tx.type == .expense else { return false }
                // Currency must match
                guard tx.currency == loanCurrency else { return false }
                // Amount within tolerance
                guard tx.amount >= lowerBound && tx.amount <= upperBound else { return false }
                // Date after loan start
                guard tx.date >= startDate else { return false }
                return true
            }
            .sorted { $0.date < $1.date }
    }
}
```

**Step 4: Run tests, verify they pass**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/LoanTransactionMatcherTests 2>&1 | grep -E "error:|passed|failed|BUILD"
```

Expected: all 5 tests pass.

**Step 5: Commit**

```bash
git add Tenra/Services/Loans/LoanTransactionMatcher.swift TenraTests/Services/LoanTransactionMatcherTests.swift
git commit -m "feat(loans): add LoanTransactionMatcher for auto-matching payments"
```

---

### Task 2: LoansViewModel.linkTransactions() method

**Files:**
- Modify: `Tenra/ViewModels/LoansViewModel.swift` (add method after line ~212)

**Step 1: Write test**

Add to `TenraTests/Services/LoanTransactionMatcherTests.swift` or a separate test file. Since `linkTransactions` mutates TransactionStore (which requires full DI), we test the **recalculation logic** as a pure function on `LoanPaymentService` instead.

Create: `TenraTests/Services/LoanLinkRecalculationTests.swift`

```swift
import Testing
@testable import Tenra

@MainActor
struct LoanLinkRecalculationTests {

    @Test func recalculateLoanState_annuity_updatesAllFields() {
        var loanInfo = LoanInfo(
            bankName: "Bank",
            loanType: .annuity,
            originalPrincipal: 20_400_000,
            remainingPrincipal: 20_400_000,
            interestRateAnnual: 12,
            termMonths: 60,
            startDate: "2021-06-15",
            monthlyPayment: 340_000,
            paymentDay: 15,
            paymentsMade: 0,
            lastReconciliationDate: "2021-06-15"
        )

        let paymentDates = ["2021-07-15", "2021-08-15", "2021-09-15"]

        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &loanInfo,
            linkedPaymentCount: paymentDates.count,
            linkedPaymentDates: paymentDates
        )

        #expect(loanInfo.paymentsMade == 3)
        #expect(loanInfo.lastPaymentDate == "2021-09-15")
        #expect(loanInfo.remainingPrincipal < 20_400_000)
        #expect(loanInfo.totalInterestPaid > 0)
    }

    @Test func recalculateLoanState_installment_simpleDivision() {
        var loanInfo = LoanInfo(
            bankName: "Bank",
            loanType: .installment,
            originalPrincipal: 20_400_000,
            remainingPrincipal: 20_400_000,
            interestRateAnnual: 0,
            termMonths: 60,
            startDate: "2021-06-15",
            monthlyPayment: 340_000,
            paymentDay: 15,
            paymentsMade: 0,
            lastReconciliationDate: "2021-06-15"
        )

        let paymentDates = ["2021-07-15", "2021-08-15", "2021-09-15"]

        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &loanInfo,
            linkedPaymentCount: 3,
            linkedPaymentDates: paymentDates
        )

        #expect(loanInfo.paymentsMade == 3)
        // 20_400_000 - 3 * 340_000 = 19_380_000
        #expect(loanInfo.remainingPrincipal == 19_380_000)
        #expect(loanInfo.totalInterestPaid == 0)
    }
}
```

**Step 2: Run tests, verify they fail**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/LoanLinkRecalculationTests 2>&1 | grep -E "error:|passed|failed|BUILD"
```

Expected: compilation error — `recalculateAfterLinking` not defined.

**Step 3: Add recalculateAfterLinking to LoanPaymentService**

Add to `Tenra/Services/Loans/LoanPaymentService.swift` (after `reconcileLoanPayments`, ~line 347):

```swift
    // MARK: - Link Existing Payments

    /// Recalculates loan state after linking existing transactions.
    /// Walks payments chronologically, applying amortization to compute remaining principal and interest.
    /// - Parameters:
    ///   - loanInfo: The loan info to update (mutated in place)
    ///   - linkedPaymentCount: Number of linked payment transactions
    ///   - linkedPaymentDates: Sorted dates of linked payments (YYYY-MM-DD)
    static func recalculateAfterLinking(
        loanInfo: inout LoanInfo,
        linkedPaymentCount: Int,
        linkedPaymentDates: [String]
    ) {
        loanInfo.paymentsMade = linkedPaymentCount
        loanInfo.lastPaymentDate = linkedPaymentDates.last
        loanInfo.lastReconciliationDate = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())
        }()

        if loanInfo.loanType == .installment {
            // Simple: principal minus payments * monthly amount
            let totalPaid = loanInfo.monthlyPayment * Decimal(linkedPaymentCount)
            loanInfo.remainingPrincipal = loanInfo.originalPrincipal - totalPaid
            loanInfo.totalInterestPaid = 0
            return
        }

        // Annuity: walk payments chronologically, compute interest/principal split
        var remaining = loanInfo.originalPrincipal
        var totalInterest: Decimal = 0

        for _ in 0..<linkedPaymentCount {
            let breakdown = paymentBreakdown(
                remainingPrincipal: remaining,
                annualRate: loanInfo.interestRateAnnual,
                monthlyPayment: loanInfo.monthlyPayment
            )
            remaining -= breakdown.principal
            totalInterest += breakdown.interest
        }

        loanInfo.remainingPrincipal = max(remaining, 0)
        loanInfo.totalInterestPaid = totalInterest
    }
```

**Step 4: Run tests, verify they pass**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests/LoanLinkRecalculationTests 2>&1 | grep -E "error:|passed|failed|BUILD"
```

**Step 5: Add linkTransactions to LoansViewModel**

Add to `Tenra/ViewModels/LoansViewModel.swift` after `reconcileLoanPayments` (~line 171):

```swift
    // MARK: - Link Existing Transactions

    /// Converts existing transactions to loan payments and recalculates loan state.
    /// - Parameters:
    ///   - loanId: The loan account ID
    ///   - transactions: Transactions to convert (will be updated to .loanPayment type)
    ///   - transactionStore: Store to update transactions through
    func linkTransactions(
        toLoan loanId: String,
        transactions: [Transaction],
        transactionStore: TransactionStore
    ) async throws {
        guard var loan = getLoan(by: loanId),
              loan.loanInfo != nil else { return }

        let sortedTransactions = transactions.sorted { $0.date < $1.date }

        // Convert each transaction to loanPayment
        for tx in sortedTransactions {
            var updated = tx
            updated.type = .loanPayment
            updated.targetAccountId = tx.accountId // source account
            updated.targetAccountName = tx.accountName
            updated.accountId = loanId
            updated.accountName = loan.name
            updated.category = TransactionType.loanPaymentCategoryName
            try await transactionStore.update(updated)
        }

        // Recalculate loan state
        let dates = sortedTransactions.map(\.date)
        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &loan.loanInfo!,
            linkedPaymentCount: sortedTransactions.count,
            linkedPaymentDates: dates
        )

        // Persist updated loan
        updateLoan(loan)
    }
```

**Step 6: Commit**

```bash
git add Tenra/Services/Loans/LoanPaymentService.swift \
       Tenra/ViewModels/LoansViewModel.swift \
       TenraTests/Services/LoanLinkRecalculationTests.swift
git commit -m "feat(loans): add linkTransactions and recalculateAfterLinking"
```

---

### Task 3: LoanLinkPaymentsView

**Files:**
- Create: `Tenra/Views/Loans/LoanLinkPaymentsView.swift`

**Step 1: Create the view**

Reference existing patterns from `LoanPaymentView.swift` and `LoanEarlyRepaymentView.swift` for sheet structure.

```swift
// Tenra/Views/Loans/LoanLinkPaymentsView.swift

import SwiftUI

struct LoanLinkPaymentsView: View {
    let loan: Account
    let transactionStore: TransactionStore
    let loansViewModel: LoansViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Transaction] = []
    @State private var selectedIds: Set<String> = []
    @State private var searchText = ""
    @State private var isLinking = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var filterAccountId: String?

    private var filteredCandidates: [Transaction] {
        var result = candidates
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.description.lowercased().contains(query)
                || String(format: "%.0f", $0.amount).contains(query)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary header
                summarySection

                // Search bar
                searchBar

                // Account filter
                if uniqueAccountIds.count > 1 {
                    accountFilter
                }

                // Transaction list
                transactionList

                // Bottom action bar
                actionBar
            }
            .navigationTitle(String(localized: "loan.linkPayments.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                loadCandidates()
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(String(localized: "loan.linkPayments.selected \(selectedIds.count)"))
                .font(AppTypography.headline)
            if !selectedIds.isEmpty {
                Text(AmountFormatter.shared.format(selectedTotal) + " " + loan.currency)
                    .font(AppTypography.title2)
                    .fontWeight(.bold)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "loan.linkPayments.search"), text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(AppSpacing.sm)
        .padding(.horizontal, AppSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md))
        .padding(.horizontal, AppSpacing.lg)
    }

    private var accountFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                UniversalFilterButton(
                    title: String(localized: "common.all"),
                    isSelected: filterAccountId == nil,
                    mode: .button { filterAccountId = nil }
                )
                ForEach(uniqueAccountIds, id: \.self) { accountId in
                    let name = transactionStore.accounts.first { $0.id == accountId }?.name ?? accountId
                    UniversalFilterButton(
                        title: name,
                        isSelected: filterAccountId == accountId,
                        mode: .button { filterAccountId = accountId }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private var transactionList: some View {
        List {
            ForEach(filteredCandidates, id: \.id) { tx in
                transactionRow(tx)
            }
        }
        .listStyle(.plain)
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        let isSelected = selectedIds.contains(tx.id)
        return Button {
            if isSelected {
                selectedIds.remove(tx.id)
            } else {
                selectedIds.insert(tx.id)
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.description)
                        .font(AppTypography.body)
                    HStack(spacing: AppSpacing.xs) {
                        Text(tx.date)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                        if let name = tx.accountName {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(name)
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(AmountFormatter.shared.format(tx.amount) + " " + tx.currency)
                    .font(AppTypography.body)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        VStack(spacing: AppSpacing.sm) {
            Divider()
            Button {
                Task { await linkSelected() }
            } label: {
                Group {
                    if isLinking {
                        ProgressView()
                    } else {
                        Text(String(localized: "loan.linkPayments.link \(selectedIds.count)"))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedIds.isEmpty || isLinking)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    // MARK: - Actions

    private func loadCandidates() {
        let allTransactions = transactionStore.transactions
        candidates = LoanTransactionMatcher.findCandidates(
            for: loan,
            in: allTransactions
        )
        // Pre-select all candidates
        selectedIds = Set(candidates.map(\.id))
    }

    private func linkSelected() async {
        isLinking = true
        defer { isLinking = false }

        do {
            try await loansViewModel.linkTransactions(
                toLoan: loan.id,
                transactions: selectedTransactions,
                transactionStore: transactionStore
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
```

**Step 2: Build to verify compilation**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

**Step 3: Commit**

```bash
git add Tenra/Views/Loans/LoanLinkPaymentsView.swift
git commit -m "feat(loans): add LoanLinkPaymentsView for transaction linking UI"
```

---

### Task 4: Wire up in LoanDetailView + Localization

**Files:**
- Modify: `Tenra/Views/Loans/LoanDetailView.swift` (~lines 86-131, menu section)
- Modify: `Tenra/en.lproj/Localizable.strings` (add new keys)

**Step 1: Add menu item to LoanDetailView**

In `LoanDetailView.swift`, find the menu section (~line 96-130). Add a "Link Payments" button after "Early Repayment" and before the Divider:

```swift
// After the "Early Repayment" button (~line 117) and before the Divider (~line 119):
Button {
    showLinkPayments = true
} label: {
    Label(String(localized: "loan.linkPayments"), systemImage: "link")
}
```

Add the `@State` property near the other sheet states:

```swift
@State private var showLinkPayments = false
```

Add the `.sheet` modifier (near other sheets):

```swift
.sheet(isPresented: $showLinkPayments) {
    if let loan = loansViewModel.getLoan(by: accountId) {
        LoanLinkPaymentsView(
            loan: loan,
            transactionStore: transactionStore,
            loansViewModel: loansViewModel
        )
    }
}
```

**Step 2: Add localization keys**

Add to `Tenra/en.lproj/Localizable.strings` in the loan section:

```
"loan.linkPayments" = "Link Payments";
"loan.linkPayments.title" = "Link Payments";
"loan.linkPayments.selected %lld" = "%lld selected";
"loan.linkPayments.search" = "Search by description or amount";
"loan.linkPayments.link %lld" = "Link %lld Payments";
```

Check if the project uses `Localizable.xcstrings` (JSON) instead and add keys in the appropriate format.

**Step 3: Build to verify**

```bash
xcodebuild build -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -20
```

**Step 4: Commit**

```bash
git add Tenra/Views/Loans/LoanDetailView.swift Tenra/en.lproj/Localizable.strings
git commit -m "feat(loans): wire LoanLinkPaymentsView into LoanDetailView menu"
```

---

### Task 5: Add LoanLinkPaymentsView to Xcode project + final integration

**Step 1: Verify all new files are in Xcode project**

Since this is an Xcode project (not SPM), new `.swift` files may need to be added to the `project.pbxproj`. If using Xcode's automatic file discovery, this may be handled automatically. Verify:

```bash
grep -c "LoanTransactionMatcher" Tenra.xcodeproj/project.pbxproj
grep -c "LoanLinkPaymentsView" Tenra.xcodeproj/project.pbxproj
grep -c "LoanLinkRecalculationTests" Tenra.xcodeproj/project.pbxproj
```

If counts are 0, the files need to be added via Xcode or by editing `project.pbxproj`.

**Step 2: Run full test suite**

```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests 2>&1 | grep -E "passed|failed|error:" | tail -20
```

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "feat(loans): link existing payments to loan — complete feature"
```

---

## Summary of Changes

| # | Task | New Files | Modified Files |
|---|------|-----------|---------------|
| 1 | LoanTransactionMatcher | `Services/Loans/LoanTransactionMatcher.swift`, `Tests/LoanTransactionMatcherTests.swift` | — |
| 2 | Recalculation + ViewModel | `Tests/LoanLinkRecalculationTests.swift` | `LoanPaymentService.swift`, `LoansViewModel.swift` |
| 3 | LoanLinkPaymentsView | `Views/Loans/LoanLinkPaymentsView.swift` | — |
| 4 | Wiring + l10n | — | `LoanDetailView.swift`, `Localizable.strings` |
| 5 | Integration test | — | Possibly `project.pbxproj` |
