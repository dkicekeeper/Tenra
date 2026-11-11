//
//  AssistantFeedbackChatTests.swift
//  TenraTests
//
//  The feedback talk in Ten's chat (AssistantViewModel.startFeedback): Ten asks, the person
//  answers with a chip and then in words, and the words go to the owner, never to the model.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssistantFeedbackChatTests {

    /// Keeps what was sent; fails while `failing` is on.
    @MainActor
    private final class Outbox: AgentFeedbackTransport {
        var sent: [AgentFeedbackMessage] = []
        var failing = false

        nonisolated func feedback(_ message: AgentFeedbackMessage) async throws {
            try await MainActor.run {
                if failing { throw URLError(.notConnectedToInternet) }
                sent.append(message)
            }
        }
    }

    private func makeModel(_ transport: ScriptedTransport = ScriptedTransport([])) -> AssistantViewModel {
        AssistantViewModel.feedbackPause = .zero
        return AssistantViewModel(conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()), context: { "" })
    }

    private func lastLine(_ model: AssistantViewModel) -> String? {
        guard case .reply(let reply, _)? = model.entries.last?.content,
              case .text(let text)? = reply.blocks.first else { return nil }
        return text
    }

    @Test func tenAsksAndOffersTwoAnswers() {
        let model = makeModel()
        #expect(model.startFeedback(source: .notice, transport: Outbox()))
        #expect(model.feedbackStep == .mood)
        #expect(model.entries.count == 1)
        #expect(lastLine(model) == String(localized: "feedback.chat.askMood"))
        #expect(model.suggestions == [AssistantViewModel.feedbackLike, AssistantViewModel.feedbackDislike])
    }

    @Test func likingItLeadsToWhatElseAndTheWordsGoToTheOwner() async {
        let outbox = Outbox()
        let transport = ScriptedTransport([])
        let model = makeModel(transport)
        var sentMoods: [AgentFeedbackMessage.Mood?] = []
        model.startFeedback(source: .notice, transport: outbox) { sentMoods.append($0) }

        await model.send(AssistantViewModel.feedbackLike)
        #expect(model.feedbackStep == .details(.good))
        #expect(lastLine(model) == String(localized: "feedback.chat.askGood"))
        #expect(model.suggestions.isEmpty)
        #expect(outbox.sent.isEmpty)

        await model.send("  A widget with the balance  ")
        #expect(outbox.sent == [AgentFeedbackMessage(text: "A widget with the balance", mood: .good, source: .notice)])
        #expect(lastLine(model) == String(localized: "feedback.chat.thanks"))
        #expect(model.feedbackStep == nil)
        #expect(model.phase == .idle)
        #expect(sentMoods == [.good])
        // Nothing of the talk reached the model.
        #expect(transport.calls.isEmpty)
    }

    @Test func notLikingItAsksWhatWentWrong() async {
        let outbox = Outbox()
        let model = makeModel()
        model.startFeedback(source: .notice, transport: outbox)

        await model.send(AssistantViewModel.feedbackDislike)
        #expect(model.feedbackStep == .details(.bad))
        #expect(lastLine(model) == String(localized: "feedback.chat.askBad"))

        await model.send("Too many steps to add an expense")
        #expect(outbox.sent.first?.mood == .bad)
    }

    @Test func wordsTypedInsteadOfAChipAreTheAnswer() async {
        let outbox = Outbox()
        let model = makeModel()
        model.startFeedback(source: .notice, transport: outbox)

        await model.send("Please add a dark icon")
        #expect(outbox.sent == [AgentFeedbackMessage(text: "Please add a dark icon", mood: nil, source: .notice)])
        #expect(model.feedbackStep == nil)
    }

    @Test func afterTheSurveyTenSkipsTheFirstQuestion() async {
        let outbox = Outbox()
        let model = makeModel()
        model.startFeedback(source: .survey, transport: outbox)
        #expect(model.feedbackStep == .details(.bad))
        #expect(lastLine(model) == String(localized: "feedback.chat.askBad"))
        #expect(model.suggestions.isEmpty)

        await model.send("It lost my categories")
        #expect(outbox.sent == [AgentFeedbackMessage(text: "It lost my categories", mood: .bad, source: .survey)])
    }

    @Test func aFailedSendKeepsTheQuestionOpen() async {
        let outbox = Outbox()
        outbox.failing = true
        let model = makeModel()
        var sent = false
        model.startFeedback(source: .notice, transport: outbox) { _ in sent = true }
        await model.send(AssistantViewModel.feedbackDislike)

        await model.send("The app is slow")
        #expect(lastLine(model) == String(localized: "feedback.chat.failed"))
        #expect(model.feedbackStep == .details(.bad))
        #expect(!sent)

        outbox.failing = false
        await model.send("The app is slow")
        #expect(outbox.sent.count == 1)
        #expect(sent)
    }

    @Test func aNewChatEndsTheTalk() async {
        let transport = ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_1", source: "r1", mood: "idle", suggestions: [])])]])
        let outbox = Outbox()
        let model = makeModel(transport)
        model.startFeedback(source: .notice, transport: outbox)

        model.reset()
        #expect(model.feedbackStep == nil)
        #expect(model.entries.isEmpty)
        await model.send("How much did I spend?")
        #expect(outbox.sent.isEmpty)
        #expect(transport.calls.count >= 1)
    }
}
