//
//  TransactionAddCoordinator.swift
//  Tenra
//
//  Coordinator for TransactionAddModal.
//  Handles transaction creation with form validation and currency conversion.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class TransactionAddCoordinator {

    // MARK: - Dependencies

    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    @ObservationIgnored let accountsViewModel: AccountsViewModel

    @ObservationIgnored private let transactionStore: TransactionStore

    // MARK: - State

    var formData: TransactionFormData

    // MARK: - Initialization

    init(
        category: String,
        type: TransactionType,
        currency: String,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionStore: TransactionStore
    ) {
        self.formData = TransactionFormData(
            category: category,
            type: type,
            currency: currency,
            suggestedAccountId: nil  // Will be computed in onAppear
        )

        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.transactionStore = transactionStore
    }

    // MARK: - Public Methods

    /// Compute suggested account ID asynchronously.
    /// Only regular accounts are eligible — loan/deposit accounts are technical
    /// containers and never offered as the source for a new income/expense/transfer.
    func suggestedAccountId() async -> String? {
        let suggested = accountsViewModel.suggestedAccount(
            forCategory: formData.category,
            transactions: transactionsViewModel.allTransactions,
            amount: formData.amountDouble
        )
        if let suggested, !suggested.isLoan, !suggested.isDeposit {
            return suggested.id
        }
        return accountsViewModel.regularAccounts.first?.id
    }

    /// Get regular accounts (no loans / deposits) sorted by manual order, then by balance.
    /// This is the picker source for income/expense/transfer creation flows.
    func rankedAccounts() -> [Account] {
        guard let balanceCoordinator = accountsViewModel.balanceCoordinator else {
            return accountsViewModel.regularAccounts.sortedByOrder()
        }

        let balances = balanceCoordinator.balances

        return accountsViewModel.regularAccounts.sorted { account1, account2 in
            // 1. PRIORITY: Manual order
            if let order1 = account1.order, let order2 = account2.order {
                return order1 < order2
            }
            if account1.order != nil { return true }
            if account2.order != nil { return false }

            // 2. Higher balance first (for accounts without manual order)
            let balance1 = balances[account1.id] ?? 0
            let balance2 = balances[account2.id] ?? 0
            return balance1 > balance2
        }
    }

    /// Get available subcategories for current category
    func availableSubcategories() -> [Subcategory] {
        // O(1) via categoryIdByName.
        guard let categoryId = categoriesViewModel.transactionStore?
                .categoryIdByName[formData.category.lowercased()] else {
            return []
        }
        return categoriesViewModel.getSubcategoriesForCategory(categoryId)
    }

    /// Update currency when account selection changes
    func updateCurrencyForSelectedAccount() {
        guard let accountId = formData.accountId,
              let account = accountsViewModel.accounts.first(where: { $0.id == accountId }) else {
            return
        }

        formData.currency = account.currency
    }

    /// Save transaction
    func save() async -> ValidationResult {
        let accounts = accountsViewModel.accounts

        // Step 1: Validate form data
        let validationResult = validate(accounts: accounts)
        guard validationResult.isValid else {
            return validationResult
        }

        guard let account = accounts.first(where: { $0.id == formData.accountId }) else {
            return ValidationResult(isValid: false, errors: [.accountNotFound])
        }

        // Step 2: Conversion fields (TransactionConversion): the amount in the account's
        // currency when it differs, which the balance moves by, and the equivalent the row
        // shows. `convertedAmount` used to hold the BASE-currency value instead, and a
        // missing rate saved the raw foreign amount; now it refuses the save. Checked
        // before the recurring branch too: its occurrences convert from the same cache.
        guard let conversion = await conversionFields(account: account) else {
            return ValidationResult(
                isValid: false,
                errors: [.custom(String(localized: "currency.error.conversionFailed"))]
            )
        }

        // Step 3: Handle recurring series if enabled
        if case .frequency = formData.recurring {
            do {
                try await createRecurringSeriesWithSubcategories()
            } catch {
                return ValidationResult(isValid: false, errors: [.custom(error.localizedDescription)])
            }
            // The generator creates occurrences for ALL dates (past, today, future).
            // Never fall through to add a separate individual transaction — it would
            // duplicate today's generated occurrence (which already carries a recurring badge).
            RatingPromptService.shared.recordTransactionAdded()
            return .valid
        }

        // Step 4: Create and add transaction via TransactionStore
        let transaction = createTransaction(conversion: conversion)

        let createdTransaction: Transaction
        do {
            createdTransaction = try await transactionStore.add(transaction)
        } catch {
            return ValidationResult(isValid: false, errors: [.custom(error.localizedDescription)])
        }

        // Step 5: Link subcategories if any selected
        if !formData.subcategoryIds.isEmpty {
            await linkSubcategories(to: createdTransaction)
        }

        RatingPromptService.shared.recordTransactionAdded()
        return .valid
    }

    // MARK: - Private Methods

    /// Creates a recurring series and links any selected subcategories to ALL generated transactions.
    /// Uses `await transactionStore.createSeries()` directly so that generated transactions
    /// are already in the store when we call `linkSubcategories(to:)`.
    private func createRecurringSeriesWithSubcategories() async throws {
        guard case .frequency(let freq) = formData.recurring else { return }

        let series = RecurringSeries(
            amount: formData.parsedAmount!,
            currency: formData.currency,
            category: formData.category,
            subcategory: nil,
            description: formData.description,
            accountId: formData.accountId!,
            targetAccountId: nil,
            frequency: freq,
            startDate: DateFormatters.dateFormatter.string(from: formData.selectedDate)
        )

        // Await full series creation — generator runs synchronously inside createSeries,
        // so all transactions (backfill + 1 future) are in transactionStore.transactions after this.
        try await transactionStore.createSeries(series)

        // Link selected subcategories to every generated transaction
        guard !formData.subcategoryIds.isEmpty else { return }

        let generatedTransactions = transactionStore.transactions.filter {
            $0.recurringSeriesId == series.id
        }
        for tx in generatedTransactions {
            await linkSubcategories(to: tx)
        }
    }

    private func createTransaction(conversion: TransactionConversion) -> Transaction {
        Transaction(
            id: "",
            date: DateFormatters.dateFormatter.string(from: formData.selectedDate),
            description: formData.description,
            amount: formData.amountDouble!,
            currency: formData.currency,
            convertedAmount: conversion.convertedAmount,
            type: formData.type,
            category: formData.category,
            subcategory: nil,
            accountId: formData.accountId!,
            targetAccountId: nil,
            targetCurrency: conversion.targetCurrency,
            targetAmount: conversion.targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970
        )
    }

    private func linkSubcategories(to transaction: Transaction) async {
        // First, ensure subcategories are linked to the category — O(1) via index.
        if let categoryId = categoriesViewModel.transactionStore?
            .categoryIdByName[formData.category.lowercased()] {
            for subcategoryId in formData.subcategoryIds {
                categoriesViewModel.linkSubcategoryToCategory(
                    subcategoryId: subcategoryId,
                    categoryId: categoryId
                )
            }
        }

        // Then link subcategories to the transaction
        categoriesViewModel.linkSubcategoriesToTransaction(
            transactionId: transaction.id,
            subcategoryIds: Array(formData.subcategoryIds)
        )
    }

    // MARK: - Validation & Conversion

    private func validate(accounts: [Account]) -> ValidationResult {
        var errors: [ValidationError] = []

        // Validate amount
        guard let decimalAmount = formData.parsedAmount else {
            errors.append(.invalidAmount)
            return .invalid(errors)
        }

        guard decimalAmount > 0 else {
            errors.append(.amountMustBePositive)
            return .invalid(errors)
        }

        guard AmountFormatter.validate(decimalAmount) else {
            errors.append(.amountExceedsMaximum)
            return .invalid(errors)
        }

        // Validate account selection
        guard let accountId = formData.accountId else {
            errors.append(.accountNotSelected)
            return .invalid(errors)
        }

        // Validate account exists
        guard accounts.contains(where: { $0.id == accountId }) else {
            errors.append(.accountNotFound)
            return .invalid(errors)
        }

        return .valid
    }

    /// Conversion fields for the new transaction on `account`, nil when the amount must be
    /// converted into the account's currency and no rate can be had (cache, then network).
    private func conversionFields(account: Account) async -> TransactionConversion? {
        guard let amount = formData.amountDouble else { return nil }
        let currency = formData.currency
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency

        func fields() -> TransactionConversion? {
            TransactionConversion.singleAccount(
                amount: amount,
                currency: currency,
                accountCurrency: account.currency,
                baseCurrency: baseCurrency,
                convert: TransactionConversion.cachedRate
            )
        }

        if let cached = fields() { return cached }
        await TransactionConversion.loadRates(Set([currency, account.currency, baseCurrency]))
        return fields()
    }

}
