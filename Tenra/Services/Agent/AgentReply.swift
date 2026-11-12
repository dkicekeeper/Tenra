//
//  AgentReply.swift
//  Tenra
//
//  The assistant's reply, decoded from the input of its `render_reply` tool call. The model
//  picks which cards to show; every figure in a card comes from a tool result by reference
//  (`source` = the result's `result_id`, `path` = a dotted path inside it), never from text
//  (docs/domains/assistant.md §4). Block types the app doesn't know yet decode as
//  `.unsupported`, so the server can add one without breaking older builds. `render_reply`
//  is not a strict tool (the API refuses the grammar of its block union), so a block the
//  model got wrong decodes as `.unsupported` too, and the rest of the reply still shows.
//

import Foundation

nonisolated enum AgentMood: String, Sendable, Equatable, Decodable {
    case idle, happy, concerned, celebrate
    /// Steady progress the person made: a budget kept, money put towards a goal.
    case proud
    /// Something out of the ordinary: an unusually large expense, a sudden jump.
    case surprised
    /// The person thanked Ten or said something kind.
    case love
    /// A light tip or a friendly joke.
    case playful
    /// What the person asked about has nothing to show.
    case empty
    /// Something went wrong for the person and Ten is sorry. Set on the phone only (the
    /// feedback talk after a complaint); the server's render_reply never sends it.
    case sad

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
    /// The assets list, and one asset by its id (plan-assets-roadmap 1.4). A version without
    /// them reads the block as unsupported and leaves it out.
    case assets, asset
    /// The lists of Finances and what the person keeps there by id (plan-ten-agent 4.2).
    case accounts, deposits, loans, goals, goal, debts, debt
    /// Settings, its backups screen and the guide to the Wallet automation.
    case settings, backups
    case walletGuide = "wallet_guide"
}

/// What an `open` block with the destination "create" starts: the app's own form for a new
/// one, over its list, which keeps the form's checks, the Pro gate and the one way to save.
/// Only what Ten has no draft tool for.
nonisolated enum AgentCreateKind: String, Sendable, Equatable, Decodable {
    case account, deposit, loan, category
}

/// What the person already said about the new thing, put into the form's fields before they
/// see it. Every field is optional and a mistyped one is left out: the form then starts empty
/// there. Amounts are the person's own words, as in a draft, never the model's figures.
nonisolated struct AgentFormPrefill: Sendable, Hashable, Decodable {
    var name: String?
    /// An account's balance, a deposit's or a loan's amount, a category's budget.
    var amount: Decimal?
    var currency: String?
    var bank: String?
    /// A deposit's or a loan's yearly rate.
    var ratePercent: Decimal?
    /// A loan's term.
    var termMonths: Int?
    /// The day of the month interest is posted or the payment is due.
    var day: Int?
    /// A category of income rather than of expenses.
    var income: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, amount, currency, bank, day, income
        case ratePercent = "rate_percent"
        case termMonths = "term_months"
    }

    init(
        name: String? = nil, amount: Decimal? = nil, currency: String? = nil, bank: String? = nil,
        ratePercent: Decimal? = nil, termMonths: Int? = nil, day: Int? = nil, income: Bool? = nil
    ) {
        self.name = name
        self.amount = amount
        self.currency = currency
        self.bank = bank
        self.ratePercent = ratePercent
        self.termMonths = termMonths
        self.day = day
        self.income = income
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? {
            let value = (try? c.decodeIfPresent(String.self, forKey: key))?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) }
        }
        func positive(_ key: CodingKeys) -> Decimal? {
            (try? c.decodeIfPresent(Decimal.self, forKey: key)).flatMap { $0 > 0 ? $0 : nil }
        }
        name = text(.name)
        amount = positive(.amount)
        currency = text(.currency).map { $0.uppercased() }.flatMap { $0.count == 3 ? $0 : nil }
        bank = text(.bank)
        ratePercent = positive(.ratePercent).flatMap { $0 <= 1000 ? $0 : nil }
        termMonths = (try? c.decodeIfPresent(Int.self, forKey: .termMonths)).flatMap { (1...600).contains($0) ? $0 : nil }
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)).flatMap { (1...31).contains($0) ? $0 : nil }
        income = try? c.decodeIfPresent(Bool.self, forKey: .income)
    }
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
    /// An `open` block whose destination is "create": the form for a new one, prefilled.
    case create(kind: AgentCreateKind, prefill: AgentFormPrefill, label: String)
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, label, source, path, kind, title, destination, prefill
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
        case "open" where (try? c.decode(String.self, forKey: .destination)) == "create":
            self = .create(
                kind: try c.decode(AgentCreateKind.self, forKey: .kind),
                prefill: (try? c.decodeIfPresent(AgentFormPrefill.self, forKey: .prefill)) ?? AgentFormPrefill(),
                label: try c.decode(String.self, forKey: .label)
            )
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
        blocks = try c.decode([LenientBlock].self, forKey: .blocks).map(\.block)
        mood = try c.decodeIfPresent(AgentMood.self, forKey: .mood) ?? .idle
        suggestions = (try? c.decodeIfPresent([String].self, forKey: .suggestions)) ?? []
    }

    /// A block with a missing or mistyped field shows nothing instead of failing the reply.
    private nonisolated struct LenientBlock: Decodable {
        let block: AgentBlock

        private enum CodingKeys: String, CodingKey { case type }

        init(from decoder: Decoder) throws {
            if let block = try? AgentBlock(from: decoder) {
                self.block = block
            } else {
                let type = try? decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .type)
                self.block = .unsupported(type: type ?? "")
            }
        }
    }
}
