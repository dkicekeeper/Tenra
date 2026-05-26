//
//  TransactionCategoryPickerCoordinator.swift
//  Tenra
//
//  Coordinator for TransactionCategoryPickerView.
//  Manages the reactive category list and navigation state (category → AddTransactionModal).
//

import Foundation
import SwiftUI
import Observation

/// Stable identity for category selection — uses category name, not UUID.
/// Hashable so it can drive `.navigationDestination(item:)` in addition to `.sheet(item:)`.
struct CategorySelection: Identifiable, Hashable {
    var id: String { "\(category)_\(type.rawValue)" }
    let category: String
    let type: TransactionType
}

@Observable
@MainActor
final class TransactionCategoryPickerCoordinator {

    // MARK: - Dependencies

    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transactionStore: TransactionStore
    private var timeFilterManager: TimeFilterManager
    @ObservationIgnored private let categoryMapper: CategoryDisplayDataMapperProtocol

    // MARK: - Observable State

    /// Display snapshot consumed by the picker view. Recomputed by `recompute()`
    /// in response to filter/tx/category mutations — never rebuilt inside `body`.
    /// First render shows categories with `total = 0` from the synchronous init seed
    /// below; the first `recompute()` populates totals from a Task.detached run.
    ///
    /// Why stored instead of computed: the previous `var categories` computed
    /// property invoked `categoryExpenses(...)` on every body re-eval, which walked
    /// 19k transactions with `DateFormatter.date(from:)` on MainActor and stalled
    /// the home-screen reveal animation.
    private(set) var categories: [CategoryDisplayData] = []

    var activeSelection: CategorySelection?
    var showingAddCategory = false

    // MARK: - Initialization

    init(
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore,
        timeFilterManager: TimeFilterManager,
        categoryMapper: CategoryDisplayDataMapperProtocol? = nil
    ) {
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.transactionStore = transactionStore
        self.timeFilterManager = timeFilterManager
        self.categoryMapper = categoryMapper ?? CategoryDisplayDataMapper()

        // Synchronous first-pass seed: produce the category grid with `total = 0`
        // immediately so the first frame is never empty. The view's `.task(id:)`
        // then fires `recompute()` to fill in real amounts on a background thread.
        // Mapping ~30 categories takes microseconds on MainActor.
        self.categories = self.categoryMapper.mapCategories(
            customCategories: categoriesViewModel.customCategories,
            categoryExpenses: [:],
            type: .expense,
            baseCurrency: transactionsViewModel.appSettings.baseCurrency,
            currentFilter: timeFilterManager.currentFilter
        )
    }

    // MARK: - Snapshot Refresh

    /// Recompute `categories` for the current filter + transaction snapshot.
    ///
    /// The expensive O(N_tx) category-expense walk (with date parsing + FX conversion)
    /// runs in `Task.detached(priority: .userInitiated)`. Only the small
    /// O(N_categories) mapper call returns to MainActor.
    ///
    /// Call from a view-level `.task(id:)` keyed on filter / mutation-version /
    /// rates-version / baseCurrency; SwiftUI auto-cancels in-flight runs when the
    /// key changes and starts a fresh one — no manual task tracking needed.
    func recompute() async {
        // Capture every MainActor-bound input as a Sendable snapshot.
        let txs = transactionStore.transactions
        let filter = timeFilterManager.currentFilter
        let range = filter.dateRange()
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let customCategories = categoriesViewModel.customCategories
        let validNames = Set(customCategories.map { $0.name })

        let expenses = await Task.detached(priority: .userInitiated) {
            Self.computeCategoryExpenses(
                transactions: txs,
                filterStart: range.start,
                filterEnd: range.end,
                baseCurrency: baseCurrency,
                validCategoryNames: validNames
            )
        }.value

        guard !Task.isCancelled else { return }

        let mapped = categoryMapper.mapCategories(
            customCategories: customCategories,
            categoryExpenses: expenses,
            type: .expense,
            baseCurrency: baseCurrency,
            currentFilter: filter
        )
        categories = mapped
    }

    /// Pure mirror of `TransactionQueryService.calculateCategoryExpensesFromTransactions`.
    /// Safe to call from any actor — every dependency (`DateFormatter`,
    /// `CurrencyConverter.convertSync`, value types) is documented as actor-safe.
    private nonisolated static func computeCategoryExpenses(
        transactions: [Transaction],
        filterStart: Date,
        filterEnd: Date,
        baseCurrency: String,
        validCategoryNames: Set<String>
    ) -> [String: CategoryExpense] {
        // Thread-local formatter — DateFormatter is documented thread-safe since iOS 7
        // but using a local instance avoids contention with the shared singleton.
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        let now = Date()
        var result: [String: CategoryExpense] = [:]
        result.reserveCapacity(validCategoryNames.count)

        for tx in transactions where tx.type == .expense {
            guard let date = dateFormatter.date(from: tx.date),
                  date >= filterStart && date < filterEnd,
                  date <= now else { continue }

            let categoryName = tx.category.isEmpty
                ? "Uncategorized"  // matches String(localized: "category.uncategorized") fallback
                : tx.category

            // Filter out tx tagged to deleted custom categories. Empty names
            // (the Uncategorized bucket) always pass.
            if !validCategoryNames.contains(categoryName) && !tx.category.isEmpty {
                continue
            }

            let amount: Double
            if tx.currency == baseCurrency {
                amount = tx.amount
            } else if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) {
                amount = fx
            } else {
                amount = tx.convertedAmount ?? tx.amount
            }

            if var existing = result[categoryName] {
                existing.total += amount
                if let sub = tx.subcategory {
                    existing.subcategories[sub, default: 0] += amount
                }
                result[categoryName] = existing
            } else {
                var subs: [String: Double] = [:]
                if let sub = tx.subcategory { subs[sub] = amount }
                result[categoryName] = CategoryExpense(total: amount, subcategories: subs)
            }
        }
        return result
    }

    // MARK: - Public Methods

    func handleCategorySelected(_ category: String, type: TransactionType) {
        activeSelection = CategorySelection(category: category, type: type)
        HapticManager.light()
    }

    func handleAddCategory() {
        showingAddCategory = true
        HapticManager.light()
    }

    func handleCategoryAdded(_ category: CustomCategory) {
        HapticManager.success()
        categoriesViewModel.addCategory(category)
        transactionsViewModel.invalidateCaches()
        showingAddCategory = false
    }

    func dismissModal() {
        activeSelection = nil
    }

    // MARK: - Convenience Computed Properties

    var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    /// Accounts surfaced to the user-driven add-transaction flow.
    /// Loan/deposit accounts are technical containers and never appear here —
    /// they only show up via their dedicated detail screens (LoanDetailView, etc.).
    var accounts: [Account] {
        accountsViewModel.regularAccounts
    }
}
