//
//  DebtRepository.swift
//  Tenra
//
//  Personal debts in CoreData v15 (`DebtEntity`), outside the DataRepositoryProtocol facade
//  like the assistant's threads and facts: DebtStore is the only caller. A debt's repayments
//  are kept as JSON on its row. Backups carry the debts with the rest of the store, "delete
//  all data" removes them, and DebtStore reads them again when the store is replaced.
//

import CoreData
import Foundation
import os

nonisolated final class DebtRepository: @unchecked Sendable {
    private static let logger = Logger(subsystem: "Tenra", category: "DebtRepository")
    private static let entityName = "DebtEntity"
    let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    /// Every debt, oldest first.
    func all() async -> [PersonalDebt] {
        let context = stack.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<DebtEntity>(entityName: Self.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            let entities = (try? context.fetch(request)) ?? []
            return entities.compactMap(Self.debt)
        }
    }

    /// Writes the debt over its earlier copy, or adds it.
    func save(_ debt: PersonalDebt) async {
        let context = stack.newBackgroundContext()
        await context.perform {
            do {
                let request = NSFetchRequest<DebtEntity>(entityName: Self.entityName)
                request.predicate = NSPredicate(format: "id == %@", debt.id)
                let entity: DebtEntity
                if let existing = try context.fetch(request).first {
                    entity = existing
                } else {
                    // The entity from this context's model: a test host has its own model loaded too.
                    guard let description = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else { return }
                    entity = DebtEntity(entity: description, insertInto: context)
                }
                entity.id = debt.id
                entity.direction = debt.direction.rawValue
                entity.person = debt.person
                entity.amount = debt.amount
                entity.currency = debt.currency
                entity.date = debt.date
                entity.dueDate = debt.dueDate
                entity.note = debt.note
                entity.repayments = try debt.repayments.isEmpty ? nil : JSONEncoder().encode(debt.repayments)
                entity.settledAt = debt.settledAt
                entity.order = debt.order.map { NSNumber(value: $0) }
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
                let request = NSFetchRequest<DebtEntity>(entityName: Self.entityName)
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

    private static func debt(_ entity: DebtEntity) -> PersonalDebt? {
        guard let id = entity.id, !id.isEmpty, let person = entity.person else { return nil }
        return PersonalDebt(
            id: id,
            direction: entity.direction.flatMap(DebtDirection.init(rawValue:)) ?? .owedToMe,
            person: person,
            amount: entity.amount,
            currency: entity.currency ?? "KZT",
            date: entity.date ?? .distantPast,
            dueDate: entity.dueDate,
            note: entity.note,
            repayments: entity.repayments.flatMap { try? JSONDecoder().decode([DebtRepayment].self, from: $0) } ?? [],
            settledAt: entity.settledAt,
            order: entity.order?.intValue
        )
    }
}
