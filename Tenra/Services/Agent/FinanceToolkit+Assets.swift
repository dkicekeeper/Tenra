//
//  FinanceToolkit+Assets.swift
//  Tenra
//
//  Ten's tools for assets and net worth (docs/domains/assets.md, docs/domains/assistant.md §3,
//  archive/plans/plan-assets.md §7). `get_assets` reads every held asset (and the latest sold ones) with the
//  app's own figures (AssetValuationMath through AssetStore: the value, the gain, the growth a
//  year, the share, the loan, rent and upkeep, out of date); `get_net_worth` gives its parts
//  (NetWorthCalculator) and its months (the net worth insight). `draft_asset` and
//  `draft_asset_valuation` file drafts the person saves on the confirm card, through AssetStore.
//  New assets are Tenra Pro: without it `draft_asset` says so. A valuation can come from an area
//  and a price per unit the person found in listings: the phone multiplies them, never the
//  model. Input shapes are the contract in server/assistant/src/tools.ts.
//

import Foundation

extension FinanceToolkit {
    /// Sold assets listed by `get_assets`, the latest sale first.
    static let soldAssetsListed = 5

    /// Months of net worth `get_net_worth` gives for a chart.
    static let netWorthMonthsListed = 12

    // MARK: - Read

    /// `get_assets`: the held assets (and the latest sold ones) with their value, the day it was
    /// set, whether it is an estimate or out of date, the purchase, the gain and growth a year,
    /// the share and the loan, rent and upkeep over 12 months and the yield; the owned value in
    /// the base currency, and what the held ones counted in net worth come to.
    func assetsResult() async throws -> AgentToolOutput {
        guard let assets else { return .failure(Self.notYet("get_assets")) }
        await assets.load()
        await loadMissingRates(assets.assets.map(\.currency))
        let today = now()
        let base = store.baseCurrency
        let rates = RateSnapshot()
        var total = 0.0
        var gainTotal = 0.0
        var hasGain = false
        var missingRates: Set<String> = []

        let listed = assets.held + assets.sold.prefix(Self.soldAssetsListed)
        let items: [JSONValue] = listed.map { asset in
            let summary = assets.summary(for: asset, today: today)
            let income = assets.incomeSummary(for: asset, today: today)
            let ownedBase = Self.inBase(summary.ownedValue, asset.currency, base, rates)
            let counted = !asset.isSold && asset.includeInNetWorth
            if counted {
                if let owned = ownedBase.numberValue {
                    total += owned
                    if let gain = summary.gain, let gainBase = Self.inBase(gain * min(1, max(0, asset.ownershipShare)), asset.currency, base, rates).numberValue {
                        gainTotal += gainBase
                        hasGain = true
                    }
                } else {
                    missingRates.insert(asset.currency)
                }
            }
            let number = { (value: Double?) in value.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null }
            let percent = { (value: Double?) in value.map { JSONValue.number(($0 * 10).rounded() / 10) } ?? .null }
            let day = { (date: Date?) in date.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null }
            // Typed up front: a literal this long is slow to infer from the return alone.
            let row: [String: JSONValue] = [
                "id": .string(asset.id),
                "name": .string(asset.name),
                "kind": .string(asset.kind.rawValue),
                "currency": .string(asset.currency),
                "value": .number(FinanceToolkitCompute.round2(summary.value)),
                "value_base": Self.inBase(summary.value, asset.currency, base, rates),
                "valued_on": day(summary.valuedOn),
                "is_estimate": .bool(summary.isEstimate),
                "out_of_date": .bool(AssetValuationMath.isStale(asset, today: today, calendar: calendar)),
                "purchase_price": number(asset.purchasePrice),
                "purchase_date": day(asset.purchaseDate),
                "gain": number(summary.gain),
                "gain_percent": percent(summary.gainPercent),
                "annual_growth_percent": percent(summary.annualGrowthPercent),
                "depreciation_percent_a_year": percent(AssetValuationMath.depreciationRate(of: asset).map { $0 * 100 }),
                "share_percent": .number((min(1, max(0, asset.ownershipShare)) * 100).rounded()),
                "owned_value": .number(FinanceToolkitCompute.round2(summary.ownedValue)),
                "owned_value_base": ownedBase,
                "loan_left": number(summary.loanRemaining),
                "own_money_in_it": number(summary.equity),
                "rent_last_12_months": number(income.rentYear),
                "upkeep_last_12_months": number(income.upkeepYear),
                "rental_yield_percent": percent(income.yieldPercent),
                "full_result": number(income.fullResult),
                "counted_in_net_worth": .bool(counted),
                "sold": .bool(asset.isSold),
                "sold_on": day(asset.soldAt),
            ]
            return .object(row)
        }
        return .success([
            "assets": .array(items),
            "total_base": .number(FinanceToolkitCompute.round2(total)),
            "gain_base": hasGain ? .number(FinanceToolkitCompute.round2(gainTotal)) : .null,
            "currency": .string(base),
            "missing_rates": .array(missingRates.sorted().map(JSONValue.string)),
        ])
    }

