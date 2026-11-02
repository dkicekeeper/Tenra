//
//  AssetValuationMath.swift
//  Tenra
//
//  What an asset is worth and how it did (docs/domains/assets.md): the value (the latest
//  valuation, or the purchase price without one, less the depreciation since when the asset has
//  a rule), the person's share of it, the gain over the purchase price, the growth a year once a
//  year has passed, the person's own money in it after the linked loan, and whether the
//  valuation is out of date. Every screen and Ten take these figures from here, never their own
//  maths, as GoalProgress does for goals. All amounts are in the asset's currency.
//

import Foundation

nonisolated enum AssetValuationMath {
    nonisolated struct Summary: Equatable {
        /// What the whole asset is worth (the sale price once sold).
        var value: Double
        /// The day of the figure it comes from: the latest valuation's, or the purchase's.
        var valuedOn: Date?
        /// `value` is that figure less the depreciation since it (shown with "≈").
        var isEstimate = false
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

    /// The purchase (when its price and day are known) and every valuation, by day: the points
    /// of the value chart and of the history list. The purchase comes first in its day, and
    /// valuations of one day keep the order they were added in; a valuation dated before the
    /// purchase comes before it.
    static func history(of asset: Asset, calendar: Calendar = .current) -> [AssetValuation] {
        var points: [(day: Date, rank: Int, valuation: AssetValuation)] = []
        if let price = asset.purchasePrice, let date = asset.purchaseDate {
            let purchase = AssetValuation(id: purchasePointId(asset), date: date, value: price, source: .purchase)
            points.append((calendar.startOfDay(for: date), -1, purchase))
        }
        for (offset, valuation) in asset.valuations.enumerated() {
            points.append((calendar.startOfDay(for: valuation.date), offset, valuation))
        }
        return points.sorted { ($0.day, $0.rank) < ($1.day, $1.rank) }.map(\.valuation)
    }

    /// The latest point of `history` but the sale: the purchase, when no valuation is later.
    static func latestPoint(of asset: Asset, calendar: Calendar = .current) -> AssetValuation? {
        history(of: asset, calendar: calendar).last { $0.source != .sale }
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

    /// The value now: the sale price once sold, else the latest point (a valuation, or the
    /// purchase when it is later), else the purchase price; nil when there is none of them.
    static func currentValue(of asset: Asset) -> Double? {
        if asset.isSold, let sale = asset.sale { return sale.value }
        return latestPoint(of: asset)?.value ?? asset.purchasePrice
    }

    static func summary(
        of asset: Asset,
        loan: LoanBalance? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let latest = asset.isSold
            ? (asset.sale ?? latestPoint(of: asset, calendar: calendar))
            : latestPoint(of: asset, calendar: calendar)
        var value = latest?.value ?? asset.purchasePrice ?? 0
        var valuedOn = latest?.date ?? asset.purchaseDate
        var isEstimate = false
        // A held asset with a depreciation rule: its value today, from the latest point.
        if !asset.isSold, depreciationRate(of: asset) != nil,
           let estimated = estimate(timeline(of: asset, calendar: calendar), on: today, calendar: calendar) {
            value = estimated.value
            valuedOn = estimated.basedOn ?? valuedOn
            isEstimate = estimated.isEstimate
        }
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
                   let span = years(from: start, to: end, calendar: calendar), span >= 1 {
                    annualGrowth = (pow(value / price, 1 / span) - 1) * 100
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
            isEstimate: isEstimate,
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
    nonisolated struct DatedValue: Equatable, Sendable {
        var date: Date
        var value: Double
    }

    /// What the assets were worth over time, each at the person's share: a point on every day a
    /// purchase or a valuation happened (and today, when an asset loses value by its rule), an
    /// asset counted from its first point on at its value on that day (one without any dated
    /// point at its value throughout). `convert` moves an asset's amount into the total's
    /// currency (today's rates). The latest `limit` points.
    static func totalHistory(
        of assets: [Asset],
        limit: Int = 24,
        today: Date = Date(),
        calendar: Calendar = .current,
        convert: (Double, Asset) -> Double
    ) -> [DatedValue] {
        let timelines = assets.map { (asset: $0, timeline: timeline(of: $0, calendar: calendar)) }
        var days = Set(timelines.flatMap { $0.timeline.points.map(\.date) })
        if timelines.contains(where: { $0.timeline.depreciationPerYear != nil && !$0.timeline.points.isEmpty }) {
            days.insert(calendar.startOfDay(for: today))
        }
        let points = days.sorted().map { day in
            let total = timelines.reduce(0.0) { sum, item in
                let value = estimate(item.timeline, on: day, calendar: calendar)?.value ?? 0
                return sum + convert(value * item.timeline.share, item.asset)
            }
            return DatedValue(date: day, value: total)
        }
        return Array(points.suffix(limit))
    }

    // MARK: - Charts by time (D3)

    /// The days of a chart that runs evenly in time: DesignKit's sparklines space their points
    /// evenly, so a purchase in 2018 and two valuations in 2026 took a third of the width each
    /// (the owner's decision D3, 2026-11-02: resample here). `start`, then a month apart (a few
    /// months when the span is long, at most `limit` days), then `end`.
    static func chartDays(from start: Date, to end: Date, limit: Int = 48, calendar: Calendar = .current) -> [Date] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard last > first else { return [first] }
        let months = max(1, calendar.dateComponents([.month], from: first, to: last).month ?? 1)
        let step = max(1, Int((Double(months) / Double(max(1, limit - 1))).rounded(.up)))
        var days = [first]
        var index = 1
        while let next = calendar.date(byAdding: .month, value: step * index, to: first), next < last {
            days.append(next)
            index += 1
        }
        days.append(last)
        return days
    }

    /// An asset's value over time on `chartDays`, from its first dated point to today: its value
    /// on each day (less the depreciation, with a rule); a sold one ends on its sale price on the
    /// sale day. Empty without a dated point.
    static func chartHistory(of asset: Asset, today: Date = Date(), limit: Int = 48, calendar: Calendar = .current) -> [DatedValue] {
        let line = timeline(of: asset, calendar: calendar)
        guard let first = line.points.first?.date else { return [] }
        let end = asset.soldAt ?? today
        var points = chartDays(from: first, to: end, limit: limit, calendar: calendar).compactMap { day in
            estimate(line, on: day, calendar: calendar).map { DatedValue(date: day, value: $0.value) }
        }
        if asset.isSold, let sale = asset.sale {
            points.append(DatedValue(date: calendar.startOfDay(for: sale.date), value: sale.value))
        }
        return points
    }

    /// The assets' total over time on `chartDays`, from the first dated point of any of them to
    /// today, each at its share and in the total's currency (`convert`); an asset counts from its
    /// first point on, one without a dated point throughout (as `totalHistory`).
    static func totalChartHistory(
        of assets: [Asset],
        today: Date = Date(),
        limit: Int = 48,
        calendar: Calendar = .current,
        convert: (Double, Asset) -> Double
    ) -> [DatedValue] {
        let timelines = assets.map { (asset: $0, timeline: timeline(of: $0, calendar: calendar)) }
        guard let first = timelines.compactMap({ $0.timeline.points.first?.date }).min() else { return [] }
        return chartDays(from: first, to: today, limit: limit, calendar: calendar).map { day in
            let total = timelines.reduce(0.0) { sum, item in
                let value = estimate(item.timeline, on: day, calendar: calendar)?.value ?? 0
                return sum + convert(value * item.timeline.share, item.asset)
            }
            return DatedValue(date: day, value: total)
        }
    }

    // MARK: - Value on a day (phase 3)

    /// What an asset is worth on any day, without the asset itself (net worth's history reads it
    /// off the main actor): its dated points up to the sale, its depreciation, its share.
    nonisolated struct Timeline: Equatable, Sendable {
        /// The purchase and the valuations, without the sale, oldest first, at each day's start.
        var points: [DatedValue]
        /// The value of an asset without a dated point (a price without a day): counted
        /// throughout.
        var undatedValue: Double?
        /// The share of the value lost each year after a point; nil keeps the point's value.
        var depreciationPerYear: Double?
        /// From this day on the asset is gone.
        var soldAt: Date?
        /// 0…1.
        var share: Double
        var currency: String
    }

    /// A value on a day and the point it comes from.
    nonisolated struct Estimate: Equatable, Sendable {
        var value: Double
        /// The day of the point; nil for an asset without a dated point.
        var basedOn: Date?
        /// The point's value less the depreciation since it.
        var isEstimate: Bool
    }

    /// The asset's depreciation a year, when it has a rule: above 0, below 1.
    static func depreciationRate(of asset: Asset) -> Double? {
        guard let rate = asset.depreciationPerYear, rate > 0, rate < 1 else { return nil }
        return rate
    }

    /// Years ahead the depreciation forecast looks (plan-assets-roadmap 2.9).
    static let forecastYears = 3

    /// What a held asset that depreciates will be worth in `years` years: its rate from the
    /// latest dated point (the purchase or a valuation), the whole asset as the hero shows it.
    /// Nil without a rate, once sold, or without a dated point (nothing to wear from).
    static func forecast(
        of asset: Asset,
        today: Date = Date(),
        years: Int = forecastYears,
        calendar: Calendar = .current
    ) -> DatedValue? {
        guard !asset.isSold, depreciationRate(of: asset) != nil,
              let day = calendar.date(byAdding: .year, value: years, to: calendar.startOfDay(for: today)),
              let estimate = estimate(timeline(of: asset, calendar: calendar), on: day, calendar: calendar),
              estimate.isEstimate else { return nil }
        return DatedValue(date: day, value: estimate.value)
    }

    static func timeline(of asset: Asset, calendar: Calendar = .current) -> Timeline {
        let points = history(of: asset, calendar: calendar)
            .filter { $0.source != .sale }
            .map { DatedValue(date: calendar.startOfDay(for: $0.date), value: $0.value) }
        return Timeline(
            points: points,
            undatedValue: points.isEmpty ? (latestValuation(of: asset)?.value ?? asset.purchasePrice) : nil,
            depreciationPerYear: depreciationRate(of: asset),
            soldAt: asset.soldAt.map { calendar.startOfDay(for: $0) },
            share: min(1, max(0, asset.ownershipShare)),
            currency: asset.currency
        )
    }

    /// The value on `day`: the latest point up to it, less the depreciation for the years since
    /// (`value × (1 − rate)^years`, in whole units of its currency: an estimate has no cents).
    /// nil before the first point (not owned yet) and from the sale on; an asset without a dated
    /// point is worth its value throughout.
    static func estimate(_ timeline: Timeline, on day: Date, calendar: Calendar = .current) -> Estimate? {
        let start = calendar.startOfDay(for: day)
        if let soldAt = timeline.soldAt, start >= soldAt { return nil }
        guard !timeline.points.isEmpty else {
            return timeline.undatedValue.map { Estimate(value: $0, basedOn: nil, isEstimate: false) }
        }
        guard let base = timeline.points.last(where: { $0.date <= start }) else { return nil }
        guard let rate = timeline.depreciationPerYear,
              let span = years(from: base.date, to: start, calendar: calendar), span > 0 else {
            return Estimate(value: base.value, basedOn: base.date, isEstimate: false)
        }
        return Estimate(value: (base.value * pow(1 - rate, span)).rounded(), basedOn: base.date, isEstimate: true)
    }

    // MARK: - Out of date (phase 3)

    /// Months after which a valuation is out of date: prices of homes and cars move, so six;
    /// twelve for the rest.
    static func staleAfterMonths(_ kind: AssetKind) -> Int {
        kind.group == .other ? 12 : 6
    }

    /// The day the value was last set: the latest point (a valuation, or the purchase when it is
    /// later), else the purchase, else when the asset was added.
    static func lastValuedOn(_ asset: Asset, calendar: Calendar = .current) -> Date {
        latestPoint(of: asset, calendar: calendar)?.date ?? asset.purchaseDate ?? asset.createdAt
    }

    /// A held asset whose value was last set more than `staleAfterMonths` ago: its card says so
    /// and Ten reminds once a half-year.
    static func isStale(_ asset: Asset, today: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !asset.isSold,
              let limit = calendar.date(byAdding: .month, value: -staleAfterMonths(asset.kind), to: calendar.startOfDay(for: today))
        else { return false }
        return calendar.startOfDay(for: lastValuedOn(asset, calendar: calendar)) < limit
    }

    // MARK: - Rent and upkeep

    /// A transaction of an asset's rent or upkeep, in the asset's currency.
    nonisolated struct DatedAmount: Equatable, Sendable {
        var date: Date
        var amount: Double
    }

    /// What an asset brings in and costs (phase 2 of the plan), in its currency. A figure is nil
    /// when the asset has no link of its kind.
    nonisolated struct IncomeSummary: Equatable {
        /// Rent over the 12 months up to today (up to the sale for a sold asset).
        var rentYear: Double?
        /// Upkeep (tax, the building's fees, repairs) over the same 12 months.
        var upkeepYear: Double?
        /// (rent − upkeep) over 12 months as a percent of the value (of the person's share of it,
        /// with `yieldOnShare`); needs a rent link and a value above zero.
        var yieldPercent: Double?
        /// Every rent since the purchase (all of it without a purchase day).
        var rentTotal: Double?
        var upkeepTotal: Double?
        /// The gain (the share's, with `yieldOnShare`) plus every rent minus every upkeep; needs a
        /// purchase price and a link.
        var fullResult: Double?
        /// Any rent recorded at all (none: the screen offers to record it).
        var hasRent: Bool
    }

    static func income(
        rent: [DatedAmount]?,
        upkeep: [DatedAmount]?,
        summary: Summary,
        purchaseDate: Date?,
        soldAt: Date?,
        onShare share: Double? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> IncomeSummary {
        let todayStart = calendar.startOfDay(for: today)
        let end = soldAt.map { min(calendar.startOfDay(for: $0), todayStart) } ?? todayStart
        let yearStart = calendar.date(byAdding: .year, value: -1, to: end) ?? end
        let since = purchaseDate.map { calendar.startOfDay(for: $0) }

        /// The amounts dated after `after` (when given), from `from` on (when given) and up to
        /// `end`: realized ones only.
        func sum(_ items: [DatedAmount]?, after: Date? = nil, from: Date? = nil) -> Double? {
            guard let items else { return nil }
            return items.reduce(0.0) { total, item in
                let day = calendar.startOfDay(for: item.date)
                guard day <= end,
                      after.map({ day > $0 }) ?? true,
                      from.map({ day >= $0 }) ?? true else { return total }
                return total + item.amount
            }
        }

        let rentYear = sum(rent, after: yearStart)
        let upkeepYear = sum(upkeep, after: yearStart)
        let rentTotal = sum(rent, from: since)
        let upkeepTotal = sum(upkeep, from: since)
        var yield: Double?
        // By default of the whole value; of the person's share when the asset asks for it (D2:
        // the rent a co-owner records is their own).
        let part = share.map { min(1, max(0, $0)) } ?? 1
        let base = summary.value * part
        if let rentYear, base > 0 {
            yield = (rentYear - (upkeepYear ?? 0)) / base * 100
        }
        var fullResult: Double?
        if let gain = summary.gain, rentTotal != nil || upkeepTotal != nil {
            fullResult = gain * part + (rentTotal ?? 0) - (upkeepTotal ?? 0)
        }
        return IncomeSummary(
            rentYear: rentYear,
            upkeepYear: upkeepYear,
            yieldPercent: yield,
            rentTotal: rentTotal,
            upkeepTotal: upkeepTotal,
            fullResult: fullResult,
            hasRent: !(rent ?? []).isEmpty
        )
    }

    /// Two links count the same transactions: one category, and either of them takes all of it
    /// (no subcategory) or both take a subcategory in common. Two assets held at the same time
    /// may not share them, else the rent of two flats under one "Rent" counts twice.
    static func overlaps(_ a: AssetCategoryLink, _ b: AssetCategoryLink) -> Bool {
        a.categoryId == b.categoryId
            && (a.isWholeCategory || b.isWholeCategory || !Set(a.subcategoryIds).isDisjoint(with: b.subcategoryIds))
    }

    /// The days an asset is held: from its purchase day (open without one) to its sale day
    /// (open while it is held). Its rent and upkeep are the payments of these days (the owner's
    /// car, 2026-11-02: bought in June 2021, it counted the repairs of the car before it).
    struct HeldPeriod: Equatable {
        var start: Date?
        var end: Date?

        func contains(_ day: Date, calendar: Calendar = .current) -> Bool {
            let day = calendar.startOfDay(for: day)
            if let start, day < calendar.startOfDay(for: start) { return false }
            if let end, day > calendar.startOfDay(for: end) { return false }
            return true
        }
    }

    static func heldPeriod(of asset: Asset) -> HeldPeriod {
        HeldPeriod(start: asset.purchaseDate, end: asset.soldAt)
    }

    /// Two held periods share more than a day: one sold on the day the next was bought (a car
    /// replaced by the next) do not.
    static func overlaps(_ a: HeldPeriod, _ b: HeldPeriod, calendar: Calendar = .current) -> Bool {
        if let aStart = a.start, let bEnd = b.end,
           calendar.startOfDay(for: aStart) >= calendar.startOfDay(for: bEnd) { return false }
        if let bStart = b.start, let aEnd = a.end,
           calendar.startOfDay(for: bStart) >= calendar.startOfDay(for: aEnd) { return false }
        return true
    }

    /// Two assets' links count the same transactions: the links overlap and so do the days the
    /// assets are held. A car sold before the next one was bought may keep the same "Transport".
    static func overlaps(
        _ a: AssetCategoryLink, held aHeld: HeldPeriod,
        _ b: AssetCategoryLink, held bHeld: HeldPeriod
    ) -> Bool {
        overlaps(a, b) && overlaps(aHeld, bHeld)
    }

    /// Whole and part years between two days; nil when the end is before the start.
    static func years(from start: Date, to end: Date, calendar: Calendar = .current) -> Double? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        guard days >= 0 else { return nil }
        return Double(days) / daysPerYear
    }
}
