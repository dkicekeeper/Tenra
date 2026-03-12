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

    @NSManaged nonisolated public var balance: Double         // Current balance (updated incrementally)
    @NSManaged nonisolated public var initialBalance: Double  // Balance at account creation (never changes)
    @NSManaged nonisolated public var bankName: String?
    @NSManaged nonisolated public var createdAt: Date?
    @NSManaged nonisolated public var currency: String?
    @NSManaged nonisolated public var depositInfoData: Data?  // Stores full DepositInfo as JSON (v5)
    @NSManaged nonisolated public var id: String?
    @NSManaged nonisolated public var isDeposit: Bool
    @NSManaged nonisolated public var isLoan: Bool
    @NSManaged nonisolated public var loanInfoData: Data?     // Stores full LoanInfo as JSON (v6)
    @NSManaged nonisolated public var logo: String?  // Deprecated: Use iconSourceData instead
    @NSManaged nonisolated public var iconSourceData: Data?  // Stores full IconSource as JSON
    @NSManaged nonisolated public var name: String?
    @NSManaged nonisolated public var shouldCalculateFromTransactions: Bool  // ✨ Phase 10: Track balance calculation mode
    @NSManaged nonisolated public var targetTransactions: NSSet?
    @NSManaged nonisolated public var transactions: NSSet?

}

// MARK: Generated accessors for targetTransactions
extension AccountEntity {

    @objc(addTargetTransactionsObject:)
    @NSManaged nonisolated public func addToTargetTransactions(_ value: TransactionEntity)

    @objc(removeTargetTransactionsObject:)
    @NSManaged nonisolated public func removeFromTargetTransactions(_ value: TransactionEntity)

    @objc(addTargetTransactions:)
    @NSManaged nonisolated public func addToTargetTransactions(_ values: NSSet)

    @objc(removeTargetTransactions:)
    @NSManaged nonisolated public func removeFromTargetTransactions(_ values: NSSet)

}

// MARK: Generated accessors for transactions
extension AccountEntity {

    @objc(addTransactionsObject:)
    @NSManaged nonisolated public func addToTransactions(_ value: TransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged nonisolated public func removeFromTransactions(_ value: TransactionEntity)

    @objc(addTransactions:)
    @NSManaged nonisolated public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged nonisolated public func removeFromTransactions(_ values: NSSet)

}

extension AccountEntity : Identifiable {

}
