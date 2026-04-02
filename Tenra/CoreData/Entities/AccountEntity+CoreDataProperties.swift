//
//  AccountEntity+CoreDataProperties.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData


public typealias AccountEntityCoreDataPropertiesSet = NSSet

extension AccountEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AccountEntity> {
        return NSFetchRequest<AccountEntity>(entityName: "AccountEntity")
    }

    @NSManaged public nonisolated var balance: Double         // Current balance (updated incrementally)
    @NSManaged public nonisolated var initialBalance: Double  // Balance at account creation (never changes)
    @NSManaged public nonisolated var bankName: String?
    @NSManaged public nonisolated var createdAt: Date?
    @NSManaged public nonisolated var currency: String?
    @NSManaged public nonisolated var depositInfoData: Data?  // Stores full DepositInfo as JSON (v5)
    @NSManaged public nonisolated var id: String?
    @NSManaged public nonisolated var isDeposit: Bool
    @NSManaged public nonisolated var isLoan: Bool
    @NSManaged public nonisolated var loanInfoData: Data?     // Stores full LoanInfo as JSON (v6)
    @NSManaged public nonisolated var logo: String?  // Deprecated: Use iconSourceData instead
    @NSManaged public nonisolated var iconSourceData: Data?  // Stores full IconSource as JSON
    @NSManaged public nonisolated var name: String?
    @NSManaged public nonisolated var shouldCalculateFromTransactions: Bool  // ✨ Phase 10: Track balance calculation mode
    @NSManaged public nonisolated var targetTransactions: NSSet?
    @NSManaged public nonisolated var transactions: NSSet?

}

// MARK: Generated accessors for targetTransactions
extension AccountEntity {

    @objc(addTargetTransactionsObject:)
    @NSManaged public nonisolated func addToTargetTransactions(_ value: TransactionEntity)

    @objc(removeTargetTransactionsObject:)
    @NSManaged public nonisolated func removeFromTargetTransactions(_ value: TransactionEntity)

    @objc(addTargetTransactions:)
    @NSManaged public nonisolated func addToTargetTransactions(_ values: NSSet)

    @objc(removeTargetTransactions:)
    @NSManaged public nonisolated func removeFromTargetTransactions(_ values: NSSet)

}

// MARK: Generated accessors for transactions
extension AccountEntity {

    @objc(addTransactionsObject:)
    @NSManaged public nonisolated func addToTransactions(_ value: TransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public nonisolated func removeFromTransactions(_ value: TransactionEntity)

    @objc(addTransactions:)
    @NSManaged public nonisolated func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public nonisolated func removeFromTransactions(_ values: NSSet)

}

extension AccountEntity : Identifiable {

}
