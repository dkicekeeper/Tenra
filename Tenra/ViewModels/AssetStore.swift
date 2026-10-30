//
//  AssetStore.swift
//  Tenra
//
//  The assets (docs/domains/assets.md): the list the Finances card and the asset screens
//  read, and every change to it. AssetValuationMath does the arithmetic; a linked loan's
//  remaining principal is read live from the loan account (`loanBalance`, wired by
//  AppCoordinator).
//
//  Kept in CoreData v17 through AssetRepository; nil keeps the assets in memory only
//  (previews, tests). The list reloads when the store is replaced (delete all data, a restored
//  backup).
//

import Foundation
import Observation

@Observable
final class AssetStore {
    /// The assets' total for a hero: the owned value and, over the ones with a purchase price,
    /// the gain.
    struct Totals: Equatable {
        var value: Double
        /// What the assets with a purchase price gained over it; nil when none has one.
        var gain: Double?
        /// That gain as a percent of what they cost; nil without a cost above zero.
        var gainPercent: Double?
    }

    /// In list order.
    private(set) var assets: [Asset] = []
    /// The kept assets have been read: an empty list means there are none.
    private(set) var isLoaded: Bool

    /// A loan account's remaining principal; nil when the account is gone. Set by AppCoordinator.
    @ObservationIgnored var loanBalance: (String) -> AssetValuationMath.LoanBalance? = { _ in nil }
    /// The transactions of a category link of one type (rent `.income`, upkeep `.expense`), from
    /// TransactionStore's category index; none once the category is gone. Set by AppCoordinator.
    @ObservationIgnored var transactionsOfLink: (AssetCategoryLink, TransactionType) -> [Transaction] = { _, _ in [] }
    /// Called after the assets change (and once they are read): net worth is recomputed. Set by
    /// AppCoordinator.
    @ObservationIgnored var didChange: () -> Void = {}

    @ObservationIgnored private let repository: AssetRepository?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var resetObserver: NSObjectProtocol?

