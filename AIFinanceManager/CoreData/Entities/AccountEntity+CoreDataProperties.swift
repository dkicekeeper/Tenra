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

    @NSManaged public var balance: Double         // Current balance (updated incrementally)
    @NSManaged public var initialBalance: Double  // Balance at account creation (never changes)
    @NSManaged public var bankName: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var currency: String?
    @NSManaged public var depositInfoData: Data?  // Stores full DepositInfo as JSON (v5)
    @NSManaged public var id: String?
    @NSManaged public var isDeposit: Bool
    @NSManaged public var isLoan: Bool
    @NSManaged public var loanInfoData: Data?     // Stores full LoanInfo as JSON (v6)
    @NSManaged public var logo: String?  // Deprecated: Use iconSourceData instead
    @NSManaged public var iconSourceData: Data?  // Stores full IconSource as JSON
    @NSManaged public var name: String?
    @NSManaged public var shouldCalculateFromTransactions: Bool  // ✨ Phase 10: Track balance calculation mode
    @NSManaged public var targetTransactions: NSSet?
    @NSManaged public var transactions: NSSet?

}

// MARK: Generated accessors for targetTransactions
extension AccountEntity {

    @objc(addTargetTransactionsObject:)
    @NSManaged public func addToTargetTransactions(_ value: TransactionEntity)

    @objc(removeTargetTransactionsObject:)
    @NSManaged public func removeFromTargetTransactions(_ value: TransactionEntity)

    @objc(addTargetTransactions:)
    @NSManaged public func addToTargetTransactions(_ values: NSSet)

    @objc(removeTargetTransactions:)
    @NSManaged public func removeFromTargetTransactions(_ values: NSSet)

}

// MARK: Generated accessors for transactions
extension AccountEntity {

    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: TransactionEntity)

    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: TransactionEntity)

    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)

    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)

}

extension AccountEntity : Identifiable {

}
