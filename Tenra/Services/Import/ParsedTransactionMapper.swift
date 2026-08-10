//
//  ParsedTransactionMapper.swift
//  Tenra
//
//  ParsedTransaction (bank-agnostic recognition output) -> Transaction (the
//  app's canonical model), so a recognized statement can be reviewed as real
//  transaction cards in ImportTransactionPreviewView instead of the CSV
//  preview / column-mapping flow.
//
//  Amounts stay positive; direction lives entirely in TransactionType, per
//  the SummaryContribution rule (Tenra/Models/SummaryContribution.swift) —
//  never negate an amount here to express direction.
//
//  accountId is deliberately left nil: ImportTransactionPreviewView assigns
//  it per row, defaulted by currency.
//

import Foundation

nonisolated enum ParsedTransactionMapper {

    static func transactions(from statement: ParsedStatement, defaultCurrency: String) -> [Transaction] {
        statement.transactions.map { transaction(from: $0, defaultCurrency: defaultCurrency) }
    }

    private static func transaction(from parsed: ParsedTransaction, defaultCurrency: String) -> Transaction {
        let type = transactionType(for: parsed.direction)
        return Transaction(
            id: UUID().uuidString,
            date: parsed.date,
            description: parsed.descriptionText,
            amount: parsed.amount,
            currency: parsed.currency ?? defaultCurrency,
            type: type,
            category: category(for: type),
            accountId: nil
        )
    }

    private static func transactionType(for direction: TransactionDirection) -> TransactionType {
        switch direction {
        case .income: return .income
        case .expense: return .expense
        case .transfer: return .internalTransfer
        }
    }

    /// Mirrors the "uncategorized" convention CSV/voice/receipt import already
    /// use for account-less, category-less transactions (`TransactionStore.validate`
    /// explicitly allows an empty category) — except internal transfers, which
    /// must carry the locale-independent canonical category name so aggregates
    /// group them correctly (`TransactionStore.transfer`).
    private static func category(for type: TransactionType) -> String {
        type == .internalTransfer ? TransactionType.transferCategoryName : ""
    }
}
