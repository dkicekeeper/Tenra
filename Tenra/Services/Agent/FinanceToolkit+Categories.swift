//
//  FinanceToolkit+Categories.swift
//  Tenra
//
//  The assistant tidies the categories (docs/plan-ten-agent.md, order in the data).
//  `get_category_audit` reads how they are used (FinanceToolkitCompute.categoryAudit, swept off
//  the main actor). `draft_category_change` drafts one of three changes to a category: a new
//  name (`TransactionStore.updateCategory` rewrites the name on its records), folding it into
//  another of the same type (`TransactionStore.mergeCategory`), or deleting one no record uses.
//  Each is a draft: nothing changes before Save, and Undo puts the category back as it was.
//

import Foundation

/// What a saved merge did besides the store's part, so Undo can put it back.
struct AgentCategoryMergeUndo: Equatable {
    let merge: TransactionStore.CategoryMerge
    /// The folded category's subcategories, and the ones newly linked to the other category.
    let subcategoryIds: [String]
    let newlyLinkedSubcategoryIds: [String]
    /// The remembered merchants that pointed at the folded category.
    let merchantIds: [String]
}

/// What a saved subcategory draft did, so Undo can put it back.
struct AgentSubcategoryUndo: Equatable {
    let subcategoryId: String
    let categoryId: String
    /// The subcategory did not exist before, and was not linked to the category before.
    let created: Bool
    let newlyLinked: Bool
    /// The subcategories each tagged record had.
    let previous: [String: [String]]
}

extension FinanceToolkit {
    /// The most records one subcategory draft tags.
    static let subcategoryTagLimit = 300

    private struct SubcategoryInput: Decodable {
        let category: String
        let name: String
        let merchant: String?
    }