    /// `get_net_worth`: money on the accounts, the assets, what others owe, the loans and what
    /// the person owes, in the base currency (NetWorthCalculator, as the net worth insight), as
    /// lines for a chart and as fields for metrics; and net worth at the end of each of the last
    /// months, when the insights have computed them.
    func netWorthResult() async throws -> AgentToolOutput {
        if let assets { await assets.load() }
        if let debts { await debts.load() }
        let base = store.baseCurrency
        let holdings = NetWorthCalculator.Holdings(
            assets: assets?.netWorthHoldings ?? [],
            owedToMe: debts?.netWorthHoldings(.owedToMe) ?? [],
            iOwe: debts?.netWorthHoldings(.iOwe) ?? []
        )
        await loadMissingRates(
            store.accounts.map(\.currency) + (holdings.assets + holdings.owedToMe + holdings.iOwe).map(\.currency)
        )
        let rates = RateSnapshot()
        let balances = store.balanceCoordinator.balances
        let stored = Dictionary(store.accounts.map { ($0.id, $0.balance) }, uniquingKeysWith: { first, _ in first })
        var missingRates: Set<String> = []
        // A currency without a rate stays out of the total, never counted as its own amount.
        let result = NetWorthCalculator.compute(
            accounts: store.accounts,
            balanceFor: { balances[$0] ?? stored[$0] ?? 0 },
            holdings: holdings,
            baseCurrency: base,
            convert: { amount, from, to in
                if let converted = rates.convert(amount, from: from, to: to) { return converted }
                missingRates.insert(from)
                return 0
            }
        )

        let lines: [JSONValue] = result.lines
            .filter { $0.kind == .money || $0.amount > 0 }
            .map { line -> JSONValue in
                // The key in whole (an interpolated LocalizationValue looks up `row.%@`).
                let labelKey = "insights.formula.netWorth.row.\(line.kind.rawValue)"
                return [
                    "key": .string(Self.wire(line.kind)),
                    "label": .string(String(localized: String.LocalizationValue(labelKey))),
                    "total": .number(FinanceToolkitCompute.round2(line.amount)),
                    "subtracted": .bool(line.kind.isLiability),
                ]
            }

        var history: [JSONValue] = []
        if let insight = insights?.precomputedInsight(id: "net_worth", granularity: .month),
           case .netWorth(let detail) = insight.detailData {
            history = detail.points.suffix(Self.netWorthMonthsListed).compactMap { point in
                point.cumulativeBalance.map { value in
                    [
                        "key": .string(point.key),
                        "label": .string(InsightGranularity.month.headingLabel(for: point.key)),
                        "total": .number(FinanceToolkitCompute.round2(value)),
                    ]
                }
            }
        }

        var fields: [String: JSONValue] = [
            "currency": .string(base),
            "net_worth": .number(FinanceToolkitCompute.round2(result.total)),
            "lines": .array(lines),
            "history": .array(history),
            "missing_rates": .array(missingRates.sorted().map(JSONValue.string)),
        ]
        for kind in NetWorthCalculator.Line.Kind.allCases {
            fields[Self.wire(kind)] = .number(FinanceToolkitCompute.round2(result.amount(kind)))
        }
        if history.isEmpty {
            fields["history_note"] = "The months are not computed yet. Show the lines, not a chart."
        }
        return .success(.object(fields))
    }

    // MARK: - Draft an asset

    private struct DraftAssetInput: Decodable {
        let name: String
        let kind: String
        let currency: String?
        let purchasePrice: Double?
        let purchaseDate: String?
        let value: Double?
        let sharePercent: Double?
        let loanAccount: String?

