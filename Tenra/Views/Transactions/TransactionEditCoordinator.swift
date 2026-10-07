//
//  TransactionEditCoordinator.swift
//  Tenra
//
//  Phase 16 (2026-02-17): Coordinator for TransactionEditView.
//  Consolidates 12 @State variables into a single @Observable coordinator,
//  consistent with TransactionAddCoordinator architecture.
//

import Foundation
import SwiftUI

// MARK: - Edit Form Data

/// Form state for editing an existing transaction.
struct EditTransactionFormData {
    var amountText: String
    var descriptionText: String
    var selectedCategory: String
    var selectedSubcategoryIds: Set<String>
    var selectedAccountId: String?
    var selectedTargetAccountId: String?
    var selectedDate: Date
    var selectedCurrency: String
    var recurring: RecurringOption

    // UI-only state
    var showingSubcategorySearch: Bool = false
    var showingSubcategoryReorder: Bool = false
    var subcategorySearchText: String = ""
    var showingRecurringDisableDialog: Bool = false
}

// MARK: - Bulk Category Proposal

/// Offered after a save that changed the category: the other saved
/// transactions of the same merchant that still carry the old category.
struct BulkCategoryProposal: Identifiable, Equatable {
    let id = UUID()
    /// The edited description, trimmed and capped for the alert text.
    let merchant: String
    let previousCategory: String
    let newCategory: String
    let transactionIds: [String]
}

// MARK: - TransactionEditCoordinator

@Observable
@MainActor
final class TransactionEditCoordinator {

    // MARK: - Dependencies

    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored private let transactionStore: TransactionStore

    // MARK: - Original Transaction

    let transaction: Transaction

    // MARK: - State

    var formData: EditTransactionFormData

    /// Error message to display in MessageBanner, nil when no error.
    var errorMessage: String?

    /// Non-nil while the "apply to similar transactions" alert is up.
    var bulkCategoryProposal: BulkCategoryProposal?

    /// The save's `onSuccess` (dismisses the sheet), held until the user answers the alert.
    @ObservationIgnored private var pendingSuccess: (() -> Void)?

    // MARK: - Computed: Available Categories

    var availableCategories: [String] {
        var categories: Set<String> = []
        // Loan/deposit transaction types pull from the .expense (or .income for
        // interest accrual) catalog so users can tag payments alongside regular
        // spend — matches the subscription edit flow.
        let pickerType = transaction.type.categoryPickerSourceType

        for customCategory in categoriesViewModel.customCategories where customCategory.type == pickerType {
            categories.insert(customCategory.name)
        }

        // Names that only exist on other transactions (deleted categories) are NOT offered:
        // picking one failed `TransactionStore.validate` with categoryNotFound, and collecting
        // them was a full pass over every transaction on each body evaluation (every
        // calculator key press). The edited transaction's own category stays selectable.
        if !transaction.category.isEmpty {
            categories.insert(transaction.category)
        }

        return Array(categories).sortedByCustomOrder(
            customCategories: categoriesViewModel.customCategories,
            type: pickerType
        )
    }

    // MARK: - Computed: Category ID

    var categoryId: String? {
        // O(1) via index; legacy linear scan kept as fallback for preview/test contexts.
        if let store = categoriesViewModel.transactionStore,
           let id = store.categoryIdByName[formData.selectedCategory.lowercased()] {
            return id
        }
        return categoriesViewModel.customCategories.first { $0.name == formData.selectedCategory }?.id
    }

    // MARK: - Computed: Available Subcategories

    var availableSubcategories: [Subcategory] {
        guard let catId = categoryId else { return [] }
        return categoriesViewModel.getSubcategoriesForCategory(catId)
    }

    // MARK: - Computed: Can Save

    var canSave: Bool {
        // Internal transfers carry no category. System types (loan/deposit) accept
        // either the technical default ("Loan Payment", etc.) or any expense/income
        // category the user picked.
        switch transaction.type {
        case .internalTransfer:
            return true
        case .loanPayment, .loanEarlyRepayment,
             .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
            return true
        default:
            return !formData.selectedCategory.isEmpty &&
                   availableCategories.contains(formData.selectedCategory)
        }
    }

    // MARK: - Initialization

