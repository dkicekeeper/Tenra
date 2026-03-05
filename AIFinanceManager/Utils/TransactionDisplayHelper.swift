//
//  TransactionDisplayHelper.swift
//  AIFinanceManager
//
//  Phase 16 (2026-02-17): Centralized display logic for transactions.
//  Eliminates duplication between TransactionCard and other transaction display components.
//
//  Usage:
//  ```swift
//  TransactionDisplayHelper.amountColor(for: transaction.type)
//  TransactionDisplayHelper.amountPrefix(for: transaction.type)
//  TransactionDisplayHelper.isFutureDate(transaction.date)
//  ```
//

import SwiftUI

/// Centralized display helpers for transaction UI rendering.
/// Shared between TransactionCard, TransferAmountView, and any other transaction display components.
enum TransactionDisplayHelper {

    // MARK: - Amount Color

    /// Returns the appropriate foreground color for an amount based on transaction type.
    static func amountColor(for type: TransactionType) -> Color {
        switch type {
        case .income:
            return .green
        case .expense:
            return .primary
        case .internalTransfer:
            return .primary
        case .depositTopUp, .depositInterestAccrual:
            return .green
        case .depositWithdrawal:
            return .primary
        case .loanPayment, .loanEarlyRepayment:
            return .primary
        }
    }

    /// Returns the amount color with deposit-context awareness.
    /// When a depositAccountId is provided, direction (incoming/outgoing) determines color.
    static func amountColor(
        for type: TransactionType,
        targetAccountId: String?,
        depositAccountId: String?,
        isPlanned: Bool = false
    ) -> Color {
        if isPlanned { return .blue }

        if let depositId = depositAccountId, type == .internalTransfer {
            let isIncoming = targetAccountId == depositId
            return isIncoming ? .green : .primary
        }

        return amountColor(for: type)
    }

    // MARK: - Amount Prefix

    /// Returns the amount prefix string (+/-) for a transaction type.
    static func amountPrefix(for type: TransactionType) -> String {
        switch type {
        case .income:
            return "+"
        case .expense:
            return "-"
        case .internalTransfer:
            return ""
        case .depositTopUp, .depositInterestAccrual:
            return "+"
        case .depositWithdrawal:
            return "-"
        case .loanPayment, .loanEarlyRepayment:
            return "-"
        }
    }

    /// Returns the amount prefix with deposit-context and planned-state awareness.
    static func amountPrefix(
        for type: TransactionType,
        targetAccountId: String?,
        depositAccountId: String?,
        isPlanned: Bool = false
    ) -> String {
        if isPlanned { return "+" }

        if let depositId = depositAccountId {
            if type == .depositInterestAccrual {
                return "+"
            } else if type == .internalTransfer {
                let isIncoming = targetAccountId == depositId
                return isIncoming ? "+" : "-"
            }
        }

        return amountPrefix(for: type)
    }

    // MARK: - Future Date Detection

    /// Returns true if the transaction date is strictly in the future (after today's start of day).
    static func isFutureDate(_ dateString: String) -> Bool {
        guard let transactionDate = DateFormatters.dateFormatter.date(from: dateString) else {
            return false
        }
        let today = Calendar.current.startOfDay(for: Date())
        return transactionDate > today
    }

    /// Returns the display opacity for a transaction: 0.5 for future dates, 1.0 otherwise.
    static func displayOpacity(for dateString: String) -> Double {
        isFutureDate(dateString) ? 0.5 : 1.0
    }

    // MARK: - Accessibility

    /// Builds the full accessibility description for a transaction.
    static func accessibilityText(
        for transaction: Transaction,
        accounts: [Account]
    ) -> String {
        let typeText: String
        switch transaction.type {
        case .income:
            typeText = String(localized: "transactionType.income")
        case .expense:
            typeText = String(localized: "transactionType.expense")
        default:
            typeText = String(localized: "transactionType.transfer")
        }

        let amountText = Formatting.formatCurrency(transaction.amount, currency: transaction.currency)
        var text = "\(typeText), \(transaction.category), \(amountText)"

        if transaction.type == .internalTransfer {
            if let sourceId = transaction.accountId,
               let source = accounts.first(where: { $0.id == sourceId }) {
                text += ", from \(source.name)"
            }
            if let targetId = transaction.targetAccountId,
               let target = accounts.first(where: { $0.id == targetId }) {
                text += ", to \(target.name)"
            }
        } else {
            if let accountId = transaction.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                text += ", \(account.name)"
            }
        }

        if !transaction.description.isEmpty {
            text += ", \(transaction.description)"
        }

        if transaction.recurringSeriesId != nil {
            text += ", \(String(localized: "transaction.recurring"))"
        }

        return text
    }
}
