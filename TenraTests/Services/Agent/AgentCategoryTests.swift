//
//  AgentCategoryTests.swift
//  TenraTests
//
//  The assistant tidies the categories (FinanceToolkit+Categories): `get_category_audit` says
//  how each one is used, and `draft_category_change` drafts a rename, a merge or the deletion
//  of an unused category, refusing what would lose records. Nothing is written before Save.
//  Amounts are KZT: no FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentCategoryTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    /// Returns the store too: tests must retain it.
    private static func make() -> (FinanceToolkit, AgentDraftBook, TransactionStore) {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.categories = [
            CustomCategory(id: "cat_cafe", name: "Кафе", colorHex: "#FF9500", type: .expense),
            CustomCategory(id: "cat_food", name: "Продукты", colorHex: "#34C759", type: .expense),
            CustomCategory(id: "cat_gifts", name: "Подарки", colorHex: "#FF2D55", type: .expense),
            CustomCategory(id: "cat_salary", name: "Зарплата", colorHex: "#5856D6", type: .income),
        ]
        store.accounts = [Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_850)]
        store.transactions = [
            Transaction(id: "t_glovo", date: "2026-10-27", description: "Glovo", amount: 4_200, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            Transaction(id: "t_coffee", date: "2026-10-26", description: "Glovo", amount: 1_800, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            Transaction(id: "t_magnum", date: "2026-10-25", description: "Magnum", amount: 6_000, currency: "KZT", type: .expense, category: "Продукты", accountId: "acc_kaspi"),
        ]
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { _ in .series("unused") },
            undo: { _ in }
        ))
        let toolkit = FinanceToolkit(store: store, drafts: book, learned: VoiceLearningStore(defaults: defaults), now: { now })
        return (toolkit, book, store)
    }

    @Test func theAuditSaysHowEachCategoryIsUsed() async throws {
        let (toolkit, _, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "get_category_audit", input: [:])
        let value = try #require(output.value, "\(output.error ?? "")")
        // Largest first: Кафе and Продукты are level, so by name.
        #expect(value.value(atPath: "categories.0.id") == "cat_cafe")
        #expect(value.value(atPath: "categories.0.records") == 2)
        #expect(value.value(atPath: "categories.0.share_percent") == 50)
        #expect(value.value(atPath: "categories.0.top_merchants.0.name") == "Glovo")
        #expect(value.value(atPath: "categories.0.top_merchants.0.records") == 2)
        #expect(value.value(atPath: "categories.1.id") == "cat_food")
        // Nothing in either: by name, Зарплата before Подарки.
        #expect(value.value(atPath: "categories.3.id") == "cat_gifts")
        #expect(value.value(atPath: "categories.3.unused") == true)
        #expect(value.value(atPath: "without_category.records") == 0)
    }

    @Test func budgetSuggestionsCountTheLastThreeWholeMonths() async throws {
        let (toolkit, _, store) = Self.make()
        store.categories[0].budgetAmount = 5_000
        store.transactions += [
            Transaction(id: "t_sep", date: "2026-09-10", description: "Glovo", amount: 9_000, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            Transaction(id: "t_aug", date: "2026-08-10", description: "Glovo", amount: 3_000, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
            // Before the three months, and in the month that is not over: not counted.
            Transaction(id: "t_jun", date: "2026-06-10", description: "Glovo", amount: 50_000, currency: "KZT", type: .expense, category: "Кафе", accountId: "acc_kaspi"),
        ]
        let output = await toolkit.execute(name: "suggest_budgets", input: [:])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["from"] == "2026-07-01")
        #expect(value.value(atPath: "categories.0.category_id") == "cat_cafe")
        #expect(value.value(atPath: "categories.0.average") == 4_000)
        #expect(value.value(atPath: "categories.0.highest") == 9_000)
        #expect(value.value(atPath: "categories.0.limit") == 5_000)
        #expect(value.value(atPath: "categories.0.months_over") == 1)
        #expect(value.value(atPath: "categories.0.months.2.month") == "2026-09")
    }

    @Test func aRenameIsDraftedAndATwinIsRefused() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_category_change", input: ["category": "cat_cafe", "name": "Еда вне дома"])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["action"] == "rename")
        #expect(value["records"] == 2)
        guard case .categoryRename(let before, let name)? = book.drafts["draft_1"]?.operations.first else {
            Issue.record("expected a rename")
            return
        }
        #expect(before.id == "cat_cafe")
        #expect(name == "Еда вне дома")
        // Nothing is renamed before Save.
        #expect(store.categories.first?.name == "Кафе")

        let twin = await toolkit.execute(name: "draft_category_change", input: ["category": "cat_cafe", "name": "продукты"])
        #expect(twin.value == nil)
    }

    @Test func aMergeCountsTheRecordsItMoves() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_category_change", input: ["category": "Кафе", "merge_into": "cat_food"])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["action"] == "merge")
        #expect(value["into_id"] == "cat_food")
        guard case .categoryMerge(let from, let into, let records)? = book.drafts["draft_1"]?.operations.first else {
            Issue.record("expected a merge")
            return
        }
        #expect(from.id == "cat_cafe")
        #expect(into.id == "cat_food")
        #expect(records == 2)

        let mixed = await toolkit.execute(name: "draft_category_change", input: ["category": "cat_cafe", "merge_into": "cat_salary"])
        #expect(mixed.value == nil)
    }

    @Test func merchantsListTheirCategoriesAndARuleIsDrafted() async throws {
        let (toolkit, book, store) = Self.make()
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let output = await toolkit.merchantsResult(
            memory: MerchantCategoryMemory(defaults: defaults), groups: MerchantGroupStore(defaults: defaults)
        )
        #expect(output.value(atPath: "merchants.0.merchant") == "Glovo")
        #expect(output.value(atPath: "merchants.0.records") == 2)
        #expect(output.value(atPath: "merchants.0.categories.0.category") == "Кафе")
        #expect(output.value(atPath: "merchants.0.remembered_category") == JSONValue.null)
        #expect(output["merchants_total"] == 2)

        let rule = await toolkit.execute(name: "draft_merchant_rule", input: ["merchant": "Glovo", "category": "cat_food"])
        let value = try #require(rule.value, "\(rule.error ?? "")")
        #expect(value["records_in_other_categories"] == 2)
        let food: CustomCategory = store.categories[1]
        let expected: [AgentDraftOperation] = [AgentDraftOperation.merchantRule(merchant: "Glovo", category: food)]
        let drafted: [AgentDraftOperation] = book.drafts["draft_1"]?.operations ?? []
        #expect(drafted == expected)

        let income = await toolkit.execute(name: "draft_merchant_rule", input: ["merchant": "Glovo", "category": "cat_salary"])
        #expect(income.value == nil)
    }

    @Test func aSubcategoryDraftTagsTheMerchantsRecords() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let output = await toolkit.execute(name: "draft_subcategory", input: ["category": "cat_cafe", "name": "Доставка", "merchant": "glovo"])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["new"] == true)
        #expect(value["records"] == 2)
        let cafe: CustomCategory = store.categories[0]
        let ids: [String] = ["t_glovo", "t_coffee"]
        let expected: [AgentDraftOperation] = [AgentDraftOperation.subcategoryTag(category: cafe, name: "Доставка", transactionIds: ids)]
        let drafted: [AgentDraftOperation] = book.drafts["draft_1"]?.operations ?? []
        #expect(drafted == expected)

        let nobody = await toolkit.execute(name: "draft_subcategory", input: ["category": "cat_cafe", "name": "Доставка", "merchant": "magnum"])
        #expect(nobody.value == nil)
    }

    @Test func onlyAnUnusedCategoryIsDeleted() async throws {
        let (toolkit, book, store) = Self.make()
        _ = store
        let used = await toolkit.execute(name: "draft_category_change", input: ["category": "cat_cafe", "delete": true])
        #expect(used.value == nil)
        #expect(book.drafts.isEmpty)

        let unused = await toolkit.execute(name: "draft_category_change", input: ["category": "cat_gifts", "delete": true])
        let value = try #require(unused.value, "\(unused.error ?? "")")
        #expect(value["action"] == "delete")
        let gifts: CustomCategory = store.categories[2]
        let expected: [AgentDraftOperation] = [AgentDraftOperation.categoryDelete(gifts)]
        let drafted: [AgentDraftOperation] = book.drafts["draft_1"]?.operations ?? []
        #expect(drafted == expected)

        let both = await toolkit.execute(name: "draft_category_change", input: ["category": "cat_gifts", "delete": true, "name": "Подарочки"])
        #expect(both.value == nil)
    }
}
