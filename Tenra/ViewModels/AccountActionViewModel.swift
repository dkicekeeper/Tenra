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

    var selectedAction: ActionType
    var amountText: String = ""
    var selectedCurrency: String
    var descriptionText: String = ""
    var selectedCategory: String? = nil
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

    var availableAccounts: [Account] {
        accountsViewModel.accounts.filter { $0.id != account.id }
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

        // The current account is always the source — deposit transfers are always
        // outgoing (Variant A). To put money INTO a deposit, the user goes from the
        // source account's screen.
        let sourceId = account.id
        let targetId = targetAccountId

        let sourceCurrency = account.currency

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
