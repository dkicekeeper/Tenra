//
//  AccountsViewModel.swift
//  Tenra
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

    var accounts: [Account] {
        transactionStore?.accounts ?? []
    }

    // MARK: - Dependencies

    @ObservationIgnored var balanceCoordinator: BalanceCoordinator?

    @ObservationIgnored weak var transactionStore: TransactionStore?

    // MARK: - Private Properties

    @ObservationIgnored private let repository: DataRepositoryProtocol

    /// Cache for `suggestedAccount(forCategory:)`. Keyed by category, valid only for a specific
    /// `TransactionStore.mutationVersion`. On version mismatch the whole map is dropped.
    /// Cuts repeated form-open suggestions from O(N) over 19k tx to O(1).
    @ObservationIgnored private var suggestionCache: [String: String] = [:]
    @ObservationIgnored private var suggestionCacheVersion: Int = -1

    /// Cached filtered accounts (regular / deposit / loan). Versioned against
    /// `TransactionStore.accountsMutationVersion`; refilled on first read after invalidation.
    @ObservationIgnored private var cachedRegularAccounts: [Account] = []
    @ObservationIgnored private var cachedDepositAccounts: [Account] = []
    @ObservationIgnored private var cachedLoanAccounts: [Account] = []
    @ObservationIgnored private var filterCacheVersion: Int = -1

    // MARK: - Initialization

    init(repository: DataRepositoryProtocol = UserDefaultsRepository()) {
        self.repository = repository
    }

    /// Перезагружает все данные из хранилища (используется после импорта)
    func reloadFromStorage() {
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

        transactionStore?.addAccount(account)

        // Register account with BalanceCoordinator
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
        transactionStore?.deleteAccount(account.id)
        // Note: Transaction deletion is handled by the calling view

        // Remove account from BalanceCoordinator
        if let coordinator = balanceCoordinator {
            Task {
                await coordinator.removeAccount(account.id)
            }
        }
    }

    func deleteAccounts(_ ids: Set<String>, deleteTransactions: Bool) async {
        if deleteTransactions {
            let accountsToDelete = accounts.filter { ids.contains($0.id) }
            for account in accountsToDelete {
                await transactionStore?.deleteTransactions(forAccountId: account.id)
            }
        }

        // Single batch delete + single persist (avoids savingInProgress race)
        transactionStore?.deleteAccounts(ids)

        // Remove all from BalanceCoordinator
        if let coordinator = balanceCoordinator {
            for id in ids {
                await coordinator.removeAccount(id)
            }
        }
    }

    // MARK: - Account Balance Management

    func getInitialBalance(for accountId: String) -> Double? {
        return accounts.first(where: { $0.id == accountId })?.initialBalance
    }

    func setInitialBalance(_ balance: Double, for accountId: String) {
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

        transactionStore?.addAccount(account)

        // Register deposit with BalanceCoordinator
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
            transactionStore?.updateAccount(account)

            // Update deposit in BalanceCoordinator
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

    /// Получить счет по ID — O(1) via TransactionStore.accountById index.
    /// Falls back to a linear scan only if the store hasn't been wired yet (e.g. tests).
    func getAccount(by id: String) -> Account? {
        if let store = transactionStore {
            return store.accountById[id]
        }
        return accounts.first { $0.id == id }
    }
    
    /// Получить все обычные счета (не депозиты и не кредиты).
    /// Кешируется по `TransactionStore.accountsMutationVersion` — пересчёт только при
    /// реальном изменении массива accounts, а не на каждый body re-eval вьюшки.
    var regularAccounts: [Account] {
        ensureFilterCachesValid()
        return cachedRegularAccounts
    }

    /// Все депозитные счета. См. `regularAccounts` про правило кеша.
    var depositAccounts: [Account] {
        ensureFilterCachesValid()
        return cachedDepositAccounts
    }

    /// Все кредитные счета. См. `regularAccounts` про правило кеша.
    var loanAccounts: [Account] {
        ensureFilterCachesValid()
        return cachedLoanAccounts
    }

    /// Refills the regular/deposit/loan caches if `accountsMutationVersion` advanced
    /// since the last refill. Single O(N=accounts.count) pass replaces three separate
    /// `.filter` walks per access (and per body re-eval).
    private func ensureFilterCachesValid() {
        let currentVersion = transactionStore?.accountsMutationVersion ?? 0
        guard currentVersion != filterCacheVersion else { return }
        filterCacheVersion = currentVersion
        let all = accounts
        var regular: [Account] = []
        var deposits: [Account] = []
        var loans: [Account] = []
        regular.reserveCapacity(all.count)
        for account in all {
            if account.isDeposit {
                deposits.append(account)
            } else if account.isLoan {
                loans.append(account)
            } else {
                regular.append(account)
            }
        }
        cachedRegularAccounts = regular
        cachedDepositAccounts = deposits
        cachedLoanAccounts = loans
    }

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
            transactionsByAccount: transactionStore?.transactionsByAccount,
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
        // Cache only the no-amount path. The amount-aware path needs to recheck balances,
        // which can change without a tx mutation (FX rate refreshes, etc.).
        let canCache = amount == nil
        if canCache, let store = transactionStore {
            if store.mutationVersion != suggestionCacheVersion {
                suggestionCache.removeAll(keepingCapacity: true)
                suggestionCacheVersion = store.mutationVersion
            }
            if let cachedId = suggestionCache[category],
               let cached = store.accountById[cachedId] {
                return cached
            }
        }

        let result = AccountRankingService.suggestedAccount(
            forCategory: category,
            accounts: accounts,
            transactions: transactions,
            transactionsByAccount: transactionStore?.transactionsByAccount,
            amount: amount
        )

        if canCache, let id = result?.id {
            suggestionCache[category] = id
        }
        return result
    }

    // MARK: - Private Helpers
}
