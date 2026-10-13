//
//  AgentReplyDataTests.swift
//  TenraTests
//
//  Reply blocks read their figures from tool results by reference: an amount keeps the
//  currency it was computed in, a percentage stays a percentage, and a reference that does not
//  resolve shows nothing.
//

import Foundation
import Testing
@testable import Tenra

struct AgentReplyDataTests {

    private let results: [String: JSONValue] = [
        "toolu_sum": [
            "currency": "KZT",
            "type": "expense",
            "total": 12_000,
            "count": 3,
            "groups": [
                ["key": "cat_food", "label": "Продукты", "total": 8_000, "count": 1, "share": 0.667],
                ["key": "cat_cafe", "label": "Кафе", "total": 4_000, "count": 2, "share": 0.333],
            ],
        ],
        "toolu_cmp": [
            "currency": "KZT",
            "type": "expense",
            "current": ["from": "2026-10-01", "to": "2026-10-31", "total": 12_000],
            "previous": ["from": "2026-09-01", "to": "2026-09-30", "total": 4_000],
            "change": 8_000,
            "change_percent": 200,
            "groups": [["key": "cat_food", "label": "Продукты", "current": 8_000, "previous": 0, "change": 8_000]],
        ],
        "toolu_months": [
            "currency": "KZT",
            "groups": [["key": "2026-09", "label": "2026-09", "total": 4_000], ["key": "2026-10", "label": "2026-10", "total": 12_000]],
        ],
        "toolu_acc": [
            "currency": "KZT",
            "total_base": 260_850,
            "accounts": [["id": "acc_usd", "currency": "USD", "balance": 500, "balance_base": 260_000]],
        ],
        "toolu_search": ["currency": "KZT", "count_total": 2, "items": [["id": "t2"], ["id": "t1"]]],
        "toolu_budgets": ["currency": "KZT", "budgets": [["category_id": "cat_cafe"], ["category_id": "cat_food"]]],
    ]

    @Test func amountsKeepTheirCurrency() throws {
        let metric = try #require(AgentReplyData.metric(label: "Расходы", source: "toolu_sum", path: "total", trendPath: nil, results: results))
        #expect(metric.value == .amount(12_000, currency: "KZT"))
        #expect(metric.isExpense)

        let usd = try #require(AgentReplyData.metric(label: "Доллары", source: "toolu_acc", path: "accounts.0.balance", trendPath: nil, results: results))
        #expect(usd.value == .amount(500, currency: "USD"))
        let inBase = try #require(AgentReplyData.metric(label: "В тенге", source: "toolu_acc", path: "accounts.0.balance_base", trendPath: nil, results: results))
        #expect(inBase.value == .amount(260_000, currency: "KZT"))
    }

    @Test func percentagesAndCountsAreNotMoney() throws {
        let change = try #require(AgentReplyData.metric(label: "Рост", source: "toolu_cmp", path: "change_percent", trendPath: nil, results: results))
        #expect(change.value == .percent(200))
        let count = try #require(AgentReplyData.metric(label: "Операций", source: "toolu_sum", path: "count", trendPath: nil, results: results))
        #expect(count.value == .count(3))
    }

    @Test func aTrendComesFromItsOwnPath() throws {
        let metric = try #require(AgentReplyData.metric(label: "Октябрь", source: "toolu_cmp", path: "current.total", trendPath: "change_percent", results: results))
        #expect(metric.value == .amount(12_000, currency: "KZT"))
        #expect(metric.changePercent == 200)
        // A trend path that is money, not a percentage, is not a trend badge.
        let noBadge = try #require(AgentReplyData.metric(label: "Октябрь", source: "toolu_cmp", path: "current.total", trendPath: "change", results: results))
        #expect(noBadge.changePercent == nil)
    }

    @Test func unresolvedReferencesShowNothing() {
        #expect(AgentReplyData.metric(label: "?", source: "toolu_missing", path: "total", trendPath: nil, results: results) == nil)
        #expect(AgentReplyData.metric(label: "?", source: "toolu_sum", path: "groups", trendPath: nil, results: results) == nil)
        #expect(AgentReplyData.chart(source: "toolu_sum", path: "total", results: results) == nil)
    }

    @Test func chartsReadGroups() throws {
        let categories = try #require(AgentReplyData.chart(source: "toolu_sum", path: "groups", results: results))
        #expect(categories.groups.map(\.label) == ["Продукты", "Кафе"])
        #expect(categories.groups.map(\.value) == [8_000, 4_000])
        #expect(categories.isTimeline == false)

        let compared = try #require(AgentReplyData.chart(source: "toolu_cmp", path: "groups", results: results))
        #expect(compared.groups.first?.value == 8_000)
        #expect(compared.groups.first?.previous == 0)

        let months = try #require(AgentReplyData.chart(source: "toolu_months", path: "groups", results: results))
        #expect(months.isTimeline)
    }

    @Test func listsGiveIdsInOrder() {
        #expect(AgentReplyData.transactionIds(source: "toolu_search", results: results) == ["t2", "t1"])
        #expect(AgentReplyData.budgetCategoryIds(source: "toolu_budgets", only: nil, results: results) == ["cat_cafe", "cat_food"])
        #expect(AgentReplyData.budgetCategoryIds(source: "toolu_budgets", only: ["cat_food"], results: results) == ["cat_food"])
        #expect(AgentReplyData.recurringIds(source: "toolu_missing", results: results).isEmpty)
    }
}
