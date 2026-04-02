//
//  BalanceCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of Balance Refactoring Phase 4
//  Cleaned up in Phase 36: removed queue/cache/statistics infra
//
//  Protocol for balance coordination
//  Single entry point for all balance operations
//

import Foundation

// MARK: - Balance Coordinator Protocol

/// Protocol for coordinating balance calculations and updates
/// Provides a unified interface for balance management across the app
@MainActor
protocol BalanceCoordinatorProtocol: AnyObject {

    // MARK: - Published State

    /// Current balances for all accounts
    /// UI components observe this for real-time updates
    var balances: [String: Double] { get }

    // MARK: - Account Management

    /// Register accounts with the coordinator.
    /// Uses persisted `account.balance` for instant zero-delay display.
    /// - Parameter accounts: Array of accounts to register
    func registerAccounts(_ accounts: [Account]) async

    /// Remove account from coordinator
    /// - Parameter accountId: Account ID to remove
    func removeAccount(_ accountId: String) async

    // MARK: - Transaction Updates

    /// Update balances for a transaction operation
    /// - Parameters:
    ///   - transaction: The transaction
    ///   - operation: Operation type (add/remove/update)
    func updateForTransaction(
        _ transaction: Transaction,
        operation: TransactionUpdateOperation
    ) async

    /// Update balances for multiple transactions (batch)
    /// - Parameters:
    ///   - transactions: Array of transactions
    ///   - operation: Operation type
    func updateForTransactions(
        _ transactions: [Transaction],
        operation: TransactionUpdateOperation
    ) async

    // MARK: - Account Updates

    /// Update balance for account directly
    /// - Parameters:
    ///   - account: The account
    ///   - newBalance: New balance value
    func updateForAccount(
        _ account: Account,
        newBalance: Double
    ) async

    /// Update deposit info for account
    /// - Parameters:
    ///   - account: The account
    ///   - depositInfo: Updated deposit info
    func updateDepositInfo(
        _ account: Account,
        depositInfo: DepositInfo
    ) async

    // MARK: - Recalculation

    /// Recalculate all balances from scratch
    /// - Parameters:
    ///   - accounts: All accounts
    ///   - transactions: All transactions
    func recalculateAll(
        accounts: [Account],
        transactions: [Transaction]
    ) async

    /// Recalculate balances for specific accounts
    /// - Parameters:
    ///   - accountIds: Set of account IDs to recalculate
    ///   - accounts: All accounts
    ///   - transactions: All transactions
    func recalculateAccounts(
        _ accountIds: Set<String>,
        accounts: [Account],
        transactions: [Transaction]
    ) async

    // MARK: - Optimistic Updates

    /// Apply optimistic update (instant UI feedback)
    /// - Parameters:
    ///   - accountId: Account ID
    ///   - delta: Balance change amount
    /// - Returns: Operation ID for potential revert
    func optimisticUpdate(
        accountId: String,
        delta: Double
    ) async -> UUID

    /// Revert optimistic update
    /// - Parameter operationId: Operation ID from optimisticUpdate
    func revertOptimisticUpdate(_ operationId: UUID) async

    // MARK: - Calculation Modes

    /// Mark account as imported (transactions already in balance)
    /// - Parameter accountId: Account ID
    func markAsImported(_ accountId: String) async

    /// Mark account as manual (transactions need to be applied)
    /// - Parameter accountId: Account ID
    func markAsManual(_ accountId: String) async

    /// Set initial balance for account
    /// - Parameters:
    ///   - balance: Initial balance
    ///   - accountId: Account ID
    func setInitialBalance(_ balance: Double, for accountId: String) async

    /// Get initial balance for account
    /// - Parameter accountId: Account ID
    /// - Returns: Initial balance if set
    func getInitialBalance(for accountId: String) async -> Double?
}
