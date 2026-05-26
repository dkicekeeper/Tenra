//
//  BalanceCalculationEngine.swift
//  Tenra
//
//  Created on 2026-02-02
//
//  Pure functions for balance calculations.
//  Stateless, testable, reusable logic.
//

import Foundation

// MARK: - Realized-Date Rule (single source of truth)

/// The one definition of "realized" used across the data layer: a transaction
/// affects current/realized figures (balance AND account/category aggregates)
/// iff its date is on or before today. Future-dated rows (incl. generated
/// recurring occurrences) are excluded until their date arrives. Centralised here
/// so balance and every aggregate path apply the exact same cutoff.
enum LedgerPolicyRule {
    /// Pure, no shared mutable state — safe to call from any actor.
    /// Marked `nonisolated` explicitly because the project default isolation is
    /// MainActor; without this annotation, background-thread callers (the
    /// detached snapshot builder in TransactionStore+LoadSnapshot, InsightsService
    /// nonisolated paths) trigger Swift 6 isolation warnings on every call.
    nonisolated static func isRealized(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date <= Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Update Operation

/// Represents a transaction update operation
enum TransactionUpdateOperation: Equatable {
    case add(Transaction)
    case remove(Transaction)
    case update(old: Transaction, new: Transaction)
}

// MARK: - Balance Calculation Engine

/// Pure, stateless balance calculation logic
/// All functions are thread-safe and have no side effects
struct BalanceCalculationEngine {

    // MARK: - Dependencies

    /// Cache manager for optimized date parsing
    private let cacheManager: TransactionCacheManager?

    // MARK: - Initialization

    init(cacheManager: TransactionCacheManager? = nil) {
        self.cacheManager = cacheManager
    }

    // MARK: - Full Balance Calculation

    /// Calculate balance for an account from scratch
    /// - Parameters:
    ///   - account: The account to calculate balance for
    ///   - transactions: All transactions to consider
    ///   - mode: Calculation mode (fromInitialBalance or preserveImported)
    /// - Returns: Calculated balance
    func calculateBalance(
        account: AccountBalance,
        transactions: [Transaction],
        mode: BalanceMode
    ) -> Double {
        switch mode {
        case .preserveImported:
            // For imported accounts, balance is already correct
            // New transactions should be applied incrementally
            return account.currentBalance

        case .fromInitialBalance:
            // Calculate from initial balance + transactions
            guard let initialBalance = account.initialBalance else {
                // No initial balance set, return current
                return account.currentBalance
            }

            // Full recalc is just Σ of the SAME per-transaction contribution the
            // incremental path applies — so the two cannot diverge by construction.
            var balance = initialBalance
            for tx in transactions {
                balance += contribution(of: tx, to: account, policy: .currentBalance)
            }
            return balance
        }
    }

    // MARK: - Future-Date Gate

    /// Whether a transaction should affect the *current* balance.
    ///
    /// Mirrors the `txDate <= today` guard in `calculateBalanceFromInitial`: future-dated
    /// transactions are excluded from the current balance. The incremental add/remove/update
    /// callers MUST consult this before applying a delta — otherwise a future tx that full
    /// recalculation excluded can still be added/reverted incrementally, silently shifting
    /// the balance (e.g. deleting an imported future expense inflates the account).
    /// Unparseable dates are excluded too, matching the recalc guard.
    func affectsCurrentBalance(_ transaction: Transaction) -> Bool {
        LedgerPolicyRule.isRealized(parseDate(transaction.date))
    }

    // MARK: - Transaction Contribution (single source of truth)

    /// Eligibility policy for a transaction's contribution to a balance.
    enum LedgerPolicy {
        /// Realized / current balance: exclude future-dated tx and deposit events
        /// on/before the deposit's startDate (baked into the initial principal).
        case currentBalance
        /// Raw arithmetic with no temporal gating.
        case allTime
    }

    /// THE single definition of how one transaction moves one account's balance.
    ///
    /// Every balance path — full recalculation and incremental add/remove/update —
    /// derives from this one function, so they cannot disagree. The per-type signed
    /// table and the eligibility gates (`txDate <= today`, deposit `startDate` cutoff)
    /// live here exactly once. Returns 0 when the transaction does not touch `account`
    /// or is gated out by `policy`.
    func contribution(
        of tx: Transaction,
        to account: AccountBalance,
        policy: LedgerPolicy
    ) -> Double {
        if policy == .currentBalance {
            guard affectsCurrentBalance(tx) else { return 0 }
            // Deposit events on/before startDate are already in initialPrincipal.
            if account.isDeposit, let cutoff = account.depositInfo?.startDate, tx.date <= cutoff {
                return 0
            }
        }

        let accountId = account.accountId
        let currency = account.currency

        switch tx.type {
        case .income:
            return tx.accountId == accountId ? getTransactionAmount(tx, for: currency) : 0

        case .expense:
            return tx.accountId == accountId ? -getTransactionAmount(tx, for: currency) : 0

        case .internalTransfer:
            if tx.accountId == accountId { return -getSourceAmount(tx) }
            if tx.targetAccountId == accountId { return getTargetAmount(tx) }
            return 0

        case .depositTopUp, .depositInterestAccrual:
            return tx.accountId == accountId ? getTransactionAmount(tx, for: currency) : 0

        case .depositWithdrawal:
            return tx.accountId == accountId ? -getTransactionAmount(tx, for: currency) : 0

        case .loanPayment, .loanEarlyRepayment:
            // Source bank leg: the full payment (principal + interest) left this account.
            if tx.accountId == accountId {
                return -getTransactionAmount(tx, for: currency)
            }
            // Loan (target) leg contributes nothing: the loan account's balance is the
            // outstanding debt (loanInfo.remainingPrincipal), which a payment reduces only
            // by its principal portion — interest is a bank expense, not debt reduction.
            // The debt is sourced from remainingPrincipal in recalc / registerAccounts,
            // not from summing payment legs. See BalanceCoordinator loan handling.
            return 0
        }
    }

    // MARK: - Incremental Updates (O(1))

    /// Apply a single transaction to a balance (incremental update)
    /// Much faster than full recalculation - O(1) vs O(n)
    /// - Parameters:
    ///   - transaction: The transaction to apply
    ///   - currentBalance: Current balance before transaction
    ///   - account: The account
    ///   - isSource: true if this is the source account for transfers
    /// - Returns: New balance after applying transaction
    func applyTransaction(
        _ transaction: Transaction,
        to currentBalance: Double,
        for account: AccountBalance,
        isSource: Bool = true
    ) -> Double {
        // Pure arithmetic helper: apply the contribution unconditionally (no temporal
        // gating). Source/target is resolved by account-id matching inside `contribution`.
        return currentBalance + contribution(of: transaction, to: account, policy: .allTime)
    }

    /// Revert a transaction from a balance (undo operation)
    /// - Parameters:
    ///   - transaction: The transaction to revert
    ///   - currentBalance: Current balance before revert
    ///   - account: The account
    ///   - isSource: true if this is the source account for transfers
    /// - Returns: New balance after reverting transaction
    func revertTransaction(
        _ transaction: Transaction,
        from currentBalance: Double,
        for account: AccountBalance,
        isSource: Bool = true
    ) -> Double {
        return currentBalance - contribution(of: transaction, to: account, policy: .allTime)
    }

    /// Calculate delta for incremental update
    /// - Parameters:
    ///   - operation: The update operation (add/remove/update)
    ///   - accountId: The account ID
    ///   - accountCurrency: The account currency
    /// - Returns: Balance delta to apply
    func calculateDelta(
        for operation: TransactionUpdateOperation,
        accountId: String,
        accountCurrency: String
    ) -> Double {
        switch operation {
        case .add(let transaction):
            return calculateTransactionDelta(
                transaction,
                accountId: accountId,
                accountCurrency: accountCurrency,
                isAdding: true
            )

        case .remove(let transaction):
            return calculateTransactionDelta(
                transaction,
                accountId: accountId,
                accountCurrency: accountCurrency,
                isAdding: false
            )

        case .update(let oldTx, let newTx):
            // Revert old, apply new
            let revertDelta = calculateTransactionDelta(
                oldTx,
                accountId: accountId,
                accountCurrency: accountCurrency,
                isAdding: false
            )
            let applyDelta = calculateTransactionDelta(
                newTx,
                accountId: accountId,
                accountCurrency: accountCurrency,
                isAdding: true
            )
            return revertDelta + applyDelta
        }
    }

    /// Calculate delta for a single transaction
    private func calculateTransactionDelta(
        _ transaction: Transaction,
        accountId: String,
        accountCurrency: String,
        isAdding: Bool
    ) -> Double {
        let account = AccountBalance(accountId: accountId, currentBalance: 0, currency: accountCurrency)
        let delta = contribution(of: transaction, to: account, policy: .allTime)
        return isAdding ? delta : -delta
    }

    // MARK: - Initial Balance Calculation

    /// Calculate initial balance from current balance and transactions
    /// Formula: initialBalance = currentBalance - Σtransactions
    /// - Parameters:
    ///   - currentBalance: Current account balance
    ///   - accountId: Account ID
    ///   - accountCurrency: Account currency
    ///   - transactions: All transactions for this account
    /// - Returns: Calculated initial balance
    func calculateInitialBalance(
        currentBalance: Double,
        accountId: String,
        accountCurrency: String,
        transactions: [Transaction]
    ) -> Double {
        var transactionsSum: Double = 0

        for tx in transactions {
            switch tx.type {
            case .income:
                if tx.accountId == accountId {
                    transactionsSum += getTransactionAmount(tx, for: accountCurrency)
                }
            case .expense:
                if tx.accountId == accountId {
                    transactionsSum -= getTransactionAmount(tx, for: accountCurrency)
                }
            case .internalTransfer:
                if tx.accountId == accountId {
                    transactionsSum -= getSourceAmount(tx)
                } else if tx.targetAccountId == accountId {
                    transactionsSum += getTargetAmount(tx)
                }
            case .depositTopUp, .depositWithdrawal, .depositInterestAccrual:
                break

            case .loanPayment, .loanEarlyRepayment:
                // Loan payments reduce balance on BOTH the source bank (accountId) and
                // the loan (targetAccountId after the orientation flip).
                if tx.accountId == accountId || tx.targetAccountId == accountId {
                    transactionsSum -= getTransactionAmount(tx, for: accountCurrency)
                }
            }
        }

        return currentBalance - transactionsSum
    }

    // MARK: - Private Helpers

    /// Parse date with cache support
    private func parseDate(_ dateString: String) -> Date? {
        if let cache = cacheManager {
            return cache.getParsedDate(for: dateString)
        }
        return DateFormatters.dateFormatter.date(from: dateString)
    }

    /// Get transaction amount in target currency
    /// Uses convertedAmount if transaction currency differs from account currency
    private func getTransactionAmount(_ transaction: Transaction, for targetCurrency: String) -> Double {
        // For expenses/income with different currencies, use targetAmount (converted to account currency)
        // This ensures balance updates use the correct amount in the account's currency
        if transaction.currency != targetCurrency {
            // Use targetAmount if available (amount in account currency)
            if let targetAmount = transaction.targetAmount {
                return targetAmount
            }
            // Fallback to convertedAmount for backward compatibility
            if let convertedAmount = transaction.convertedAmount {
                return convertedAmount
            }
        }
        // Same currency or no conversion available - use original amount
        return transaction.amount
    }

    /// Get source amount for internal transfer
    private func getSourceAmount(_ transaction: Transaction) -> Double {
        return transaction.convertedAmount ?? transaction.amount
    }

    /// Get target amount for internal transfer
    private func getTargetAmount(_ transaction: Transaction) -> Double {
        return transaction.targetAmount ?? transaction.convertedAmount ?? transaction.amount
    }
}

// MARK: - Debug Extension

#if DEBUG
extension BalanceCalculationEngine {
    /// Test helper: calculate balance change for account from transaction list
    func debugCalculateBalanceChange(
        accountId: String,
        accountCurrency: String,
        transactions: [Transaction]
    ) -> Double {
        var balance: Double = 0

        for tx in transactions {
            balance += calculateTransactionDelta(
                tx,
                accountId: accountId,
                accountCurrency: accountCurrency,
                isAdding: true
            )
        }

        return balance
    }
}
#endif
