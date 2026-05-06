//
//  AccountActionViewModel.swift
//  Tenra
//

import Foundation
import OSLog

@Observable
@MainActor
final class AccountActionViewModel {

    // MARK: - Observable State

    var selectedAction: ActionType {
        didSet { applyDefaultsForAction() }
    }
    var amountText: String = ""
    var selectedCurrency: String
    var descriptionText: String = ""
    var selectedCategory: String? = nil
    var selectedSourceAccountId: String? = nil
    var selectedTargetAccountId: String? = nil
    var selectedDate: Date = Date()
    var showingError: Bool = false
    var errorMessage: String = ""
    var shouldDismiss: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored let account: Account
    @ObservationIgnored let accountsViewModel: AccountsViewModel
    @ObservationIgnored let transactionsViewModel: TransactionsViewModel
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "AccountActionViewModel")

    // MARK: - Nested Types

    enum ActionType {
        case income
        case transfer
    }

    // MARK: - Computed Properties

    /// Source picker accounts for transfer mode — all accounts except the currently
    /// selected target. Includes deposits in either role.
    var availableSourceAccounts: [Account] {
        accountsViewModel.accounts.filter { $0.id != selectedTargetAccountId }
    }

    /// Target picker accounts — all accounts except the currently selected source
    /// (for transfer) or all accounts (for income top-up).
    var availableTargetAccounts: [Account] {
        switch selectedAction {
        case .transfer:
            return accountsViewModel.accounts.filter { $0.id != selectedSourceAccountId }
        case .income:
            return accountsViewModel.accounts
        }
    }

    var incomeCategories: [String] {
        let validNames = Set(
            transactionsViewModel.customCategories
                .filter { $0.type == .income }
                .map { $0.name }
        )
        return transactionsViewModel.incomeCategories.filter { validNames.contains($0) }
    }

    var navigationTitleText: String {
        selectedAction == .income
            ? String(localized: "transactionForm.accountTopUp")
            : String(localized: "transactionForm.transfer")
    }

    var headerForAccountSelection: String {
        String(localized: "transactionForm.toAccount")
    }

    // MARK: - Init

    init(
        account: Account,
        accountsViewModel: AccountsViewModel,
        transactionsViewModel: TransactionsViewModel,
        defaultAction: ActionType? = nil
    ) {
        self.account = account
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
        self.selectedCurrency = account.currency
        self.selectedAction = defaultAction ?? .transfer
        applyDefaultsForAction()
    }

    /// Resets source/target selections to the action-appropriate defaults so that
    /// the tapped account always lands in the meaningful slot:
    /// - transfer: tapped account is the source; target is unselected.
    /// - income:   tapped account is the target; source is a category.
    private func applyDefaultsForAction() {
        switch selectedAction {
        case .transfer:
            selectedSourceAccountId = account.id
            selectedTargetAccountId = nil
        case .income:
            selectedSourceAccountId = nil
            selectedTargetAccountId = account.id
        }
        selectedCurrency = account.currency
    }

    /// Called when the user picks a new account in the carousel that drives the
    /// amount currency: source for transfer, target for income. Mirrors the
    /// "currency follows account" behavior from `TransactionAddModal`.
    func updateCurrencyForPrimaryAccount() {
        let primaryId: String? = {
            switch selectedAction {
            case .transfer: return selectedSourceAccountId
            case .income:   return selectedTargetAccountId
            }
        }()
        guard let id = primaryId,
              let account = accountsViewModel.accounts.first(where: { $0.id == id }) else {
            return
        }
        selectedCurrency = account.currency
    }

    // MARK: - Save

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

    // MARK: - Private: Income (Top-up)

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

        let targetAccountId = selectedTargetAccountId ?? account.id
        guard let targetAccount = accountsViewModel.accounts.first(where: { $0.id == targetAccountId }) else {
            errorMessage = String(localized: "transactionForm.accountNotFound")
            showingError = true
            HapticManager.error()
            return
        }

        var convertedAmount: Double? = nil
        if selectedCurrency != targetAccount.currency {
            guard let converted = await CurrencyConverter.convert(
                amount: amount,
                from: selectedCurrency,
                to: targetAccount.currency
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
            accountId: targetAccount.id,
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
        let sourceId = selectedSourceAccountId ?? account.id

        guard let targetAccountId = selectedTargetAccountId else {
            errorMessage = String(localized: "transactionForm.selectTargetAccount")
            showingError = true
            HapticManager.warning()
            return
        }

        guard targetAccountId != sourceId else {
            errorMessage = String(localized: "transactionForm.cannotTransferToSame")
            showingError = true
            HapticManager.warning()
            return
        }

        guard let sourceAccount = accountsViewModel.accounts.first(where: { $0.id == sourceId }) else {
            errorMessage = String(localized: "transactionForm.accountNotFound")
            showingError = true
            HapticManager.error()
            return
        }

        guard let targetAccount = accountsViewModel.accounts.first(where: { $0.id == targetAccountId }) else {
            errorMessage = String(localized: "transactionForm.accountNotFound")
            showingError = true
            HapticManager.error()
            return
        }

        let targetId = targetAccountId
        let sourceCurrency = sourceAccount.currency
        let targetCurrency = targetAccount.currency

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

        let currenciesToLoad = Set([selectedCurrency, sourceCurrency, targetCurrency])

        for currency in currenciesToLoad where currency != "KZT" {
            if await CurrencyConverter.getExchangeRate(for: currency) == nil {
                errorMessage = String(localized: "currency.error.ratesUnavailable")
                showingError = true
                HapticManager.error()
                return
            }
        }

        if selectedCurrency != sourceCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: selectedCurrency, to: sourceCurrency) != nil else {
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

        if sourceCurrency != targetCurrency {
            guard await CurrencyConverter.convert(amount: amount, from: sourceCurrency, to: targetCurrency) != nil else {
                errorMessage = String(localized: "currency.error.crossConversionFailed")
                showingError = true
                HapticManager.error()
                return
            }
        }

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
}
