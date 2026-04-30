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

            let calculated = calculateBalanceFromInitial(
                initialBalance: initialBalance,
                accountId: account.accountId,
                accountCurrency: account.currency,
                transactions: transactions,
                depositStartDate: account.isDeposit ? account.depositInfo?.startDate : nil
            )

            return calculated
        }
    }

    /// Calculate balance from initial balance + transactions.
    /// `depositStartDate` (when set) skips events on/before that date — they are baked
    /// into `initialBalance` for deposits and must not be double-counted.
    private func calculateBalanceFromInitial(
        initialBalance: Double,
        accountId: String,
        accountCurrency: String,
        transactions: [Transaction],
        depositStartDate: String? = nil
    ) -> Double {
        let today = Calendar.current.startOfDay(for: Date())
        var balance = initialBalance

        for tx in transactions {
            if let cutoff = depositStartDate, tx.date <= cutoff {
                continue
            }
            guard let txDate = parseDate(tx.date), txDate <= today else {
                continue
            }

            switch tx.type {
            case .income:
                if tx.accountId == accountId {
                    balance += getTransactionAmount(tx, for: accountCurrency)
                }

            case .expense:
                if tx.accountId == accountId {
                    balance -= getTransactionAmount(tx, for: accountCurrency)
                }

            case .internalTransfer:
                if tx.accountId == accountId {
                    balance -= getSourceAmount(tx)
                } else if tx.targetAccountId == accountId {
                    balance += getTargetAmount(tx)
                }

            case .depositTopUp, .depositInterestAccrual:
                if tx.accountId == accountId {
                    balance += getTransactionAmount(tx, for: accountCurrency)
                }

            case .depositWithdrawal:
                if tx.accountId == accountId {
                    balance -= getTransactionAmount(tx, for: accountCurrency)
                }

            case .loanPayment, .loanEarlyRepayment:
                // Loan payments reduce the loan account balance
                if tx.accountId == accountId {
                    balance -= getTransactionAmount(tx, for: accountCurrency)
                }
                // Manual payments also reduce the source bank account balance
                if let targetId = tx.targetAccountId, targetId == accountId {
                    balance -= getTransactionAmount(tx, for: accountCurrency)
                }
            }
        }

        return balance
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
        switch transaction.type {
        case .income:
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .expense:
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .internalTransfer:
            if isSource {
                return currentBalance - getSourceAmount(transaction)
            } else {
                return currentBalance + getTargetAmount(transaction)
            }

        case .depositTopUp, .depositInterestAccrual:
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .depositWithdrawal:
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .loanPayment, .loanEarlyRepayment:
            if transaction.accountId == account.id || transaction.targetAccountId == account.id {
                return currentBalance - getTransactionAmount(transaction, for: account.currency)
            }
            return currentBalance
        }
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
        switch transaction.type {
        case .income:
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .expense:
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .internalTransfer:
            if isSource {
                return currentBalance + getSourceAmount(transaction)
            } else {
                return currentBalance - getTargetAmount(transaction)
            }

        case .depositTopUp, .depositInterestAccrual:
            return currentBalance - getTransactionAmount(transaction, for: account.currency)

        case .depositWithdrawal:
            return currentBalance + getTransactionAmount(transaction, for: account.currency)

        case .loanPayment, .loanEarlyRepayment:
            if transaction.accountId == account.id || transaction.targetAccountId == account.id {
                return currentBalance + getTransactionAmount(transaction, for: account.currency)
            }
            return currentBalance
        }
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
        let sign: Double = isAdding ? 1.0 : -1.0

        switch transaction.type {
        case .income:
            if transaction.accountId == accountId {
                return sign * getTransactionAmount(transaction, for: accountCurrency)
            }

        case .expense:
            if transaction.accountId == accountId {
                return -sign * getTransactionAmount(transaction, for: accountCurrency)
            }

        case .internalTransfer:
            if transaction.accountId == accountId {
                // Source - subtract
                return -sign * getSourceAmount(transaction)
            } else if transaction.targetAccountId == accountId {
                // Target - add
                return sign * getTargetAmount(transaction)
            }

        case .depositTopUp, .depositInterestAccrual:
            if transaction.accountId == accountId {
                return sign * getTransactionAmount(transaction, for: accountCurrency)
            }

        case .depositWithdrawal:
            if transaction.accountId == accountId {
                return -sign * getTransactionAmount(transaction, for: accountCurrency)
            }

        case .loanPayment, .loanEarlyRepayment:
            // Loan payments reduce the loan account balance
            if transaction.accountId == accountId {
                return -sign * getTransactionAmount(transaction, for: accountCurrency)
            }
            // Manual payments also reduce the source bank account balance
            if transaction.targetAccountId == accountId {
                return -sign * getTransactionAmount(transaction, for: accountCurrency)
            }
        }

        return 0
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
                if tx.accountId == accountId {
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
