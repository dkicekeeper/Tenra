//
//  TransactionFingerprint.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  CSV Import Refactoring - Duplicate Detection
//

import Foundation

/// Fingerprint for transaction duplicate detection
/// Compares transactions by date, amount, description, and accountId
struct TransactionFingerprint: Hashable {
    let date: String
    let amount: Double
    let description: String
    let accountId: String

    init(from transaction: Transaction) {
        self.date = transaction.date
        self.amount = transaction.amount
        self.description = transaction.description.lowercased().trimmingCharacters(in: .whitespaces)
        self.accountId = transaction.accountId ?? ""
    }
}
