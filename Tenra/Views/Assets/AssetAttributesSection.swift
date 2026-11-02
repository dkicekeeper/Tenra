//
//  AssetAttributesSection.swift
//  Tenra
//
//  The asset form's characteristics (docs/domains/assets.md, CoreData v19): where the asset is
//  and what it is like, by its kind, for an estimate by listings (docs/plan-assets-roadmap.md
//  §3.4). A flat: the area, rooms, year, building, floor and condition; a car: the make, model,
//  year and mileage; land: the ares and their use. In Kazakhstan a car also has its steering wheel
//  and whether it is customs cleared. Every field may stay empty.
//

import SwiftUI

/// The characteristics as the form edits them: each field as typed, the utilities as a set.
struct AssetAttributesDraft: Equatable {
    typealias Field = AssetAttributes.Field

    var texts: [Field: String] = [:]
    var utilities: Set<String> = []

    init() {}

    /// The asset's characteristics; a country it has none for is `defaultCountry` (the phone's).
    init(_ attributes: AssetAttributes, defaultCountry: String?) {
        for field in Field.allCases {
            switch (field.kind, attributes[field]) {
            case (.set, .list(let list)?):
                utilities = Set(list)
            case (.flag, .flag(let flag)?):
                texts[field] = flag ? "true" : "false"
            case (.integer, .number(let number)?):
                texts[field] = String(Int(number))
            case (.number, .number(let number)?):
                texts[field] = Self.numberText(number)
            case (_, .text(let text)?):
                texts[field] = text
            default:
                break
            }
        }
        if texts[.country] == nil, let defaultCountry {
            texts[.country] = defaultCountry
        }
    }

    /// Where the asset is, then what it is like, as the form shows them for `kind`.
    static func formFields(for kind: AssetKind) -> (place: [Field], details: [Field]) {
        let place: [Field] = kind.group == .realEstate ? [.country, .city, .district] : [.country, .city]
        switch kind {
        case .apartment: return (place, [.areaM2, .rooms, .yearBuilt, .building, .floor, .floors, .condition])
        case .house: return (place, [.areaM2, .landAres, .yearBuilt, .building, .floors, .utilities, .condition])
        case .commercial: return (place, [.commercialType, .areaM2, .floor, .condition])
        case .land: return (place, [.landAres, .landUse, .utilities])
        case .vehicle:
            return (place, [.make, .model, .generation, .year, .mileageKm, .engineL, .fuel, .transmission, .drive,
                            .steering, .customsCleared, .condition])
        case .other: return (place, [.details, .year, .condition])
        }
    }

    /// The characteristics to save for `kind` over the asset's: the form's fields as typed (a
    /// number that does not read is left out), the kind's fields the form does not show as they
    /// were, another kind's dropped, keys of a later version kept. The country only goes with
    /// something else.
    func attributes(for kind: AssetKind, over original: AssetAttributes) -> AssetAttributes {
        var result = original
        let kindFields = Set(Field.fields(for: kind))
        let shown = Self.formFields(for: kind)
        for field in Field.allCases where field != .country && !kindFields.contains(field) {
            result[field] = nil
        }
        for field in shown.place + shown.details where field != .country {
            result[field] = value(of: field)
        }
        let hasOthers = result.values.keys.contains { $0 != Field.country.rawValue }
        result[.country] = hasOthers ? value(of: .country) : nil
        return result
    }

