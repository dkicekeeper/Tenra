//
//  AssetRepository.swift
//  Tenra
//
//  Assets in CoreData v17 (`AssetEntity`), outside the DataRepositoryProtocol facade like the
//  goals and debts (GoalRepository, DebtRepository): AssetStore is the only caller. An asset's
//  valuations and category links are kept as JSON on its row. Backups carry the assets with
//  the rest of the store, "delete all data" removes them, and AssetStore reads them again when
//  the store is replaced.
//

import CoreData
import Foundation
import os

nonisolated final class AssetRepository: @unchecked Sendable {
    private static let logger = Logger(subsystem: "Tenra", category: "AssetRepository")
    private static let entityName = "AssetEntity"
    let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    /// Every asset, in list order.
    func all() async -> [Asset] {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<AssetEntity>(entityName: Self.entityName)
            request.sortDescriptors = [
                NSSortDescriptor(key: "order", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
            ]
            let entities = (try? context.fetch(request)) ?? []
            return entities.compactMap(Self.asset)
        }
    }

    /// Writes the asset over its earlier copy, or adds it.
    func save(_ asset: Asset) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<AssetEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", asset.id)
                let entity: AssetEntity
                if let existing = try context.fetch(request).first {
                    entity = existing
                } else {
                    // The entity from this context's model: a test host has its own model loaded too.
                    guard let description = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else { return }
                    entity = AssetEntity(entity: description, insertInto: context)
                }
                let encoder = JSONEncoder()
                entity.id = asset.id
                entity.name = asset.name
                entity.kind = asset.kind.rawValue
                entity.iconSourceData = asset.iconSource.flatMap { try? encoder.encode($0) }
                entity.currency = asset.currency
                entity.purchaseDate = asset.purchaseDate
                entity.purchasePrice = asset.purchasePrice.map { NSNumber(value: $0) }
                entity.valuations = try asset.valuations.isEmpty ? nil : encoder.encode(asset.valuations)
                entity.depreciationPerYear = asset.depreciationPerYear.map { NSNumber(value: $0) }
                entity.ownershipShare = asset.ownershipShare
                entity.linkedLoanAccountId = asset.linkedLoanAccountId
                entity.incomeLinkData = try asset.incomeLink.map { try encoder.encode($0) }
                entity.expenseLinkData = try asset.expenseLink.map { try encoder.encode($0) }
                entity.includeInNetWorth = asset.includeInNetWorth
                entity.soldAt = asset.soldAt
                entity.note = asset.note
                entity.order = Int32(clamping: asset.order)
                entity.createdAt = asset.createdAt
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func delete(id: String) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<AssetEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", id)
                for entity in try context.fetch(request) {
                    context.delete(entity)
                }
                if context.hasChanges { try context.save() }
            } catch {
                Self.logger.error("delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func asset(_ entity: AssetEntity) -> Asset? {
        guard let id = entity.id, !id.isEmpty, let name = entity.name else { return nil }
        let decoder = JSONDecoder()
        return Asset(
            id: id,
            name: name,
            kind: entity.kind.flatMap(AssetKind.init(rawValue:)) ?? .other,
            iconSource: entity.iconSourceData.flatMap { try? decoder.decode(IconSource.self, from: $0) },
            currency: entity.currency ?? "KZT",
            purchaseDate: entity.purchaseDate,
            purchasePrice: entity.purchasePrice?.doubleValue,
            valuations: entity.valuations.flatMap { try? decoder.decode([AssetValuation].self, from: $0) } ?? [],
            depreciationPerYear: entity.depreciationPerYear?.doubleValue,
            ownershipShare: entity.ownershipShare,
            linkedLoanAccountId: entity.linkedLoanAccountId,
            incomeLink: entity.incomeLinkData.flatMap { try? decoder.decode(AssetCategoryLink.self, from: $0) },
            expenseLink: entity.expenseLinkData.flatMap { try? decoder.decode(AssetCategoryLink.self, from: $0) },
            includeInNetWorth: entity.includeInNetWorth,
            soldAt: entity.soldAt,
            note: entity.note,
            order: Int(entity.order),
            createdAt: entity.createdAt ?? .distantPast
        )
    }
}
