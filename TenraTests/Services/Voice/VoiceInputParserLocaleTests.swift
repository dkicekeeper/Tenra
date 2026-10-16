//
//  VoiceInputParserLocaleTests.swift
//  TenraTests
//
//  English, Japanese and Korean phrases, amounts written with grouped thousands
//  or CJK units, "$"/"dollars" in the local currency, and keyword targets that
//  resolve to the user's own category whatever language it was created in.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct VoiceInputParserLocaleTests {

    /// Parser over an isolated repository with `categories` seeded as expense
    /// categories. The parser holds the VMs weakly, so the caller retains them.
    private static func makeParser(categories: [String]) -> (VoiceInputParser, CategoriesViewModel, AccountsViewModel, TransactionsViewModel) {
        let repo = UserDefaultsRepository(
            userDefaults: UserDefaults(suiteName: "voice_locale_tests.\(UUID().uuidString)")!
        )
        let categoriesVM = CategoriesViewModel(repository: repo)
        let accountsVM = AccountsViewModel(repository: repo)
        let transactionsVM = TransactionsViewModel(repository: repo)
        for name in categories {
            categoriesVM.addCategory(CustomCategory(
                name: name,
                iconSource: .sfSymbol("circle.fill"),
                colorHex: "#64748b",
                type: .expense
            ))
        }
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesVM,
            accountsViewModel: accountsVM,
            transactionsViewModel: transactionsVM
        )
        return (parser, categoriesVM, accountsVM, transactionsVM)
    }

    private static let english = ["Groceries", "Dining out", "Transport", "Housing", "Health", "Entertainment", "Other"]
    private static let japanese = ["食費", "外食", "交通", "その他"]
    private static let korean = ["장보기", "외식", "교통", "기타"]

    // MARK: - English

    @Test func englishLunchIsDiningOut() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.english)
        _ = (cat, acc, tx)
        let result = parser.parse("Spent 12 dollars on lunch")
        #expect(result.amount == Decimal(12))
        #expect(result.type == .expense)
        #expect(result.categoryName == "Dining out")
        #expect(result.currencyCode == "USD")
    }

    @Test func englishGroceries() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.english)
        _ = (cat, acc, tx)
        #expect(parser.parse("groceries 45").categoryName == "Groceries")
    }

    /// "restaurant" targets the German preset name; the group resolves it.
    @Test func englishRestaurantResolvesThroughGroup() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.english)
        _ = (cat, acc, tx)
        #expect(parser.parse("dinner at a restaurant 30").categoryName == "Dining out")
    }

    @Test func rentMatchesOnlyAsAWord() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.english)
        _ = (cat, acc, tx)
        #expect(parser.parse("paid 1200 rent").categoryName == "Housing")
        #expect(parser.parse("40 for my parents").categoryName != "Housing")
        #expect(parser.parse("trente 15").categoryName != "Housing")
    }

    /// "medicine" is longer than "cine" (Spanish cinema), so it wins.
    @Test func medicineIsHealthNotCinema() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.english)
        _ = (cat, acc, tx)
        #expect(parser.parse("medicine 20").categoryName == "Health")
    }

    /// An English keyword lands in the user's Russian category.
    @Test func englishKeywordFindsRussianCategory() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: ["Продукты", "Кафе и рестораны", "Прочее"])
        _ = (cat, acc, tx)
        #expect(parser.parse("groceries 20").categoryName == "Продукты")
        #expect(parser.parse("coffee 5").categoryName == "Кафе и рестораны")
    }

    /// No keyword: the "Other" preset in the user's language, even when
    /// `category.other` reads differently ("Другое" vs the preset "Прочее").
    @Test func noKeywordFallsBackToOtherPreset() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: ["Продукты", "Прочее"])
        _ = (cat, acc, tx)
        let name = parser.parse("999 непонятно").categoryName
        #expect(name == "Прочее" || name == String(localized: "category.other"))
    }

    // MARK: - Japanese

    @Test func japaneseConvenienceStore() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.japanese)
        _ = (cat, acc, tx)
        let result = parser.parse("コンビニで500円使った")
        #expect(result.amount == Decimal(500))
        #expect(result.currencyCode == "JPY")
        #expect(result.categoryName == "食費")
    }

    @Test func japaneseManUnit() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.japanese)
        _ = (cat, acc, tx)
        let result = parser.parse("ランチ 1万2000円")
        #expect(result.amount == Decimal(12000))
        #expect(result.categoryName == "外食")
    }

    // MARK: - Korean

    @Test func koreanGroupedThousands() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.korean)
        _ = (cat, acc, tx)
        let result = parser.parse("점심 12,000원 썼어")
        #expect(result.amount == Decimal(12000))
        #expect(result.currencyCode == "KRW")
        #expect(result.categoryName == "외식")
    }

    /// "1만 2천" is one amount: the segmenter must not split it into two clauses.
    @Test func koreanUnitsStayOneOperation() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.korean)
        _ = (cat, acc, tx)
        let ops = parser.parseMulti("택시 1만 2천 원")
        #expect(ops.count == 1)
        #expect(ops.first?.amount == Decimal(12000))
        #expect(ops.first?.categoryName == "교통")
        #expect(VoiceInputSegmenter.segment("택시 1만 2천 원").count == 1)
    }

    @Test func koreanBareManWon() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: Self.korean)
        _ = (cat, acc, tx)
        let result = parser.parse("만원 커피")
        #expect(result.amount == Decimal(10000))
        #expect(result.categoryName == "외식")
    }

    // MARK: - Amounts

    @Test func groupedAndDecimalAmounts() {
        let (parser, cat, acc, tx) = Self.makeParser(categories: [])
        _ = (cat, acc, tx)
        #expect(parser.parse("1,500 taxi").amount == Decimal(1500))
        #expect(parser.parse("12,50 euro").amount == Decimal(string: "12.5"))
        #expect(parser.parse("1.234,56 €").amount == Decimal(string: "1234.56"))
        #expect(parser.parse("12.000 euro").amount == Decimal(12000))
        #expect(parser.parse("10 000 тенге").amount == Decimal(10000))
    }

    @Test func decimalAmountReadsSeparators() {
        #expect(VoiceInputParser.decimalAmount("12,000") == Decimal(12000))
        #expect(VoiceInputParser.decimalAmount("12,50") == Decimal(string: "12.5"))
        #expect(VoiceInputParser.decimalAmount("1.234,56") == Decimal(string: "1234.56"))
        #expect(VoiceInputParser.decimalAmount("1,234.56") == Decimal(string: "1234.56"))
        #expect(VoiceInputParser.decimalAmount("10 000") == Decimal(10000))
        #expect(VoiceInputParser.decimalAmount("1500") == Decimal(1500))
        #expect(VoiceInputParser.decimalAmount("12a") == nil)
    }

    @Test func cjkNumeralsExpand() {
        #expect(VoiceInputParser.expandCJKNumerals("1万2000円") == "12000円")
        #expect(VoiceInputParser.expandCJKNumerals("1만 2천 원") == "12000 원")
        #expect(VoiceInputParser.expandCJKNumerals("만원") == "10000원")
        #expect(VoiceInputParser.expandCJKNumerals("百万円") == "1000000円")
        #expect(VoiceInputParser.expandCJKNumerals("1,000万円") == "10000000円")
        #expect(VoiceInputParser.expandCJKNumerals("1.5万") == "15000")
        #expect(VoiceInputParser.expandCJKNumerals("千葉で500円") == "千葉で500円")
        #expect(VoiceInputParser.expandCJKNumerals("500 на такси") == "500 на такси")
    }

    // MARK: - Currency

    @Test func dollarsReadInTheLocalDollar() {
        #expect(VoiceInputParser.currencyCode(in: "12 dollars", localCurrency: "CAD") == "CAD")
        #expect(VoiceInputParser.currencyCode(in: "12 dollars", localCurrency: "KZT") == "USD")
        #expect(VoiceInputParser.currencyCode(in: "12 dollars", localCurrency: nil) == "USD")
        #expect(VoiceInputParser.currencyCode(in: "$12", localCurrency: "MXN") == "MXN")
        #expect(VoiceInputParser.currencyCode(in: "12 dólares", localCurrency: "MXN") == "USD")
        #expect(VoiceInputParser.currencyCode(in: "r$ 50", localCurrency: "USD") == "BRL")
        #expect(VoiceInputParser.currencyCode(in: "12 usd", localCurrency: "CAD") == "USD")
    }

    @Test func currencyWordsCountAtWordStart() {
        #expect(VoiceInputParser.currencyCode(in: "500 тг", localCurrency: nil) == "KZT")
        #expect(VoiceInputParser.currencyCode(in: "20 euros", localCurrency: nil) == "EUR")
        #expect(VoiceInputParser.currencyCode(in: "20 chez le coiffeur", localCurrency: nil) == nil)
        #expect(VoiceInputParser.currencyCode(in: "병원 30000원", localCurrency: nil) == "KRW")
        #expect(VoiceInputParser.currencyCode(in: "병원", localCurrency: nil) == nil)
        #expect(VoiceInputParser.currencyCode(in: "500円", localCurrency: nil) == "JPY")
    }

    @Test func containsWordNeedsWordEdges() {
        #expect(VoiceInputParser.containsWord("rent", in: "paid rent today"))
        #expect(VoiceInputParser.containsWord("rent", in: "rent"))
        #expect(!VoiceInputParser.containsWord("rent", in: "my parent"))
        #expect(!VoiceInputParser.containsWord("rent", in: "trente"))
        #expect(VoiceInputParser.containsWord("bus", in: "bus 2.50"))
        #expect(!VoiceInputParser.containsWord("bus", in: "business"))
    }
}
