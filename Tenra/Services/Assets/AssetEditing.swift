//
//  AssetEditing.swift
//  Tenra
//
//  The rules of changing an asset (docs/domains/assets.md), shared by its form (AssetEditView)
//  and Ten's draft_asset (finding A7 of the assets audit): a value typed is a valuation of
//  today, the sale price once sold, and nothing for a new asset bought today at that price (the
//  purchase is its only point); a new currency moves the purchase price and the valuations at
//  today's rates, or none of them without a rate.
//

import Foundation

nonisolated enum AssetEditing {
    /// A purchase made today at `value`: the purchase is the only point, no valuation.
    static func isPurchaseToday(value: Double, price: Double?, date: Date?, today: Date, calendar: Calendar = .current) -> Bool {
        guard let price, let date else { return false }
        return abs(price - value) < PersonalDebt.centTolerance && calendar.isDate(date, inSameDayAs: today)
    }

    /// The asset with a value typed for it: a sold one's sale price; a held one's valuation of
    /// today, except a new asset bought today at that price.
    static func applying(
        value: Double,
        to asset: Asset,
        isNew: Bool,
        today: Date,
        source: AssetValuation.Source = .manual,
        calendar: Calendar = .current
    ) -> Asset {
        var result = asset
        if result.isSold, let index = result.valuations.lastIndex(where: { $0.source == .sale }) {
            result.valuations[index].value = value
        } else if !isNew || !isPurchaseToday(value: value, price: result.purchasePrice, date: result.purchaseDate, today: today, calendar: calendar) {
            result.valuations.append(AssetValuation(date: today, value: value, source: source))
        }
        return result
    }

    /// The valuations and the purchase price in another currency, each through `convert` (today's
    /// rate, to the cent); nil when one of them cannot be converted, so the currency stays.
    static func moved(
        _ asset: Asset,
        convert: (Double) -> Double?
    ) -> (valuations: [AssetValuation], purchasePrice: Double?)? {
        var valuations: [AssetValuation] = []
        for valuation in asset.valuations {
            guard let value = convert(valuation.value) else { return nil }
            var copy = valuation
            copy.value = (value * 100).rounded() / 100
            if var listings = copy.listings, let low = convert(listings.low), let high = convert(listings.high) {
                listings.low = (low * 100).rounded() / 100
                listings.high = (high * 100).rounded() / 100
                copy.listings = listings
            } else {
                copy.listings = nil
            }
            valuations.append(copy)
        }
        var price: Double?
        if let purchase = asset.purchasePrice {
            guard let converted = convert(purchase) else { return nil }
            price = (converted * 100).rounded() / 100
        }
        return (valuations, price)
    }
}
