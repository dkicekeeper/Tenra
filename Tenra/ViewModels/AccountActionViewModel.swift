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
    /// Subcategory tags for a top-up. Income transactions support subcategories exactly
    /// like expenses do (the catalog and the link tables are type-agnostic); this screen
    /// simply had no picker before. Always empty for transfers.
    var selectedSubcategoryIds: Set<String> = []
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
    @ObservationIgnored let categoriesViewModel: CategoriesViewModel
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "AccountActionViewModel")

    /// Set once the user picks a transfer target themselves. After that we stop
    /// re-suggesting on every source change — an explicit choice outranks the model.
    @ObservationIgnored private var userPickedTarget = false

    // MARK: - Nested Types

    enum ActionType {
        case income
        case transfer
    }

    // MARK: - Computed Properties

    /// Source picker accounts. Shows ALL accounts (no cross-filter against the target).
    /// Cross-filtering mutated this list whenever the target changed, which re-laid out
    /// the source carousel and visibly scrolled it; the same-account case is caught by
    /// the save-time guard instead. Includes deposits in either role.
    var availableSourceAccounts: [Account] {
        accountsViewModel.accounts
    }

    /// Target picker accounts — all accounts (same reasoning as `availableSourceAccounts`).
    var availableTargetAccounts: [Account] {
        accountsViewModel.accounts
    }

    var incomeCategories: [String] {
        let validNames = Set(
            transactionsViewModel.customCategories
                .filter { $0.type == .income }
                .map { $0.name }
        )
        return transactionsViewModel.incomeCategories.filter { validNames.contains($0) }
    }

    /// Custom-category id of the selected income category — feeds the subcategory picker.
    /// `nil` while nothing is selected (or for transfers), which hides the picker.
    var selectedCategoryId: String? {
        guard selectedAction == .income, let name = selectedCategory else { return nil }
        return transactionsViewModel.customCategories.first {
            $0.type == .income && $0.name == name
        }?.id
    }

    /// Income category changed — its subcategories don't carry over to another category.
    /// Cleared unconditionally: `CategoryCardSelectorView` writes the binding *before*
    /// calling back (and only on a real change), so comparing against `selectedCategory`
    /// here would always see the new value and never fire.
    func handleCategorySelectionChange() {
        selectedSubcategoryIds.removeAll()
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
        categoriesViewModel: CategoriesViewModel,
        defaultAction: ActionType? = nil
    ) {
        self.account = account
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.selectedCurrency = account.currency
        self.selectedAction = defaultAction ?? .transfer
        applyDefaultsForAction()
    }

    /// Resets source/target selections to the action-appropriate defaults so that
    /// the tapped account always lands in the meaningful slot:
    /// - transfer: tapped account is the source; target is unselected.
    /// - income:   tapped account is the target; source is a category.
    private func applyDefaultsForAction() {
        // Subcategory tags belong to the income category that was picked for the
        // previous action; a switch invalidates them (transfers have none at all).
        selectedSubcategoryIds.removeAll()
        switch selectedAction {
        case .transfer:
            selectedSourceAccountId = account.id
            selectedTargetAccountId = defaultTargetAccountId(for: account.id)
        case .income:
            selectedSourceAccountId = nil
            selectedTargetAccountId = account.id
            // Default the income category so its carousel also shows a selection on appear.
            if selectedCategory == nil {
                selectedCategory = incomeCategories.first
            }
        }
        selectedCurrency = account.currency
    }

    /// Source picker changed (user tap/scroll). Keeps the amount currency in sync and, for
    /// transfers, re-suggests the target for the new source — the carousels no longer
    /// cross-filter (that caused scroll jumps), so equality is prevented here instead.
    func handleSourceSelectionChange() {
        updateCurrencyForPrimaryAccount()
        guard selectedAction == .transfer,
              let source = selectedSourceAccountId else { return }

        // Transfer habits are pair-shaped ("Freedom deposit → Freedom card"), so a new
        // source implies a different likely target — re-suggest rather than only nudging
        // on a clash. Once the user has picked a target themselves we stop overriding it
        // and fall back to the clash-only nudge.
        if userPickedTarget {
            guard source == selectedTargetAccountId else { return }
            selectedTargetAccountId = neighborAccountId(of: source)
        } else {
            selectedTargetAccountId = defaultTargetAccountId(for: source)
        }
    }

    /// Target picker changed. For transfers, nudges the source off the target if they clash.
    func handleTargetSelectionChange() {
        updateCurrencyForPrimaryAccount()
        guard selectedAction == .transfer else { return }
        userPickedTarget = true
        guard let target = selectedTargetAccountId,
              target == selectedSourceAccountId else { return }
        selectedSourceAccountId = neighborAccountId(of: target)
    }

    /// Default counterpart for a transfer out of `sourceId`: the account the user
    /// actually transfers to, learned from their history. Falls back to the carousel
    /// neighbor for accounts with no transfer history (new users, first transfer).
    private func defaultTargetAccountId(for sourceId: String) -> String? {
        if let learned = accountsViewModel.suggestedTransferTarget(forSource: sourceId),
           learned.id != sourceId {
            return learned.id
        }
        return neighborAccountId(of: sourceId)
    }

    /// The account adjacent to `accountId` in the carousel's display order (the same
    /// `sortedByOrder()` the selector uses). Prefers the next card, falling back to the
    /// previous one at the end — so a clash shifts to the neighbor instead of jumping
    /// to the first account.
    private func neighborAccountId(of accountId: String) -> String? {
        let ordered = accountsViewModel.accounts.sortedByOrder()
        guard let idx = ordered.firstIndex(where: { $0.id == accountId }) else {
            return ordered.first(where: { $0.id != accountId })?.id
        }
        if idx + 1 < ordered.count { return ordered[idx + 1].id }
        if idx - 1 >= 0 { return ordered[idx - 1].id }
        return nil
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
            let created = try await transactionStore.add(transaction)
            // Subcategory links need the STORE-assigned id (we send `id: ""`), so they
            // are written after the add — same order as TransactionAddCoordinator.
            linkSelectedSubcategories(to: created)
            HapticManager.success()
            shouldDismiss = true
        } catch {
            logger.error("Failed to save income transaction: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showingError = true
            HapticManager.error()
        }
    }

    /// Attaches the picked subcategories to the saved top-up. Mirrors
    /// `TransactionAddCoordinator.linkSubcategories`: first make sure each subcategory is
    /// linked to the category (so it shows up in that category's carousel next time),
    /// then link it to the transaction itself.
    private func linkSelectedSubcategories(to transaction: Transaction) {
        guard !selectedSubcategoryIds.isEmpty, !transaction.id.isEmpty else { return }

        // Resolved the same way the picker resolved it (income category, matched by
        // name + type) rather than through `categoryIdByName`, which is keyed by name
        // alone and would hand back the expense category when both share a name.
        if let categoryId = selectedCategoryId {
            for subcategoryId in selectedSubcategoryIds {
                categoriesViewModel.linkSubcategoryToCategory(
                    subcategoryId: subcategoryId,
                    categoryId: categoryId
                )
            }
        }

        categoriesViewModel.linkSubcategoriesToTransaction(
            transactionId: transaction.id,
            subcategoryIds: Array(selectedSubcategoryIds)
        )
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
