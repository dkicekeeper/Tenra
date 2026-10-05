//
//  IntentSubcategoryStore.swift
//  Tenra
//
//  Subcategory reads and writes for an intent, straight against CoreData.
//
//  A process launched only to run an intent stops after initializeFastPath(),
//  which loads no subcategory data: TransactionStore's subcategory arrays and
//  indexes are empty there (and CategoriesViewModel copies those empty arrays
//  in setupTransactionStoreObserver). Linking through CategoriesViewModel in
//  that state hands `saveTransactionSubcategoryLinks` an empty list plus the
//  new link, and that save deletes every link not in the list: the
//  subcategories of every other transaction. So before the full load, links
//  are inserted one at a time and reads go to CoreData.
//
//  The viewContext is used because the app only reads through it (the
//  history FRC); a save here carries nothing but these inserts.
//

import CoreData
import OSLog

enum IntentSubcategoryStore {

    private static let log = Logger(subsystem: "Tenra", category: "IntentSubcategoryStore")

    /// Subcategories linked to the given categories, in the given category
    /// order and then the user's order inside each category, without repeats.
    static func subcategories(
        ofCategoryIds categoryIds: [String],
        context: NSManagedObjectContext
    ) -> [Subcategory] {
        guard !categoryIds.isEmpty else { return [] }

        let linkRequest = NSFetchRequest<CategorySubcategoryLinkEntity>(entityName: "CategorySubcategoryLinkEntity")
        linkRequest.predicate = NSPredicate(format: "categoryId IN %@", categoryIds)
        linkRequest.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        guard let links = try? context.fetch(linkRequest), !links.isEmpty else { return [] }

        var orderedIds: [String] = []
        var seen = Set<String>()
        for categoryId in categoryIds {
            for link in links where link.categoryId == categoryId {
                if let id = link.subcategoryId, seen.insert(id).inserted {
                    orderedIds.append(id)
                }
            }
        }

        let subcategoryRequest = NSFetchRequest<SubcategoryEntity>(entityName: "SubcategoryEntity")
        subcategoryRequest.predicate = NSPredicate(format: "id IN %@", orderedIds)
        guard let rows = try? context.fetch(subcategoryRequest) else { return [] }

        var nameById: [String: String] = [:]
        for row in rows {
            if let id = row.id, nameById[id] == nil { nameById[id] = row.name ?? "" }
        }
        return orderedIds.compactMap { id in
            nameById[id].map { Subcategory(id: id, name: $0) }
        }
    }

    /// Adds links for one transaction and saves at once, leaving every other
    /// link untouched. Saved before returning because an intent process can be
    /// suspended as soon as `perform()` returns.
    static func addLinks(
        transactionId: String,
        subcategoryIds: [String],
        context: NSManagedObjectContext
    ) {
        guard !transactionId.isEmpty, !subcategoryIds.isEmpty else { return }
        for subcategoryId in subcategoryIds {
            _ = TransactionSubcategoryLinkEntity.from(
                TransactionSubcategoryLink(transactionId: transactionId, subcategoryId: subcategoryId),
                context: context
            )
        }
        do {
            try context.save()
        } catch {
            log.error("addLinks failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
        }
    }
}
