//
//  AssetSaleTests.swift
//  TenraTests
//
//  The sale's money (plan-assets-roadmap 2.4, docs/domains/assets.md §Sale): the proceeds are
//  the sale price at the person's share, and the money counts as recorded once an income of
//  the weeks around the sale day has that amount in the asset's currency, or names the asset.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssetSaleTests {

    /// The calendar the stored day keys are written in.
    private static let calendar = Calendar.current

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func soldCar(price: Double = 8_000_000, share: Double = 1) -> Asset {
        Asset(
            name: "Camry",
            kind: .vehicle,
            currency: "KZT",
            purchaseDate: Self.day(2022, 5, 1),
            purchasePrice: 10_000_000,
            valuations: [AssetValuation(date: Self.day(2026, 9, 10), value: price, source: .sale)],
            ownershipShare: share,
            soldAt: Self.day(2026, 9, 10)
        )
    }

    private func income(_ amount: Double, on date: String, currency: String = "KZT", description: String = "", type: TransactionType = .income) -> Transaction {
        Transaction(id: UUID().uuidString, date: date, description: description, amount: amount, currency: currency, type: type, category: "Other", accountId: "card")
    }

    @Test("The proceeds: the sale price at the person's share, none while held")
    func proceeds() {
        #expect(AssetSale.proceeds(of: soldCar()) == 8_000_000)
        #expect(AssetSale.proceeds(of: soldCar(price: 8_000_001, share: 0.5)) == 4_000_000.5)
        var held = soldCar()
        held.soldAt = nil
        held.valuations = []
        #expect(AssetSale.proceeds(of: held) == nil)
        #expect(AssetSale.window(of: held) == nil)
    }

    @Test("The window: a month before the sale day to three months after")
    func window() throws {
        let window = try #require(AssetSale.window(of: soldCar()))
        #expect(window.lowerBound == "2026-08-11")
        #expect(window.upperBound == "2026-12-09")
    }

    @Test("Recorded: an income at the proceeds in the asset's currency, inside the window")
    func recordedByAmount() {
        let car = soldCar(share: 0.5)
        #expect(AssetSale.isRecorded(car, among: [income(4_000_000, on: "2026-09-12")]))
        // Another amount, another currency, outside the window, or an expense: not the sale.
        #expect(!AssetSale.isRecorded(car, among: [income(3_900_000, on: "2026-09-12")]))
        #expect(!AssetSale.isRecorded(car, among: [income(4_000_000, on: "2026-09-12", currency: "USD")]))
        #expect(!AssetSale.isRecorded(car, among: [income(4_000_000, on: "2027-01-15")]))
        #expect(!AssetSale.isRecorded(car, among: [income(4_000_000, on: "2026-09-12", type: .expense)]))
    }

    @Test("Recorded: an income naming the asset, whatever its amount")
    func recordedByName() {
        let car = soldCar()
        #expect(AssetSale.isRecorded(car, among: [income(7_850_000, on: "2026-09-20", description: "Sale: camry, after fees")]))
        #expect(!AssetSale.isRecorded(car, among: [income(7_850_000, on: "2026-09-20", description: "Salary")]))
    }

    @Test("A held asset has nothing to record")
    func heldIsRecorded() {
        var held = soldCar()
        held.soldAt = nil
        #expect(AssetSale.isRecorded(held, among: []))
    }
}
