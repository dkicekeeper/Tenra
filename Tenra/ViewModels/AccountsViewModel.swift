//
//  AccountsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026
//
//  ViewModel for managing accounts

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class AccountsViewModel {
    // MARK: - Observable Properties

    /// Phase 16: Accounts read directly from TransactionStore (Single Source of Truth)
    /// No more array copies — @Observable tracks changes automatically
    var accounts: [Account] {
        transactionStore?.accounts ?? []
    }

    // MARK: - Dependencies

    /// REFACTORED 2026-02-02: BalanceCoordinator as Single Source of Truth
    /// Injected by AppCoordinator, optional for backward compatibility
    @ObservationIgnored var balanceCoordinator: BalanceCoordinator?

    /// PHASE 3: TransactionStore as Single Source of Truth for accounts
    /// ViewModels observe this instead of owning data
    @ObservationIgnored weak var transactionStore: TransactionStore?

    // MARK: - Private Properties

    @ObservationIgnored private let repository: DataRepositoryProtocol

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
        // PHASE 3: Don't load accounts here anymore - will be synced from TransactionStore
        // self.accounts = repository.loadAccounts()
    }

    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {

        // PHASE 3: TransactionStore is the owner - it will reload and publish to observers
        // No need to reload here - accounts will be updated via subscription
        // Just trigger syncInitialBalancesToCoordinator when accounts change


        // MIGRATED: Sync accounts with BalanceCoordinator after reload
        syncInitialBalancesToCoordinator()
    }
    
    // MARK: - Account CRUD Operations
    
    func addAccount(name: String, initialBalance: Double, currency: String, iconSource: IconSource? = nil, shouldCalculateFromTransactions: Bool = false) async {

        let account = Account(
            name: name,
            currency: currency,
            iconSource: iconSource,
            shouldCalculateFromTransactions: shouldCalculateFromTransactions,
            initialBalance: shouldCalculateFromTransactions ? 0.0 : initialBalance
        )

        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.addAccount(account)

        // NEW: Register account with BalanceCoordinator (now synchronous)
        if let coordinator = balanceCoordinator {
            await coordinator.registerAccounts([account])
            // Используем initialBalance вместо balance
            let initialBal = account.initialBalance ?? 0.0
            await coordinator.setInitialBalance(initialBal, for: account.id)

            // If shouldCalculateFromTransactions is true, DON'T mark as manual
            // This allows the account balance to be calculated from transactions
            if !shouldCalculateFromTransactions {
                await coordinator.markAsManual(account.id)
            }
        }
    }
    
    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let oldAccount = accounts[index]

        // Detect balance change by comparing initialBalance fields.
        // When AccountEditView edits the balance, it sets initialBalance to the desired current balance.
        // When balance wasn't edited, the existing account is copied with original initialBalance preserved.
        let newInitial = account.initialBalance ?? 0
        let oldInitial = oldAccount.initialBalance ?? 0
        let balanceChanged = abs(newInitial - oldInitial) > 0.001

        if balanceChanged, let coordinator = balanceCoordinator, let store = transactionStore {
            // account.initialBalance here = desired CURRENT balance (from the edit view text field)
            let desiredBalance = account.initialBalance ?? oldAccount.balance

            // Back-calculate correct initialBalance: initialBalance = desiredBalance - Σ(transactions)
            let engine = BalanceCalculationEngine()
            let correctInitialBalance = engine.calculateInitialBalance(
                currentBalance: desiredBalance,
                accountId: account.id,
                accountCurrency: account.currency,
                transactions: store.transactions
            )

            var corrected = account
            corrected.initialBalance = correctInitialBalance
            corrected.shouldCalculateFromTransactions = false
            store.updateAccount(corrected)

            Task {
                await coordinator.setInitialBalance(correctInitialBalance, for: account.id)
                await coordinator.markAsManual(account.id)
                await coordinator.recalculateAccounts(
                    [account.id],
                    accounts: store.accounts,
                    transactions: store.transactions
                )
            }
        } else {
            // No balance change — just update name/currency/icon
            transactionStore?.updateAccount(account)
        }
    }

    func deleteAccount(_ account: Account) {
        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.deleteAccount(account.id)
        // Note: Transaction deletion is handled by the calling view

        // NEW: Remove account from BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.removeAccount(account.id)
            }
        }
    }
    
    // MARK: - Account Balance Management

    /// MIGRATED: Get initial balance from BalanceCoordinator (Single Source of Truth)
    func getInitialBalance(for accountId: String) -> Double? {
        // Direct access to BalanceCoordinator not possible (async)
        // Use account.initialBalance as fallback for backward compatibility
        return accounts.first(where: { $0.id == accountId })?.initialBalance
    }

    /// MIGRATED: Set initial balance via BalanceCoordinator (Single Source of Truth)
    func setInitialBalance(_ balance: Double, for accountId: String) {
        // Delegate to BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.setInitialBalance(balance, for: accountId)
            }
        }
    }
    
    // MARK: - Deposit Operations
    
    /// Add a fully-formed deposit Account (preserves computed dates in DepositInfo)
    func addDepositAccount(_ account: Account) {
        guard account.isDeposit, let depositInfo = account.depositInfo else { return }

        transactionStore?.addAccount(account)

        let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.registerAccounts([account])
                await coordinator.setInitialBalance(balance, for: account.id)
                await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
            }
        }
    }

    func addDeposit(
        name: String,
        balance: Double,
        currency: String,
        bankName: String,
        iconSource: IconSource? = nil,
        principalBalance: Decimal,
        capitalizationEnabled: Bool,
        interestRateAnnual: Decimal,
        interestPostingDay: Int
    ) {
        let depositInfo = DepositInfo(
            bankName: bankName,
            principalBalance: principalBalance,
            capitalizationEnabled: capitalizationEnabled,
            interestRateAnnual: interestRateAnnual,
            interestPostingDay: interestPostingDay
        )

        let balance = NSDecimalNumber(decimal: principalBalance).doubleValue
        let account = Account(
            name: name,
            currency: currency,
            iconSource: iconSource,
            depositInfo: depositInfo,
            shouldCalculateFromTransactions: false,  // Депозиты всегда manual
            initialBalance: balance
        )

        // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
        transactionStore?.addAccount(account)

        // NEW: Register deposit with BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.registerAccounts([account])
                await coordinator.setInitialBalance(balance, for: account.id)
                if let depositInfo = account.depositInfo {
                    await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
                }
            }
        }
    }
    
    func updateDeposit(_ account: Account) {
        guard account.isDeposit else { return }
        if accounts.firstIndex(where: { $0.id == account.id }) != nil {
            // PHASE 3: Delegate to TransactionStore (Single Source of Truth)
            transactionStore?.updateAccount(account)

            // NEW: Update deposit in BalanceCoordinator
            if let coordinator = balanceCoordinator, let depositInfo = account.depositInfo {
                let balance = NSDecimalNumber(decimal: depositInfo.principalBalance).doubleValue
                Task {
                    await coordinator.updateForAccount(account, newBalance: balance)
                    await coordinator.updateDepositInfo(account, depositInfo: depositInfo)
                    await coordinator.setInitialBalance(balance, for: account.id)
                }
            }
        }
    }
    
    func deleteDeposit(_ account: Account) {
        deleteAccount(account)
    }

    // MARK: - Loan Operations

    /// Add a fully-formed loan Account (preserves computed fields in LoanInfo)
    func addLoanAccount(_ account: Account) {
        guard account.isLoan, let loanInfo = account.loanInfo else { return }

        transactionStore?.addAccount(account)

        let balance = NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.registerAccounts([account])
                await coordinator.setInitialBalance(balance, for: account.id)
            }
        }
    }

    func updateLoan(_ account: Account) {
        guard account.isLoan else { return }
        if accounts.firstIndex(where: { $0.id == account.id }) != nil {
            transactionStore?.updateAccount(account)

            if let coordinator = balanceCoordinator, let loanInfo = account.loanInfo {
                let balance = NSDecimalNumber(decimal: loanInfo.remainingPrincipal).doubleValue
                Task {
                    await coordinator.updateForAccount(account, newBalance: balance)
                    await coordinator.setInitialBalance(balance, for: account.id)
                }
            }
        }
    }

    func deleteLoan(_ account: Account) {
        deleteAccount(account)
    }

    // MARK: - Helper Methods

    /// Синхронизирует initialAccountBalances с BalanceCoordinator
    /// Вызывается при инициализации и перезагрузке для обеспечения согласованности данных
    private func syncInitialBalancesToCoordinator() {
        guard let coordinator = balanceCoordinator else { return }


        Task {
            // Register all accounts
            await coordinator.registerAccounts(accounts)

            // Set initial balances and modes based on account configuration
            for account in accounts {

                // Используем initialBalance вместо balance
                let initialBal = account.initialBalance ?? 0.0
                await coordinator.setInitialBalance(initialBal, for: account.id)

                // Only mark as manual if shouldCalculateFromTransactions is false
                if !account.shouldCalculateFromTransactions {
                    await coordinator.markAsManual(account.id)
                }
            }

        }
    }

    /// Получить счет по ID
    func getAccount(by id: String) -> Account? {
        return accounts.first { $0.id == id }
    }
    
    /// Получить все обычные счета (не депозиты и не кредиты)
    var regularAccounts: [Account] {
        return accounts.filter { !$0.isDeposit && !$0.isLoan }
    }
    
    // MIGRATED: syncAccountBalances removed - now managed by BalanceCoordinator (Single Source of Truth)
    // Balances are no longer synced manually between ViewModels
    // All balance updates go through BalanceCoordinator.updateForTransaction()


    // MARK: - Intelligent Account Ranking
    
    /// Получить счета, отсортированные по частоте использования с учетом контекста
    /// - Parameters:
    ///   - transactions: История транзакций
    ///   - type: Тип транзакции
    ///   - amount: Сумма транзакции (опционально)
    ///   - category: Категория транзакции (опционально)
    ///   - sourceAccountId: ID счета источника для переводов (опционально)
    /// - Returns: Отсортированный массив счетов
    func rankedAccounts(
        transactions: [Transaction],
        type: TransactionType,
        amount: Double? = nil,
        category: String? = nil,
        sourceAccountId: String? = nil
    ) -> [Account] {
        let context = AccountRankingContext(
            type: type,
            amount: amount,
            category: category,
            sourceAccountId: sourceAccountId
        )
        
        return AccountRankingService.rankAccounts(
            accounts: accounts,
            transactions: transactions,
            context: context
        )
    }
    
    /// Получить рекомендуемый счет для категории (адаптивное автоподставление)
    /// - Parameters:
    ///   - category: Категория транзакции
    ///   - transactions: История транзакций
    ///   - amount: Сумма транзакции (опционально)
    /// - Returns: Рекомендуемый счет или первый доступный
    func suggestedAccount(
        forCategory category: String,
        transactions: [Transaction],
        amount: Double? = nil
    ) -> Account? {
        return AccountRankingService.suggestedAccount(
            forCategory: category,
            accounts: accounts,
            transactions: transactions,
            amount: amount
        )
    }

    // MARK: - Private Helpers
    // PHASE 3: saveAccounts removed - TransactionStore handles persistence
}
