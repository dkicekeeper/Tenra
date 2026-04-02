//
//  AccountActionViewModel.swift
//  AIFinanceManager
//

import Foundation
import OSLog

@Observable
@MainActor
final class AccountActionViewModel {

    // MARK: - Observable State (UI-driving properties — tracked by @Observable)

    var selectedAction: ActionType = .transfer
    var amountText: String = ""
    var selectedCurrency: String
    var descriptionText: String = ""
    var selectedCategory: String? = nil
    var selectedTargetAccountId: String? = nil
    var selectedDate: Date = Date()
    var showingError: Bool = false
    var errorMessage: String = ""
    var shouldDismiss: Bool = false

    // MARK: - Dependencies (@ObservationIgnored per Phase 23 — let deps in @Observable must be ignored)

    @ObservationIgnored let account: Account
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored let transferDirection: DepositTransferDirection?
    @ObservationIgnored private let logger = Logger(subsystem: "AIFinanceManager", category: "AccountActionViewModel")

    // MARK: - Nested Types

    enum ActionType {
        case income
        case transfer
    }

    // MARK: - Computed Properties

    var availableAccounts: [Account] {
        accountsViewModel.accounts.filter { $0.id != account.id }
    }

    var incomeCategories: [String] {
        transactionsViewModel.incomeCategories
    }

    var navigationTitleText: String {
        if account.isDeposit {
            if let direction = transferDirection {
                return direction == .toDeposit
                    ? String(localized: "transactionForm.depositTopUp")
                    : String(localized: "transactionForm.depositWithdrawal")
            }
            return String(localized: "transactionForm.depositTopUp")
        }
        return selectedAction == .income
            ? String(localized: "transactionForm.accountTopUp")
            : String(localized: "transactionForm.transfer")
    }

    var headerForAccountSelection: String {
        if account.isDeposit {
            if let direction = transferDirection {
                return direction == .toDeposit
                    ? String(localized: "transactionForm.fromAccount")
                    : String(localized: "transactionForm.toAccount")
            }
            return String(localized: "transactionForm.fromAccount")
        }
        return String(localized: "transactionForm.toAccount")
    }

    // MARK: - Init

    init(
        account: Account,
        accountsViewModel: AccountsViewModel,
        transactionsViewModel: TransactionsViewModel,
        transferDirection: DepositTransferDirection? = nil
    ) {
        self.account = account
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
        self.transferDirection = transferDirection
        self.selectedCurrency = account.currency
    }

    // MARK: - Save

    /// Validates input, converts currency if needed, and persists the transaction or transfer.
    /// `transactionStore` is passed from the View (via @Environment) to avoid storing it here.
    func saveTransaction(date: Date, transactionStore: TransactionStore) async {
        guard !amountText.isEmpty,
              let amount = Double(AmountInputFormatting.cleanAmountString(amountText)),
              amount > 0 else {
            errorMessage = String(localized: "transactionForm.enterPositiveAmount")
            showingError = true
            HapticManager.warning()
            return
        }

        let dateFormatter = DateFormatters.dateFormatter
        let transactionDate = dateFormatter.string(from: date)
        let finalDescription = descriptionText.isEmpty
            ? (selectedAction == .income ? String(localized: "transactionForm.accountTopUp") : "")
            : descriptionText

        if selectedAction == .income {
            await saveIncomeTransaction(
                amount: amount,
                transactionDate: transactionDate,
                finalDescription: finalDescription,
                transactionStore: transactionStore
            )
        } else {
            await saveTransfer(
                amount: amount,
                transactionDate: transactionDate,
                finalDescription: finalDescription,
                transactionStore: transactionStore
            )
        }
    }

    // MARK: - Private: Income

