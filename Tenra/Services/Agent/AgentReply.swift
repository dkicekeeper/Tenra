//
//  AgentReply.swift
//  Tenra
//
//  The assistant's reply, decoded from the input of its `render_reply` tool call. The model
//  picks which cards to show; every figure in a card comes from a tool result by reference
//  (`source` = the tool_use id, `path` = a dotted path inside that result), never from text
//  (docs/plan-ai-assistant.md §3.3). Block types the app doesn't know yet decode as
//  `.unsupported`, so the server can add one without breaking older builds.
//

import Foundation

nonisolated enum AgentMood: String, Sendable, Equatable, Decodable {
    case idle, happy, concerned, celebrate

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentMood(rawValue: raw) ?? .idle
    }
}

nonisolated enum AgentChartKind: String, Sendable, Equatable, Decodable {
    case bar, line, donut
}

nonisolated enum AgentDestination: String, Sendable, Equatable, Decodable {
    case category, account, analytics, history, budgets, subscriptions
}

nonisolated enum AgentBlock: Sendable, Equatable, Decodable {
    case text(String)
    case metric(label: String, source: String, path: String, trendPath: String?)
    case chart(kind: AgentChartKind, title: String, source: String, path: String)
    case transactions(title: String?, source: String)
    case budgets(source: String, categoryIds: [String]?)
    case recurring(source: String)
    case forecast(source: String)
    case insight(source: String, insightId: String)
    case confirm(draftId: String)
    case open(destination: AgentDestination, targetId: String?, label: String)
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, label, source, path, kind, title, destination
        case trendPath = "trend_path"
        case categoryIds = "category_ids"
        case insightId = "insight_id"
        case draftId = "draft_id"
        case targetId = "target_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "metric":
            self = .metric(
                label: try c.decode(String.self, forKey: .label),
                source: try c.decode(String.self, forKey: .source),
                path: try c.decode(String.self, forKey: .path),
                trendPath: try c.decodeIfPresent(String.self, forKey: .trendPath)
            )
        case "chart":
            self = .chart(
                kind: try c.decode(AgentChartKind.self, forKey: .kind),
                title: try c.decode(String.self, forKey: .title),
                source: try c.decode(String.self, forKey: .source),
                path: try c.decode(String.self, forKey: .path)
            )
        case "transactions":
            self = .transactions(title: try c.decodeIfPresent(String.self, forKey: .title), source: try c.decode(String.self, forKey: .source))
        case "budgets":
            self = .budgets(source: try c.decode(String.self, forKey: .source), categoryIds: try c.decodeIfPresent([String].self, forKey: .categoryIds))
        case "recurring":
            self = .recurring(source: try c.decode(String.self, forKey: .source))
        case "forecast":
            self = .forecast(source: try c.decode(String.self, forKey: .source))
        case "insight":
            self = .insight(source: try c.decode(String.self, forKey: .source), insightId: try c.decode(String.self, forKey: .insightId))
        case "confirm":
            self = .confirm(draftId: try c.decode(String.self, forKey: .draftId))
        case "open":
            self = .open(
                destination: try c.decode(AgentDestination.self, forKey: .destination),
                targetId: try c.decodeIfPresent(String.self, forKey: .targetId),
                label: try c.decode(String.self, forKey: .label)
            )
        default:
            self = .unsupported(type: type)
        }
    }

    /// The tool result this block reads its data from, if any.
    var source: String? {
        switch self {
        case .metric(_, let source, _, _), .chart(_, _, let source, _), .transactions(_, let source),
             .budgets(let source, _), .recurring(let source), .forecast(let source), .insight(let source, _):
            return source
        default:
            return nil
        }
    }
}

nonisolated struct AgentReply: Sendable, Equatable, Decodable {
    let blocks: [AgentBlock]
    let mood: AgentMood
    let suggestions: [String]

    private enum CodingKeys: String, CodingKey { case blocks, mood, suggestions }

    init(blocks: [AgentBlock], mood: AgentMood, suggestions: [String]) {
        self.blocks = blocks
        self.mood = mood
        self.suggestions = suggestions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try c.decode([AgentBlock].self, forKey: .blocks)
        mood = try c.decodeIfPresent(AgentMood.self, forKey: .mood) ?? .idle
        suggestions = try c.decodeIfPresent([String].self, forKey: .suggestions) ?? []
    }
}
