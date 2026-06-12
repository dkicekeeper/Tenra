//
//  VoiceInputParserTests.swift
//  TenraTests
//
//  Rewritten (2026-06-11, Plan 004) against the current ViewModel-based API.
//  The year-heuristic cases are covered by VoiceInputParserAmountTests.swift;
//  this file focuses on type, date, category, and multi-utterance parsing.
//
//  Pattern: mirrors VoiceInputParserAmountTests — @MainActor struct, same
//  makeParser() helper. Categories are seeded via CategoriesViewModel so that
//  the category-matching path is exercised (not just the hardcoded-name
//  fallback).
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct VoiceInputParserTests {

    // MARK: - Helpers

    /// Builds a parser backed by an isolated in-memory repository so tests
    /// never touch shared state. VMs are returned and must be retained by the
    /// caller — the parser holds only *weak* references to them.
    private static func makeParser() -> (VoiceInputParser, CategoriesViewModel, AccountsViewModel, TransactionsViewModel) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "voice_parser_tests.\(UUID().uuidString)")!
        )
        let categoriesVM = CategoriesViewModel(repository: repo)
        let accountsVM   = AccountsViewModel(repository: repo)
        let transactionsVM = TransactionsViewModel(repository: repo)

        // Seed a handful of categories so the live-category lookup in
        // parseCategory() finds a match and returns the seeded name.
        // The parser also has a built-in categoryMap keyed on RU keywords
        // ("такси" → "Транспорт", "кофе" → "Еда", etc.); when no live
        // category matches it falls back to the hardcoded string directly,
        // so the assertions below work whether or not these inserts land
        // before parse() runs — but seeding makes the path deterministic.
        categoriesVM.addCategory(CustomCategory(
            name: "Транспорт",
            iconSource: .sfSymbol("car.fill"),
            colorHex: "#3b82f6",
            type: .expense
        ))
        categoriesVM.addCategory(CustomCategory(
            name: "Еда",
            iconSource: .sfSymbol("fork.knife"),
            colorHex: "#f97316",
            type: .expense
        ))
        categoriesVM.addCategory(CustomCategory(
            name: "Продукты",
            iconSource: .sfSymbol("cart.fill"),
            colorHex: "#22c55e",
            type: .expense
        ))

        let parser = VoiceInputParser(
            categoriesViewModel: categoriesVM,
            accountsViewModel: accountsVM,
            transactionsViewModel: transactionsVM
        )
        return (parser, categoriesVM, accountsVM, transactionsVM)
    }

    // MARK: - 1. Simple expense phrase (RU)

    /// "500 на такси" → amount 500, type .expense, category "Транспорт".
    /// Derivation:
    ///   - amount: the bare number 500 is matched by the plain-number regex.
    ///   - type: no income keyword present → parseType defaults to .expense.
    ///   - category: categoryMap["такси"] → ("Транспорт", "Такси");
    ///     the live category "Транспорт" matches → returns seeded name.
    @Test("RU: '500 на такси' → amount 500, expense, Транспорт")
    func simpleRuExpense() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("500 на такси")

        #expect(result.amount == Decimal(500))
        #expect(result.type == .expense)
        #expect(result.categoryName == "Транспорт")
    }

    // MARK: - 2. English equivalent

    /// "spent 20 on groceries" — "spent" is in Self.expenseKeywords (EN group) → .expense;
    /// amount 20. Category: no RU keyword matches → falls back to localized "category.other".
    /// We assert only amount and type so the test doesn't depend on localisation of "other".
    @Test("EN: 'spent 20 on groceries' → amount 20, expense via keyword")
    func simpleEnExpense() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("spent 20 on groceries")

        #expect(result.amount == Decimal(20))
        #expect(result.type == .expense)
    }

    // MARK: - 3. Income keyword

    /// "доход 5000" → income type, amount 5000.
    /// Derivation:
    ///   - parseTypeOptional iterates Self.incomeKeywords (static let, line ~555);
    ///     "доход" is in that list → returns .income.
    ///   - amount: 5000 matched by plain-number regex.
    @Test("RU: 'доход 5000' → income, amount 5000")
    func incomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("доход 5000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(5000))
    }

    /// "получил зарплату 100000" — "получил" is in Self.incomeKeywords → .income.
    @Test("RU: 'получил зарплату 100000' → income, amount 100000")
    func receivedSalary() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("получил зарплату 100000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(100_000))
    }

    /// "received salary 1000" — "received" is in Self.incomeKeywords (EN group) → .income;
    /// "salary" is also in incomeKeywords but "received" wins on first match.
    @Test("EN: 'received salary 1000' → income, amount 1000")
    func enIncomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("received salary 1000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(1000))
    }

    /// "got paid 500" — "got paid" is in Self.incomeKeywords (EN group) → .income.
    /// "paid" is NOT in expenseKeywords (to avoid this phrase being mis-classified
    /// as expense, since expense is checked first). This test pins that decision.
    @Test("EN: 'got paid 500' → income (not expense), amount 500")
    func enGotPaidIsIncome() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("got paid 500")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(500))
    }

    // MARK: - 4. Date extraction

    /// "вчера такси 300" → parsed date == Calendar.current start-of-yesterday.
    /// parseDate() returns calendar.date(byAdding: .day, value: -1, to: today).
    /// We compare at day granularity to avoid sub-second jitter.
    @Test("RU: 'вчера' keyword → date is start-of-yesterday")
    func yesterdayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("вчера такси 300")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expectedYesterday = cal.date(byAdding: .day, value: -1, to: today)!

        #expect(cal.startOfDay(for: result.date) == expectedYesterday)
    }

    /// "yesterday 300 groceries" — "yesterday" is now matched by parseDate
    /// (EN keyword added alongside "вчера") → date is start-of-yesterday.
    /// Derivation: parseDate checks text.contains("yesterday") → returns
    /// calendar.date(byAdding: .day, value: -1, to: today).
    @Test("EN: 'yesterday' keyword → date is start-of-yesterday")
    func enYesterdayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("yesterday 300 groceries")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expectedYesterday = cal.date(byAdding: .day, value: -1, to: today)!

        #expect(cal.startOfDay(for: result.date) == expectedYesterday)
    }

    /// "today 50 coffee" — "today" is now matched by parseDate → start-of-today.
    @Test("EN: 'today' keyword → date is start-of-today")
    func enTodayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("today 50 coffee")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        #expect(cal.startOfDay(for: result.date) == today)
    }

    /// A phrase with no date keyword in either language → date defaults to today.
    @Test("No date keyword → date defaults to today")
    func defaultDateIsToday() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("300 groceries")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        #expect(cal.startOfDay(for: result.date) == today)
    }

    // MARK: - 5. parseMulti splits two operations

    /// "500 на такси и 1000 на еду"
    /// VoiceInputSegmenter splits on "и" when both sides contain an amount.
    ///   left  = "500 на такси"  → amount 500
    ///   right = "1000 на еду"   → amount 1000
    /// Returns exactly 2 ParsedOperations.
    @Test("parseMulti splits '500 на такси и 1000 на еду' into 2 operations")
    func parseMultiSplitsTwoOperations() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let ops = parser.parseMulti("500 на такси и 1000 на еду")

        #expect(ops.count == 2)

        // Both amounts should be present (order: left before right).
        let amounts = ops.compactMap { $0.amount }
        #expect(amounts.contains(Decimal(500)))
        #expect(amounts.contains(Decimal(1000)))
    }

    // MARK: - 6. Unmatched category falls back to localized "other"

    /// A phrase that contains no keyword from categoryMap → foundCategory
    /// defaults to `String(localized: "category.other")` (or the live
    /// category matching that name, if any). We verify the result is non-nil
    /// and not one of the seeded category names — i.e. it's the fallback, not
    /// a false match.
    @Test("Unknown category phrase → fallback category (not Транспорт/Еда/Продукты)")
    func unknownCategoryFallsBack() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("потратил 999 на что-то непонятное")

        // categoryName is non-nil (always filled — parseCategory always sets foundCategory).
        #expect(result.categoryName != nil)
        // Must not be one of the seeded categories whose keywords appear in the phrase.
        #expect(result.categoryName != "Транспорт")
        #expect(result.categoryName != "Еда")
        #expect(result.categoryName != "Продукты")
    }
}
