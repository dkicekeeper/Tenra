//
//  TransactionIDGenerator.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct TransactionIDGenerator {
    nonisolated static func generateID(for transaction: Transaction) -> String {
        let normalizedDate = transaction.date.trimmingCharacters(in: .whitespaces)
        let normalizedDescription = normalizeWhitespace(transaction.description)
        let normalizedType = normalizeWhitespace(transaction.type.rawValue)
        let normalizedCurrency = transaction.currency.trimmingCharacters(in: .whitespaces).uppercased()
        let normalizedAmount = String(format: "%.2f", transaction.amount)
        // Включаем createdAt для уникальности - позволяет создавать несколько транзакций с одинаковыми параметрами
        let createdAtString = String(format: "%.3f", transaction.createdAt) // 3 знака после запятой для миллисекунд
        
        let key = "\(normalizedDate)|\(normalizedDescription)|\(normalizedAmount)|\(normalizedType)|\(normalizedCurrency)|\(createdAtString)"
        
        return hashHex(for: key)
    }
    
    nonisolated static func generateID(date: String, description: String, amount: Double, type: TransactionType, currency: String, createdAt: TimeInterval? = nil) -> String {
        let normalizedDate = date.trimmingCharacters(in: .whitespaces)
        let normalizedDescription = normalizeWhitespace(description)
        let normalizedType = normalizeWhitespace(type.rawValue)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespaces).uppercased()
        let normalizedAmount = String(format: "%.2f", amount)
        // Включаем createdAt для уникальности, если передан
        let createdAtString = createdAt != nil ? String(format: "%.3f", createdAt!) : String(format: "%.3f", Date().timeIntervalSince1970)
        
        let key = "\(normalizedDate)|\(normalizedDescription)|\(normalizedAmount)|\(normalizedType)|\(normalizedCurrency)|\(createdAtString)"
        
        return hashHex(for: key)
    }
    
    private nonisolated static func normalizeWhitespace(_ value: String) -> String {
        return value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
    
    private nonisolated static func hashHex(for value: String) -> String {
        var hasher = Hasher()
        hasher.combine(value)
        let raw = hasher.finalize()
        let unsigned = UInt64(bitPattern: Int64(raw))
        return String(format: "%016llx", unsigned)
    }
}