    /// `draft_subcategory`: a subcategory in a category, and a merchant's records there tagged
    /// with it.
    func draftSubcategory(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_subcategory")) }
        let args = try input.decoded(as: SubcategoryInput.self)
        let subject = try category(args.category, field: "category")
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw FinanceToolError(message: "name must be 1 to 40 characters.") }
        let merchant = args.merchant?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        var ids: [String] = []
        var total = 0
        if !merchant.isEmpty {
            for tx in store.transactions where tx.category == subject.name && tx.type == subject.type
                && tx.description.lowercased().contains(merchant) {
                total += 1
                if ids.count < Self.subcategoryTagLimit { ids.append(tx.id) }
            }
            guard total > 0 else {
                throw FinanceToolError(message: "No record of \(subject.name) has \(merchant) in its name. Check the merchant with get_category_audit or search_transactions.")
            }
        }
        let exists = (store.subcategoryIdsByCategoryId[subject.id] ?? [])
            .contains { store.subcategoryById[$0]?.name.lowercased() == name.lowercased() }
        guard !(exists && ids.isEmpty) else {
            throw FinanceToolError(message: "\(subject.name) already has the subcategory \(name). Give a merchant to tag its records with it.")
        }
        let id = drafts.add([.subcategoryTag(category: subject, name: name, transactionIds: ids)])
        return .success([
            "draft_id": .string(id),
            "category_id": .string(subject.id),
            "category": .string(subject.name),
            "subcategory": .string(name),
            "new": .bool(!exists),
            "records": .number(Double(ids.count)),
            "records_left": .number(Double(total - ids.count)),
            "saved": false,
        ])
    }

    private struct CategoryChangeInput: Decodable {
        let category: String
        let name: String?
        let mergeInto: String?
        let delete: Bool?

        enum CodingKeys: String, CodingKey {
            case category, name, delete
            case mergeInto = "merge_into"
        }
    }

    /// `get_category_audit`: every expense and income category with how it is used.
    func categoryAudit() async -> JSONValue {
        let snapshot = makeSnapshot()
        let categories: [FinanceToolkitCompute.AuditCategory] = store.categories
            .filter { $0.type == .expense || $0.type == .income }
            .map { category in
                FinanceToolkitCompute.AuditCategory(
                    id: category.id,
                    name: category.name,
                    isIncome: category.type == .income,
                    hasBudget: (category.budgetAmount ?? 0) > 0,
                    subcategories: (store.subcategoryIdsByCategoryId[category.id] ?? []).compactMap { id in
                        store.subcategoryById[id].map { FinanceToolkitCompute.AuditCategory.Sub(id: id, name: $0.name) }
                    }
                )
            }
        let tags = store.subcategoryIdsByTransactionId
        let sweepCalendar = self.calendar
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.categoryAudit(snapshot, categories: categories, subcategoryIdsByTransaction: tags, calendar: sweepCalendar)
        }.value
    }

    /// An expense or income category by id, else by name; a name both types use needs the id.
    private func category(_ raw: String, field: String) throws -> CustomCategory {
        let reference = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = store.categories.filter { $0.type == .expense || $0.type == .income }
        if let byId = all.first(where: { $0.id == reference }) { return byId }
        let named = all.filter { $0.name.lowercased() == reference.lowercased() }
        guard let first = named.first else {
            throw FinanceToolError(message: "Unknown category \(reference) in \(field). Use a category id from <app_context>.")
        }
        guard named.count == 1 else {
            throw FinanceToolError(message: "\(reference) is both an expense and an income category. Use the category id in \(field).")
        }
        return first
    }

    /// The records that carry the category's name, as a rename or a merge would move them.
    func recordCount(of category: CustomCategory) -> Int {
        store.transactions.reduce(into: 0) { count, tx in
            if tx.category == category.name, tx.type != .internalTransfer, tx.type.categoryPickerSourceType == category.type { count += 1 }
        }
    }

    /// `draft_category_change`: a new name, a merge into another category, or deleting an
    /// unused one. Exactly one of them.
    func draftCategoryChange(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_category_change")) }
        let args = try input.decoded(as: CategoryChangeInput.self)
        let subject = try category(args.category, field: "category")
        let newName = args.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let target = args.mergeInto?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actions = [!newName.isEmpty, !target.isEmpty, args.delete == true].filter { $0 }.count
        guard actions == 1 else {
            throw FinanceToolError(message: "Give exactly one of name (rename), merge_into (fold into another category) or delete true.")
        }
        let records = recordCount(of: subject)
        let operation: AgentDraftOperation
        var result: [String: JSONValue] = [
            "category_id": .string(subject.id),
            "category": .string(subject.name),
            "records": .number(Double(records)),
            "saved": false,
        ]
        if !newName.isEmpty {
            guard newName.count <= 40 else { throw FinanceToolError(message: "name must be 40 characters or fewer.") }
            guard newName != subject.name else { throw FinanceToolError(message: "Nothing changes: the category is already called that.") }
            if let twin = store.categories.first(where: { $0.id != subject.id && $0.type == subject.type && $0.name.lowercased() == newName.lowercased() }) {
                throw FinanceToolError(message: "A category called \(twin.name) exists (\(twin.id)). To join them use merge_into.")
            }
            operation = .categoryRename(before: subject, name: newName)
            result["action"] = "rename"
            result["name"] = .string(newName)
        } else if !target.isEmpty {
            let into = try category(target, field: "merge_into")
            guard into.id != subject.id else { throw FinanceToolError(message: "A category cannot be merged into itself.") }
            guard into.type == subject.type else {
                throw FinanceToolError(message: "\(subject.name) and \(into.name) are of different types (expense and income): they cannot be merged.")
            }
            operation = .categoryMerge(from: subject, into: into, records: records)
            result["action"] = "merge"
            result["into_id"] = .string(into.id)
            result["into"] = .string(into.name)
            // The folded category's budget goes with it.
            result["budget_lost"] = .bool((subject.budgetAmount ?? 0) > 0)
        } else {
            guard records == 0 else {
                throw FinanceToolError(message: "\(subject.name) has \(records) records: it cannot be deleted here. Fold it into another category with merge_into, which keeps the records.")
            }
            guard !store.recurringSeries.contains(where: { $0.category == subject.name }) else {
                throw FinanceToolError(message: "A subscription or a regular payment uses \(subject.name): change it there first, or use merge_into.")
            }
            operation = .categoryDelete(subject)
            result["action"] = "delete"
            result["budget_lost"] = .bool((subject.budgetAmount ?? 0) > 0)
        }
        result["draft_id"] = .string(drafts.add([operation]))
        return .success(.object(result))
    }

    /// What a category draft will do (FinanceToolkit.describe).
    func describeCategoryChange(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .categoryRename(let before, let name):
            return ["type": "category_rename", "category_id": .string(before.id), "from": .string(before.name), "to": .string(name)]
        case .categoryMerge(let from, let into, let records):
            return [
                "type": "category_merge", "category_id": .string(from.id), "category": .string(from.name),
                "into_id": .string(into.id), "into": .string(into.name), "records": .number(Double(records)),
            ]
        case .categoryDelete(let category):
            return ["type": "category_delete", "category_id": .string(category.id), "category": .string(category.name)]
        case .subcategoryTag(let category, let name, let transactionIds):
            return [
                "type": "subcategory", "category_id": .string(category.id), "category": .string(category.name),
                "subcategory": .string(name), "records": .number(Double(transactionIds.count)),
            ]
        default:
            return .null
        }
    }
}

