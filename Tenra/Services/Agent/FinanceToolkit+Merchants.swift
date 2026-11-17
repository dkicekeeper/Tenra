//
//  FinanceToolkit+Merchants.swift
//  Tenra
//
//  The assistant tidies the merchants (docs/plan-ten-agent.md, order in the data).
//  `get_merchants` reads the merchants of the last twelve months of expenses: how many records
//  each has, the categories they went to, the category remembered for it
//  (MerchantCategoryMemory, what a payment that records itself gets) and its brand
//  (MerchantGroupStore), and the merchants whose names start alike and are not one brand yet.
//  `draft_merchant_rule` drafts the category remembered for a merchant; `draft_merchant_brand`
//  drafts joining points of one brand. Both are drafts: nothing changes before Save, and Undo
//  puts the memory or the brand back. Moving the records already saved is `draft_recategorize`.
//

import Foundation

/// What a saved merchant rule replaced, so Undo can put it back.
struct AgentMerchantRuleUndo: Equatable {
    let merchant: String
    let previousCategoryId: String?
    let previousSubcategoryIds: [String]?
}

extension FinanceToolkitCompute {
    /// The most merchants and the most look-alike groups one result lists.
    nonisolated static let merchantLimit = 40
    nonisolated static let merchantLookAlikeLimit = 10

    private nonisolated struct MerchantTally {
        var records = 0
        var total = 0.0
        var names: [String: Int] = [:]
        var categories: [String: Int] = [:]
    }

    /// - Parameters:
    ///   - remembered: normalized merchant → the category remembered for it.
    ///   - brands: normalized merchant → its brand's name.
    nonisolated static func merchants(
        _ s: FinanceSnapshot,
        remembered: [String: String],
        brands: [String: String],
        calendar: Calendar = .current
    ) -> JSONValue {
        let from = calendar.date(byAdding: .month, value: -12, to: s.now).map(FastDateParser.string(from:)) ?? s.today
        let rates = RateSnapshot()
        var tallies: [String: MerchantTally] = [:]
        for tx in s.transactions where tx.type == .expense && tx.date >= from && tx.date <= s.today {
            let key = CategorySuggestionService.normalizedMerchant(tx.description)
            guard key.count >= CategorySuggestionService.minimumMerchantLength else { continue }
            var tally = tallies[key] ?? MerchantTally()
            tally.records += 1
            tally.total += baseAmount(tx, base: s.baseCurrency, rates: rates)
            tally.names[tx.description.trimmingCharacters(in: .whitespacesAndNewlines), default: 0] += 1
            tally.categories[tx.category, default: 0] += 1
            tallies[key] = tally
        }
        func name(_ tally: MerchantTally, key: String) -> String {
            tally.names.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? key
        }
        let ranked = tallies.sorted { $0.value.records != $1.value.records ? $0.value.records > $1.value.records : $0.key < $1.key }
        let rows: [JSONValue] = ranked.prefix(merchantLimit).map { key, tally in
            let categories = tally.categories
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { JSONValue.object(["category": .string($0.key), "records": .number(Double($0.value))]) }
            return [
                "merchant": .string(name(tally, key: key)),
                "records": .number(Double(tally.records)),
                "total": .number(round2(tally.total)),
                "categories": .array(categories),
                "remembered_category": remembered[key].map(JSONValue.string) ?? .null,
                "brand": brands[key].map(JSONValue.string) ?? .null,
            ]
        }
        // Names that start with the same word and are not one brand yet: maybe one brand's points.
        var byFirstWord: [String: [String]] = [:]
        for (key, _) in tallies where brands[key] == nil {
            guard let word = key.split(separator: " ").first, word.count >= 3 else { continue }
            byFirstWord[String(word), default: []].append(key)
        }
        let lookAlikes: [JSONValue] = byFirstWord
            .filter { $0.value.count > 1 }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(merchantLookAlikeLimit)
            .map { word, keys in
                [
                    "starts_with": .string(word),
                    "merchants": .array(keys.sorted().compactMap { key in tallies[key].map { JSONValue.string(name($0, key: key)) } }),
                ]
            }
        return [
            "from": .string(from),
            "to": .string(s.today),
            "currency": .string(s.baseCurrency),
            "merchants": .array(rows),
            "merchants_total": .number(Double(tallies.count)),
            "look_alike": .array(lookAlikes),
        ]
    }
}

extension FinanceToolkit {
    private struct RuleInput: Decodable {
        let merchant: String
        let category: String
    }

    private struct BrandInput: Decodable {
        let merchants: [String]
        let name: String?
    }

    /// `get_merchants`: the merchants of the last twelve months of expenses.
    func merchantsResult(memory: MerchantCategoryMemory = .shared, groups: MerchantGroupStore = .shared) async -> JSONValue {
        let snapshot = makeSnapshot()
        let categoryNames = Dictionary(store.categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var remembered: [String: String] = [:]
        for merchant in memory.merchants {
            if let name = categoryNames[merchant.categoryId] { remembered[merchant.id] = name }
        }
        var brands: [String: String] = [:]
        for group in groups.groups {
            let name = groups.displayName(of: group)
            for member in group.members { brands[member] = name }
        }
        let sweepCalendar = calendar
        let rememberedCopy = remembered
        let brandsCopy = brands
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.merchants(snapshot, remembered: rememberedCopy, brands: brandsCopy, calendar: sweepCalendar)
        }.value
    }

