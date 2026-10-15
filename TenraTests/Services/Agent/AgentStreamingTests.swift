//
//  AgentStreamingTests.swift
//  TenraTests
//
//  The reply's text while it streams (AgentPartialReply): render_reply's unfinished input JSON
//  is closed where it was cut and its text blocks read out; a cut that cannot be read yields
//  nothing. The conversation reports each new state of the text, and the server's "reply"
//  event decodes. Text blocks are Markdown, split into ArticleBody blocks (AgentReplyMarkdown).
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentStreamingTests {

    @Test func theTextSoFarIsReadFromAnUnfinishedReply() {
        let full = #"{"blocks":[{"type":"text","text":"В октябре **кафе** выросли."},{"type":"metric","label":"Кафе","source":"r1","path":"total"},{"type":"text","text":"Можно урезать"}],"mood":"concerned"}"#
        #expect(AgentPartialReply.texts(fromPartialJSON: full) == ["В октябре **кафе** выросли.", "Можно урезать"])

        // Cut inside the first text: what is written so far.
        let cut = String(full.prefix(43))
        #expect(AgentPartialReply.texts(fromPartialJSON: cut) == ["В октябре"])
        // Cut inside a key or right after a colon: nothing new, or the text closed so far.
        #expect(AgentPartialReply.texts(fromPartialJSON: #"{"blocks":[{"ty"#) == nil)
        #expect(AgentPartialReply.texts(fromPartialJSON: #"{"blocks":[{"type":"text","text":"#) == [])
        // Before the blocks start.
        #expect(AgentPartialReply.texts(fromPartialJSON: #"{"blo"#) == nil)
        #expect(AgentPartialReply.texts(fromPartialJSON: "") == nil)
    }

    @Test func aCutAfterABackslashOrInsideAnEscapeIsHandled() {
        #expect(AgentPartialReply.texts(fromPartialJSON: #"{"blocks":[{"type":"text","text":"Line\"#) == ["Line"])
        #expect(AgentPartialReply.texts(fromPartialJSON: #"{"blocks":[{"type":"text","text":"Say \"hi\" now"#) == [#"Say "hi" now"#])
        #expect(AgentPartialReply.closing(#"{"a":[1,2,"#) == #"{"a":[1,2]}"#)
        #expect(AgentPartialReply.closing(#"{"a":"#) == #"{"a":null}"#)
        #expect(AgentPartialReply.closing("]") == nil)
    }

    @Test func theConversationReportsTheReplyAsItStreams() async throws {
        let reply: JSONValue = ["blocks": [["type": "text", "text": "Hello"]], "mood": "happy", "suggestions": []]
        let transport = ScriptedTransport([[
            .tool(name: AgentProtocol.renderReplyTool),
            .reply(#"{"blocks":[{"type":"text","text":"Hel"#),
            .reply(#"lo"#),
            .reply(#""}],"mood":"happy","suggestions":[]}"#),
            AgentScript.done([AgentScript.toolUse("toolu_1", AgentProtocol.renderReplyTool, reply)]),
        ]])
        let conversation = AgentConversation(transport: transport, toolkit: FakeToolkit())
        var progress: [AgentConversation.Progress] = []

        _ = try await conversation.send("Привет") { progress.append($0) }

        #expect(progress == [
            .toolStarted(AgentProtocol.renderReplyTool),
            .replyText(["Hel"]),
            .replyText(["Hello"]),
        ])
    }

    @Test func theServersReplyEventDecodes() {
        #expect(AgentSSEParser.decode(event: "reply", data: #"{"json":"{\"blocks\""}"#) == .reply(#"{"blocks""#))
    }

    // MARK: - Markdown

    @Test func markdownBecomesArticleBlocks() {
        let text = """
        ### План на месяц
        Траты на **кафе** выросли.
        Это заметно.

        - Готовить дома
        - Поставить бюджет

        1. Открыть бюджеты
        2) Выбрать кафе
        > Бюджет можно поменять в любой день.
        """
        #expect(AgentReplyMarkdown.blocks(text) == [
            .heading("План на месяц", level: 3),
            .paragraph("Траты на **кафе** выросли.\nЭто заметно."),
            .bullets(["Готовить дома", "Поставить бюджет"]),
            .steps(["Открыть бюджеты", "Выбрать кафе"]),
            .note("Бюджет можно поменять в любой день."),
        ])
    }

    @Test func plainTextStaysOneParagraph() {
        #expect(AgentReplyMarkdown.blocks("Всё в порядке, бюджет не превышен.") == [.paragraph("Всё в порядке, бюджет не превышен.")])
        #expect(AgentReplyMarkdown.blocks("**Важно**: проверь счёт") == [.paragraph("**Важно**: проверь счёт")])
        #expect(AgentReplyMarkdown.blocks("#хэштег без пробела") == [.paragraph("#хэштег без пробела")])
        #expect(AgentReplyMarkdown.blocks("") == [])
    }
}
