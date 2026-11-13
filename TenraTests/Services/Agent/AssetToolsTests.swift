//
//  AssetToolsTests.swift
//  TenraTests
//
//  Ten and assets (FinanceToolkit+Assets.swift, phase 4 of archive/plans/plan-assets.md): <app_context> lists
//  the held assets by id, name and kind without amounts, and says "none" when there are none;
//  get_assets reports the app's own figures (AssetValuationMath) and the total in the base
//  currency; get_net_worth gives its lines (NetWorthCalculator); draft_asset files a new asset
//  (Tenra Pro, a valuation of today for what it is worth now) and draft_asset_valuation a value,
//  given or multiplied from an area and a price per unit on the phone; both save through
//  AssetStore and undo. estimate_asset_value sends the asset's kind, the country and its
//  characteristics (saved in its form, v19, with what the model gave over them; never the name)
//  to the server's valuation, asks for what the kind still needs before any search, and gives
//  its value against the app's; the server's refusals become what to tell the user. get_assets
//  lists what is saved and what is missing for an estimate. Amounts are KZT,
//  so no shared FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssetToolsTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    private struct Setup {
        let toolkit: FinanceToolkit
        let book: AgentDraftBook
        /// Retained: AccountsViewModel keeps it weakly.
        let store: TransactionStore
        let assets: AssetStore
        let debts: DebtStore
    }

    /// The server's `POST /v1/valuation`, answering what it is given.
    private nonisolated final class FakeValuation: AgentValuationTransport, @unchecked Sendable {
        private(set) var sent: [[String: JSONValue]] = []
        private let answer: Result<JSONValue, AgentServerError>

        init(_ answer: Result<JSONValue, AgentServerError>) {
            self.answer = answer
        }

        func valuation(asset: [String: JSONValue]) async throws -> JSONValue {
            sent.append(asset)
            return try answer.get()
        }
    }

    /// The server's answer for a flat priced by 14 listings.
    private static let estimate: JSONValue = [
        "status": "ok", "currency": "KZT", "value": 72_500_000, "low": 67_800_000, "high": 76_100_000,
        "accuracy": "medium", "basis": "per_unit", "count": 14,
        "per_unit": ["unit": "m2", "median": 1_130_000, "low": 1_060_000, "high": 1_190_000],
        "listings": [
            ["title": "Listings", "url": "https://krisha.kz/prodazha/kvartiry/almaty/", "site": "krisha.kz", "price": 70_000_000, "currency": "KZT", "size_m2": 62, "rooms": 2],
            ["title": "Listings", "url": "https://olx.kz/nedvizhimost/", "site": "olx.kz", "price": 74_000_000, "currency": "KZT", "size_m2": 66, "rooms": 2],
        ],
        "searched_at": "2026-10-28T10:00:00Z", "searches": 2, "model": "claude-haiku-5-5", "quota": ["used": 1, "limit": 30],
    ]

    private static func make(isPro: Bool = true, valuation: AgentValuationTransport? = nil) -> Setup {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_000),
        ]
        let assets = AssetStore(repository: nil)
        let debts = DebtStore(repository: nil)
        let book = AgentDraftBook(writer: AgentDraftBook.Writer(
            save: { try await AgentDraftBook.Writer.savePlan($0, goals: nil, debts: debts, assets: assets, isPro: { isPro }) },
            undo: { await AgentDraftBook.Writer.undoPlan($0, goals: nil, debts: debts, assets: assets) }
        ))
        let toolkit = FinanceToolkit(
            store: store,
            drafts: book,
            debts: debts,
            assets: assets,
            valuation: valuation,
            isPro: { isPro },
            learned: VoiceLearningStore(defaults: defaults),
            now: { now }
        )
        return Setup(toolkit: toolkit, book: book, store: store, assets: assets, debts: debts)
    }

    private static func day(_ key: String) -> Date {
        FastDateParser.date(from: key)!
    }

    /// The flat of the plan: 24M in 2018, valued 70M this month.
    private static var flat: Asset {
        Asset(
            id: "a_flat", name: "Квартира", kind: .apartment, currency: "KZT",
            purchaseDate: day("2018-10-29"), purchasePrice: 24_000_000,
            valuations: [AssetValuation(id: "v1", date: day("2026-10-16"), value: 70_000_000)]
        )
    }

    // MARK: - Context

    @Test func theContextListsHeldAssetsOrSaysNone() {
        let setup = Self.make()
        var sold = Self.flat
        sold.id = "a_old"
        sold.soldAt = Self.day("2026-01-01")
        let snapshot = AgentContextSnapshot(store: setup.store, assets: [Self.flat, sold], now: Self.now)
        let text = AgentContextBuilder.text(for: snapshot)
        #expect(text.contains(#"assets: a_flat "Квартира" (apartment, KZT)"#))
        #expect(!text.contains("a_old"))

        let none = AgentContextBuilder.text(for: AgentContextSnapshot(store: setup.store, now: Self.now))
        #expect(none.contains("\nassets: none\n"))
    }

    // MARK: - Read

    @Test func getAssetsReportsTheAppsFigures() async throws {
        let setup = Self.make()
        var flat = Self.flat
        flat.ownershipShare = 0.5
        await setup.assets.add(flat)

        let output = await setup.toolkit.execute(name: "get_assets", input: [:])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result.value(atPath: "assets.0.value")?.numberValue == 70_000_000)
        #expect(result.value(atPath: "assets.0.gain")?.numberValue == 46_000_000)
        #expect(result.value(atPath: "assets.0.gain_percent")?.numberValue == 191.7)
        #expect(result.value(atPath: "assets.0.share_percent")?.numberValue == 50)
        #expect(result.value(atPath: "assets.0.owned_value")?.numberValue == 35_000_000)
        #expect(result.value(atPath: "assets.0.out_of_date")?.boolValue == false)
        #expect(result.value(atPath: "assets.0.valued_on")?.stringValue == "2026-10-16")
        #expect(result["total_base"]?.numberValue == 35_000_000)
        #expect(result["gain_base"]?.numberValue == 23_000_000)
    }

    @Test func getNetWorthGivesItsLines() async throws {
        let setup = Self.make()
        await setup.assets.add(Self.flat)
        await setup.debts.add(PersonalDebt(id: "d_mum", direction: .iOwe, person: "Мама", amount: 100_000, currency: "KZT"))

        let output = await setup.toolkit.execute(name: "get_net_worth", input: [:])
        let result = try #require(output.value, "\(output.error ?? "")")
        let money = try #require(result["money"]?.numberValue)
        #expect(result["assets"]?.numberValue == 70_000_000)
        #expect(result["i_owe"]?.numberValue == 100_000)
        #expect(result["net_worth"]?.numberValue == money + 70_000_000 - 100_000)
        // Money always; the parts with something in them; owed to the person and loans are empty.
        #expect(result["lines"]?.arrayValue?.compactMap { $0["key"]?.stringValue } == ["money", "assets", "i_owe"])
        #expect(result.value(atPath: "lines.2.subtracted")?.boolValue == true)
    }

    // MARK: - Drafts

    @Test func draftAssetSavesAnAssetWorthItsValueAndUndoRemovesIt() async throws {
        let setup = Self.make()
        let output = await setup.toolkit.execute(name: "draft_asset", input: [
            "name": "Квартира", "kind": "apartment", "purchase_price": 24_000_000, "purchase_date": "2018-10-29", "value": 70_000_000,
        ])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["draft_id"] == "draft_1")
        #expect(result["value"]?.numberValue == 70_000_000)
        #expect(result["gain"]?.numberValue == 46_000_000)
        #expect(setup.assets.assets.isEmpty)

        await setup.book.save("draft_1")
        let saved = try #require(setup.assets.assets.first)
        #expect(saved.name == "Квартира")
        #expect(saved.valuations.map(\.source) == [.assistant])
        #expect(saved.currency == setup.store.baseCurrency)
        await setup.book.undo("draft_1")
        #expect(setup.assets.assets.isEmpty)

        // Neither a value nor a price, an unknown kind, a date without a price: refused.
        let empty = await setup.toolkit.execute(name: "draft_asset", input: ["name": "Дача", "kind": "house"])
        #expect(empty.error != nil)
        let odd = await setup.toolkit.execute(name: "draft_asset", input: ["name": "Яхта", "kind": "boat", "value": 1])
        #expect(odd.error != nil)
        let undated = await setup.toolkit.execute(name: "draft_asset", input: ["name": "Дача", "kind": "house", "value": 5, "purchase_date": "2020-01-01"])
        #expect(undated.error != nil)
    }

    @Test func aNewAssetNeedsProAndItsValuationDoesNot() async throws {
        let free = Self.make(isPro: false)
        let refused = await free.toolkit.execute(name: "draft_asset", input: ["name": "Машина", "kind": "vehicle", "value": 9_000_000])
        #expect(refused.error?.contains("Tenra Pro") == true)
        #expect(free.book.drafts.isEmpty)

        // An asset kept after Pro ended stays open to value.
        await free.assets.add(Self.flat)
        let output = await free.toolkit.execute(name: "draft_asset_valuation", input: ["asset": "a_flat", "value": 72_000_000])
        #expect(output.value != nil)
    }

    @Test func aValuationFromAnAreaIsMultipliedOnThePhone() async throws {
        let setup = Self.make()
        await setup.assets.add(Self.flat)
        let output = await setup.toolkit.execute(name: "draft_asset_valuation", input: [
            "asset": "a_flat", "area": 52, "price_per_unit": 1_400_000, "note": "krisha.kz",
        ])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result["value"]?.numberValue == 72_800_000)
        #expect(result["previous_value"]?.numberValue == 70_000_000)
        #expect(result["change"]?.numberValue == 2_800_000)
        #expect(result["change_percent"]?.numberValue == 4)

        let draftId = try #require(result["draft_id"]?.stringValue)
        await setup.book.save(draftId)
        #expect(setup.assets.summary(for: try #require(setup.assets.asset(id: "a_flat")), today: Self.now).value == 72_800_000)
        await setup.book.undo(draftId)
        #expect(setup.assets.asset(id: "a_flat")?.valuations.count == 1)

        // Without a value or both parts of one, and for a sold asset: refused.
        let half = await setup.toolkit.execute(name: "draft_asset_valuation", input: ["asset": "a_flat", "area": 52])
        #expect(half.error != nil)
        await setup.assets.sell(assetId: "a_flat", price: 75_000_000, date: Self.day("2026-10-27"))
        let sold = await setup.toolkit.execute(name: "draft_asset_valuation", input: ["asset": "a_flat", "value": 80_000_000])
        #expect(sold.error != nil)
    }

    // MARK: - Estimate from listings

    @Test func anEstimateSendsTheKindAndPlaceNeverTheNameAndComparesWithTheAppsValue() async throws {
        let server = FakeValuation(.success(Self.estimate))
        let setup = Self.make(valuation: server)
        await setup.assets.add(Self.flat)

        let output = await setup.toolkit.execute(name: "estimate_asset_value", input: [
            "asset": "a_flat", "country": "kz", "city": "Алматы", "district": "Бостандыкский", "area_m2": 64, "rooms": 2,
            "name": "Квартира на Абая", "notes": "anything else",
        ])
        let result = try #require(output.value, "\(output.error ?? "")")
        let sent = try #require(server.sent.first)
        #expect(sent["kind"] == "apartment")
        #expect(sent["country"] == "KZ")
        #expect(sent["area_m2"]?.numberValue == 64)
        #expect(sent["district"] == "Бостандыкский")
        #expect(!sent.keys.contains("name") && !sent.keys.contains("notes") && !sent.keys.contains("asset"))

        #expect(result["status"] == "ok")
        #expect(result["value_in_asset_currency"]?.numberValue == 72_500_000)
        #expect(result["low_in_asset_currency"]?.numberValue == 67_800_000)
        #expect(result["current_value"]?.numberValue == 70_000_000)
        #expect(result["change_percent"]?.numberValue == 3.6)
        #expect(result["count"]?.numberValue == 14)
        #expect(result["sites"] == ["krisha.kz", "olx.kz"])
        #expect(result["estimates_left"]?.numberValue == 29)
        // The model sees no links.
        #expect(result.value(atPath: "listings.0")?.objectValue?.keys.contains("url") == false)
        // Nothing is saved: the model offers draft_asset_valuation.
        #expect(setup.assets.asset(id: "a_flat")?.valuations.count == 1)
    }

    @Test func theServersRefusalsSayWhatToDoInstead() async throws {
        let cases: [(AgentServerError, String)] = [
            (.disabled, "not switched on"),
            (.quotaExceeded(limit: 30), "(30)"),
            (.invalidRequest(reason: "area_m2"), "area_m2"),
            (.regionUnavailable, "region"),
            (.busy, "try"),
        ]
        for (error, words) in cases {
            let setup = Self.make(valuation: FakeValuation(.failure(error)))
            await setup.assets.add(Self.flat)
            let output = await setup.toolkit.execute(name: "estimate_asset_value", input: ["asset": "a_flat", "city": "Алматы", "area_m2": 64])
            #expect(output.error?.contains(words) == true, "\(error): \(output.error ?? "no error")")
        }

        // Without the server, an unknown asset, a sold one: refused before any search.
        let offline = Self.make()
        await offline.assets.add(Self.flat)
        let unavailable = await offline.toolkit.execute(name: "estimate_asset_value", input: ["asset": "a_flat"])
        #expect(unavailable.error?.contains("not available") == true)
        let server = FakeValuation(.success(Self.estimate))
        let setup = Self.make(valuation: server)
        let unknown = await setup.toolkit.execute(name: "estimate_asset_value", input: ["asset": "a_none"])
        #expect(unknown.error != nil)
        await setup.assets.add(Self.flat)
        await setup.assets.sell(assetId: "a_flat", price: 75_000_000, date: Self.day("2026-10-27"))
        let sold = await setup.toolkit.execute(name: "estimate_asset_value", input: ["asset": "a_flat"])
        #expect(sold.error != nil)
        #expect(server.sent.isEmpty)
    }

    /// The characteristics saved in the form go with the estimate, what the user said in the
    /// chat over them; another kind's field, a later version's key and a value the server would
    /// refuse stay out.
    @Test func savedCharacteristicsGoWithTheEstimateAndTheChatsOverThem() async throws {
        let server = FakeValuation(.success(Self.estimate))
        let setup = Self.make(valuation: server)
        var flat = Self.flat
        flat.attributes = AssetAttributes([
            "country": .text("TR"), "city": .text("İstanbul"), "area_m2": .number(64), "rooms": .number(2),
            "building": .text("monolith"), "make": .text("Toyota"), "later_field": .text("kept"),
        ])
        await setup.assets.add(flat)

        let output = await setup.toolkit.execute(name: "estimate_asset_value", input: ["asset": "a_flat", "rooms": 3, "floor": 2.5])
        _ = try #require(output.value, "\(output.error ?? "")")
        let sent = try #require(server.sent.first)
        #expect(sent["country"] == "TR")
        #expect(sent["city"] == "İstanbul")
        #expect(sent["area_m2"]?.numberValue == 64)
        #expect(sent["rooms"]?.numberValue == 3)
        #expect(sent["building"] == "monolith")
        #expect(!sent.keys.contains("make") && !sent.keys.contains("floor") && !sent.keys.contains("later_field"))
    }

    /// Without what the kind needs (a flat's city and area), the model is told what to ask, and
    /// nothing is searched.
    @Test func anEstimateWithoutWhatTheKindNeedsAsksFirst() async {
        let server = FakeValuation(.success(Self.estimate))
        let setup = Self.make(valuation: server)
        await setup.assets.add(Self.flat)
        let output = await setup.toolkit.execute(name: "estimate_asset_value", input: ["asset": "a_flat", "rooms": 2])
        #expect(output.error?.contains("city") == true)
        #expect(output.error?.contains("area_m2") == true)
        #expect(server.sent.isEmpty)
    }

    @Test func getAssetsShowsWhatIsSavedForAnEstimate() async throws {
        let setup = Self.make()
        var flat = Self.flat
        flat.attributes = AssetAttributes(["country": .text("KZ"), "city": .text("Алматы"), "rooms": .number(2)])
        await setup.assets.add(flat)
        let output = await setup.toolkit.execute(name: "get_assets", input: [:])
        let result = try #require(output.value, "\(output.error ?? "")")
        #expect(result.value(atPath: "assets.0.characteristics.city")?.stringValue == "Алматы")
        #expect(result.value(atPath: "assets.0.characteristics.country")?.stringValue == "KZ")
        #expect(result.value(atPath: "assets.0.characteristics.rooms")?.numberValue == 2)
        #expect(result.value(atPath: "assets.0.missing_for_estimate") == ["area_m2"])
    }

    @Test func theContextSaysThisVersionEstimatesFromListings() {
        let setup = Self.make()
        let text = AgentContextBuilder.text(for: AgentContextSnapshot(store: setup.store, now: Self.now))
        #expect(text.contains("\nvaluation: listings\n"))
        // The line the server reads before offering the newer `open` destinations; its words
        // are the eval fixture's (server/assistant/eval/fixture.ts).
        #expect(text.contains("\nscreens: accounts, deposits, loans, goals, goal, debts, debt, settings, backups, wallet_guide, loan_payment, review, create (account, deposit, loan, category)\n"))
        #expect(AssistantStep(tool: "estimate_asset_value") == .valuing)
    }

    @Test func describeNamesWhatAnAssetDraftWrites() {
        let setup = Self.make()
        let described = setup.toolkit.describe(.asset(Self.flat))
        #expect(described["type"] == "asset")
        #expect(described["kind"] == "apartment")
        #expect(described["value"]?.numberValue == 70_000_000)
    }
}
