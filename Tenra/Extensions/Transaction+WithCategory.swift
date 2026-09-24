//
//  Transaction+WithCategory.swift
//  Tenra
//

import Foundation

extension Transaction {
    /// Same transaction, different category. Every other stored field is
    /// carried over unchanged (including accountName / targetAccountName /
    /// targetCurrency / targetAmount and createdAt). The legacy `subcategory`
    /// string is cleared because it belonged to the old category.
    nonisolated func withCategory(_ category: String) -> Transaction {
        Transaction(
            id: id,
            date: date,
            description: description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: type,
            category: category,
            subcategory: nil,
            accountId: accountId,
            targetAccountId: targetAccountId,
            accountName: accountName,
            targetAccountName: targetAccountName,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount,
            recurringSeriesId: recurringSeriesId,
            recurringOccurrenceId: recurringOccurrenceId,
            createdAt: createdAt
        )
    }
}
