//
//  WidgetSnapshotTests.swift
//  TenraTests
//
//  The app writes WidgetSnapshot as JSON and the widget extension reads it with its own copy of
//  the type (TenraWidgets/WidgetData.swift): the keys are the contract. Also the links the
//  widgets open (tenra://add).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct WidgetSnapshotTests {

    @Test("The JSON keys the widget extension reads")
    func keys() throws {
        let snapshot = WidgetSnapshot(
            day: "2026-10-22",
            currency: "KZT",
            amountsHidden: false,
            allowance: 8_400,
            incomeDay: "2026-10-25",
            spentToday: 3_200,
            categories: [.init(name: "Food", symbol: "fork.knife", colorHex: "#FF9500")]
        )
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        #expect(Set(object.keys) == ["version", "day", "currency", "amountsHidden", "allowance", "incomeDay", "spentToday", "categories"])
        let category = try #require((object["categories"] as? [[String: Any]])?.first)
        #expect(Set(category.keys) == ["name", "symbol", "colorHex"])
        #expect(object["version"] as? Int == 1)
    }

    @Test("The formats the widget reads, and a snapshot without them")
    func formatsKeys() throws {
        let formats = WidgetSnapshot.Formats(decimal: ",", grouping: "\u{00A0}", symbolBefore: false, cents: "whenPresent", dateStyle: "words")
        let snapshot = WidgetSnapshot(day: "2026-10-22", currency: "KZT", amountsHidden: false, allowance: nil,
                                      incomeDay: nil, spentToday: 0, categories: [], formats: formats)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let inner = try #require(object["formats"] as? [String: Any])
        #expect(Set(inner.keys) == ["decimal", "grouping", "symbolBefore", "cents", "dateStyle"])

        let india = WidgetSnapshot.Formats(decimal: ".", grouping: ",", symbolBefore: true, cents: "never", dateStyle: "iso", secondaryGrouping: 2)
        let withIndia = WidgetSnapshot(day: "d", currency: "INR", amountsHidden: false, allowance: nil, incomeDay: nil,
                                       spentToday: 0, categories: [], formats: india)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(withIndia))
        #expect(back.formats == india)

        let old = Data(#"{"version":1,"day":"d","currency":"KZT","amountsHidden":false,"spentToday":0,"categories":[]}"#.utf8)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: old).formats == nil)
    }

    @Test("tenra://add opens the assistant, with a category its add form")
    func links() throws {
        #expect(AppCoordinator.quickAdd(from: try #require(URL(string: "tenra://add"))) == .init(category: nil))
        #expect(AppCoordinator.quickAdd(from: try #require(URL(string: "tenra://add?category=Coffee%20shops"))) == .init(category: "Coffee shops"))
        #expect(AppCoordinator.quickAdd(from: try #require(URL(string: "tenra://add?category="))) == .init(category: nil))
        #expect(AppCoordinator.quickAdd(from: try #require(URL(string: "tenra://settings"))) == nil)
        #expect(AppCoordinator.quickAdd(from: URL(fileURLWithPath: "/tmp/statement.pdf")) == nil)
    }
}
