//
//  AssetEstimate.swift
//  Tenra
//
//  What an asset is worth by listings of comparable ones for sale (POST /v1/valuation on Ten's
//  server, docs/domains/assistant.md §8; docs/domains/assets.md): the request made from its kind,
//  country and characteristics, and the answer read back. Shared by Ten's estimate_asset_value
//  (FinanceToolkit+Assets) and the asset screen's "Estimate from listings" (AssetEstimateSheet).
//  The server finds the listings and does the arithmetic; the phone never sends the asset's name.
//

import Foundation

nonisolated enum AssetEstimateRequest {
    /// The asset's characteristics with `overrides` (what the user said in the chat) over them:
    /// only the kind's fields, only values the server takes.
    static func attributes(_ attributes: AssetAttributes, kind: AssetKind, overrides: [String: JSONValue] = [:]) -> AssetAttributes {
        var merged = attributes
        for field in AssetAttributes.Field.fields(for: kind) {
            if let given = overrides[field.rawValue].flatMap(attributeValue), field.accepts(given) {
                merged[field] = given
            }
        }
        return merged
    }

    /// The country given, else the one saved, else the phone's region.
    static func country(_ given: String?, attributes: AssetAttributes) -> String {
        let trimmed = given?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let trimmed, trimmed.count == 2 { return trimmed }
        return attributes.country ?? Locale.current.region?.identifier.uppercased() ?? "KZ"
    }

    /// The request's `asset`: the kind, the country and the fields the server takes for the kind.
    static func body(kind: AssetKind, attributes: AssetAttributes, country: String) -> [String: JSONValue] {
        var body: [String: JSONValue] = ["kind": .string(kind.rawValue), "country": .string(country)]
        for (key, value) in attributes.request(for: kind) {
            body[key] = jsonValue(value)
        }
        return body
    }

    static func jsonValue(_ value: AssetAttributes.Value) -> JSONValue {
        switch value {
        case .text(let text): return .string(text)
        case .number(let number): return .number(number)
        case .flag(let flag): return .bool(flag)
        case .list(let list): return .array(list.map(JSONValue.string))
        }
    }

    /// A value from the model's input as a characteristic; nil for null, an object or a list
    /// with anything but strings in it.
    static func attributeValue(_ value: JSONValue) -> AssetAttributes.Value? {
        switch value {
        case .string(let text): return .text(text)
        case .number(let number): return .number(number)
        case .bool(let flag): return .flag(flag)
        case .array(let items):
            let texts = items.compactMap(\.stringValue)
            return texts.count == items.count ? .list(texts) : nil
        case .null, .object: return nil
        }
    }
}

/// The server's answer to one estimate, in the market's currency (the one most comparables are
/// priced in).
nonisolated struct AssetEstimate: Equatable, Sendable {
    enum Accuracy: String, Sendable {
        case high, medium, low
    }

    /// A comparable listing the value was taken from: its site, link and asking price.
    struct Listing: Equatable, Sendable, Identifiable {
        let id: Int
        let title: String
        let site: String
        let url: URL?
        let price: Double
        let currency: String
        let sizeM2: Double?
        let landAres: Double?
        let rooms: Int?
        let year: Int?
        let mileageKm: Double?
    }

    /// Three comparables or more: a value. Else too few were found.
    let isSufficient: Bool
    let marketCurrency: String?
    /// The median; low and high are the quartiles.
    let value: Double?
    let low: Double?
    let high: Double?
    /// Comparables in the value.
    let count: Int
    let accuracy: Accuracy?
    let listings: [Listing]
    let searchedAt: Date?
    /// Estimates left this month, when the server said.
    let estimatesLeft: Int?

    init(answer: JSONValue) {
        isSufficient = answer["status"]?.stringValue == "ok" && answer["value"]?.numberValue != nil
        marketCurrency = answer["currency"]?.stringValue
        value = answer["value"]?.numberValue
        low = answer["low"]?.numberValue
        high = answer["high"]?.numberValue
        count = Int(answer["count"]?.numberValue ?? 0)
        accuracy = answer["accuracy"]?.stringValue.flatMap(Accuracy.init(rawValue:))
        let items = answer["listings"]?.arrayValue ?? []
        listings = items.enumerated().compactMap { index, item in
            guard let price = item["price"]?.numberValue, let currency = item["currency"]?.stringValue else { return nil }
            let link = item["url"]?.stringValue.flatMap(URL.init(string:))
            return Listing(
                id: index,
                title: item["title"]?.stringValue ?? "",
                site: item["site"]?.stringValue ?? link?.host() ?? "",
                // Only a web link opens: never another scheme from a search result.
                url: link?.scheme == "https" || link?.scheme == "http" ? link : nil,
                price: price,
                currency: currency,
                sizeM2: item["size_m2"]?.numberValue,
                landAres: item["land_ares"]?.numberValue,
                rooms: item["rooms"]?.numberValue.map { Int($0) },
                year: item["year"]?.numberValue.map { Int($0) },
                mileageKm: item["mileage_km"]?.numberValue
            )
        }
        searchedAt = answer["searched_at"]?.stringValue.flatMap(Self.date)
        if let limit = answer.value(atPath: "quota.limit")?.numberValue, let used = answer.value(atPath: "quota.used")?.numberValue {
            estimatesLeft = max(0, Int(limit - used))
        } else {
            estimatesLeft = nil
        }
    }

    /// The server's `toISOString()`, with or without the milliseconds.
    private static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    /// The sites the comparables came from.
    var sites: [String] {
        Array(Set(listings.map(\.site).filter { !$0.isEmpty })).sorted()
    }
}