    private func saveIncomeTransaction(
        amount: Double,
        transactionDate: String,
        finalDescription: String,
        transactionStore: TransactionStore
    ) async {
        guard let category = selectedCategory, !incomeCategories.isEmpty else {
            errorMessage = String(localized: "transactionForm.selectCategoryIncome")
            showingError = true
            HapticManager.warning()
            return
        }

        // Convert currency if different from account's currency
        var convertedAmount: Double? = nil
        if selectedCurrency != account.currency {
            guard let converted = await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: account.currency
            ) else {
                errorMessage = String(localized: "currency.error.conversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
            convertedAmount = converted
        }

        let transaction = Transaction(
            id: "",
            date: transactionDate,
            description: finalDescription,
            amount: amount,
            currency: selectedCurrency,
            convertedAmount: convertedAmount,
            type: .income,
            category: category,
            subcategory: nil,
            accountId: account.id,
            targetAccountId: nil
        )

        do {
            _ = try await transactionStore.add(transaction)
            HapticManager.success()
            shouldDismiss = true
        } catch {
            logger.error("Failed to save income transaction: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
            HapticManager.error()
        }
    }

    // MARK: - Private: Transfer

    private func saveTransfer(
        amount: Double,
        transactionDate: String,
        finalDescription: String,
        transactionStore: TransactionStore
    ) async {
        // Validate target account selection
        guard let targetAccountId = selectedTargetAccountId else {
            errorMessage = String(localized: "transactionForm.selectTargetAccount")
            showingError = true
            HapticManager.warning()
            return
        }

        guard targetAccountId != account.id else {
            errorMessage = String(localized: "transactionForm.cannotTransferToSame")
            showingError = true
            HapticManager.warning()
            return
        }

        guard accountsViewModel.accounts.contains(where: { $0.id == targetAccountId }) else {
            errorMessage = String(localized: "transactionForm.accountNotFound")
            showingError = true
            HapticManager.error()
            return
        }

        // Determine source and target IDs (deposit direction logic)
        let (sourceId, targetId): (String, String)
        if account.isDeposit, let direction = transferDirection {
            switch direction {
            case .toDeposit:
                sourceId = targetAccountId
                targetId = account.id
            case .fromDeposit:
                sourceId = account.id
                targetId = targetAccountId
            }
        } else {
            sourceId = account.id
            targetId = targetAccountId
        }

        // Resolve source currency
        let sourceCurrency = resolveSourceCurrency(sourceId: sourceId)

        // Convert source amount if needed
        if selectedCurrency != sourceCurrency {
            guard await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: sourceCurrency
            ) != nil else {
                errorMessage = String(localized: "currency.error.conversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        // Pre-load exchange rates for all involved currencies
        let targetAccount = accountsViewModel.accounts.first(where: { $0.id == targetId })
        let targetCurrency = targetAccount?.currency ?? selectedCurrency
        let currenciesToLoad = Set([selectedCurrency, account.currency, targetCurrency])

        for currency in currenciesToLoad where currency != "KZT" {
            if await CurrencyConverter.getExchangeRate(for: currency) == nil {
                errorMessage = String(localized: "currency.error.ratesUnavailable")
                showingError = true
                HapticManager.error()
                return
            }
        }

        // Validate all needed conversions can be done
        if selectedCurrency != account.currency {
            guard await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: account.currency) != nil else {
                errorMessage = String(localized: "currency.error.sourceConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        if selectedCurrency != targetCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: targetCurrency) != nil else {
                errorMessage = String(localized: "currency.error.targetConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        if account.currency != targetCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: account.currency, to: targetCurrency) != nil else {
                errorMessage = String(localized: "currency.error.crossConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

        // Compute target amount
        var precomputedTargetAmount: Double?
        if selectedCurrency != targetCurrency {
            precomputedTargetAmount = await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: targetCurrency
            )
        } else {
            precomputedTargetAmount = amount
        }

        // Execute transfer
        do {
            try await transactionStore.transfer(
                from: sourceId,
                to: targetId,
                amount: amount,
                currency: selectedCurrency,
                targetAmount: precomputedTargetAmount,
                targetCurrency: targetCurrency,
                date: transactionDate,
                description: finalDescription
            )
            HapticManager.success()
            shouldDismiss = true
        } catch {
            logger.error("Failed to save transfer: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
            HapticManager.error()
        }
    }

    // MARK: - Private: Helpers

    private func resolveSourceCurrency(sourceId: String) -> String {
        if account.isDeposit, let direction = transferDirection {
            if direction == .fromDeposit { return account.currency }
            return accountsViewModel.accounts.first(where: { $0.id == sourceId })?.currency ?? account.currency
        }
        return accountsViewModel.accounts.first(where: { $0.id == sourceId })?.currency ?? account.currency
    }
}