        enum CodingKeys: String, CodingKey {
            case name, kind, currency, value
            case purchasePrice = "purchase_price"
            case purchaseDate = "purchase_date"
            case sharePercent = "share_percent"
            case loanAccount = "loan_account"
        }
    }

    /// `draft_asset`: something the person owns, with what they paid and when (if they know) and
    /// what it is worth now (a valuation of today through Ten), their share and the loan it was
    /// bought with. Tenra Pro: without it the answer says so and points to remembering it as a
    /// fact.
    func draftAsset(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, assets != nil else { return .failure(Self.notYet("draft_asset")) }
        guard isPro() else {
            throw FinanceToolError(message: "Assets are a Tenra Pro feature and this user does not have Tenra Pro. Say so in one sentence (they can turn Pro on in the app), and offer to remember it as a fact with draft_fact instead.")
        }
        let args = try input.decoded(as: DraftAssetInput.self)
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceToolError(message: "name is required.") }
        guard let kind = AssetKind(rawValue: args.kind) else {
            throw FinanceToolError(message: "kind must be one of \(AssetKind.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let price = try Self.positiveOrNil(args.purchasePrice, field: "purchase_price")
        let value = try Self.positiveOrNil(args.value, field: "value")
        guard price != nil || value != nil else {
            throw FinanceToolError(message: "Give value (what it is worth now) or purchase_price, or both. If the user said neither, ask them in one sentence instead of drafting.")
        }
        var purchaseDate: Date?
        if let raw = args.purchaseDate, !raw.isEmpty {
            guard price != nil else { throw FinanceToolError(message: "purchase_date goes with purchase_price.") }
            purchaseDate = calendar.startOfDay(for: try pastOrToday(raw, field: "purchase_date"))
        }
        var share = 1.0
        if let percent = args.sharePercent {
            guard percent.isFinite, percent > 0, percent <= 100 else { throw FinanceToolError(message: "share_percent must be above 0 and at most 100.") }
            share = percent / 100
        }
        var loan: Account?
        if let reference = args.loanAccount, !reference.isEmpty {
            guard let named = resolveAccount(reference, in: store.accounts.filter(\.isLoan)) else {
                throw FinanceToolError(message: "Unknown loan account \(reference). Use a loan account id from <app_context>.")
            }
            loan = named
        }
        let currency = args.currency.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? store.baseCurrency

        var asset = Asset(
            name: name,
            kind: kind,
            currency: currency,
            purchaseDate: purchaseDate,
            purchasePrice: price,
            ownershipShare: share,
            linkedLoanAccountId: loan?.id,
            createdAt: now()
        )
        // What it is worth now is a valuation of today, unless it is the price of a purchase
        // made today (as the form does).
        if let value {
            let boughtToday = price.map { abs($0 - value) < PersonalDebt.centTolerance } == true
                && purchaseDate.map { calendar.isDate($0, inSameDayAs: now()) } == true
            if !boughtToday {
                asset.valuations = [AssetValuation(date: now(), value: value, source: .assistant)]
            }
        }
        let summary = AssetValuationMath.summary(of: asset, today: now(), calendar: calendar)
        let id = drafts.add([.asset(asset)])
        return .success([
            "draft_id": .string(id),
            "name": .string(name),
            "kind": .string(kind.rawValue),
            "currency": .string(currency),
            "value": .number(FinanceToolkitCompute.round2(summary.value)),
            "purchase_price": price.map(JSONValue.number) ?? .null,
            "purchase_date": purchaseDate.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
            "gain": summary.gain.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
            "gain_percent": summary.gainPercent.map { JSONValue.number(($0 * 10).rounded() / 10) } ?? .null,
            "annual_growth_percent": summary.annualGrowthPercent.map { JSONValue.number(($0 * 10).rounded() / 10) } ?? .null,
            "share_percent": .number((share * 100).rounded()),
            "loan_account_id": loan.map { JSONValue.string($0.id) } ?? .null,
            "saved": false,
        ])
    }

    // MARK: - Draft a valuation

    private struct DraftValuationInput: Decodable {
        let asset: String
        let value: Double?
        let area: Double?
        let pricePerUnit: Double?
        let date: String?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case asset, value, area, date, note
            case pricePerUnit = "price_per_unit"
        }
    }

