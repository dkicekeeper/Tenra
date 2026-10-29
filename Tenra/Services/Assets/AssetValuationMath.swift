//
//  AssetValuationMath.swift
//  Tenra
//
//  What an asset is worth and how it did (docs/domains/assets.md): the value (the latest
//  valuation, or the purchase price without one), the person's share of it, the gain over the
//  purchase price, the growth a year once a year has passed, and the person's own money in it
//  after the linked loan. Every screen (and Ten, later) takes these figures from here, never
//  its own maths, as GoalProgress does for goals. All amounts are in the asset's currency.
//

import Foundation

nonisolated enum AssetValuationMath {
    nonisolated struct Summary: Equatable {
        /// What the whole asset is worth (the sale price once sold).
        var value: Double
        /// The day of that figure: the latest valuation's, or the purchase's.
        var valuedOn: Date?
        /// `value` × the ownership share: what counts towards the person's net worth.
        var ownedValue: Double
        /// `value` − the purchase price; nil without a purchase price.
        var gain: Double?
        /// The gain as a percent of the purchase price (192 for 24M → 70M); nil without a
        /// purchase price above zero.
        var gainPercent: Double?
        /// `value` ÷ the purchase price (2.9 for 24M → 70M).
        var multiple: Double?
        /// The average growth a year, in percent; only once a year has passed since the
        /// purchase (until the sale for a sold asset), with both amounts above zero.
        var annualGrowthPercent: Double?
        /// What is left of the linked loan, in the asset's currency; nil without one (or once it
        /// is gone).
        var loanRemaining: Double?
        /// `ownedValue` − `loanRemaining`: the person's own money in the asset; nil without a
        /// loan.
        var equity: Double?
    }

    /// A loan's remaining principal, in its own currency.
    nonisolated struct LoanBalance: Equatable {
        var amount: Double
        var currency: String
    }

    /// Days in an average year, for the growth a year.
    static let daysPerYear = 365.25

    /// The purchase (when its price and day are known) and every valuation, oldest first: the
    /// points of the value chart and of the history list. Valuations of one day keep the order
    /// they were added in.
    static func history(of asset: Asset) -> [AssetValuation] {
        var points: [AssetValuation] = []
        if let price = asset.purchasePrice, let date = asset.purchaseDate {
            points.append(AssetValuation(id: purchasePointId(asset), date: date, value: price, source: .purchase))
        }
        let valuations = asset.valuations.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        points.append(contentsOf: valuations)
        return points
    }

    /// The id of the purchase point in `history`, which is not a stored valuation.
    static func purchasePointId(_ asset: Asset) -> String {
        "purchase:\(asset.id)"
    }

    /// The latest valuation by day (the later added one of a day), if any.
    static func latestValuation(of asset: Asset) -> AssetValuation? {
        asset.valuations.enumerated()
            .max { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }?
            .element
    }

    /// The value now: the sale price once sold, else the latest valuation, else the purchase
    /// price; nil when there is none of them.
    static func currentValue(of asset: Asset) -> Double? {
        if asset.isSold, let sale = asset.sale { return sale.value }
        return latestValuation(of: asset)?.value ?? asset.purchasePrice
    }

    static func summary(
        of asset: Asset,
        loan: LoanBalance? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let latest = asset.isSold ? (asset.sale ?? latestValuation(of: asset)) : latestValuation(of: asset)
        let value = latest?.value ?? asset.purchasePrice ?? 0
        let valuedOn = latest?.date ?? asset.purchaseDate
        let share = min(1, max(0, asset.ownershipShare))
        let ownedValue = value * share

        var gain: Double?
        var gainPercent: Double?
        var multiple: Double?
        var annualGrowth: Double?
        if let price = asset.purchasePrice {
            gain = value - price
            if price > 0 {
                gainPercent = (value - price) / price * 100
                multiple = value / price
                let end = asset.soldAt ?? today
                if let start = asset.purchaseDate, value > 0,
                   let years = years(from: start, to: end, calendar: calendar), years >= 1 {
                    annualGrowth = (pow(value / price, 1 / years) - 1) * 100
                }
            }
        }

        var loanRemaining: Double?
        var equity: Double?
        if let loan, !asset.isSold {
            let remaining = loan.currency == asset.currency
                ? loan.amount
                : CurrencyConverter.convertSync(amount: loan.amount, from: loan.currency, to: asset.currency) ?? loan.amount
            loanRemaining = remaining
            equity = ownedValue - remaining
        }

        return Summary(
            value: value,
            valuedOn: valuedOn,
            ownedValue: ownedValue,
            gain: gain,
            gainPercent: gainPercent,
            multiple: multiple,
            annualGrowthPercent: annualGrowth,
            loanRemaining: loanRemaining,
            equity: equity
        )
    }

    /// A total on a day.
    nonisolated struct DatedValue: Equatable {
        var date: Date
        var value: Double
    }

    /// What the assets were worth over time, each at the person's share: a point on every day a
    /// purchase or a valuation happened, an asset counted from its first point on at its latest
    /// value up to that day (one without any dated point at its value throughout). `convert`
    /// moves an asset's amount into the total's currency (today's rates). The latest
    /// `limit` points.
    static func totalHistory(
        of assets: [Asset],
        limit: Int = 24,
        calendar: Calendar = .current,
        convert: (Double, Asset) -> Double
    ) -> [DatedValue] {
        let histories = assets.map { asset in
            (asset: asset, points: history(of: asset).map { (day: calendar.startOfDay(for: $0.date), value: $0.value) })
        }
        let days = Set(histories.flatMap { $0.points.map(\.day) }).sorted()
        let share = { (asset: Asset) in min(1, max(0, asset.ownershipShare)) }
        let points = days.map { day in
            let total = histories.reduce(0.0) { sum, item in
                let value: Double
                if item.points.isEmpty {
                    value = currentValue(of: item.asset) ?? 0
                } else {
                    value = item.points.last { $0.day <= day }?.value ?? 0
                }
                return sum + convert(value * share(item.asset), item.asset)
            }
            return DatedValue(date: day, value: total)
        }
        return Array(points.suffix(limit))
    }

    /// Whole and part years between two days; nil when the end is before the start.
    static func years(from start: Date, to end: Date, calendar: Calendar = .current) -> Double? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        guard days >= 0 else { return nil }
        return Double(days) / daysPerYear
    }
}
