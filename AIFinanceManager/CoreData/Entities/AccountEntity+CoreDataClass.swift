//
//  AccountEntity+CoreDataClass.swift
//  AIFinanceManager
//
//  Created by Daulet K on 23.01.2026.
//
//

public import Foundation
public import CoreData

public typealias AccountEntityCoreDataClassSet = NSSet


public class AccountEntity: NSManagedObject {

}

// MARK: - Conversion Methods
extension AccountEntity {
    /// Convert to domain model
    func toAccount() -> Account {
        // Load iconSource from JSON data (new approach)
        let iconSource: IconSource?
        if let data = iconSourceData,
           let decoded = try? JSONDecoder().decode(IconSource.self, from: data) {
            iconSource = decoded
        } else if let logoString = logo, let bankLogo = BankLogo(rawValue: logoString), bankLogo != .none {
            // Fallback: Migrate from old logo field to iconSource (backward compatibility)
            iconSource = .bankLogo(bankLogo)
        } else {
            iconSource = nil
        }

        // Decode full DepositInfo from JSON data (v5+)
        let depositInfo: DepositInfo?
        if let data = depositInfoData,
           let decoded = try? JSONDecoder().decode(DepositInfo.self, from: data) {
            depositInfo = decoded
        } else {
            depositInfo = nil
        }

        // `balance`        — current running balance, updated by BalanceCoordinator on every mutation
        // `initialBalance` — balance at account creation, stored once and never overwritten
        //
        // Migration note: accounts created before this field existed will have initialBalance == 0.
        // For manual accounts that never had initialBalance set (0) but balance > 0, we can't
        // recover initialBalance, but that's fine — we only need `balance` (current) at startup.

        let resolvedInitialBalance: Double? = shouldCalculateFromTransactions ? 0.0 : initialBalance

        return Account(
            id: id ?? "",
            name: name ?? "",
            currency: currency ?? "KZT",
            iconSource: iconSource,
            depositInfo: depositInfo,
            createdDate: createdAt,
            shouldCalculateFromTransactions: shouldCalculateFromTransactions,
            initialBalance: resolvedInitialBalance,
            balance: balance  // Pass current balance separately
        )
    }

    /// Create from domain model
    nonisolated static func from(_ account: Account, context: NSManagedObjectContext) -> AccountEntity {
        let entity = AccountEntity(context: context)
        entity.id = account.id
        entity.name = account.name
        // On creation: balance = initialBalance (no transactions yet)
        let startingBalance = account.initialBalance ?? 0
        entity.balance = startingBalance
        entity.initialBalance = startingBalance  // Stored separately — never overwritten after creation
        entity.currency = account.currency

        // Save full iconSource as JSON data (new approach)
        if let iconSource = account.iconSource,
           let encoded = try? JSONEncoder().encode(iconSource) {
            entity.iconSourceData = encoded
        } else {
            entity.iconSourceData = nil
        }

        // Keep logo field for backward compatibility
        if case .bankLogo(let bankLogo) = account.iconSource {
            entity.logo = bankLogo.rawValue
        } else {
            entity.logo = BankLogo.none.rawValue
        }

        entity.isDeposit = account.isDeposit
        entity.bankName = account.depositInfo?.bankName
        entity.createdAt = account.createdDate ?? Date()
        entity.shouldCalculateFromTransactions = account.shouldCalculateFromTransactions

        // Encode full DepositInfo as JSON (v5+)
        if let depositInfo = account.depositInfo,
           let encoded = try? JSONEncoder().encode(depositInfo) {
            entity.depositInfoData = encoded
        } else {
            entity.depositInfoData = nil
        }

        return entity
    }
}
