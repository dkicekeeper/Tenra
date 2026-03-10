//
//  BalanceStore.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 1
//
//  SINGLE SOURCE OF TRUTH for account balances
//  Thread-safe state management with @MainActor
//

import Foundation
import Observation

// MARK: - Account Balance Model

/// Represents an account's balance state
struct AccountBalance: Equatable, Identifiable {
    let accountId: String
    var currentBalance: Double
    var initialBalance: Double?
    var depositInfo: DepositInfo?
    let currency: String
    let isDeposit: Bool

    var id: String { accountId }

    init(
        accountId: String,
        currentBalance: Double,
        initialBalance: Double? = nil,
        depositInfo: DepositInfo? = nil,
        currency: String,
        isDeposit: Bool = false
    ) {
        self.accountId = accountId
        self.currentBalance = currentBalance
        self.initialBalance = initialBalance
        self.depositInfo = depositInfo
        self.currency = currency
        self.isDeposit = isDeposit
    }

    /// Create AccountBalance from Account model
    static func from(_ account: Account) -> AccountBalance {
        return AccountBalance(
            accountId: account.id,
            currentBalance: account.balance,
            initialBalance: account.initialBalance,
            depositInfo: account.depositInfo,
            currency: account.currency,
            isDeposit: account.isDeposit
        )
    }
}

// MARK: - Balance Calculation Mode

/// Determines how balance should be calculated for an account
/// NOTE: This is separate from BalanceCalculationService's version for new architecture
enum BalanceMode: Equatable {
    /// Manual accounts: balance = initialBalance + Σtransactions
    /// Used for accounts created manually with a specified initial balance
    case fromInitialBalance

    /// Imported accounts: transactions are already factored into current balance
    /// Used for accounts imported from CSV where balance already includes all transactions
    case preserveImported
}

// MARK: - Balance Update Operation

/// Represents a balance update operation
struct BalanceStoreUpdate: Equatable, Identifiable {
    let id: UUID
    let accountId: String
    let newBalance: Double
    let source: Source
    let timestamp: Date

    enum Source: Equatable {
        case transaction(String)      // Transaction ID
        case recalculation
        case csvImport
        case manual
        case deposit
    }

    init(
        accountId: String,
        newBalance: Double,
        source: Source,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.newBalance = newBalance
        self.source = source
        self.timestamp = timestamp
    }
}

// MARK: - Balance Store

/// Thread-safe store for account balances
/// SINGLE SOURCE OF TRUTH - all balance data flows through this store
/// ✅ MIGRATED 2026-02-12: Now using @Observable instead of ObservableObject
@Observable
@MainActor
final class BalanceStore {

    // MARK: - Observable State

    /// Current balances for all accounts
    /// UI components observe this for real-time updates
    /// ✅ No @Published needed - @Observable provides automatic tracking
    private(set) var balances: [String: Double] = [:]

    // MARK: - Private State

    /// Detailed account balance information
    private var accounts: [String: AccountBalance] = [:]

    /// Calculation mode for each account
    private var calculationModes: [String: BalanceMode] = [:]

    /// History of balance updates (for debugging/auditing)
    /// Phase 36: @ObservationIgnored — history mutations must not trigger UI re-renders
    @ObservationIgnored private var updateHistory: [BalanceStoreUpdate] = []
    @ObservationIgnored private let maxHistorySize: Int = 100

    // MARK: - Initialization

    init() {
    }

    // MARK: - Account Management

    /// Register an account in the store
    func registerAccount(_ account: AccountBalance) {
        accounts[account.accountId] = account
        balances[account.accountId] = account.currentBalance

    }

    /// Register multiple accounts
    func registerAccounts(_ accountList: [AccountBalance]) {
        for account in accountList {
            accounts[account.accountId] = account
            balances[account.accountId] = account.currentBalance
        }

    }

    /// Remove account from store
    func removeAccount(_ accountId: String) {
        accounts.removeValue(forKey: accountId)
        balances.removeValue(forKey: accountId)
        calculationModes.removeValue(forKey: accountId)

    }

    /// Get account details
    func getAccount(_ accountId: String) -> AccountBalance? {
        return accounts[accountId]
    }

    /// Get all accounts
    func getAllAccounts() -> [AccountBalance] {
        return Array(accounts.values)
    }

    // MARK: - Balance Operations

    /// Set balance for a specific account
    func setBalance(
        _ balance: Double,
        for accountId: String,
        source: BalanceStoreUpdate.Source = .manual
    ) {
        guard var account = accounts[accountId] else {
            return
        }

        account.currentBalance = balance
        accounts[accountId] = account
        balances[accountId] = balance

        recordUpdate(BalanceStoreUpdate(
            accountId: accountId,
            newBalance: balance,
            source: source
        ))

    }

