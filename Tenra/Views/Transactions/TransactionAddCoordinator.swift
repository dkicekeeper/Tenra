//
//  TransactionAddCoordinator.swift
//  AIFinanceManager
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

    // ✅ REFACTORED: TransactionStore is now REQUIRED (not optional)
    // No more dual paths - always use TransactionStore
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

    /// ✅ REFACTORED: Simplified account suggestion - no manual caching
    /// Compute suggested account ID asynchronously
    func suggestedAccountId() async -> String? {
        let suggested = accountsViewModel.suggestedAccount(
            forCategory: formData.category,
            transactions: transactionsViewModel.allTransactions,
            amount: formData.amountDouble
        )
        return suggested?.id ?? accountsViewModel.accounts.first?.id
    }

    /// Get accounts sorted by manual order, then by balance (fast, no transaction scanning needed)
    func rankedAccounts() -> [Account] {
        // Simply sort by manual order first, then balance - instant and no need to scan transactions!
        guard let balanceCoordinator = accountsViewModel.balanceCoordinator else {
            return accountsViewModel.accounts.sortedByOrder()
        }

        let balances = balanceCoordinator.balances

        return accountsViewModel.accounts.sorted { account1, account2 in
            // 1. PRIORITY: Manual order (if both have order, sort by order)
            if let order1 = account1.order, let order2 = account2.order {
                return order1 < order2
            }
            // If only one has order, it goes first
            if account1.order != nil {
                return true
            }
            if account2.order != nil {
                return false
            }

            // 2. Deposits at the end (for accounts without manual order)
            if account1.isDeposit != account2.isDeposit {
                return !account1.isDeposit
            }

            // 3. Higher balance first (for accounts without manual order)
            let balance1 = balances[account1.id] ?? 0
            let balance2 = balances[account2.id] ?? 0
            return balance1 > balance2
        }
    }

    /// Get available subcategories for current category
    func availableSubcategories() -> [Subcategory] {
        guard let categoryId = categoriesViewModel.customCategories.first(where: {
            $0.name == formData.category
        })?.id else {
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

        // Step 2: Handle recurring series if enabled
        if case .frequency = formData.recurring {
            do {
                try await createRecurringSeriesWithSubcategories()
            } catch {
                return ValidationResult(isValid: false, errors: [.custom(error.localizedDescription)])
            }
            // The generator creates occurrences for ALL dates (past, today, future).
            // Never fall through to add a separate individual transaction — it would
            // duplicate today's generated occurrence (which already carries a recurring badge).
            return .valid
        }

        // Step 3: Convert currency to base currency
        let baseCurrency = transactionsViewModel.appSettings.baseCurrency
        let conversionResult = await convertCurrency(
            amount: formData.parsedAmount!,
            from: formData.currency,
            to: baseCurrency
        )

        // Step 4: Calculate target amounts (for different currency scenarios)
        let targetAmounts = await calculateTargetAmounts(
            amount: formData.parsedAmount!,
            currency: formData.currency,
            account: account,
            baseCurrency: baseCurrency
        )

        // Step 5: Create and add transaction via TransactionStore
        let transaction = createTransaction(
            convertedAmount: conversionResult.convertedAmount,
            targetAmounts: targetAmounts
        )

        // ✅ REFACTORED: Single code path - always use TransactionStore
        let createdTransaction: Transaction
        do {
            createdTransaction = try await transactionStore.add(transaction)
        } catch {
            return ValidationResult(isValid: false, errors: [.custom(error.localizedDescription)])
        }

        // Step 6: Link subcategories if any selected
        if !formData.subcategoryIds.isEmpty {
            await linkSubcategories(to: createdTransaction)
        }

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

    private func createTransaction(
        convertedAmount: Double?,
        targetAmounts: TargetAmounts
    ) -> Transaction {
        Transaction(
            id: "",
            date: DateFormatters.dateFormatter.string(from: formData.selectedDate),
            description: formData.description,
            amount: formData.amountDouble!,
            currency: formData.currency,
            convertedAmount: convertedAmount,
            type: formData.type,
            category: formData.category,
            subcategory: nil,
            accountId: formData.accountId!,
            targetAccountId: nil,
            targetCurrency: targetAmounts.targetCurrency,
            targetAmount: targetAmounts.targetAmount,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970
        )
    }

    private func linkSubcategories(to transaction: Transaction) async {
        // First, ensure subcategories are linked to the category
        if let categoryId = categoriesViewModel.customCategories.first(where: { $0.name == formData.category })?.id {
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

    // MARK: - Phase 2: Inline Validation & Conversion (formerly FormService)

    /// ✅ REFACTORED: Validation logic moved from FormService
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

    /// ✅ REFACTORED: Currency conversion moved from FormService
    private func convertCurrency(
        amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String
    ) async -> CurrencyConversionResult {
        // No conversion needed if currencies match
        guard sourceCurrency != targetCurrency else {
            return CurrencyConversionResult(convertedAmount: nil, exchangeRate: nil)
        }

        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue

        // Pre-fetch exchange rates
        _ = await CurrencyConverter.getExchangeRate(for: sourceCurrency)
        _ = await CurrencyConverter.getExchangeRate(for: targetCurrency)

        // Try sync conversion first (uses cache)
        if let convertedAmount = CurrencyConverter.convertSync(
            amount: amountDouble,
            from: sourceCurrency,
            to: targetCurrency
        ) {
            let rate = convertedAmount / amountDouble
            return CurrencyConversionResult(
                convertedAmount: convertedAmount,
                exchangeRate: rate
            )
        }

        // Fallback to async conversion
        if let convertedAmount = await CurrencyConverter.convert(
            amount: amountDouble,
            from: sourceCurrency,
            to: targetCurrency
        ) {
            let rate = convertedAmount / amountDouble
            return CurrencyConversionResult(
                convertedAmount: convertedAmount,
                exchangeRate: rate
            )
        }

        return CurrencyConversionResult(convertedAmount: nil, exchangeRate: nil)
    }

    /// ✅ REFACTORED: Target amounts calculation moved from FormService
    private func calculateTargetAmounts(
        amount: Decimal,
        currency: String,
        account: Account,
        baseCurrency: String
    ) async -> TargetAmounts {
        let accountCurrency = account.currency

        // Case 1: Transaction currency differs from account currency
        // Need to convert to account currency for correct balance update
        if currency != accountCurrency {
            let conversionResult = await convertCurrency(
                amount: amount,
                from: currency,
                to: accountCurrency
            )

            return TargetAmounts(
                targetCurrency: accountCurrency,
                targetAmount: conversionResult.convertedAmount
            )
        }

        // Case 2: Transaction currency == Account currency, but differs from base currency
        // Show equivalent in base currency for UI display
        if currency == accountCurrency && currency != baseCurrency {
            let conversionResult = await convertCurrency(
                amount: amount,
                from: currency,
                to: baseCurrency
            )

            if conversionResult.convertedAmount != nil {
                return TargetAmounts(
                    targetCurrency: baseCurrency,
                    targetAmount: conversionResult.convertedAmount
                )
            }
        }

        // Case 3: All currencies match or no conversion available
        return .none
    }

}