    /// `draft_asset_valuation`: what a held asset is worth on a day (today by default), in its
    /// currency: a value, or an area times a price per unit the person found in listings,
    /// multiplied here. Assets kept after Pro ends stay open to value.
    func draftAssetValuation(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let assets else { return .failure(Self.notYet("draft_asset_valuation")) }
        await assets.load()
        let args = try input.decoded(as: DraftValuationInput.self)
        let reference = args.asset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let asset = assets.asset(id: reference) ?? assets.assets.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown asset \(reference). Use an asset id from <app_context>.")
        }
        guard !asset.isSold else {
            throw FinanceToolError(message: "\(asset.name) is sold: its value is the sale price, changed on its screen.")
        }
        let value: Double
        var area: Double?
        var unitPrice: Double?
        if let given = try Self.positiveOrNil(args.value, field: "value") {
            value = FinanceToolkitCompute.round2(given)
        } else if let size = try Self.positiveOrNil(args.area, field: "area"),
                  let price = try Self.positiveOrNil(args.pricePerUnit, field: "price_per_unit") {
            value = FinanceToolkitCompute.round2(size * price)
            area = size
            unitPrice = price
        } else {
            throw FinanceToolError(message: "Give value, or area and price_per_unit (for example square metres and the price of one in listings). If the user has not said, ask them.")
        }
        let date = try pastOrToday(args.date, field: "date")
        let note = args.note.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let before = assets.summary(for: asset, today: now())
        let valuation = AssetValuation(date: date, value: value, source: .assistant, note: note)
        var after = asset
        after.valuations.append(valuation)
        let summaryAfter = AssetValuationMath.summary(of: after, today: now(), calendar: calendar)
        let change = value - before.value
        let id = drafts.add([.assetValuation(assetId: asset.id, valuation)])
        return .success([
            "draft_id": .string(id),
            "asset_id": .string(asset.id),
            "name": .string(asset.name),
            "currency": .string(asset.currency),
            "value": .number(value),
            "area": area.map(JSONValue.number) ?? .null,
            "price_per_unit": unitPrice.map(JSONValue.number) ?? .null,
            "date": .string(FastDateParser.string(from: date)),
            "previous_value": .number(FinanceToolkitCompute.round2(before.value)),
            "change": .number(FinanceToolkitCompute.round2(change)),
            "change_percent": before.value > 0 ? .number((change / before.value * 1000).rounded() / 10) : .null,
            "gain_after": summaryAfter.gain.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
            "note": note.map(JSONValue.string) ?? .null,
            "saved": false,
        ])
    }

    // MARK: - Describe

    /// What an asset or valuation draft will write (FinanceToolkit.describe).
    func describeAsset(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .asset(let asset):
            return [
                "type": "asset",
                "name": .string(asset.name),
                "kind": .string(asset.kind.rawValue),
                "currency": .string(asset.currency),
                "purchase_price": asset.purchasePrice.map(JSONValue.number) ?? .null,
                "purchase_date": asset.purchaseDate.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "value": AssetValuationMath.latestValuation(of: asset).map { JSONValue.number($0.value) } ?? .null,
                "share_percent": .number((asset.ownershipShare * 100).rounded()),
            ]
        case .assetValuation(let assetId, let valuation):
            return [
                "type": "asset_valuation",
                "asset_id": .string(assetId),
                "name": assets?.asset(id: assetId).map { JSONValue.string($0.name) } ?? .null,
                "value": .number(valuation.value),
                "date": .string(FastDateParser.string(from: valuation.date)),
                "note": valuation.note.map(JSONValue.string) ?? .null,
            ]
        default:
            return .null
        }
    }

    // MARK: - Helpers

    /// A net worth line as the tools name it.
    static func wire(_ kind: NetWorthCalculator.Line.Kind) -> String {
        switch kind {
        case .money: "money"
        case .assets: "assets"
        case .owedToMe: "owed_to_me"
        case .loans: "loans"
        case .iOwe: "i_owe"
        }
    }

    /// nil stays nil; a number must be finite and above zero.
    private static func positiveOrNil(_ value: Double?, field: String) throws -> Double? {
        guard let value else { return nil }
        guard value.isFinite, value > 0 else { throw FinanceToolError(message: "\(field) must be positive.") }
        return value
    }
}
