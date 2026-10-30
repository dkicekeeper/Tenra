//
//  Asset.swift
//  Tenra
//
//  Something the person owns and what it is worth (docs/domains/assets.md): a home, a car,
//  land, anything else. An asset never changes an account balance or a transaction: buying a
//  flat in 2018 stays an expense, and the asset lives next to it with its own purchase price
//  and valuations. AssetValuationMath turns these into the value, the gain and the growth.
//  Adding an asset is Tenra Pro; assets already kept stay open after Pro ends.
//

import Foundation

nonisolated enum AssetKind: String, Codable, CaseIterable, Sendable {
    case apartment, house, land, commercial   // real estate
    case vehicle                              // transport
    case other                                // jewellery, equipment, a business, anything

    /// The list's sections.
    enum Group: Int, CaseIterable, Comparable, Sendable {
        case realEstate, transport, other

        static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var group: Group {
        switch self {
        case .apartment, .house, .land, .commercial: return .realEstate
        case .vehicle: return .transport
        case .other: return .other
        }
    }

    /// The icon of an asset whose person picked none.
    var defaultIcon: IconSource {
        switch self {
        case .apartment: return .sfSymbol("building.2.fill")
        case .house: return .sfSymbol("house.fill")
        case .land: return .sfSymbol("mountain.2.fill")
        case .commercial: return .sfSymbol("storefront.fill")
        case .vehicle: return .sfSymbol("car.fill")
        case .other: return .sfSymbol("shippingbox.fill")
        }
    }
}

/// What the asset was worth on a day, in the asset's currency. The purchase is not stored as
/// one: it comes from the asset's purchase price and date (AssetValuationMath.history).
nonisolated struct AssetValuation: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case purchase, manual, assistant, sale
    }

    var id: String
    var date: Date
    var value: Double
    var source: Source
    /// Where the figure came from: "listings on krisha.kz", "the bank's valuer".
    var note: String?

    init(id: String = UUID().uuidString, date: Date, value: Double, source: Source = .manual, note: String? = nil) {
        self.id = id
        self.date = date
        self.value = value
        self.source = source
        self.note = note
    }
}

/// A category (and optionally some of its subcategories) whose transactions belong to an asset:
/// its rent, its upkeep. By id: categories are renamed. Read from phase 2 of the plan.
nonisolated struct AssetCategoryLink: Codable, Equatable, Hashable, Sendable {
    var categoryId: String
    /// The subcategories whose transactions count, any of them; empty: the whole category. So
    /// two flats under one "Rent" category are not counted twice, and one flat's upkeep can be
    /// its tax and its repairs (several since 2026-10-30, the owner's request).
    var subcategoryIds: [String]

    init(categoryId: String, subcategoryIds: [String] = []) {
        self.categoryId = categoryId
        self.subcategoryIds = subcategoryIds
    }

    /// One subcategory or the whole category.
    init(categoryId: String, subcategoryId: String?) {
        self.init(categoryId: categoryId, subcategoryIds: subcategoryId.map { [$0] } ?? [])
    }

    /// The whole category: no subcategory picked.
    var isWholeCategory: Bool { subcategoryIds.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case categoryId, subcategoryIds
        /// One subcategory, as links were saved before several could be picked.
        case subcategoryId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        if let ids = try container.decodeIfPresent([String].self, forKey: .subcategoryIds) {
            subcategoryIds = ids
        } else {
            subcategoryIds = try container.decodeIfPresent(String.self, forKey: .subcategoryId).map { [$0] } ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(subcategoryIds, forKey: .subcategoryIds)
        // An older version of the app reads the first one rather than the whole category.
        try container.encodeIfPresent(subcategoryIds.first, forKey: .subcategoryId)
    }
}

nonisolated struct Asset: Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: AssetKind
    var iconSource: IconSource?
    var currency: String
    var purchaseDate: Date?
    /// nil: an inheritance, a gift, not remembered.
    var purchasePrice: Double?
    /// Oldest first; the last one is the current value.
    var valuations: [AssetValuation]
    /// A share of the value lost each year after the latest valuation (a car: 0.15); nil keeps
    /// the last valuation. A new valuation is the new base (AssetValuationMath.estimate).
    var depreciationPerYear: Double?
    /// 1 for a whole asset; 0.5 for a house owned with a spouse. Net worth counts the share.
    var ownershipShare: Double
    /// The mortgage or car loan (a loan account's id).
    var linkedLoanAccountId: String?
    /// Rent (phase 2 of the plan).
    var incomeLink: AssetCategoryLink?
    /// Upkeep: tax, the building's fees, repairs, insurance (phase 2 of the plan).
    var expenseLink: AssetCategoryLink?
    var includeInNetWorth: Bool
    /// When it was sold; the sale price is the `.sale` valuation.
    var soldAt: Date?
    var note: String?
    /// Position in its list.
    var order: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: AssetKind,
        iconSource: IconSource? = nil,
        currency: String,
        purchaseDate: Date? = nil,
        purchasePrice: Double? = nil,
        valuations: [AssetValuation] = [],
        depreciationPerYear: Double? = nil,
        ownershipShare: Double = 1,
        linkedLoanAccountId: String? = nil,
        incomeLink: AssetCategoryLink? = nil,
        expenseLink: AssetCategoryLink? = nil,
        includeInNetWorth: Bool = true,
        soldAt: Date? = nil,
        note: String? = nil,
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.iconSource = iconSource
        self.currency = currency
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.valuations = valuations
        self.depreciationPerYear = depreciationPerYear
        self.ownershipShare = ownershipShare
        self.linkedLoanAccountId = linkedLoanAccountId
        self.incomeLink = incomeLink
        self.expenseLink = expenseLink
        self.includeInNetWorth = includeInNetWorth
        self.soldAt = soldAt
        self.note = note
        self.order = order
        self.createdAt = createdAt
    }

    var isSold: Bool { soldAt != nil }

    /// The sale: its price and day.
    var sale: AssetValuation? {
        valuations.last { $0.source == .sale }
    }

    /// The icon in lists and cards.
    var displayIcon: IconSource {
        iconSource ?? kind.defaultIcon
    }
}