    /// One field as stored, nil when empty or unreadable.
    func value(of field: Field) -> AssetAttributes.Value? {
        if case .set(let options) = field.kind {
            let picked = options.filter(utilities.contains)
            return picked.isEmpty ? nil : .list(picked)
        }
        let text = (texts[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch field.kind {
        case .text(let limit):
            return .text(String(text.prefix(limit)))
        case .integer(let range):
            guard let number = AssetAttributes.parseNumber(text), number.rounded() == number,
                  number >= Double(range.lowerBound), number <= Double(range.upperBound) else { return nil }
            return .number(number)
        case .number(let range):
            guard let number = AssetAttributes.parseNumber(text), range.contains(number) else { return nil }
            return .number(number)
        case .flag:
            return text == "true" ? .flag(true) : text == "false" ? .flag(false) : nil
        case .choice(let options):
            return options.contains(text) ? .text(text) : nil
        case .set:
            return nil
        }
    }

    /// "65,5" in Russian, "65.5" in English; whole numbers without a fraction.
    private static func numberText(_ number: Double) -> String {
        numberFormatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

struct AssetAttributesSection: View {
    typealias Field = AssetAttributes.Field

    let kind: AssetKind
    @Binding var draft: AssetAttributesDraft

    var body: some View {
        let fields = AssetAttributesDraft.formFields(for: kind)
        VStack(spacing: AppSpacing.lg) {
            FormSection(header: String(localized: "asset.attributes.place")) {
                ForEach(fields.place, id: \.self) { field in
                    row(field)
                }
            }
            FormSection(header: String(localized: "asset.attributes"), footer: String(localized: "asset.attributes.hint")) {
                ForEach(fields.details.filter(isShown), id: \.self) { field in
                    row(field)
                }
            }
        }
    }

    /// The steering wheel and customs clearance count in Kazakhstan's listings only.
    private func isShown(_ field: Field) -> Bool {
        switch field {
        case .steering, .customsCleared: return draft.texts[.country] == "KZ"
        default: return true
        }
    }

    @ViewBuilder
    private func row(_ field: Field) -> some View {
        let title = Self.title(of: field)
        let notSet = String(localized: "asset.attr.notSet")
        if field == .country {
            UniversalRow(title, icon: Self.icon(of: field), accessory: .picker(text(field), options: Self.countries))
        } else {
            switch field.kind {
            case .set(let options):
                ChipPicker(title, options: options, selection: $draft.utilities, inset: AppSpacing.lg) { option in
                    Self.title(of: field, option: option)
                }
            case .choice(let options):
                UniversalRow(
                    title,
                    icon: Self.icon(of: field),
                    accessory: .menu(text(field), options: choices(options, of: field))
                )
            case .flag:
                UniversalRow(
                    title,
                    icon: Self.icon(of: field),
                    accessory: .menu(text(field), options: [
                        (label: notSet, value: ""),
                        (label: String(localized: "asset.attr.yes"), value: "true"),
                        (label: String(localized: "asset.attr.no"), value: "false"),
                    ])
                )
            case .integer:
                UniversalRow(title, icon: Self.icon(of: field), accessory: .textField(text(field), placeholder: notSet, keyboard: .numberPad))
            case .number:
                UniversalRow(title, icon: Self.icon(of: field), accessory: .textField(text(field), placeholder: notSet, keyboard: .decimalPad))
            case .text:
                UniversalRow(title, icon: Self.icon(of: field), accessory: .textField(text(field), placeholder: notSet))
            }
        }
    }

    private func text(_ field: Field) -> Binding<String> {
        Binding(
            get: { draft.texts[field] ?? "" },
            set: { draft.texts[field] = $0 }
        )
    }

    /// "Not set", then the field's options; a car is never "rough" (a flat's shell finish).
    private func choices(_ options: [String], of field: Field) -> [(label: String, value: String)] {
        let shown = field == .condition && kind.group != .realEstate ? options.filter { $0 != "rough" } : options
        var result: [(label: String, value: String)] = [(label: String(localized: "asset.attr.notSet"), value: "")]
        for option in shown {
            result.append((label: Self.title(of: field, option: option), value: option))
        }
        return result
    }

    static func title(of field: Field) -> String {
        String(localized: String.LocalizationValue("asset.attr.\(field.rawValue)"))
    }

    static func title(of field: Field, option: String) -> String {
        String(localized: String.LocalizationValue("asset.attr.\(field.rawValue).\(option)"))
    }

    private static func icon(of field: Field) -> String {
        switch field {
        case .country: return "globe"
        case .city, .region: return "building.2"
        case .district, .complex: return "map"
        case .areaM2: return "square.dashed"
        case .rooms: return "door.left.hand.closed"
        case .yearBuilt, .year: return "calendar"
        case .newBuilding, .building: return "building"
        case .floor: return "stairs"
        case .floors: return "square.stack.3d.up"
        case .condition: return "paintbrush"
        case .landAres: return "ruler"
        case .landUse: return "tree"
        case .utilities: return "bolt"
        case .commercialType: return "storefront"
        case .make: return "car"
        case .model: return "car.side"
        case .generation: return "tag"
        case .engineL: return "engine.combustion"
        case .fuel: return "fuelpump"
        case .transmission: return "gearshape"
        case .drive: return "gearshape.2"
        case .mileageKm: return "speedometer"
        case .customsCleared: return "doc.text"
        case .steering: return "steeringwheel"
        case .details: return "shippingbox"
        }
    }

    /// Every country by its name in the phone's language, with "Not set" first.
    private static let countries: [(label: String, value: String)] = {
        let locale = Locale.current
        let skipped: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ"]
        let list = Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isUppercase } && !skipped.contains($0) }
            .compactMap { code in locale.localizedString(forRegionCode: code).map { (label: $0, value: code) } }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return [(label: String(localized: "asset.attr.notSet"), value: "")] + list
    }()
}
