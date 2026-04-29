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

    // MARK: - Computed: Available Categories

    var availableCategories: [String] {
        var categories: Set<String> = []
        let transactionType = transaction.type

        for customCategory in categoriesViewModel.customCategories where customCategory.type == transactionType {
            categories.insert(customCategory.name)
        }

        for tx in transactionsViewModel.allTransactions where tx.type == transactionType {
            if !tx.category.isEmpty {
                categories.insert(tx.category)
            }
        }

        if !transaction.category.isEmpty {
            categories.insert(transaction.category)
        }

        return Array(categories).sortedByCustomOrder(
            customCategories: categoriesViewModel.customCategories,
            type: transactionType
        )
    }

    // MARK: - Computed: Category ID

    var categoryId: String? {
        categoriesViewModel.customCategories.first { $0.name == formData.selectedCategory }?.id
    }

    // MARK: - Computed: Available Subcategories

    var availableSubcategories: [Subcategory] {
        guard let catId = categoryId else { return [] }
        return categoriesViewModel.getSubcategoriesForCategory(catId)
    }

    // MARK: - Computed: Can Save

    var canSave: Bool {
        if transaction.type == .internalTransfer { return true }
        return !formData.selectedCategory.isEmpty &&
               availableCategories.contains(formData.selectedCategory)
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

        // Validate category (not required for transfers)
        if transaction.type != .internalTransfer {
            guard !formData.selectedCategory.isEmpty,
                  availableCategories.contains(formData.selectedCategory) else {
                errorMessage = String(localized: "transactionForm.selectCategory")
                HapticManager.warning()
                return false
            }
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

        let dateString = DateFormatters.dateFormatter.string(from: formData.selectedDate)

        // Handle recurring series
        var finalRecurringSeriesId: String? = await handleRecurringSeries(
            amount: amount,
            dateString: dateString
        )
        var finalRecurringOccurrenceId: String? = transaction.recurringOccurrenceId
        if case .never = formData.recurring {
            finalRecurringSeriesId = nil
            finalRecurringOccurrenceId = nil
        }

        // Currency conversion
        let convertedAmount = await convertCurrencyIfNeeded(amount: amount)

        // Build updated transaction
        let updatedTransaction = Transaction(
            id: transaction.id,
            date: dateString,
            description: formData.descriptionText,
            amount: amount,
            currency: formData.selectedCurrency,
            convertedAmount: convertedAmount,
            type: transaction.type,
            category: formData.selectedCategory,
            subcategory: nil,
            accountId: formData.selectedAccountId,
            targetAccountId: formData.selectedTargetAccountId,
            recurringSeriesId: finalRecurringSeriesId,
            recurringOccurrenceId: finalRecurringOccurrenceId,
            createdAt: transaction.createdAt
        )

        do {
            try await transactionStore.update(updatedTransaction)

            // Link subcategories
            categoriesViewModel.linkSubcategoriesToTransaction(
                transactionId: transaction.id,
                subcategoryIds: Array(formData.selectedSubcategoryIds)
            )

            HapticManager.success()
            onSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
    }

    // MARK: - Private: Recurring Series

    /// Manages recurring series creation/update. Returns the final recurringSeriesId.
    /// Async so we can await series creation and then link subcategories to generated transactions.
    private func handleRecurringSeries(amount: Double, dateString: String) async -> String? {
        guard case .frequency(let freq) = formData.recurring else {
            return nil
        }

        if transaction.recurringSeriesId == nil {
            // Create new series — await so generated transactions are in the store
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
            try? await transactionStore.createSeries(series)

            // Link selected subcategories to all generated transactions (backfill + future)
            if !formData.selectedSubcategoryIds.isEmpty {
                let generated = transactionStore.transactions.filter {
                    $0.recurringSeriesId == series.id
                }
                for tx in generated {
                    categoriesViewModel.linkSubcategoriesToTransaction(
                        transactionId: tx.id,
                        subcategoryIds: Array(formData.selectedSubcategoryIds)
                    )
                }
            }
            return series.id
        } else {
            // Update existing series
            if let seriesId = transaction.recurringSeriesId,
               let idx = transactionsViewModel.recurringSeries.firstIndex(where: { $0.id == seriesId }) {
                var series = transactionsViewModel.recurringSeries[idx]
                series.amount = Decimal(amount)
                series.category = formData.selectedCategory
                series.description = formData.descriptionText.isEmpty ? formData.selectedCategory : formData.descriptionText
                series.accountId = formData.selectedAccountId
                series.targetAccountId = formData.selectedTargetAccountId
                series.frequency = freq
                series.isActive = true
                transactionsViewModel.updateRecurringSeries(series)
            }
            return transaction.recurringSeriesId
        }
    }

    // MARK: - Private: Currency Conversion

    private func convertCurrencyIfNeeded(amount: Double) async -> Double? {
        let accountCurrency = accountsViewModel.accounts
            .first(where: { $0.id == formData.selectedAccountId })?.currency ?? transaction.currency

        guard formData.selectedCurrency != accountCurrency else { return nil }

        return await CurrencyConverter.convert(
            amount: amount,
            from: formData.selectedCurrency,
            to: accountCurrency
        )
    }
}
