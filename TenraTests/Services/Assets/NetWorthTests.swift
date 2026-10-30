//
//  NetWorthTests.swift
//  TenraTests
//
//  Phase 2 of the assets plan (docs/domains/assets.md): an asset's rent and upkeep over 12
//  months, its yield and its full result count realized transactions only (up to the sale for a
//  sold asset); two assets may not count the same transactions; net worth is money plus assets
//  plus what others owe, less the loans and what the person owes, every part in the base
//  currency, a paid-off loan and an account out of the balance left out; and the assets'
//  holdings take the share and leave the sold ones and the ones kept out of net worth. Over time
//  (phase 3), each period's end counts the assets, the debts and the loans as they stood then.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized)
struct NetWorthTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 24M in 2018, worth 70M. Computed: a static stored property is initialized off the main
    /// actor, where `day` cannot be called.
    private static var flat: Asset {
        Asset(
            id: "flat", name: "Flat", kind: .apartment, currency: "KZT",
            purchaseDate: day(2018, 10, 29), purchasePrice: 24_000_000,
            valuations: [AssetValuation(id: "v", date: day(2026, 10, 16), value: 70_000_000)]
        )
    }

    private static func summary() -> AssetValuationMath.Summary {
        AssetValuationMath.summary(of: flat, today: day(2026, 10, 29), calendar: calendar)
    }

    // MARK: - Rent and upkeep

    @Test func rentAndUpkeepOverTwelveMonthsGiveTheYield() {
        let today = Self.day(2026, 10, 29)
        // 500 000 a month for the 12 months up to today, one rent 13 months ago, one next month.
        var rent = (0..<12).map { AssetValuationMath.DatedAmount(date: Self.calendar.date(byAdding: .month, value: -$0, to: today)!, amount: 500_000) }
        rent.append(.init(date: Self.day(2025, 9, 29), amount: 500_000))
        rent.append(.init(date: Self.day(2026, 11, 29), amount: 500_000))
        let upkeep = [AssetValuationMath.DatedAmount(date: Self.day(2026, 3, 1), amount: 200_000)]
        let income = AssetValuationMath.income(
            rent: rent, upkeep: upkeep, summary: Self.summary(),
            purchaseDate: Self.flat.purchaseDate, soldAt: nil, today: today, calendar: Self.calendar
        )
        #expect(income.rentYear == 6_000_000)
        #expect(income.upkeepYear == 200_000)
        // (6M − 0.2M) / 70M.
        #expect(abs((income.yieldPercent ?? 0) - 8.2857) < 0.001)
        // Every realized rent since the purchase: 13 payments; the future one is not counted.
        #expect(income.rentTotal == 6_500_000)
        // 46M gain + 6.5M rent − 0.2M upkeep.
        #expect(income.fullResult == 52_300_000)
        #expect(income.hasRent)
    }

    @Test func withoutLinksThereIsNoIncome() {
        let income = AssetValuationMath.income(
            rent: nil, upkeep: nil, summary: Self.summary(),
            purchaseDate: Self.flat.purchaseDate, soldAt: nil, today: Self.day(2026, 10, 29), calendar: Self.calendar
        )
        #expect(income.rentYear == nil)
        #expect(income.upkeepYear == nil)
        #expect(income.yieldPercent == nil)
        #expect(income.fullResult == nil)
        #expect(!income.hasRent)
    }

    @Test func aSoldAssetsYearEndsAtTheSale() {
        let rent = [
            AssetValuationMath.DatedAmount(date: Self.day(2025, 12, 1), amount: 400_000),
            AssetValuationMath.DatedAmount(date: Self.day(2026, 5, 1), amount: 400_000),  // after the sale
        ]
        let income = AssetValuationMath.income(
            rent: rent, upkeep: nil, summary: Self.summary(),
            purchaseDate: Self.flat.purchaseDate, soldAt: Self.day(2026, 3, 1), today: Self.day(2026, 10, 29), calendar: Self.calendar
        )
        #expect(income.rentYear == 400_000)
        #expect(income.rentTotal == 400_000)
    }

    @Test func linksOfOneCategoryOverlapUnlessTheirSubcategoriesDiffer() {
        let whole = AssetCategoryLink(categoryId: "rent")
        let flatOne = AssetCategoryLink(categoryId: "rent", subcategoryId: "one")
        let flatTwo = AssetCategoryLink(categoryId: "rent", subcategoryId: "two")
        #expect(AssetValuationMath.overlaps(whole, whole))
        #expect(AssetValuationMath.overlaps(whole, flatOne))
        #expect(AssetValuationMath.overlaps(flatOne, flatOne))
        #expect(!AssetValuationMath.overlaps(flatOne, flatTwo))
        #expect(!AssetValuationMath.overlaps(whole, AssetCategoryLink(categoryId: "other")))
    }

    @Test func severalSubcategoriesOverlapOnAnyOneInCommon() {
        let taxAndRepairs = AssetCategoryLink(categoryId: "home", subcategoryIds: ["tax", "repairs"])
        let repairs = AssetCategoryLink(categoryId: "home", subcategoryId: "repairs")
        let fees = AssetCategoryLink(categoryId: "home", subcategoryIds: ["fees", "insurance"])
        #expect(AssetValuationMath.overlaps(taxAndRepairs, repairs))
        #expect(!AssetValuationMath.overlaps(taxAndRepairs, fees))
        #expect(AssetValuationMath.overlaps(fees, AssetCategoryLink(categoryId: "home")))
    }

    @Test func aLinkSavedWithOneSubcategoryReadsAsAListOfOne() throws {
        let old = Data(#"{"categoryId":"rent","subcategoryId":"flat"}"#.utf8)
        let decoded = try JSONDecoder().decode(AssetCategoryLink.self, from: old)
        #expect(decoded == AssetCategoryLink(categoryId: "rent", subcategoryIds: ["flat"]))
        let whole = try JSONDecoder().decode(AssetCategoryLink.self, from: Data(#"{"categoryId":"rent"}"#.utf8))
        #expect(whole.isWholeCategory)
        let several = AssetCategoryLink(categoryId: "home", subcategoryIds: ["repairs", "tax"])
        let roundTrip = try JSONDecoder().decode(AssetCategoryLink.self, from: JSONEncoder().encode(several))
        #expect(roundTrip == several)
    }

    // MARK: - Net worth

    private static func loan(
        _ id: String,
        remaining: Decimal,
        currency: String = "KZT",
        includeInBalance: Bool = true,
        startDate: String = "2024-01-01"
    ) -> Account {
        let info = LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 30_000_000, remainingPrincipal: remaining,
            interestRateAnnual: 12, termMonths: 120,
            startDate: startDate, paymentDay: 1
        )
        return Account(id: id, name: id, currency: currency, loanInfo: info, initialBalance: 0, balance: 0, includeInBalance: includeInBalance)
    }

    /// 1 USD = 500 KZT.
    private static func convert(_ amount: Double, _ from: String, _ to: String) -> Double? {
        switch (from, to) {
        case ("USD", "KZT"): return amount * 500
        case ("KZT", "USD"): return amount / 500
        default: return from == to ? amount : nil
        }
    }

    @Test func netWorthIsMoneyAndAssetsLessLoansAndDebtsInTheBaseCurrency() {
        let accounts = [
            Account(id: "card", name: "Card", currency: "KZT", initialBalance: 0, balance: 0),
            Account(id: "usd", name: "Dollars", currency: "USD", initialBalance: 0, balance: 0),
            Account(id: "hidden", name: "Hidden", currency: "KZT", initialBalance: 0, balance: 0, includeInBalance: false),
            Self.loan("mortgage", remaining: 20_000_000),
            Self.loan("paid", remaining: 0),
            Self.loan("hiddenLoan", remaining: 5_000_000, includeInBalance: false),
        ]
        let balances: [String: Double] = ["card": 1_000_000, "usd": 2_000, "hidden": 9_000_000]
        let result = NetWorthCalculator.compute(
            accounts: accounts,
            balanceFor: { balances[$0] ?? 0 },
            holdings: NetWorthCalculator.Holdings(
                assets: [.init(amount: 35_000_000, currency: "KZT"), .init(amount: 10_000, currency: "USD")],
                owedToMe: [.init(amount: 100_000, currency: "KZT")],
                iOwe: [.init(amount: 50_000, currency: "KZT")]
            ),
            baseCurrency: "KZT",
            convert: Self.convert
        )
        // 1M + 2 000 $ × 500; the account out of the balance is left out.
        #expect(result.amount(.money) == 2_000_000)
        #expect(result.amount(.assets) == 40_000_000)
        #expect(result.amount(.owedToMe) == 100_000)
        // The paid-off loan and the one out of the balance are left out.
        #expect(result.amount(.loans) == 20_000_000)
        #expect(result.amount(.iOwe) == 50_000)
        #expect(result.total == 22_050_000)
        #expect(result.lines.map(\.kind) == NetWorthCalculator.Line.Kind.allCases)
    }

    @Test func loansCountEvenWithoutAssets() {
        let result = NetWorthCalculator.compute(
            accounts: [
                Account(id: "card", name: "Card", currency: "KZT", initialBalance: 0, balance: 0),
                Self.loan("car", remaining: 3_000_000),
            ],
            balanceFor: { $0 == "card" ? 500_000 : 0 },
            holdings: .empty,
            baseCurrency: "KZT",
            convert: Self.convert
        )
        #expect(result.total == Double(500_000 - 3_000_000))
    }

    @Test func netWorthHoldingsTakeTheShareAndLeaveSoldAndExcludedOut() async {
        let store = AssetStore(repository: nil)
        var flat = Self.flat
        flat.ownershipShare = 0.5
        await store.add(flat)
        var garage = Asset(id: "garage", name: "Garage", kind: .commercial, currency: "KZT", purchasePrice: 3_000_000)
        garage.includeInNetWorth = false
        await store.add(garage)
        await store.add(Asset(id: "car", name: "Car", kind: .vehicle, currency: "USD", purchasePrice: 20_000))
        await store.sell(assetId: "car", price: 18_000, date: Self.day(2026, 10, 1))
        #expect(store.netWorthHoldings == [NetWorthCalculator.Holding(amount: 35_000_000, currency: "KZT")])
    }

    @Test func anAccountBalanceIsSummedInTheBaseCurrency() {
        let account = Account(id: "a", name: "A", currency: "KZT", initialBalance: 0, balance: 0)
        #expect(InsightsService.baseBalance(of: account, balanceFor: { _ in 1_000 }, baseCurrency: "KZT") == 1_000)
        #expect(InsightsService.toBase(250, currency: "KZT", baseCurrency: "KZT") == 250)
    }

    @Test func aStoreChangeIsReported() async {
        let store = AssetStore(repository: nil)
        var changes = 0
        store.didChange = { changes += 1 }
        await store.add(Self.flat)
        await store.addValuation(AssetValuation(date: Self.day(2026, 10, 30), value: 71_000_000), to: "flat")
        await store.delete(id: "flat")
        #expect(changes == 3)
    }

    // MARK: - Over time

    @Test func eachPeriodsEndCountsWhatStoodThen() {
        let today = Self.day(2026, 10, 29)
        var owedToMe = PersonalDebt(id: "lent", direction: .owedToMe, person: "A", amount: 100_000, currency: "KZT", date: Self.day(2026, 9, 15))
        owedToMe.repayments = [DebtRepayment(id: "r", amount: 40_000, date: Self.day(2026, 10, 10), note: nil)]
        let iOwe = PersonalDebt(id: "borrowed", direction: .iOwe, person: "B", amount: 50_000, currency: "KZT", date: Self.day(2026, 10, 5))
        let holdings = NetWorthCalculator.Holdings(
            assets: [], owedToMe: [], iOwe: [],
            timelines: [AssetValuationMath.timeline(of: Self.flat, calendar: Self.calendar)],
            debts: [owedToMe, iOwe]
        )
        let values = NetWorthCalculator.history(
            // September, and October (not over yet).
            periodEnds: [Self.day(2026, 10, 1), Self.day(2026, 11, 1)],
            money: [1_000_000, 2_000_000],
            accounts: [Self.loan("mortgage", remaining: 20_000_000, startDate: "2026-10-20")],
            holdings: holdings,
            baseCurrency: "KZT",
            today: today,
            calendar: Self.calendar,
            convert: Self.convert
        )
        // September: 1M + the flat at its purchase price + 100 000 lent; the loan not taken yet.
        #expect(values.first == Double(1_000_000 + 24_000_000 + 100_000))
        // Today: 2M + 70M + 60 000 still lent − 20M left of the loan − 50 000 borrowed.
        #expect(values.last == Double(2_000_000 + 70_000_000 + 60_000 - 20_000_000 - 50_000))
    }

    @Test func aPastLoanStandsBetweenWhatIsLeftTodayAndWhatWasTaken() {
        let values = NetWorthCalculator.history(
            periodEnds: [Self.day(2025, 7, 1)],
            money: [0],
            accounts: [Self.loan("mortgage", remaining: 20_000_000)],
            holdings: .empty,
            baseCurrency: "KZT",
            today: Self.day(2026, 10, 29),
            calendar: Self.calendar,
            convert: Self.convert
        )
        let left = -(values.first ?? 0)
        #expect(left >= 20_000_000)
        #expect(left <= 30_000_000)
    }

    @Test func aDebtCountsFromItsDayUntilItIsSettled() {
        var debt = PersonalDebt(direction: .owedToMe, person: "A", amount: 100_000, currency: "KZT", date: Self.day(2026, 9, 15))
        debt.settledAt = Self.day(2026, 10, 20)
        #expect(NetWorthCalculator.debtLeft(debt, on: Self.day(2026, 9, 14), calendar: Self.calendar) == 0)
        #expect(NetWorthCalculator.debtLeft(debt, on: Self.day(2026, 10, 1), calendar: Self.calendar) == 100_000)
        #expect(NetWorthCalculator.debtLeft(debt, on: Self.day(2026, 10, 20), calendar: Self.calendar) == 0)
    }
}
