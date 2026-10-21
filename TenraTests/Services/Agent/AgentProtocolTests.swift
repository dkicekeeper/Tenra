//
//  AgentProtocolTests.swift
//  TenraTests
//
//  The app side of the assistant protocol (docs/domains/assistant.md §8): JSON values that
//  round-trip, the SSE stream, the reply blocks, server errors and the <app_context> block.
//

import Foundation
import Testing
@testable import Tenra

struct AgentProtocolTests {

    @Test func jsonValueRoundTripsAndFollowsPaths() throws {
        let raw = #"{"total":1250.5,"groups":[{"key":"cat_cafe","total":82310}],"ok":true,"none":null,"name":"Кафе"}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        #expect(value.value(atPath: "total") == .number(1250.5))
        #expect(value.value(atPath: "groups.0.key") == .string("cat_cafe"))
        #expect(value.value(atPath: "groups.1.key") == nil)
        #expect(value["ok"] == .bool(true))
        #expect(value["none"] == .null)
        #expect(value["name"] == "Кафе")
        let again = try JSONDecoder().decode(JSONValue.self, from: Data(value.jsonString().utf8))
        #expect(again == value)
    }

    @Test func thinkingBlocksSurviveTheRoundTripUnchanged() throws {
        let block: JSONValue = ["type": "thinking", "thinking": "", "signature": "EpQBCkYIBRgCKkB"]
        let message = AgentWireMessage(role: .assistant, content: [block])
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AgentWireMessage.self, from: data)
        #expect(decoded == message)
    }

    @Test func sseParserCopesWithoutBlankLines() {
        // URLSession's `lines` drops blank lines, so events must also split on `event:`.
        var parser = AgentSSEParser()
        let lines = [
            "event: tool", #"data: {"name":"get_accounts"}"#,
            "event: text", #"data: {"text":"hi"}"#, "",
            "event: error", #"data: {"code":"upstream_busy","retryable":true}"#,
        ]
        var events: [AgentStreamEvent] = []
        for line in lines {
            if let event = parser.feed(line: line) { events.append(event) }
        }
        if let event = parser.finish() { events.append(event) }
        #expect(events == [.tool(name: "get_accounts"), .text("hi"), .error(code: "upstream_busy", retryable: true)])
    }

    @Test func doneEventDecodes() {
        let data = #"{"content":[{"type":"text","text":"x","citations":null}],"stop_reason":"end_turn","model":"claude-haiku-5-5","refused":false,"truncated":false,"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":3},"tier":"pro","quota":{"used":2,"limit":900}}"#
        guard case .done(let done) = AgentSSEParser.decode(event: "done", data: data) else {
            Issue.record("expected a done event")
            return
        }
        #expect(done.model == "claude-haiku-5-5")
        #expect(done.quota == AgentQuota(used: 2, limit: 900))
        #expect(done.content.first?["citations"] == .null)
    }

    @Test func replyDecodesEveryBlockAndToleratesUnknownOnes() throws {
        let raw = """
        {"blocks":[
          {"type":"text","text":"Октябрь спокойнее"},
          {"type":"metric","label":"Расходы","source":"toolu_1","path":"total","trend_path":null},
          {"type":"chart","kind":"bar","title":"По категориям","source":"toolu_1","path":"groups"},
          {"type":"transactions","title":null,"source":"toolu_2"},
          {"type":"budgets","source":"toolu_3","category_ids":["cat_cafe"]},
          {"type":"confirm","draft_id":"draft_1"},
          {"type":"open","destination":"category","target_id":"cat_cafe","label":"Открыть"},
          {"type":"hologram","source":"toolu_9"}
        ],"mood":"happy","suggestions":["Сравни с сентябрём"]}
        """
        let reply = try JSONDecoder().decode(AgentReply.self, from: Data(raw.utf8))
        #expect(reply.blocks.count == 8)
        #expect(reply.blocks[1] == .metric(label: "Расходы", source: "toolu_1", path: "total", trendPath: nil))
        #expect(reply.blocks[2].source == "toolu_1")
        #expect(reply.blocks[5] == .confirm(draftId: "draft_1"))
        #expect(reply.blocks[7] == .unsupported(type: "hologram"))
        #expect(reply.mood == .happy)
        #expect(reply.suggestions == ["Сравни с сентябрём"])
    }

    @Test func aMalformedBlockShowsNothingAndTheRestStays() throws {
        let raw = """
        {"blocks":[
          {"type":"metric","label":"Расходы","source":"toolu_1"},
          {"type":"chart","kind":"pie","title":"По категориям","source":"toolu_1","path":"groups"},
          {"source":"toolu_1"},
          {"type":"text","text":"Октябрь спокойнее"}
        ],"mood":"happy","suggestions":"Сравни с сентябрём"}
        """
        let reply = try JSONDecoder().decode(AgentReply.self, from: Data(raw.utf8))
        #expect(reply.blocks == [
            .unsupported(type: "metric"),
            .unsupported(type: "chart"),
            .unsupported(type: ""),
            .text("Октябрь спокойнее"),
        ])
        #expect(reply.suggestions.isEmpty)
    }

    /// The moods the server's render_reply schema allows (server/assistant/src/tools.ts).
    @Test func everyServerMoodDecodes() throws {
        let moods: [String: AgentMood] = [
            "idle": .idle, "happy": .happy, "concerned": .concerned, "celebrate": .celebrate,
            "proud": .proud, "surprised": .surprised, "love": .love, "playful": .playful, "empty": .empty,
        ]
        for (raw, mood) in moods {
            let reply = try JSONDecoder().decode(AgentReply.self, from: Data(#"{"blocks":[],"mood":"\#(raw)","suggestions":[]}"#.utf8))
            #expect(reply.mood == mood, "\(raw)")
        }
    }

    @Test func unknownMoodFallsBackToIdle() throws {
        let reply = try JSONDecoder().decode(AgentReply.self, from: Data(#"{"blocks":[],"mood":"ecstatic","suggestions":[]}"#.utf8))
        #expect(reply.mood == .idle)
    }

    @Test func serverErrorsMapFromStatusAndBody() {
        #expect(AgentServerError.from(status: 429, body: Data(#"{"error":"quota","limit":900}"#.utf8)) == .quotaExceeded(limit: 900))
        #expect(AgentServerError.from(status: 429, body: Data(#"{"error":"busy"}"#.utf8)) == .busy)
        #expect(AgentServerError.from(status: 451, body: Data()) == .regionUnavailable)
        #expect(AgentServerError.from(status: 400, body: Data(#"{"error":"invalid","reason":"protocol"}"#.utf8)) == .invalidRequest(reason: "protocol"))
        #expect(AgentServerError.from(status: 503, body: Data()) == .disabled)
        #expect(AgentServerError.from(status: 401, body: Data(#"{"error":"attest","reason":"missing"}"#.utf8)) == .attestation(reason: "missing"))
        #expect(AgentServerError.from(status: 401, body: Data(#"{"error":"user"}"#.utf8)) == .unauthorized)
    }

    @Test func turnRequestCarriesTheProtocolVersion() throws {
        let data = try JSONEncoder().encode(AgentTurnRequest(messages: [.userText(["hi"])]))
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(value["protocol"] == .number(Double(AgentProtocol.version)))
        #expect(value.value(atPath: "messages.0.role") == "user")
        #expect(value.value(atPath: "messages.0.content.0.text") == "hi")
        #expect(value["user"] == nil)
    }

    @Test func turnRequestSignsTheUserIdInItsBody() throws {
        let data = try JSONEncoder().encode(AgentTurnRequest(messages: [.userText(["hi"])], user: "$RCAnonymousID:abc"))
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(value["user"] == .string("$RCAnonymousID:abc"))
    }

    @Test func contextBlockMatchesTheServerFormat() throws {
        let almaty = try #require(TimeZone(identifier: "Asia/Almaty"))
        let snapshot = AgentContextSnapshot(
            today: Date(timeIntervalSince1970: 1_793_170_800), // 2026-10-28 12:00 in Almaty
            timeZone: almaty,
            locale: "ru",
            baseCurrency: "KZT",
            accounts: [.init(id: "acc_1", name: "Kaspi \"Gold\"", currency: "KZT", kind: "regular")],
            categories: [.init(id: "cat_1", name: "Кафе", isIncome: false), .init(id: "cat_2", name: "Зарплата", isIncome: true)]
        )
        let text = AgentContextBuilder.text(for: snapshot)
        #expect(text.hasPrefix("<app_context>\ntoday: 2026-10-28 (Wednesday)\nlocale: ru\nbase_currency: KZT"))
        #expect(text.contains("accounts: acc_1 \"Kaspi 'Gold'\" (KZT, regular)"))
        #expect(text.contains("expense categories: cat_1 \"Кафе\""))
        #expect(text.contains("income categories: cat_2 \"Зарплата\""))
        #expect(text.hasSuffix("</app_context>"))
        // No facts, no facts line.
        #expect(!text.contains("facts"))
    }

    @Test func contextBlockListsTheRememberedFacts() throws {
        let snapshot = AgentContextSnapshot(
            today: Date(timeIntervalSince1970: 1_793_170_800),
            timeZone: try #require(TimeZone(identifier: "Asia/Almaty")),
            locale: "ru",
            baseCurrency: "KZT",
            accounts: [],
            categories: [],
            facts: [.init(id: "f1", text: "Зарплата приходит 10-го"), .init(id: "f3", text: "Копит на \"машину\"")]
        )
        let text = AgentContextBuilder.text(for: snapshot)
        #expect(text.contains("\nfacts you remember about the user: f1 \"Зарплата приходит 10-го\"; f3 \"Копит на 'машину'\"\n</app_context>"))
    }
}
