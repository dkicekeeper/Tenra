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

    private func makeModel(_ transport: ScriptedTransport = ScriptedTransport([]), cloudConsent: Bool = false) -> AssistantViewModel {
        AssistantViewModel.feedbackPause = .zero
        var access = AssistantViewModel.Access.unlimited
        access.cloudConsent = { cloudConsent }
        return AssistantViewModel(
            conversation: AgentConversation(transport: transport, toolkit: FakeToolkit()),
            context: { "" },
            access: access
        )
    }

    /// One reply of the model: a line of text.
    private static let helpReply: [[AgentStreamEvent]] = [[AgentScript.done([
        AgentScript.toolUse("toolu_1", "render_reply", [
            "blocks": [["type": "text", "text": "Откройте форму депозита"]],
            "mood": "idle",
            "suggestions": .array([]),
        ]),
    ])]]

    private func sentToModel(_ transport: ScriptedTransport) -> String {
        guard let call = transport.calls.first, let data = try? JSONEncoder().encode(call) else { return "" }
        return String(decoding: data, as: UTF8.self)
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

    // MARK: - Ten helps with a complaint (plan-ten-agent 4.3)

    @Test func withTheCloudAllowedTenHelpsAtOnce() async {
        let outbox = Outbox()
        let transport = ScriptedTransport(Self.helpReply)
        let model = makeModel(transport, cloudConsent: true)
        model.startFeedback(source: .notice, transport: outbox)
        await model.send(AssistantViewModel.feedbackDislike)

        await model.send("I cannot find where deposits are")
        // The owner has the words, and the model got them in a <feedback> block.
        #expect(outbox.sent == [AgentFeedbackMessage(text: "I cannot find where deposits are", mood: .bad, source: .notice)])
        #expect(transport.calls.count == 1)
        #expect(sentToModel(transport).contains("<feedback>"))
        #expect(model.phase == .idle)
        #expect(lastLine(model) == "Откройте форму депозита")
        #expect(model.suggestions == [AssistantViewModel.feedbackHelped, AssistantViewModel.feedbackNotHelped])

        await model.send(AssistantViewModel.feedbackNotHelped)
        #expect(outbox.sent.last == AgentFeedbackMessage(text: "I cannot find where deposits are", mood: .bad, source: .notice, resolved: false))
        #expect(lastLine(model) == String(localized: "feedback.chat.notHelpedReply"))
        #expect(model.suggestions.isEmpty)
        // The chip went to the owner, not to the model.
        #expect(transport.calls.count == 1)
    }

    @Test func withoutTheCloudTenOffersHelpAndWaitsForTheConsent() async {
        let outbox = Outbox()
        let transport = ScriptedTransport(Self.helpReply)
        let model = makeModel(transport)
        model.startFeedback(source: .notice, transport: outbox)
        await model.send(AssistantViewModel.feedbackDislike)

        await model.send("I cannot find where deposits are")
        #expect(lastLine(model) == String(localized: "feedback.chat.thanks"))
        #expect(model.suggestions == [AssistantViewModel.feedbackHelp])
        #expect(transport.calls.isEmpty)

        // Not allowed yet: nothing goes, the caller shows the consent and sends the chip again.
        #expect(await model.send(AssistantViewModel.feedbackHelp, cloudAllowed: false) == false)
        #expect(transport.calls.isEmpty)
        #expect(model.suggestions == [AssistantViewModel.feedbackHelp])

        #expect(await model.send(AssistantViewModel.feedbackHelp, cloudAllowed: true))
        #expect(transport.calls.count == 1)
        #expect(sentToModel(transport).contains("I cannot find where deposits are"))
        #expect(model.suggestions == [AssistantViewModel.feedbackHelped, AssistantViewModel.feedbackNotHelped])

        await model.send(AssistantViewModel.feedbackHelped)
        #expect(outbox.sent.last?.resolved == true)
        #expect(lastLine(model) == String(localized: "feedback.chat.helpedReply"))
    }

    @Test func kindWordsEndWithTheThanks() async {
        let transport = ScriptedTransport(Self.helpReply)
        let model = makeModel(transport, cloudConsent: true)
        model.startFeedback(source: .notice, transport: Outbox())
        await model.send(AssistantViewModel.feedbackLike)
        await model.send("A widget with the balance")
        #expect(lastLine(model) == String(localized: "feedback.chat.thanks"))
        #expect(model.suggestions.isEmpty)
        #expect(transport.calls.isEmpty)
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
