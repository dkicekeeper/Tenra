//
//  CategoryGridExpensesTests.swift
//  TenraTests
//
//  Pins the Home category grid's totals (`TransactionCategoryPickerCoordinator
//  .computeCategoryExpenses`) to the walk it replaced, which parsed every expense's date
//  with a DateFormatter and converted through the live `convertSync` (0.3–0.4 s per
//  run), and pins its refresh key to the period's bounds: the old key used the period's
//  name, which stays "This month" across a month change.
//
//  @MainActor + .sharedProcessState: the reference walk converts through the
//  process-global CurrencyRateStore.shared, seeded per test and cleared in init.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct CategoryGridExpensesTests {

    init() {
        CurrencyRateStore.shared.clearAll()
    }

    // MARK: - Reference: the walk before 2026-10, verbatim

    private static func referenceExpenses(
        transactions: [Transaction],
        filterStart: Date,
        filterEnd: Date,
        baseCurrency: String,
        validCategoryNames: Set<String>,
        now: Date
    ) -> [String: CategoryExpense] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        var result: [String: CategoryExpense] = [:]
        for tx in transactions where tx.type == .expense {
            guard let date = dateFormatter.date(from: tx.date),
                  date >= filterStart && date < filterEnd,
                  date <= now else { continue }

            let categoryName = tx.category.isEmpty ? "Uncategorized" : tx.category
            if !validCategoryNames.contains(categoryName) && !tx.category.isEmpty {
                continue
            }

            let amount: Double
            if tx.currency == baseCurrency {
                amount = tx.amount
            } else if let fx = CurrencyConverter.convertSync(amount: tx.amount, from: tx.currency, to: baseCurrency) {
                amount = fx
            } else {
                amount = tx.convertedAmount ?? tx.amount
            }

            if var existing = result[categoryName] {
                existing.total += amount
                if let sub = tx.subcategory {
                    existing.subcategories[sub, default: 0] += amount
                }
                result[categoryName] = existing
            } else {
                var subs: [String: Double] = [:]
                if let sub = tx.subcategory { subs[sub] = amount }
                result[categoryName] = CategoryExpense(total: amount, subcategories: subs)
            }
        }
        return result
    }

    // MARK: - Fixture

    /// ~2 years of mixed transactions around today, plus future-dated ones, in the base
    /// currency, in currencies with a rate and in one without (falls back to
    /// `convertedAmount`), across valid, deleted and empty categories. Dates are the
    /// canonical "yyyy-MM-dd" every write path stores, plus a few strings both parsers reject.
    private static func fixture() -> [Transaction] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let categories = ["Food", "Transport", "", "Deleted", "Продукты"]
        let currencies = ["KZT", "KZT", "KZT", "USD", "EUR", "ZZZ"]
        let types: [TransactionType] = [.expense, .expense, .expense, .income, .loanPayment, .internalTransfer]
        let subcategories: [String?] = [nil, nil, nil, "Cafe", "Groceries"]
        let rejected = ["garbage", "", "2026-13-01", "2026-07-32"]

        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }

        return (0..<3_000).map { i in
            let date: String
            if next(100) == 0 {
                date = rejected[next(rejected.count)]
            } else {
                let day = calendar.date(byAdding: .day, value: next(760) - 700, to: today)!
                date = DateFormatters.dateFormatter.string(from: day)
            }
            let amount = Double(next(5_000_000)) / 100
            return Transaction(
                id: "tx\(i)",
                date: date,
                description: "",
                amount: amount,
                currency: currencies[next(currencies.count)],
                convertedAmount: next(2) == 0 ? nil : amount * 1.1,
                type: types[next(types.count)],
                category: categories[next(categories.count)],
                subcategory: subcategories[next(subcategories.count)]
            )
        }
    }

    private static func ranges() -> [(name: String, start: Date, end: Date)] {
        var ranges: [(name: String, start: Date, end: Date)] = [
            TimeFilterPreset.allTime, .thisMonth, .lastMonth, .last30Days, .thisYear, .lastYear
        ].map { preset in
            let range = preset.dateRange()
            return (name: preset.rawValue, start: range.start, end: range.end)
        }
        // A custom range reaching into the future: future-dated expenses stay out.
        let custom = TimeFilter.customDays(
            from: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            through: Calendar.current.date(byAdding: .day, value: 40, to: Date())!
        )
        ranges.append((name: "customIntoFuture", start: custom.startDate, end: custom.endDate))
        return ranges
    }

    // MARK: - Tests

    @Test("totals match the DateFormatter + convertSync walk for every period and base currency")
    func totalsMatchReferenceWalk() {
        CurrencyRateStore.shared.updateCurrentRates(ExchangeRates(
            pivot: "KZT",
            rates: ["USD": 512.37, "EUR": 553.91],
            date: Date(),
            providerName: "test"
        ))
        let transactions = Self.fixture()
        let valid: Set<String> = ["Food", "Transport", "Продукты"]
        let now = Date()

        for base in ["KZT", "USD"] {
            for range in Self.ranges() {
                let reference = Self.referenceExpenses(
                    transactions: transactions,
                    filterStart: range.start,
                    filterEnd: range.end,
                    baseCurrency: base,
                    validCategoryNames: valid,
                    now: now
                )
                let computed = TransactionCategoryPickerCoordinator.computeCategoryExpenses(
                    transactions: transactions,
                    filterStart: range.start,
                    filterEnd: range.end,
                    baseCurrency: base,
                    validCategoryNames: valid,
                    rates: RateSnapshot(),
                    now: now
                )
                #expect(computed == reference, "\(range.name) in \(base)")
            }
        }

        // Not vacuous: the all-time breakdown covers converted, unconvertible and
        // uncategorized expenses, and leaves the deleted category out.
        let allTime = TransactionCategoryPickerCoordinator.computeCategoryExpenses(
            transactions: transactions,
            filterStart: Date(timeIntervalSince1970: 0),
            filterEnd: Date(timeIntervalSinceNow: 86_400 * 365),
            baseCurrency: "KZT",
            validCategoryNames: valid,
            rates: RateSnapshot(),
            now: now
        )
        #expect(Set(allTime.keys) == ["Food", "Transport", "Продукты", "Uncategorized"])
        #expect(allTime["Food"]?.subcategories.isEmpty == false)
    }

    @Test("the refresh key follows the period's bounds, not its name")
    func refreshKeyFollowsBounds() {
        func monthStart(_ year: Int, _ month: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
        }
        func key(_ filter: TimeFilter) -> TransactionCategoryPickerCoordinator.RefreshKey {
            TransactionCategoryPickerCoordinator.RefreshKey(
                filterStart: filter.startDate,
                filterEnd: filter.endDate,
                filterPreset: filter.preset,
                transactionsVersion: 7,
                transactionCount: 100,
                categoriesVersion: 3,
                ratesVersion: 2,
                baseCurrency: "KZT",
                day: Calendar.current.startOfDay(for: Date())
            )
        }
        // "This month" decoded in September, then refreshed after the month changed.
        var september = TimeFilter(preset: .thisMonth)
        september.startDate = monthStart(2026, 9)
        september.endDate = monthStart(2026, 10)
        var october = september
        october.startDate = monthStart(2026, 10)
        october.endDate = monthStart(2026, 11)

        #expect(september.displayName == october.displayName)
        #expect(key(september) != key(october))
    }
}
