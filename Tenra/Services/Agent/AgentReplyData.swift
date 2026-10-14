//
//  AgentReplyData.swift
//  Tenra
//
//  Reads the figures of a reply block from the tool results it points at (`source` = the
//  tool_use id, `path` = a dotted path inside that result; docs/plan-ai-assistant.md §3.3). The
//  model never writes a number: every amount on screen comes from here, from the phone's own
//  tool results, so a block whose reference does not resolve shows nothing rather than a guess.
//
//  The shapes are FinanceToolkit's: results carry their `currency` and `type` at the top,
//  groups are `{key, label, total | current | previous, count, share}`, lists are `items`.
//

import Foundation

nonisolated enum AgentReplyData {

    // MARK: - Metric

    struct Metric: Equatable {
        enum Value: Equatable {
            case amount(Double, currency: String)
            case percent(Double)
            case count(Double)
        }

        let label: String
        let value: Value
        /// Change against the previous period, in percent, when the block names one.
        let changePercent: Double?
        /// Expenses: a rise is bad news.
        let isExpense: Bool
    }

    static func metric(label: String, source: String, path: String, trendPath: String?, results: [String: JSONValue]) -> Metric? {
        guard let result = results[source], let number = result.value(atPath: path)?.numberValue else { return nil }
        let value: Metric.Value
        switch kind(ofPath: path) {
        case .percent: value = .percent(number)
        case .count: value = .count(number)
        case .amount:
            guard let currency = currency(of: result, atPath: path) else { return nil }
            value = .amount(number, currency: currency)
        }
        var change: Double?
        if let trendPath, let trend = result.value(atPath: trendPath)?.numberValue, kind(ofPath: trendPath) == .percent {
            change = trend
        }
        return Metric(label: label, value: value, changePercent: change, isExpense: result["type"]?.stringValue == "expense")
    }

    enum PathKind: Equatable { case amount, percent, count }

    /// What a figure is, from its key: `change_percent` and `share` are percentages, `count`
    /// and `days_left` are plain numbers, everything else is money.
    static func kind(ofPath path: String) -> PathKind {
        let key = path.split(separator: ".").last.map(String.init) ?? path
        if key.contains("percent") || key == "share" { return .percent }
        if key.contains("count") || key.hasPrefix("days") { return .count }
        return .amount
    }

    /// The currency of an amount: the nearest `currency` on the way from the root to the
    /// figure (an account row has its own; a summary has one at the top). A `_base` figure is
    /// in the base currency, the one at the top.
    static func currency(of result: JSONValue, atPath path: String) -> String? {
        var found = result["currency"]?.stringValue
        if path.hasSuffix("_base") { return found }
        var node: JSONValue? = result
        for key in path.split(separator: ".").map(String.init).dropLast() {
            switch node {
            case .object(let object): node = object[key]
            case .array(let array): node = Int(key).flatMap { array.indices.contains($0) ? array[$0] : nil }
            default: node = nil
            }
            if let own = node?["currency"]?.stringValue { found = own }
        }
        return found
    }

    // MARK: - Chart

    struct ChartGroup: Equatable, Identifiable {
        let id: String
        let label: String
        let value: Double
        let previous: Double?
    }

    struct Chart: Equatable {
        let groups: [ChartGroup]
        let currency: String
        /// Groups are periods (`2026-10`, a week's Monday) rather than categories or merchants.
        let isTimeline: Bool
    }

    static func chart(source: String, path: String, results: [String: JSONValue]) -> Chart? {
        guard let result = results[source],
              let rows = result.value(atPath: path)?.arrayValue,
              let currency = result["currency"]?.stringValue else { return nil }
        let groups: [ChartGroup] = rows.compactMap { row in
            guard let key = row["key"]?.stringValue,
                  let value = (row["total"] ?? row["current"] ?? row["amount_base"])?.numberValue else { return nil }
            return ChartGroup(id: key, label: row["label"]?.stringValue ?? key, value: value, previous: row["previous"]?.numberValue)
        }
        guard !groups.isEmpty else { return nil }
        let isTimeline = groups.allSatisfy { FastDateParser.date(from: $0.id) != nil || isMonthKey($0.id) }
        return Chart(groups: groups, currency: currency, isTimeline: isTimeline)
    }

    private static func isMonthKey(_ key: String) -> Bool {
        key.count == 7 && FastDateParser.date(from: key + "-01") != nil
    }

    // MARK: - Forecast

    struct Forecast: Equatable {
        struct Obligation: Equatable {
            let date: String
            let label: String
            let amount: Double
        }

        let currency: String
        let until: String
        let dailyAllowance: Double
        let freeAmount: Double
        /// The daily balance, as a timeline chart.
        let balance: Chart
        let obligations: [Obligation]
    }

    /// A `forecast_balance` result for the forecast block.
    static func forecast(source: String, results: [String: JSONValue]) -> Forecast? {
        guard let result = results[source],
              let currency = result["currency"]?.stringValue,
              let until = result["until"]?.stringValue,
              let allowance = result["daily_allowance"]?.numberValue,
              let free = result["free_amount"]?.numberValue,
              let rows = result["series"]?.arrayValue else { return nil }
        let points: [ChartGroup] = rows.compactMap { row in
            guard let date = row["date"]?.stringValue, let balance = row["balance"]?.numberValue else { return nil }
            return ChartGroup(id: date, label: date, value: balance, previous: nil)
        }
        guard !points.isEmpty else { return nil }
        let obligations: [Forecast.Obligation] = result["obligations"]?.arrayValue?.compactMap { row in
            guard let date = row["date"]?.stringValue, let label = row["label"]?.stringValue,
                  let amount = row["amount"]?.numberValue else { return nil }
            return Forecast.Obligation(date: date, label: label, amount: amount)
        } ?? []
        return Forecast(
            currency: currency,
            until: until,
            dailyAllowance: allowance,
            freeAmount: free,
            balance: Chart(groups: points, currency: currency, isTimeline: true),
            obligations: obligations
        )
    }

    // MARK: - Lists

    /// The transaction ids of a `search_transactions` result, in its order.
    static func transactionIds(source: String, results: [String: JSONValue]) -> [String] {
        ids(in: results[source]?["items"], key: "id")
    }

    /// The category ids of a `get_budgets` result, narrowed to `only` when the block names some.
    static func budgetCategoryIds(source: String, only: [String]?, results: [String: JSONValue]) -> [String] {
        let all = ids(in: results[source]?["budgets"], key: "category_id")
        guard let only, !only.isEmpty else { return all }
        let wanted = Set(only)
        return all.filter(wanted.contains)
    }

    /// The series ids of a `list_recurring` result.
    static func recurringIds(source: String, results: [String: JSONValue]) -> [String] {
        ids(in: results[source]?["items"], key: "id")
    }

    private static func ids(in list: JSONValue?, key: String) -> [String] {
        list?.arrayValue?.compactMap { $0[key]?.stringValue } ?? []
    }
}
