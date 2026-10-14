//
//  AgentFastPathTests.swift
//  TenraTests
//
//  FastPath's test of a message (AgentFastPath): a plain record of income or expenses is
//  drafted on the phone; a question, a plan, a transfer, a regular payment or a part the parser
//  could not read goes to the model, in every language the app speaks.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentFastPathTests {

    private static func expense(_ amount: Decimal, category: String? = "Кафе", type: TransactionType = .expense) -> ParsedOperation {
        ParsedOperation(type: type, amount: amount, currencyCode: "KZT", categoryName: category)
    }

    @Test func plainRecordsAreDraftedOnThePhone() {
        #expect(AgentFastPath.isRecord("кофе 1500", operations: [Self.expense(1500)], clauses: 1))
        #expect(AgentFastPath.isRecord("кофе 1500 и такси 2300 с каспи", operations: [Self.expense(1500), Self.expense(2300, category: "Такси")], clauses: 2))
        #expect(AgentFastPath.isRecord("зарплата 500000", operations: [Self.expense(500_000, category: "Зарплата", type: .income)], clauses: 1))
        #expect(AgentFastPath.isRecord("coffee 5 dollars", operations: [Self.expense(5)], clauses: 1))
    }

    @Test func whatTheParserCouldNotReadGoesToTheModel() {
        // No category, no amount, a clause left over, a transfer type.
        #expect(!AgentFastPath.isRecord("500 Ивану", operations: [Self.expense(500, category: nil)], clauses: 1))
        #expect(!AgentFastPath.isRecord("кофе", operations: [], clauses: 1))
        #expect(!AgentFastPath.isRecord("кофе 1500", operations: [ParsedOperation(type: .expense, amount: 0, categoryName: "Кафе")], clauses: 1))
        #expect(!AgentFastPath.isRecord("кофе 1500 и такси", operations: [Self.expense(1500)], clauses: 2))
        #expect(!AgentFastPath.isRecord("каспи 5000", operations: [Self.expense(5000, type: .internalTransfer)], clauses: 1))
        #expect(!AgentFastPath.isRecord(String(repeating: "кофе 1500 ", count: 20), operations: [Self.expense(1500)], clauses: 1))
    }

    @Test(arguments: [
        "Сколько я потратил на кафе 5000?",
        "можно потратить 50000 на ресторан",
        "отложить 50000 в месяц",
        "подписка нетфликс 4990",
        "перевел 50000 с каспи на халык",
        "стоит ли гасить кредит 300000",
        "хочу купить телефон за 300000",
        "скільки я витратив на каву 1500",
        "how much did I spend on coffee 1500",
        "should I invest 100000",
        "netflix 15 monthly",
        "wie viel für Kaffee 5 Euro",
        "cuánto gasté en café 5",
        "combien pour le café 5 euros",
        "quanto ho speso per il caffè 5",
        "quanto gastei em café 5",
        "kahve için ne kadar harcadım 50",
        "コーヒーにいくら使った 500",
        "커피에 얼마 썼어 5000",
    ])
    func questionsAndPlansGoToTheModel(_ text: String) {
        #expect(AgentFastPath.readsAsQuestion(text))
        #expect(!AgentFastPath.isRecord(text, operations: [Self.expense(1500)], clauses: 1))
    }

    @Test(arguments: ["кофе 1500", "такси 2300 с каспи", "продукты 12000 вчера", "coffee 5", "Kaffee 5 Euro", "taxi 12 euros"])
    func recordsDoNotReadAsQuestions(_ text: String) {
        #expect(!AgentFastPath.readsAsQuestion(text))
    }
}
