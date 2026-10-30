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
//  AssetStore and undo. Amounts are KZT, so no shared FX state is involved.
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

    private static func make(isPro: Bool = true) -> Setup {
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

    @Test func describeNamesWhatAnAssetDraftWrites() {
        let setup = Self.make()
        let described = setup.toolkit.describe(.asset(Self.flat))
        #expect(described["type"] == "asset")
        #expect(described["kind"] == "apartment")
        #expect(described["value"]?.numberValue == 70_000_000)
    }
}
