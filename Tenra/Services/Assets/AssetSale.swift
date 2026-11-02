//
//  AssetSale.swift
//  Tenra
//
//  The sale's money (plan-assets-roadmap 2.4, docs/domains/assets.md §Sale): selling an asset
//  makes no transaction, so its screen offers to record the money as an income, the price at
//  the person's share on the sale day in the asset's currency, until an income of the sale is
//  found. An income of the sale: in the weeks around the sale day (a deposit before it, a
//  transfer after), either at that amount in that currency or naming the asset.
//

import Foundation

enum AssetSale {
    /// Days before the sale day an income can be its money (a deposit taken first).
    static let daysBefore = 30
    /// Days after it (the buyer's transfer, a bank's payout).
    static let daysAfter = 90

    /// The person's money from the sale: the sale price at their share, to the cent; nil while
    /// the asset is held.
    static func proceeds(of asset: Asset) -> Double? {
        guard asset.isSold, let sale = asset.valuations.last(where: { $0.source == .sale }) else { return nil }
        return (sale.value * asset.ownershipShare * 100).rounded() / 100
    }

    /// The days an income can be the sale's money, as stored day keys ("yyyy-MM-dd", which
    /// sort as the days do); nil while held.
    static func window(of asset: Asset, calendar: Calendar = .current) -> ClosedRange<String>? {
        guard let soldAt = asset.soldAt else { return nil }
        let day = calendar.startOfDay(for: soldAt)
        guard let start = calendar.date(byAdding: .day, value: -daysBefore, to: day),
              let end = calendar.date(byAdding: .day, value: daysAfter, to: day) else { return nil }
        return DateFormatters.dateFormatter.string(from: start)...DateFormatters.dateFormatter.string(from: end)
    }

    /// The sale's money is among `incomes` (the incomes of its window): one at the proceeds in
    /// the asset's currency, to the cent, or one whose description names the asset.
    static func isRecorded(_ asset: Asset, among incomes: [Transaction]) -> Bool {
        guard let proceeds = proceeds(of: asset), let window = window(of: asset) else { return true }
        let name = asset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return incomes.contains { tx in
            guard tx.type == .income, window.contains(tx.date) else { return false }
            if tx.currency == asset.currency, abs(tx.amount - proceeds) < PersonalDebt.centTolerance {
                return true
            }
            return !name.isEmpty && tx.description.localizedCaseInsensitiveContains(name)
        }
    }

    /// The income's description the form starts with: "Sale: Camry", so it is found again.
    static func incomeDescription(of asset: Asset) -> String {
        String(format: String(localized: "asset.saleIncome.description"), asset.name)
    }
}