    init(repository: AssetRepository?) {
        self.repository = repository
        self.isLoaded = repository == nil
        if let stack = repository?.stack {
            resetObserver = NotificationCenter.default.addObserver(
                forName: CoreDataStack.storeDidResetNotification,
                object: stack,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.loading = nil
                    Task { await self.load() }
                }
            }
        }
    }

    /// Reads the kept assets, once; later calls wait for that read.
    func load() async {
        if let loading { return await loading.value }
        guard let repository else { return }
        let task = Task { @MainActor in
            self.assets = await repository.all()
            self.isLoaded = true
            self.didChange()
        }
        loading = task
        await task.value
    }

    func asset(id: String) -> Asset? {
        assets.first { $0.id == id }
    }

    // MARK: - Reading

    /// The assets the person still has, in list order.
    var held: [Asset] {
        assets.filter { !$0.isSold }
    }

    /// The sold ones, the latest sale first.
    var sold: [Asset] {
        assets.filter(\.isSold).sorted { ($0.soldAt ?? .distantPast) > ($1.soldAt ?? .distantPast) }
    }

    /// The held assets of one section of the list.
    func held(in group: AssetKind.Group) -> [Asset] {
        held.filter { $0.kind.group == group }
    }

    /// The linked loan's remaining principal, while the loan account exists.
    func loan(for asset: Asset) -> AssetValuationMath.LoanBalance? {
        asset.linkedLoanAccountId.flatMap(loanBalance)
    }

    func summary(for asset: Asset, today: Date = Date()) -> AssetValuationMath.Summary {
        AssetValuationMath.summary(of: asset, loan: loan(for: asset), today: today)
    }

    /// The held assets counted in net worth, each at the person's share, in `currency`; and
    /// what the ones with a purchase price gained over it.
    func totals(in currency: String) -> Totals {
        var value = 0.0
        var gain = 0.0
        var cost = 0.0
        var hasCost = false
        for asset in held where asset.includeInNetWorth {
            let summary = AssetValuationMath.summary(of: asset)
            value += convert(summary.ownedValue, from: asset.currency, to: currency)
            if let price = asset.purchasePrice {
                let share = min(1, max(0, asset.ownershipShare))
                hasCost = true
                cost += convert(price * share, from: asset.currency, to: currency)
                gain += convert((summary.value - price) * share, from: asset.currency, to: currency)
            }
        }
        return Totals(
            value: value,
            gain: hasCost ? gain : nil,
            gainPercent: hasCost && cost > 0 ? gain / cost * 100 : nil
        )
    }

    /// What the held assets counted in net worth were worth over time, at their share, in
    /// `currency` (the list's hero chart).
    func valueHistory(in currency: String) -> [AssetValuationMath.DatedValue] {
        AssetValuationMath.totalHistory(of: held.filter(\.includeInNetWorth)) { [self] amount, asset in
            convert(amount, from: asset.currency, to: currency)
        }
    }

    // MARK: - Rent and upkeep

    /// The rent (`.income` of the income link) and the upkeep (`.expense` of the expense link),
    /// newest first; nil for a kind without a link.
    func linkedTransactions(of asset: Asset) -> (rent: [Transaction]?, upkeep: [Transaction]?) {
        let rent = asset.incomeLink.map { transactionsOfLink($0, .income) }
        let upkeep = asset.expenseLink.map { transactionsOfLink($0, .expense) }
        return (rent?.sorted { $0.date > $1.date }, upkeep?.sorted { $0.date > $1.date })
    }

    func incomeSummary(for asset: Asset, today: Date = Date()) -> AssetValuationMath.IncomeSummary {
        let linked = linkedTransactions(of: asset)
        return AssetValuationMath.income(
            rent: linked.rent.map { dated($0, in: asset.currency) },
            upkeep: linked.upkeep.map { dated($0, in: asset.currency) },
            summary: summary(for: asset, today: today),
            purchaseDate: asset.purchaseDate,
            soldAt: asset.soldAt,
            today: today
        )
    }

    /// The links the other assets hold, which a link of this one may not overlap
    /// (`AssetValuationMath.overlaps`).
    func takenLinks(excluding assetId: String?) -> (income: [AssetCategoryLink], expense: [AssetCategoryLink]) {
        let others = assets.filter { $0.id != assetId }
        return (others.compactMap(\.incomeLink), others.compactMap(\.expenseLink))
    }

    /// Transactions in the asset's currency, at the cached rates.
    private func dated(_ transactions: [Transaction], in currency: String) -> [AssetValuationMath.DatedAmount] {
        transactions.compactMap { tx in
            guard let date = FastDateParser.date(from: tx.date) else { return nil }
            return AssetValuationMath.DatedAmount(date: date, amount: convert(tx.amount, from: tx.currency, to: currency))
        }
    }

    // MARK: - Net worth

    /// The held assets counted in net worth, each at the person's share, in their own currency.
    var netWorthHoldings: [NetWorthCalculator.Holding] {
        held.filter(\.includeInNetWorth).map { asset in
            NetWorthCalculator.Holding(amount: AssetValuationMath.summary(of: asset).ownedValue, currency: asset.currency)
        }
    }

    /// Every asset counted in net worth, held or sold, as it stood over time: net worth's
    /// chart.
    var netWorthTimelines: [AssetValuationMath.Timeline] {
        assets.filter(\.includeInNetWorth).map { AssetValuationMath.timeline(of: $0) }
    }

    // MARK: - Out of date

    /// The held assets whose value was last set too long ago (AssetValuationMath.isStale).
    func staleAssets(today: Date = Date()) -> [Asset] {
        held.filter { AssetValuationMath.isStale($0, today: today) }
    }

    /// One asset's owned value in `currency` (the Finances card's shelf).
    func ownedValue(of asset: Asset, in currency: String) -> Double {
        convert(AssetValuationMath.summary(of: asset).ownedValue, from: asset.currency, to: currency)
    }

    private func convert(_ amount: Double, from: String, to: String) -> Double {
        from == to ? amount : CurrencyConverter.convertSync(amount: amount, from: from, to: to) ?? amount
    }

    // MARK: - Changes

    /// Adds an asset at the end of the list.
    func add(_ asset: Asset) async {
        var asset = asset
        asset.order = (assets.map(\.order).max() ?? -1) + 1
        assets.append(asset)
        await repository?.save(asset)
        didChange()
    }

    /// Writes the asset over its earlier copy.
    func update(_ asset: Asset) async {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[index] = asset
        await repository?.save(asset)
        didChange()
    }

    func delete(id: String) async {
        assets.removeAll { $0.id == id }
        await repository?.delete(id: id)
        didChange()
    }

    /// The assets of one section in the order the person dragged them to (DesignKit 8.0.0's
    /// list): they take that section's places among all the assets, in memory at once, then
    /// kept.
    func reorder(_ orderedIds: [String]) async {
        let places = orderedIds.compactMap { id in assets.first { $0.id == id }?.order }.sorted()
        var moved: [Asset] = []
        for (id, place) in zip(orderedIds, places) {
            guard let i = assets.firstIndex(where: { $0.id == id }), assets[i].order != place else { continue }
            assets[i].order = place
            moved.append(assets[i])
        }
        assets.sort { $0.order < $1.order }
        for asset in moved {
            await repository?.save(asset)
        }
    }

    /// A new valuation: the value from its day on.
    func addValuation(_ valuation: AssetValuation, to assetId: String) async {
        guard var asset = asset(id: assetId) else { return }
        asset.valuations.append(valuation)
        await update(asset)
    }

    /// Deleting the sale's valuation puts the asset back among the held ones.
    func deleteValuation(id: String, from assetId: String) async {
        guard var asset = asset(id: assetId) else { return }
        let removed = asset.valuations.first { $0.id == id }
        asset.valuations.removeAll { $0.id == id }
        if removed?.source == .sale {
            asset.soldAt = nil
        }
        await update(asset)
    }

    /// Sold for `price` on `date`: the sale becomes its last valuation and the asset leaves the
    /// held ones (and net worth). No transaction is made: the money comes in as the person
    /// records it.
    func sell(assetId: String, price: Double, date: Date, note: String? = nil) async {
        guard var asset = asset(id: assetId) else { return }
        asset.valuations.removeAll { $0.source == .sale }
        asset.valuations.append(AssetValuation(date: date, value: price, source: .sale, note: note))
        asset.soldAt = date
        await update(asset)
    }

    /// Takes the sale back: the asset is held again, at its value before the sale.
    func undoSale(assetId: String) async {
        guard var asset = asset(id: assetId) else { return }
        asset.valuations.removeAll { $0.source == .sale }
        asset.soldAt = nil
        await update(asset)
    }
}
