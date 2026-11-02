//
//  AssetAttributes.swift
//  Tenra
//
//  What an asset is like, for its valuation by listings (CoreData v19, docs/domains/assets.md,
//  docs/plan-assets-roadmap.md §3.4): where it is, a flat's area and rooms, a car's make, model,
//  year and mileage. Kept by the valuation request's own field names
//  (server/assistant/src/valuation.ts), so Ten's estimate_asset_value sends them as they are.
//  Never an address with a house number, a VIN, a plate or a name. A key this version does not
//  know (written by a later one) is kept as it is.
//

import Foundation

nonisolated struct AssetAttributes: Codable, Equatable, Hashable, Sendable {
    /// One stored value: a text, a number, yes or no, a few words from a list.
    enum Value: Codable, Equatable, Hashable, Sendable {
        case text(String)
        case number(Double)
        case flag(Bool)
        case list([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .flag(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .text(value)
            } else {
                self = .list(try container.decode([String].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .flag(let value): try container.encode(value)
            case .list(let value): try container.encode(value)
            }
        }
    }

    /// The characteristics this version knows, by the request's names.
    enum Field: String, CaseIterable, Sendable {
        case country, city, region, district, complex
        case areaM2 = "area_m2", rooms, yearBuilt = "year_built", newBuilding = "new_building"
        case building, floor, floors, condition
        case landAres = "land_ares", landUse = "land_use", utilities, commercialType = "commercial_type"
        case make, model, generation, year, engineL = "engine_l", fuel, transmission, drive
        case mileageKm = "mileage_km", customsCleared = "customs_cleared", steering
        /// What the thing is, for `other`: "Rolex Submariner 116610LN".
        case details = "description"

        enum Kind: Equatable, Sendable {
            /// Up to `max` characters, never seven digits in a row (a phone, an IIN, a VIN).
            case text(max: Int)
            case integer(ClosedRange<Int>)
            case number(ClosedRange<Double>)
            case flag
            /// One of these.
            case choice([String])
            /// Any of these.
            case set([String])
        }

        /// The server's rules for the field (`FIELDS` in valuation.ts): a value outside them makes
        /// the whole request fail, so it is never sent.
        var kind: Kind {
            switch self {
            case .country: return .text(max: 2)
            case .city, .region, .district, .complex: return .text(max: 80)
            case .areaM2: return .number(5...100_000)
            case .rooms: return .integer(0...30)
            case .yearBuilt: return .integer(1700...2100)
            case .newBuilding, .customsCleared: return .flag
            case .building: return .choice(["panel", "brick", "monolith", "block", "wood", "other"])
            case .floor: return .integer(-5...200)
            case .floors: return .integer(1...200)
            case .condition: return .choice(["rough", "needs_repair", "standard", "good", "excellent"])
            case .landAres: return .number(0.1...1_000_000)
            case .landUse: return .choice(["residential", "garden", "farm", "commercial", "other"])
            case .utilities: return .set(["gas", "water", "sewer", "electricity"])
            case .commercialType: return .choice(["office", "retail", "warehouse", "other"])
            case .make, .model, .generation: return .text(max: 40)
            case .year: return .integer(1900...2100)
            case .engineL: return .number(0.1...20)
            case .fuel: return .choice(["petrol", "diesel", "hybrid", "electric", "gas", "other"])
            case .transmission: return .choice(["automatic", "manual"])
            case .drive: return .choice(["fwd", "rwd", "awd"])
            case .mileageKm: return .number(0...3_000_000)
            case .steering: return .choice(["left", "right"])
            case .details: return .text(max: 160)
            }
        }

        /// The fields the valuation request takes for a kind (`KIND_FIELDS` in valuation.ts),
        /// the country aside: a field of another kind makes the request fail.
        static func fields(for kind: AssetKind) -> [Field] {
            let place: [Field] = [.city, .region, .district, .complex]
            let building: [Field] = [.areaM2, .rooms, .yearBuilt, .newBuilding, .building, .floor, .floors, .condition]
            switch kind {
            case .apartment: return place + building
            case .house: return place + building + [.landAres, .utilities]
            case .commercial: return place + building + [.commercialType]
            case .land: return place + [.landAres, .landUse, .utilities]
            case .vehicle:
                return [.city, .region, .make, .model, .generation, .year, .engineL, .fuel, .transmission, .drive,
                        .mileageKm, .customsCleared, .steering, .condition]
            case .other: return [.city, .region, .details, .year, .condition]
            }
        }

        /// What the request cannot go without (`required` in valuation.ts): one field of each group.
        static func required(for kind: AssetKind) -> [[Field]] {
            switch kind {
            case .apartment, .commercial: return [[.city], [.areaM2]]
            case .house: return [[.city, .region], [.areaM2]]
            case .land: return [[.city, .region], [.landAres]]
            case .vehicle: return [[.make], [.model], [.year]]
            case .other: return [[.details]]
            }
        }

        /// Whether the server takes `value` for this field.
        func accepts(_ value: Value) -> Bool {
            switch (kind, value) {
            case let (.text(limit), .text(text)):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed.count <= limit && !AssetAttributes.hasLongNumber(trimmed)
                    && !trimmed.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
            case let (.integer(range), .number(number)):
                return number.rounded() == number && number >= Double(range.lowerBound) && number <= Double(range.upperBound)
            case let (.number(range), .number(number)):
                return number.isFinite && range.contains(number)
            case (.flag, .flag):
                return true
            case let (.choice(options), .text(text)):
                return options.contains(text)
            case let (.set(options), .list(list)):
                return !list.isEmpty && list.allSatisfy(options.contains)
            default:
                return false
            }
        }
    }

    /// By field name; keys of a later version included.
    private(set) var values: [String: Value]

    init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    var isEmpty: Bool { values.isEmpty }

    subscript(field: Field) -> Value? {
        get { values[field.rawValue] }
        set { values[field.rawValue] = newValue }
    }

    func text(_ field: Field) -> String? {
        if case .text(let value) = self[field] { return value }
        return nil
    }

    func number(_ field: Field) -> Double? {
        if case .number(let value) = self[field] { return value }
        return nil
    }

    func flag(_ field: Field) -> Bool? {
        if case .flag(let value) = self[field] { return value }
        return nil
    }

    func list(_ field: Field) -> [String] {
        if case .list(let value) = self[field] { return value }
        return []
    }

    /// The fields of `kind` the server would take, by name: what the valuation request sends.
    /// The country is not among them: the request carries it on its own.
    func request(for kind: AssetKind) -> [String: Value] {
        var result: [String: Value] = [:]
        for field in Field.fields(for: kind) {
            if let value = self[field], field.accepts(value) {
                result[field.rawValue] = Self.normalized(value)
            }
        }
        return result
    }

    /// The groups of required fields `kind` has nothing for: what to ask before an estimate.
    func missing(for kind: AssetKind) -> [[Field]] {
        let sent = request(for: kind)
        return Field.required(for: kind).filter { group in !group.contains { sent[$0.rawValue] != nil } }
    }

    /// A stored ISO country code, upper-cased.
    var country: String? {
        guard let code = text(.country)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code
    }

    /// Texts trimmed, the rest as is.
    private static func normalized(_ value: Value) -> Value {
        if case .text(let text) = value { return .text(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return value
    }

    /// Seven digits or more, each perhaps followed by one other character ("8 777 123 45 67").
    static func hasLongNumber(_ text: String) -> Bool {
        var run = 0
        var gap = false
        for character in text {
            if character.isASCII, character.isNumber {
                run += 1
                gap = false
                if run >= 7 { return true }
            } else if run > 0, !gap {
                gap = true
            } else {
                run = 0
                gap = false
            }
        }
        return false
    }

    /// A number typed in the form: "65,5", "120 000", "1.6".
    static func parseNumber(_ text: String) -> Double? {
        let cleaned = text.filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    // MARK: - Codable

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// A value this version cannot read is skipped, not the whole set.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var values: [String: Value] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(Value.self, forKey: key) {
                values[key.stringValue] = value
            }
        }
        self.values = values
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in values {
            try container.encode(value, forKey: Key(stringValue: key))
        }
    }
}
