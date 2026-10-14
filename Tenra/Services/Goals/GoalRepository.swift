//
//  GoalRepository.swift
//  Tenra
//
//  Savings goals in CoreData v15 (`GoalEntity`), outside the DataRepositoryProtocol facade like
//  the assistant's threads and facts (AgentThreadStore, AgentFactStore): GoalStore is the only
//  caller. A goal's contributions are kept as JSON on its row. Backups carry the goals with
//  the rest of the store, "delete all data" removes them, and GoalStore reads them again when
//  the store is replaced.
//

import CoreData
import Foundation
import os

nonisolated final class GoalRepository: @unchecked Sendable {
    private static let logger = Logger(subsystem: "Tenra", category: "GoalRepository")
    private static let entityName = "GoalEntity"
    let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    /// Every goal, in list order.
    func all() async -> [SavingsGoal] {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<GoalEntity>(entityName: Self.entityName)
            request.sortDescriptors = [
                NSSortDescriptor(key: "order", ascending: true),
                NSSortDescriptor(key: "createdAt", ascending: true),
            ]
            let entities = (try? context.fetch(request)) ?? []
            return entities.compactMap(Self.goal)
        }
    }

    /// Writes the goal over its earlier copy, or adds it.
    func save(_ goal: SavingsGoal) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<GoalEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", goal.id)
                let entity: GoalEntity
                if let existing = try context.fetch(request).first {
                    entity = existing
                } else {
                    // The entity from this context's model: a test host has its own model loaded too.
                    guard let description = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else { return }
                    entity = GoalEntity(entity: description, insertInto: context)
                }
                let encoder = JSONEncoder()
                entity.id = goal.id
                entity.name = goal.name
                entity.iconSourceData = goal.iconSource.flatMap { try? encoder.encode($0) }
                entity.targetAmount = goal.targetAmount
                entity.currency = goal.currency
                entity.deadline = goal.deadline
                entity.linkedAccountId = goal.linkedAccountId
                entity.contributions = try goal.contributions.isEmpty ? nil : encoder.encode(goal.contributions)
                entity.createdAt = goal.createdAt
                entity.reachedAt = goal.reachedAt
                entity.order = Int32(clamping: goal.order)
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
                let request = NSFetchRequest<GoalEntity>(entityName: Self.entityName)
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

    private static func goal(_ entity: GoalEntity) -> SavingsGoal? {
        guard let id = entity.id, !id.isEmpty, let name = entity.name else { return nil }
        let decoder = JSONDecoder()
        return SavingsGoal(
            id: id,
            name: name,
            iconSource: entity.iconSourceData.flatMap { try? decoder.decode(IconSource.self, from: $0) },
            targetAmount: entity.targetAmount,
            currency: entity.currency ?? "KZT",
            deadline: entity.deadline,
            linkedAccountId: entity.linkedAccountId,
            contributions: entity.contributions.flatMap { try? decoder.decode([GoalContribution].self, from: $0) } ?? [],
            createdAt: entity.createdAt ?? .distantPast,
            reachedAt: entity.reachedAt,
            order: Int(entity.order)
        )
    }
}
