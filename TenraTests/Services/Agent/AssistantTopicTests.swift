//
//  AssistantTopicTests.swift
//  TenraTests
//
//  "Ask Ten" from a screen: each topic offers questions about the thing it names, and none of
//  them is taken for a plain record by FastPath (they go to the model).
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantTopicTests {

    @Test(arguments: [
        AssistantTopic.account(name: "Kaspi Gold"),
        .category(name: "Кафе", isIncome: false),
        .category(name: "Зарплата", isIncome: true),
        .insight(title: "Траты на кафе выросли"),
        .goal(name: "Машина"),
        .debt(person: "Асхат", owedToMe: true),
        .debt(person: "Мама", owedToMe: false),
        .asset(name: "Квартира"),
    ])
    func aTopicAsksAboutWhatItNames(_ topic: AssistantTopic) {
        let name: String
        switch topic {
        case .account(let value): name = value
        case .category(let value, _): name = value
        case .insight(let value): name = value
        case .history, .allowance: name = ""
        case .goal(let value): name = value
        case .debt(let value, _): name = value
        case .asset(let value): name = value
        }
        #expect(!topic.questions.isEmpty)
        #expect(topic.questions.allSatisfy { $0.contains(name) })
    }

    @Test func historyAsksAboutTheMonth() {
        #expect(AssistantTopic.history.questions.count == 3)
        #expect(Set(AssistantTopic.history.questions).count == 3)
    }

    /// For today (Analytics): two different questions, both read as questions, not records.
    @Test func allowanceAsksAboutTheMoneyLeft() {
        let questions = AssistantTopic.allowance.questions
        #expect(questions.count == 2)
        #expect(Set(questions).count == 2)
        #expect(questions.allSatisfy { AgentFastPath.readsAsQuestion($0) })
    }

    @Test func expenseAndIncomeCategoriesAskDifferently() {
        #expect(AssistantTopic.category(name: "X", isIncome: false).questions != AssistantTopic.category(name: "X", isIncome: true).questions)
    }
}