    /// `draft_merchant_rule`: the expense category a merchant's payments get from now on.
    func draftMerchantRule(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_merchant_rule")) }
        let args = try input.decoded(as: RuleInput.self)
        let merchant = args.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = MerchantCategoryMemory.key(forMerchant: merchant) else {
            throw FinanceToolError(message: "\(merchant) is too short to be a merchant's name. Use a name from get_merchants.")
        }
        let reference = args.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let expense = store.categories.filter { $0.type == .expense }
        guard let category = expense.first(where: { $0.id == reference })
            ?? expense.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown expense category \(reference). Use a category id from <app_context>.")
        }
        // The merchant's records that sit in another category: draft_recategorize moves them.
        let elsewhere = store.transactions.reduce(into: 0) { count, tx in
            if tx.type == .expense, tx.category != category.name, CategorySuggestionService.normalizedMerchant(tx.description) == key { count += 1 }
        }
        let id = drafts.add([.merchantRule(merchant: merchant, category: category)])
        return .success([
            "draft_id": .string(id),
            "merchant": .string(merchant),
            "category_id": .string(category.id),
            "category": .string(category.name),
            "records_in_other_categories": .number(Double(elsewhere)),
            "saved": false,
        ])
    }

    /// `draft_merchant_brand`: points of one brand joined into one merchant.
    func draftMerchantBrand(_ input: JSONValue, groups: MerchantGroupStore = .shared) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_merchant_brand")) }
        let args = try input.decoded(as: BrandInput.self)
        var seen: Set<String> = []
        var points: [String] = []
        for raw in args.merchants {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = MerchantCategoryMemory.key(forMerchant: name) else {
                throw FinanceToolError(message: "\(name) is too short to be a merchant's name. Use names from get_merchants.")
            }
            guard groups.group(forKey: key) == nil else {
                throw FinanceToolError(message: "\(name) already belongs to a brand: brands are changed on the merchant's screen.")
            }
            if seen.insert(key).inserted { points.append(name) }
        }
        guard points.count >= 2 else { throw FinanceToolError(message: "Give at least two different merchants to join.") }
        guard points.count <= 10 else { throw FinanceToolError(message: "At most 10 merchants in one brand draft.") }
        let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brand = (name?.isEmpty ?? true) ? nil : name
        let id = drafts.add([.merchantBrand(merchants: points, name: brand)])
        return .success([
            "draft_id": .string(id),
            "merchants": .array(points.map(JSONValue.string)),
            "name": brand.map(JSONValue.string) ?? .null,
            "saved": false,
        ])
    }

    private struct FeedbackInput: Decodable {
        let text: String
        let mood: String?
    }

    /// `draft_feedback`: words for the developer, sent from the card when the person confirms.
    func draftFeedback(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_feedback")) }
        let args = try input.decoded(as: FeedbackInput.self)
        let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FinanceToolError(message: "text must not be empty: ask the user what to tell the developer.") }
        guard text.count <= 2_000 else { throw FinanceToolError(message: "text must be 2000 characters or fewer.") }
        let mood = args.mood.flatMap(AgentFeedbackMessage.Mood.init(rawValue:))
        let id = drafts.add([.feedback(text: text, mood: mood)])
        return .success(["draft_id": .string(id), "text": .string(text), "sent": false])
    }

    /// What a merchant draft will do (FinanceToolkit.describe).
    func describeMerchantChange(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .merchantRule(let merchant, let category):
            return ["type": "merchant_rule", "merchant": .string(merchant), "category_id": .string(category.id), "category": .string(category.name)]
        case .feedback(let text, _):
            return ["type": "feedback", "text": .string(text)]
        case .merchantBrand(let merchants, let name):
            return ["type": "merchant_brand", "merchants": .array(merchants.map(JSONValue.string)), "name": name.map(JSONValue.string) ?? .null]
        default:
            return .null
        }
    }
}

extension AgentDraftBook.Writer {
    static func saveMerchantChange(
        _ operation: AgentDraftOperation,
        store: TransactionStore,
        memory: MerchantCategoryMemory = .shared,
        groups: MerchantGroupStore = .shared
    ) throws -> AgentSavedRecord {
        switch operation {
        case .merchantRule(let merchant, let category):
            guard store.categoryById[category.id] != nil else { throw AgentDraftError.categoryGone }
            let undo = AgentMerchantRuleUndo(
                merchant: merchant,
                previousCategoryId: memory.category(forMerchant: merchant, in: store.categories)?.id,
                previousSubcategoryIds: memory.subcategoryIds(forMerchant: merchant)
            )
            // Another category: the subcategory chosen for the old one does not carry over.
            memory.remember(categoryId: category.id, subcategoryIds: undo.previousCategoryId == category.id ? nil : [], forMerchant: merchant)
            return .merchantRuleSet(undo)
        case .merchantBrand(let merchants, let name):
            guard let anchor = merchants.first,
                  merchants.allSatisfy({ groups.group(forMerchant: $0) == nil }) else { throw AgentDraftError.recordChanged }
            groups.merge(Array(merchants.dropFirst()), into: anchor)
            guard let group = groups.group(forMerchant: anchor) else { throw AgentDraftError.recordChanged }
            if let name { groups.rename(groupId: group.id, to: name) }
            return .merchantBranded(groupId: group.id)
        default:
            throw AgentDraftError.recordChanged
        }
    }

    static func undoMerchantChange(
        _ record: AgentSavedRecord,
        memory: MerchantCategoryMemory = .shared,
        groups: MerchantGroupStore = .shared
    ) {
        switch record {
        case .merchantRuleSet(let undo):
            if let categoryId = undo.previousCategoryId {
                memory.remember(categoryId: categoryId, subcategoryIds: undo.previousSubcategoryIds ?? [], forMerchant: undo.merchant)
            } else if let key = MerchantCategoryMemory.key(forMerchant: undo.merchant) {
                memory.forget(merchantId: key)
            }
        case .merchantBranded(let groupId):
            groups.split(groupId: groupId)
        default:
            break
        }
    }
}