    /// Get current balance for account
    func getBalance(for accountId: String) -> Double? {
        return balances[accountId]
    }

    /// Update multiple balances atomically
    func updateBalances(
        _ updates: [String: Double],
        source: BalanceStoreUpdate.Source = .recalculation
    ) {
        var updatedCount = 0

        for (accountId, newBalance) in updates {
            guard var account = accounts[accountId] else { continue }

            account.currentBalance = newBalance
            accounts[accountId] = account
            balances[accountId] = newBalance

            recordUpdate(BalanceStoreUpdate(
                accountId: accountId,
                newBalance: newBalance,
                source: source
            ))

            updatedCount += 1
        }

    }

    /// Perform atomic batch update with custom logic
    func performBatchUpdate(_ block: (inout [String: AccountBalance]) -> [BalanceStoreUpdate]) {
        let updates = block(&accounts)

        // Apply updates to published balances
        for update in updates {
            balances[update.accountId] = update.newBalance
            recordUpdate(update)
        }

    }

    // MARK: - Calculation Mode Management

    /// Set calculation mode for account
    func setCalculationMode(_ mode: BalanceMode, for accountId: String) {
        calculationModes[accountId] = mode

    }

    /// Get calculation mode for account
    func getCalculationMode(for accountId: String) -> BalanceMode {
        return calculationModes[accountId] ?? .fromInitialBalance
    }

    /// Mark account as imported (transactions already in balance)
    func markAsImported(_ accountId: String) {
        setCalculationMode(.preserveImported, for: accountId)
    }

    /// Mark account as manual (transactions need to be applied)
    func markAsManual(_ accountId: String) {
        setCalculationMode(.fromInitialBalance, for: accountId)
    }

    /// Check if account is imported
    func isImported(_ accountId: String) -> Bool {
        return getCalculationMode(for: accountId) == .preserveImported
    }

    // MARK: - Initial Balance Management

    /// Set initial balance for account
    func setInitialBalance(_ balance: Double, for accountId: String) {
        guard var account = accounts[accountId] else { return }

        account.initialBalance = balance
        accounts[accountId] = account

    }

    /// Get initial balance for account
    func getInitialBalance(for accountId: String) -> Double? {
        let balance = accounts[accountId]?.initialBalance


        return balance
    }

    /// Clear initial balance for account
    func clearInitialBalance(for accountId: String) {
        guard var account = accounts[accountId] else { return }

        account.initialBalance = nil
        accounts[accountId] = account

    }

    // MARK: - Deposit Info Management

    /// Update deposit info for account
    func updateDepositInfo(_ depositInfo: DepositInfo, for accountId: String) {
        guard var account = accounts[accountId] else { return }

        account.depositInfo = depositInfo
        accounts[accountId] = account

        // Recalculate deposit balance
        var totalBalance: Decimal = depositInfo.principalBalance
        if !depositInfo.capitalizationEnabled {
            totalBalance += depositInfo.interestAccruedNotCapitalized
        }

        let newBalance = NSDecimalNumber(decimal: totalBalance).doubleValue
        balances[accountId] = newBalance

        recordUpdate(BalanceStoreUpdate(
            accountId: accountId,
            newBalance: newBalance,
            source: .deposit
        ))

    }

    // MARK: - State Management

    /// Clear all data
    func reset() {
        accounts.removeAll()
        balances.removeAll()
        calculationModes.removeAll()
        updateHistory.removeAll()

    }

    /// Get current state snapshot
    func snapshot() -> BalanceStoreSnapshot {
        return BalanceStoreSnapshot(
            accounts: accounts,
            balances: balances,
            calculationModes: calculationModes,
            updateHistory: updateHistory
        )
    }

    /// Restore from snapshot
    func restore(from snapshot: BalanceStoreSnapshot) {
        accounts = snapshot.accounts
        balances = snapshot.balances
        calculationModes = snapshot.calculationModes
        updateHistory = snapshot.updateHistory

    }

    // MARK: - Private Helpers

    /// Record update in history
    private func recordUpdate(_ update: BalanceStoreUpdate) {
        updateHistory.append(update)

        // Maintain max history size
        if updateHistory.count > maxHistorySize {
            updateHistory.removeFirst(updateHistory.count - maxHistorySize)
        }
    }
}

// MARK: - Balance Store Snapshot

/// Snapshot of BalanceStore state (for backup/restore)
struct BalanceStoreSnapshot {
    let accounts: [String: AccountBalance]
    let balances: [String: Double]
    let calculationModes: [String: BalanceMode]
    let updateHistory: [BalanceStoreUpdate]
}

// MARK: - Debug Extension

