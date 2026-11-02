//
//  AssetRepository.swift
//  Tenra
//
//  Assets in CoreData v17 (`AssetEntity`), outside the DataRepositoryProtocol facade like the
//  goals and debts (GoalRepository, DebtRepository): AssetStore is the only caller. An asset's
//  valuations, category links, (v18) payments by hand and (v19) characteristics are kept as JSON
//  on its row; a valuation that cannot be read is skipped, not the list. Backups carry the assets with
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
                // The upkeep links as an array (v19); a store of v18 or before holds one object.
                entity.expenseLinkData = try asset.expenseLinks.isEmpty ? nil : encoder.encode(asset.expenseLinks)
                entity.includeInNetWorth = asset.includeInNetWorth
                entity.soldAt = asset.soldAt
                let links = AssetTransactionLinks(excluded: asset.excludedTransactionIds, included: asset.includedTransactionIds)
                entity.transactionLinksData = links.excluded.isEmpty && links.included.isEmpty ? nil : try encoder.encode(links)
                entity.attributesData = asset.attributes.isEmpty ? nil : try encoder.encode(asset.attributes)
                entity.yieldOnShare = asset.yieldOnShare
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
        let links = entity.transactionLinksData.flatMap { try? decoder.decode(AssetTransactionLinks.self, from: $0) }
        return Asset(
            id: id,
            name: name,
            kind: entity.kind.flatMap(AssetKind.init(rawValue:)) ?? .other,
            iconSource: entity.iconSourceData.flatMap { try? decoder.decode(IconSource.self, from: $0) },
            currency: entity.currency ?? "KZT",
            purchaseDate: entity.purchaseDate,
            purchasePrice: entity.purchasePrice?.doubleValue,
            valuations: entity.valuations.map { Self.valuations(from: $0, decoder: decoder) } ?? [],
            depreciationPerYear: entity.depreciationPerYear?.doubleValue,
            ownershipShare: entity.ownershipShare,
            linkedLoanAccountId: entity.linkedLoanAccountId,
            incomeLink: entity.incomeLinkData.flatMap { try? decoder.decode(AssetCategoryLink.self, from: $0) },
            expenseLink: nil,
            includeInNetWorth: entity.includeInNetWorth,
            soldAt: entity.soldAt,
            note: entity.note,
            order: Int(entity.order),
            createdAt: entity.createdAt ?? .distantPast,
            excludedTransactionIds: links?.excluded ?? [],
            includedTransactionIds: links?.included ?? [],
            attributes: entity.attributesData.flatMap { try? decoder.decode(AssetAttributes.self, from: $0) } ?? AssetAttributes(),
            expenseLinks: entity.expenseLinkData.map { Self.links(from: $0, decoder: decoder) } ?? [],
            yieldOnShare: entity.yieldOnShare
        )
    }

    /// One entry of a list that may not decode on its own.
    nonisolated private struct Lossy<Element: Decodable>: Decodable {
        let value: Element?

        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }

    /// The upkeep links: an array, or the one object a store of v18 or before holds.
    static func links(from data: Data, decoder: JSONDecoder = JSONDecoder()) -> [AssetCategoryLink] {
        if let links = try? decoder.decode([AssetCategoryLink].self, from: data) { return links }
        return (try? decoder.decode(AssetCategoryLink.self, from: data)).map { [$0] } ?? []
    }

    /// The valuations one by one: one this version cannot read (a later one's) is skipped and the
    /// rest stay, rather than the asset losing them all on its next save.
    static func valuations(from data: Data, decoder: JSONDecoder = JSONDecoder()) -> [AssetValuation] {
        guard let entries = try? decoder.decode([Lossy<AssetValuation>].self, from: data) else { return [] }
        return entries.compactMap(\.value)
    }
}
