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

    // MARK: - 3a. German keywords (Phase 1 localization)

    /// "50 für lebensmittel ausgegeben" — "ausgegeben" is in expenseKeywords
    /// (DE group) → .expense; "lebensmittel" is in categoryMap (DE section)
    /// → category "Lebensmittel" (the German onboarding preset name).
    @Test("DE: '50 für lebensmittel ausgegeben' → expense, Lebensmittel")
    func deExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("50 für lebensmittel ausgegeben")

        #expect(result.amount == Decimal(50))
        #expect(result.type == .expense)
        #expect(result.categoryName == "Lebensmittel")
    }

    /// "gehalt bekommen 3000" — both "gehalt" and "bekommen" are in
    /// incomeKeywords (DE group) → .income.
    @Test("DE: 'gehalt bekommen 3000' → income, amount 3000")
    func deIncomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("gehalt bekommen 3000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(3000))
    }

    /// "20 euro bezahlt" — "bezahlt" is in expenseKeywords (DE group).
    /// Pins the decision to include "bezahlt" as expense even though the
    /// (rare) income phrase "bezahlt bekommen" contains it.
    @Test("DE: '20 euro bezahlt' → expense")
    func deBezahltIsExpense() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("20 euro bezahlt")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(20))
    }

    // MARK: - 3b. Spanish / French keywords (Phase 2 localization)

    /// "gasté 30 en taxi" — "gasté" is in expenseKeywords (ES group).
    @Test("ES: 'gasté 30 en taxi' → expense, amount 30")
    func esExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("gasté 30 en taxi")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(30))
    }

    /// "recibí el sueldo 2000" — "recibí" and "sueldo" are in incomeKeywords (ES group).
    @Test("ES: 'recibí el sueldo 2000' → income, amount 2000")
    func esIncomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("recibí el sueldo 2000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(2000))
    }

    /// "anteayer 40 taxi" — "anteayer" CONTAINS "ayer"; the -2 days branch
    /// must win over the yesterday branch. Pins the ordering for Spanish.
    @Test("ES: 'anteayer' beats 'ayer' substring → -2 days")
    func esAnteayerBeatsAyer() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("anteayer 40 taxi")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    /// "dépensé 25 pour le taxi" — "dépensé" is in expenseKeywords (FR group).
    @Test("FR: 'dépensé 25 pour le taxi' → expense, amount 25")
    func frExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("dépensé 25 pour le taxi")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(25))
    }

    /// "salaire reçu 3000" — "reçu"/"salaire" are in incomeKeywords (FR group).
    @Test("FR: 'salaire reçu 3000' → income, amount 3000")
    func frIncomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("salaire reçu 3000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(3000))
    }

    /// "avant-hier 15 café" — unambiguous FR keyword (unlike bare "hier",
    /// which is locale-gated because it collides with German "hier" = "here").
    @Test("FR: 'avant-hier' → -2 days (locale-independent)")
    func frAvantHierDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("avant-hier 15 café")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    // MARK: - 3c. Turkish / Portuguese keywords (Phase 3 localization)

    /// "markete 50 harcadım" — "harcadım" is in expenseKeywords (TR group).
    @Test("TR: 'markete 50 harcadım' → expense, amount 50")
    func trExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("markete 50 harcadım")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(50))
    }

    /// "maaş aldım 40000" — bare "aldım" is deliberately NOT an expense
    /// keyword (it also means "received"); "maaş" wins as income. Pins the
    /// aldım-ambiguity decision from docs/localization/tr.md.
    @Test("TR: 'maaş aldım 40000' → income (aldım ambiguity)")
    func trMaasAldimIsIncome() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("maaş aldım 40000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(40000))
    }

    /// "dün 30 taksi" — "dün" (TR) → start-of-yesterday; "bugün" contains
    /// "gün" but not "dün", so today-phrases are unaffected.
    @Test("TR: 'dün' keyword → date is start-of-yesterday")
    func trYesterdayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("dün 30 taksi")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -1, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    /// "gastei 45 no mercado" — "gastei" is in expenseKeywords (PT group).
    @Test("PT: 'gastei 45 no mercado' → expense, amount 45")
    func ptExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("gastei 45 no mercado")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(45))
    }

    /// "anteontem 20 mercado" — "anteontem" CONTAINS "ontem"; the -2 days
    /// branch must win. Pins the ordering for Portuguese.
    @Test("PT: 'anteontem' beats 'ontem' substring → -2 days")
    func ptAnteontemBeatsOntem() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("anteontem 20 mercado")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    // MARK: - 3d. Italian / Ukrainian keywords (Phase 4 localization)

    /// "speso 30 al ristorante" — "speso" is in expenseKeywords (IT group);
    /// "ristorante" maps to preset "Ristoranti".
    @Test("IT: 'speso 30 al ristorante' → expense, Ristoranti")
    func itExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("speso 30 al ristorante")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(30))
        #expect(result.categoryName == "Ristoranti")
    }

    /// "ricevuto lo stipendio 2000" — "ricevuto"/"stipendio" are IT income keywords.
    @Test("IT: 'ricevuto lo stipendio 2000' → income, amount 2000")
    func itIncomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("ricevuto lo stipendio 2000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(2000))
    }

    /// "l'altro ieri 15 caffè" — "l'altro ieri" CONTAINS "ieri"; the -2 days
    /// branch must win over the yesterday branch. Pins the ordering for Italian.
    @Test("IT: 'l'altro ieri' beats 'ieri' substring → -2 days")
    func itAltroIeriBeatsIeri() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("l'altro ieri 15 caffè")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    /// "витратив 200 на продукти" — "витратив" is a UK expense keyword;
    /// "продукти" maps to preset "Продукти".
    @Test("UK: 'витратив 200 на продукти' → expense, Продукти")
    func ukExpenseKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("витратив 200 на продукти")

        #expect(result.type == .expense)
        #expect(result.amount == Decimal(200))
        #expect(result.categoryName == "Продукти")
    }

    /// "отримав зарплату 15000" — "отримав"/"зарплата" are UK income keywords.
    @Test("UK: 'отримав зарплату 15000' → income, amount 15000")
    func ukIncomeKeyword() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("отримав зарплату 15000")

        #expect(result.type == .income)
        #expect(result.amount == Decimal(15000))
    }

    /// "позавчора 40 таксі" — "позавчора" CONTAINS "вчора"; the -2 days
    /// branch must win. Pins the ordering for Ukrainian (distinct from the
    /// Russian "позавчера"/"вчера" pair).
    @Test("UK: 'позавчора' beats 'вчора' substring → -2 days")
    func ukPozavchoraBeatsVchora() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("позавчора 40 таксі")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    // MARK: - 3e. Japanese / Korean dates (Phase 5 L1 — safe CJK date words)

    /// "昨日 タクシー 300" — Japanese "昨日" (yesterday) via contains().
    @Test("JA: '昨日' keyword → date is start-of-yesterday")
    func jaYesterdayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("昨日 タクシー 300")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -1, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    /// "一昨日 300" — 一昨日 CONTAINS 昨日; the -2 days branch must win.
    @Test("JA: '一昨日' beats '昨日' substring → -2 days")
    func jaOtotoiBeatsKinou() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("一昨日 300")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    /// "어제 3000" — Korean "어제" (yesterday) via contains().
    @Test("KO: '어제' keyword → date is start-of-yesterday")
    func koYesterdayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("어제 3000")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -1, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
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

    /// "gestern 30 taxi" — "gestern" (DE) → start-of-yesterday.
    @Test("DE: 'gestern' keyword → date is start-of-yesterday")
    func deYesterdayDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("gestern 30 taxi")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expectedYesterday = cal.date(byAdding: .day, value: -1, to: today)!

        #expect(cal.startOfDay(for: result.date) == expectedYesterday)
    }

    /// "vorgestern 30 taxi" — "vorgestern" CONTAINS "gestern", so parseDate
    /// must check the day-before-yesterday branch first. Pins that ordering.
    @Test("DE: 'vorgestern' beats 'gestern' substring → -2 days")
    func deVorgesternBeatsGestern() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("vorgestern 30 taxi")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
    }

    /// "позавчера такси 300" — same substring hazard in Russian
    /// ("позавчера" contains "вчера"). Pins the -2 days branch.
    @Test("RU: 'позавчера' beats 'вчера' substring → -2 days")
    func ruPozavcheraDate() {
        let (parser, cat, acc, tx) = Self.makeParser()
        _ = (cat, acc, tx)

        let result = parser.parse("позавчера такси 300")

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let expected = cal.date(byAdding: .day, value: -2, to: today)!

        #expect(cal.startOfDay(for: result.date) == expected)
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