    init(
        transaction: Transaction,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore
    ) {
        self.transaction = transaction
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.transactionStore = transactionStore

        // Initialize form data from the transaction
        let parsedDate = DateFormatters.dateFormatter.date(from: transaction.date) ?? Date()

        // Determine initial recurring option
        var initialRecurring: RecurringOption = .never
        if let seriesId = transaction.recurringSeriesId,
           let series = transactionsViewModel.recurringSeries.first(where: { $0.id == seriesId }) {
            initialRecurring = .frequency(series.frequency)
        }

        // Load linked subcategories
        let linkedSubcategories = categoriesViewModel.getSubcategoriesForTransaction(transaction.id)
        let linkedSubcategoryIds = Set(linkedSubcategories.map { $0.id })

        self.formData = EditTransactionFormData(
            amountText: AmountInputFormatting.bindingString(for: transaction.amount),
            descriptionText: transaction.description,
            selectedCategory: transaction.category,
            selectedSubcategoryIds: linkedSubcategoryIds,
            selectedAccountId: transaction.accountId,
            selectedTargetAccountId: transaction.targetAccountId,
            selectedDate: parsedDate,
            selectedCurrency: transaction.currency,
            recurring: initialRecurring
        )
    }

    // MARK: - Currency Sync

    /// Sync currency when account selection changes.
    func updateCurrencyForSelectedAccount() {
        guard let accountId = formData.selectedAccountId,
              let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) else { return }
        formData.selectedCurrency = account.currency
    }

    // MARK: - Recurring Handling

    /// Stop the current recurring series when recurring is disabled.
    func handleRecurringDisabled() {
        if let seriesId = transaction.recurringSeriesId {
            transactionsViewModel.stopRecurringSeries(seriesId)
        }
    }

    // MARK: - Save

    /// Validates and saves the edited transaction.
    /// Returns true on success, false on validation failure.
    func save(onSuccess: @escaping () -> Void) {
        guard validate() else { return }

        Task {
            await performSave(onSuccess: onSuccess)
        }
    }

    // MARK: - Private: Validation

    private func validate() -> Bool {
        // Validate amount
        guard !formData.amountText.isEmpty,
              let amount = Double(formData.amountText.replacingOccurrences(of: ",", with: ".")),
              amount > 0 else {
            errorMessage = String(localized: "transactionForm.enterPositiveAmount")
            HapticManager.warning()
            return false
        }

        // Validate category — required only for plain income/expense.
        // Transfer / loan / deposit types carry a fixed technical category (or any
        // category the user picked) and skip strict membership validation.
        switch transaction.type {
        case .income, .expense:
            guard !formData.selectedCategory.isEmpty,
                  availableCategories.contains(formData.selectedCategory) else {
                errorMessage = String(localized: "transactionForm.selectCategory")
                HapticManager.warning()
                return false
            }
        default:
            break
        }

        // Validate transfer: no self-transfer
        if transaction.type == .internalTransfer {
            guard let sourceId = formData.selectedAccountId,
                  let targetId = formData.selectedTargetAccountId,
                  sourceId != targetId else {
                errorMessage = String(localized: "transactionForm.cannotTransferToSame")
                HapticManager.warning()
                return false
            }

            let accounts = accountsViewModel.accounts
            guard accounts.contains(where: { $0.id == sourceId }),
                  accounts.contains(where: { $0.id == targetId }) else {
                errorMessage = String(localized: "transactionForm.accountNotFound")
                HapticManager.error()
                return false
            }
        }

        errorMessage = nil
        return true
    }

    // MARK: - Private: Async Save

    private func performSave(onSuccess: @escaping () -> Void) async {
        guard let amount = Double(formData.amountText.replacingOccurrences(of: ",", with: ".")) else { return }

        // Currency conversion first: a missing rate refuses the save before anything
        // (a new recurring series below) is written.
        guard let conversion = await conversionFields(amount: amount) else {
            errorMessage = String(localized: "currency.error.conversionFailed")
            HapticManager.error()
            return
        }

        let dateString = DateFormatters.dateFormatter.string(from: formData.selectedDate)

        // Handle recurring series
        var finalRecurringSeriesId: String?
        do {
            finalRecurringSeriesId = try await handleRecurringSeries(
                amount: amount,
                dateString: dateString
            )
        } catch {
            // Nothing was saved: the series could not be created.
            errorMessage = error.localizedDescription
            HapticManager.error()
            return
        }
        // Read the link back from the store: a one-off made recurring was just linked
        // there as the series' first occurrence.
        let storedOccurrenceId = transactionStore.transactionById[transaction.id]?.recurringOccurrenceId
        var finalRecurringOccurrenceId: String? = storedOccurrenceId ?? transaction.recurringOccurrenceId

        // Only an explicit "Never" chosen by the user detaches the transaction from its
        // series. For types whose recurring control is hidden (`allowsRecurring == false`
        // — deposit interest accruals, deposit/loan operations) `formData.recurring` is
        // `.never` by default, and treating that as intent silently dropped the link and
        // made `update()` reject the whole edit with "cannot remove recurring series".
        var detachesFromSeries = false
        if case .never = formData.recurring, transaction.type.allowsRecurring {
            detachesFromSeries = transaction.recurringSeriesId != nil
            finalRecurringSeriesId = nil
            finalRecurringOccurrenceId = nil
        } else if finalRecurringSeriesId == nil {
            // Control hidden — carry the existing link over untouched.
            finalRecurringSeriesId = transaction.recurringSeriesId
        }

        // Build updated transaction
        let updatedTransaction = Transaction(
            id: transaction.id,
            date: dateString,
            description: formData.descriptionText,
            amount: amount,
            currency: formData.selectedCurrency,
            convertedAmount: conversion.convertedAmount,
            type: transaction.type,
            category: formData.selectedCategory,
            subcategory: nil,
            accountId: formData.selectedAccountId,
            targetAccountId: formData.selectedTargetAccountId,
            targetCurrency: conversion.targetCurrency,
            targetAmount: conversion.targetAmount,
            recurringSeriesId: finalRecurringSeriesId,
            recurringOccurrenceId: finalRecurringOccurrenceId,
            createdAt: transaction.createdAt
        )

        do {
            try await transactionStore.update(updatedTransaction, allowSeriesDetach: detachesFromSeries)

            let previousSubcategoryIds = Set(
                categoriesViewModel.getSubcategoriesForTransaction(transaction.id).map(\.id)
            )

            // Link subcategories
            categoriesViewModel.linkSubcategoriesToTransaction(
                transactionId: transaction.id,
                subcategoryIds: Array(formData.selectedSubcategoryIds)
            )

            // A category or subcategory fixed here also fixes what the Wallet
            // automation will pick next time for this merchant.
            if transaction.type == .expense,
               updatedTransaction.category != transaction.category
                   || formData.selectedSubcategoryIds != previousSubcategoryIds,
               let newCategoryId = categoriesViewModel.customCategories
                   .first(where: { $0.type == .expense && $0.name == updatedTransaction.category })?.id {
                MerchantCategoryMemory.shared.correct(
                    categoryId: newCategoryId,
                    subcategoryIds: Array(formData.selectedSubcategoryIds),
                    // The original text: that is what the automation sends again.
                    forMerchant: transaction.description
                )
            }

            HapticManager.success()
            if let proposal = await makeBulkCategoryProposal(saved: updatedTransaction) {
                pendingSuccess = onSuccess
                bulkCategoryProposal = proposal
            } else {
                onSuccess()
            }
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
    }

    // MARK: - Bulk Category ("apply to similar")

    /// Other saved transactions of the same merchant that still carry the
    /// category this one had before the edit. Swept off the main actor
    /// (CLAUDE.md Red Flag 9); nil when the category did not change or nothing matches.
    private func makeBulkCategoryProposal(saved: Transaction) async -> BulkCategoryProposal? {
        let previous = transaction.category
        guard saved.type == .expense || saved.type == .income,
              !saved.category.isEmpty,
              saved.category != previous else { return nil }

        let all = transactionStore.transactions
        let links = transactionStore.subcategoryIdsByTransactionId
        let ids = await Task.detached(priority: .userInitiated) {
            CategorySuggestionService.similarTransactionIds(
                to: saved,
                previousCategory: previous,
                in: all,
                subcategoryLinks: links
            )
        }.value
        guard !ids.isEmpty else { return nil }

        let merchant = String(saved.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        return BulkCategoryProposal(
            merchant: merchant,
            previousCategory: previous,
            newCategory: saved.category,
            transactionIds: ids
        )
    }

    func applyBulkCategory(_ proposal: BulkCategoryProposal) async {
        _ = await transactionStore.recategorize(
            ids: proposal.transactionIds,
            from: proposal.previousCategory,
            to: proposal.newCategory
        )
        finishBulkPrompt()
    }

    /// Closes the prompt and runs the held `onSuccess`, which dismisses the edit sheet.
    func finishBulkPrompt() {
        bulkCategoryProposal = nil
        let done = pendingSuccess
        pendingSuccess = nil
        done?()
    }

    // MARK: - Private: Recurring Series

    /// Manages recurring series creation when the user enables recurring on a previously
    /// one-off transaction. Returns the final recurringSeriesId. Throws when the series
    /// cannot be created; nothing is saved then.
    ///
    /// The edited transaction becomes the series' FIRST occurrence
    /// (`createSeries(_:firstOccurrence:)`). Creating the series on its own generated an
    /// occurrence on the same date, so the user got two transactions for that date.
    ///
    /// Editing a transaction that is ALREADY linked to a series must NOT propagate
    /// the edit back to the series — the series carries the canonical subscription
    /// price/currency/cadence and is edited through `SubscriptionEditView`, which has
    /// its own propagation prompt. Previously this method overwrote `series.amount`,
    /// `series.category`, `series.description`, `series.accountId`, `series.frequency`,
    /// and `series.isActive` with the edited transaction's values on every save —
    /// so changing one occurrence's amount silently rewrote the subscription's
    /// canonical amount, and resumed paused series as a side effect.
    private func handleRecurringSeries(amount: Double, dateString: String) async throws -> String? {
        guard case .frequency(let freq) = formData.recurring else {
            return nil
        }

        // Already linked — leave the series untouched. The store copy counts too: a repeated
        // save (double tap, or a retry after a failed update) must not create a second
        // series for a transaction that the first save already linked.
        let linkedSeriesId = transaction.recurringSeriesId ?? transactionStore.transactionById[transaction.id]?.recurringSeriesId
        if let existingSeriesId = linkedSeriesId {
            return existingSeriesId
        }

        // Create new series with this transaction as its first occurrence — await so
        // generated transactions are in the store
        let series = RecurringSeries(
            amount: Decimal(amount),
            currency: formData.selectedCurrency,
            category: formData.selectedCategory,
            subcategory: nil,
            description: formData.descriptionText.isEmpty ? formData.selectedCategory : formData.descriptionText,
            accountId: formData.selectedAccountId,
            targetAccountId: formData.selectedTargetAccountId,
            frequency: freq,
            startDate: dateString
        )
        try await transactionStore.createSeries(series, firstOccurrence: transaction)

        // Link selected subcategories to all generated transactions (backfill + future).
        // This transaction's own links are saved by performSave, which compares them
        // with the previous ones for the merchant memory.
        if !formData.selectedSubcategoryIds.isEmpty {
            let generated = transactionStore.transactions.filter {
                $0.recurringSeriesId == series.id && $0.id != transaction.id
            }
            // One batch: one link-table write and one usage-stats rebuild for all of them.
            let subcategoryIds = Array(formData.selectedSubcategoryIds)
            var links: [String: [String]] = [:]
            for tx in generated { links[tx.id] = subcategoryIds }
            if !links.isEmpty {
                categoriesViewModel.batchLinkSubcategoriesToTransaction(links)
            }
        }
        return series.id
    }

    // MARK: - Private: Currency Conversion

    /// The conversion fields to save (`TransactionConversion`), or nil when a rate the
    /// edit needs is missing: the caller refuses the save rather than move the balance
    /// by the raw foreign amount.
    ///
    /// Saving used to keep only `convertedAmount`, re-priced at today's rate: the
    /// equivalent under the amount (`targetCurrency` / `targetAmount`) vanished on every
    /// edit, a cross-currency transfer credited its target account with the source
    /// amount, and a missing rate saved the raw amount silently. A currency pair the
    /// transaction already holds a conversion for keeps that rate
    /// (`TransactionConversion.storedRate`), so an edit that changes neither amount,
    /// currency nor account leaves the stored conversion exactly as it was.
    private func conversionFields(amount: Double) async -> TransactionConversion? {
        let original = transaction
        let accounts = accountsViewModel.accounts
        let currency = formData.selectedCurrency
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let originalAccountCurrency = accounts.first { $0.id == original.accountId }?.currency
        let accountCurrency = accounts.first { $0.id == formData.selectedAccountId }?.currency
            ?? original.currency
        let targetAccountCurrency = accounts.first { $0.id == formData.selectedTargetAccountId }?.currency
            ?? original.targetCurrency
            ?? accountCurrency
        let isTransfer = original.type == .internalTransfer

        func fields() -> TransactionConversion? {
            let convert = TransactionConversion.keepingRates(
                of: original, accountCurrency: originalAccountCurrency
            )
            if isTransfer {
                return TransactionConversion.transfer(
                    amount: amount,
                    currency: currency,
                    sourceCurrency: accountCurrency,
                    targetCurrency: targetAccountCurrency,
                    convert: convert
                )
            }
            return TransactionConversion.singleAccount(
                amount: amount,
                currency: currency,
                accountCurrency: accountCurrency,
                baseCurrency: baseCurrency,
                convert: convert
            )
        }

        if let cached = fields(),
           !TransactionConversion.lacksEquivalent(cached, currency: currency, baseCurrency: baseCurrency) {
            return cached
        }
        await TransactionConversion.loadRates(
            Set([currency, accountCurrency, isTransfer ? targetAccountCurrency : baseCurrency])
        )
        return fields()
    }
}
