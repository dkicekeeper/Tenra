//
//  CustomCategory.swift
//  Tenra
//
//  Created on 2024
//

import Foundation
import SwiftUI

struct CustomCategory: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var iconSource: IconSource // Unified icon source (SF Symbol, brandService/logo.dev)
    var colorHex: String
    var type: TransactionType
    var order: Int? // Order for displaying categories

    // Budget fields
    var budgetAmount: Double?
    var budgetPeriod: BudgetPeriod
    var budgetStartDate: Date?
    var budgetResetDay: Int

    init(id: String = UUID().uuidString, name: String, iconSource: IconSource? = nil, colorHex: String, type: TransactionType, budgetAmount: Double? = nil, budgetPeriod: BudgetPeriod = .monthly, budgetResetDay: Int = 1, order: Int? = nil) {
        self.id = id
        self.name = name
        // Default to SF Symbol based on category name if no icon provided
        self.iconSource = iconSource ?? .sfSymbol(CategoryIcon.iconName(for: name, type: type))
        self.colorHex = colorHex
        self.type = type
        self.budgetAmount = budgetAmount
        self.budgetPeriod = budgetPeriod
        self.budgetStartDate = budgetAmount != nil ? Date() : nil
        self.budgetResetDay = budgetResetDay
        self.order = order
    }

    enum BudgetPeriod: String, Codable {
        case weekly = "weekly"
        case monthly = "monthly"
        case yearly = "yearly"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, iconName, iconSource, colorHex, type, order
        case budgetAmount, budgetPeriod, budgetStartDate, budgetResetDay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        type = try container.decode(TransactionType.self, forKey: .type)

        // Migration: try new iconSource field first, fallback to old iconName
        if let savedIconSource = try container.decodeIfPresent(IconSource.self, forKey: .iconSource) {
            iconSource = savedIconSource
        } else if let oldIconName = try container.decodeIfPresent(String.self, forKey: .iconName) {
            // Migrate old iconName (SF Symbol string) to iconSource
            iconSource = .sfSymbol(oldIconName)
        } else {
            // Fallback to default icon based on category name
            iconSource = .sfSymbol(CategoryIcon.iconName(for: name, type: type))
        }

        // Order field (with backward compatibility)
        order = try? container.decode(Int.self, forKey: .order)

        // Budget fields (with backward compatibility)
        budgetAmount = try? container.decode(Double.self, forKey: .budgetAmount)
        budgetPeriod = (try? container.decode(BudgetPeriod.self, forKey: .budgetPeriod)) ?? .monthly
        budgetStartDate = try? container.decode(Date.self, forKey: .budgetStartDate)
        budgetResetDay = (try? container.decode(Int.self, forKey: .budgetResetDay)) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconSource, forKey: .iconSource)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encodeIfPresent(budgetAmount, forKey: .budgetAmount)
        try container.encode(budgetPeriod, forKey: .budgetPeriod)
        try container.encodeIfPresent(budgetStartDate, forKey: .budgetStartDate)
        try container.encode(budgetResetDay, forKey: .budgetResetDay)
    }
    
    var color: Color {
        var hexSanitized = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
}