extension AgentDraftBook.Writer {
    /// Saves a category draft. What the tool checked is checked again: time passes before Save.
    static func saveCategoryChange(
        _ operation: AgentDraftOperation,
        store: TransactionStore,
        categoriesViewModel: CategoriesViewModel,
        merchants: MerchantCategoryMemory = .shared
    ) throws -> AgentSavedRecord {
        switch operation {
        case .categoryRename(let before, let name):
            guard store.categoryById[before.id] == before,
                  !store.categories.contains(where: { $0.id != before.id && $0.type == before.type && $0.name.lowercased() == name.lowercased() })
            else { throw AgentDraftError.recordChanged }
            var renamed = before
            renamed.name = name
            categoriesViewModel.updateCategory(renamed)
            return .categoryRenamed(before: before)
        case .categoryDelete(let category):
            guard store.categoryById[category.id] == category,
                  !store.transactions.contains(where: {
                      $0.category == category.name && $0.type != .internalTransfer && $0.type.categoryPickerSourceType == category.type
                  })
            else { throw AgentDraftError.recordChanged }
            let subcategoryIds = store.subcategoryIdsByCategoryId[category.id] ?? []
            categoriesViewModel.deleteCategory(category)
            return .categoryDeleted(category, subcategoryIds: subcategoryIds)
        case .categoryMerge(let from, let into, _):
            guard store.categoryById[from.id] == from, store.categoryById[into.id] == into else { throw AgentDraftError.recordChanged }
            let subcategoryIds = store.subcategoryIdsByCategoryId[from.id] ?? []
            let already = Set(store.subcategoryIdsByCategoryId[into.id] ?? [])
            let merchantIds = merchants.merchants.filter { $0.categoryId == from.id }.map(\.id)
            guard let merge = store.mergeCategory(from.id, into: into.id) else { throw AgentDraftError.recordChanged }
            // The records keep their subcategories: those belong to the other category now.
            let newlyLinked = subcategoryIds.filter { !already.contains($0) }
            for id in newlyLinked { categoriesViewModel.linkSubcategoryToCategory(subcategoryId: id, categoryId: into.id) }
            Self.point(merchantIds, at: into.id, in: merchants)
            return .categoryMerged(AgentCategoryMergeUndo(
                merge: merge, subcategoryIds: subcategoryIds, newlyLinkedSubcategoryIds: newlyLinked, merchantIds: merchantIds
            ))
        case .subcategoryTag(let category, let name, let transactionIds):
            guard store.categoryById[category.id] != nil else { throw AgentDraftError.categoryGone }
            let existing = store.subcategories.first { $0.name.lowercased() == name.lowercased() }
            let subcategory = existing ?? categoriesViewModel.addSubcategory(name: name)
            let newlyLinked = !(store.subcategoryIdsByCategoryId[category.id] ?? []).contains(subcategory.id)
            if newlyLinked { categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategory.id, categoryId: category.id) }
            var previous: [String: [String]] = [:]
            var links: [String: [String]] = [:]
            for id in transactionIds {
                // Still there, and still in this category.
                guard let transaction = store.transactionById[id], transaction.category == category.name else { continue }
                let tags = categoriesViewModel.getSubcategoriesForTransaction(id).map(\.id)
                guard !tags.contains(subcategory.id) else { continue }
                previous[id] = tags
                links[id] = tags + [subcategory.id]
            }
            if !links.isEmpty { categoriesViewModel.batchLinkSubcategoriesToTransaction(links) }
            return .subcategoryTagged(AgentSubcategoryUndo(
                subcategoryId: subcategory.id, categoryId: category.id, created: existing == nil, newlyLinked: newlyLinked, previous: previous
            ))
        default:
            throw AgentDraftError.recordChanged
        }
    }

    static func undoCategoryChange(
        _ record: AgentSavedRecord,
        store: TransactionStore,
        categoriesViewModel: CategoriesViewModel,
        merchants: MerchantCategoryMemory = .shared
    ) {
        switch record {
        case .categoryRenamed(let before):
            guard var current = store.categoryById[before.id],
                  !store.categories.contains(where: { $0.id != before.id && $0.type == before.type && $0.name.lowercased() == before.name.lowercased() })
            else { return }
            current.name = before.name
            categoriesViewModel.updateCategory(current)
        case .categoryDeleted(let category, let subcategoryIds):
            guard store.categoryById[category.id] == nil else { return }
            categoriesViewModel.addCategory(category)
            guard store.categoryById[category.id] != nil else { return }
            for id in subcategoryIds { categoriesViewModel.linkSubcategoryToCategory(subcategoryId: id, categoryId: category.id) }
        case .categoryMerged(let undo):
            store.undoCategoryMerge(undo.merge)
            guard store.categoryById[undo.merge.removed.id] != nil else { return }
            for id in undo.subcategoryIds { categoriesViewModel.linkSubcategoryToCategory(subcategoryId: id, categoryId: undo.merge.removed.id) }
            for id in undo.newlyLinkedSubcategoryIds { categoriesViewModel.unlinkSubcategoryFromCategory(subcategoryId: id, categoryId: undo.merge.intoId) }
            Self.point(undo.merchantIds, at: undo.merge.removed.id, in: merchants)
        case .subcategoryTagged(let undo):
            let current = undo.previous.filter { store.transactionById[$0.key] != nil }
            if !current.isEmpty { categoriesViewModel.batchLinkSubcategoriesToTransaction(current) }
            if undo.created {
                categoriesViewModel.deleteSubcategory(undo.subcategoryId)
            } else if undo.newlyLinked {
                categoriesViewModel.unlinkSubcategoryFromCategory(subcategoryId: undo.subcategoryId, categoryId: undo.categoryId)
            }
        default:
            break
        }
    }

    /// The remembered merchants follow their category; their subcategory choice stays.
    private static func point(_ merchantIds: [String], at categoryId: String, in merchants: MerchantCategoryMemory) {
        let ids = Set(merchantIds)
        for merchant in merchants.merchants where ids.contains(merchant.id) {
            if let subcategoryIds = merchant.subcategoryIds {
                merchants.reassign(merchantId: merchant.id, categoryId: categoryId, subcategoryIds: subcategoryIds)
            } else {
                merchants.remember(categoryId: categoryId, subcategoryIds: nil, forMerchant: merchant.displayName)
            }
        }
    }
}
