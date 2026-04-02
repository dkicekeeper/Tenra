//
//  RecurringTransaction.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

enum RecurringSeriesKind: String, Codable, Hashable {
    case generic = "generic"
    case subscription = "subscription"
}

enum SubscriptionStatus: String, Codable, Hashable {
    case active = "active"
    case paused = "paused"
    case archived = "archived"
}

struct RecurringSeries: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var isActive: Bool
    var amount: Decimal
    var currency: String
    var category: String
    var subcategory: String?
    var description: String
    var accountId: String?
    var targetAccountId: String?
    var frequency: RecurringFrequency
    var startDate: String // YYYY-MM-DD
    var lastGeneratedDate: String? // YYYY-MM-DD
    
    // Subscription-specific fields
    var kind: RecurringSeriesKind
    var iconSource: IconSource? // Unified icon/logo source (SF Symbol, brand service)
    var reminderOffsets: [Int]? // Days before charge (e.g., [1, 3, 7, 30])
    var status: SubscriptionStatus? // For subscriptions: active/paused/archived
    
    init(
        id: String = UUID().uuidString,
        isActive: Bool = true,
        amount: Decimal,
        currency: String,
        category: String,
        subcategory: String? = nil,
        description: String,
        accountId: String? = nil,
        targetAccountId: String? = nil,
        frequency: RecurringFrequency,
        startDate: String,
        lastGeneratedDate: String? = nil,
        kind: RecurringSeriesKind = .generic,
        iconSource: IconSource? = nil,
        reminderOffsets: [Int]? = nil,
        status: SubscriptionStatus? = nil
    ) {
        self.id = id
        self.isActive = isActive
        self.amount = amount
        self.currency = currency
        self.category = category
        self.subcategory = subcategory
        self.description = description
        self.accountId = accountId
        self.targetAccountId = targetAccountId
        self.frequency = frequency
        self.startDate = startDate
        self.lastGeneratedDate = lastGeneratedDate
        self.kind = kind
        self.iconSource = iconSource
        self.reminderOffsets = reminderOffsets
        self.status = status
    }
    
    // Helper computed property
    nonisolated var isSubscription: Bool {
        kind == .subscription
    }
    
    // Subscription status (defaults to active for subscriptions, nil for generic)
    var subscriptionStatus: SubscriptionStatus? {
        if kind == .subscription {
            return status ?? .active
        }
        return nil
    }
    
    // Custom decoder for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, isActive, amount, currency, category, subcategory, description
        case accountId, targetAccountId, frequency, startDate, lastGeneratedDate
        case kind, brandLogo, brandId, iconSource, reminderOffsets, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        amount = try container.decode(Decimal.self, forKey: .amount)
        currency = try container.decode(String.self, forKey: .currency)
        category = try container.decode(String.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        description = try container.decode(String.self, forKey: .description)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        targetAccountId = try container.decodeIfPresent(String.self, forKey: .targetAccountId)
        frequency = try container.decode(RecurringFrequency.self, forKey: .frequency)
        startDate = try container.decode(String.self, forKey: .startDate)
        lastGeneratedDate = try container.decodeIfPresent(String.self, forKey: .lastGeneratedDate)

        // New fields with defaults for backward compatibility
        kind = try container.decodeIfPresent(RecurringSeriesKind.self, forKey: .kind) ?? .generic

        // Migration: try new iconSource field first, fallback to old brandLogo/brandId
        if let savedIconSource = try container.decodeIfPresent(IconSource.self, forKey: .iconSource) {
            iconSource = savedIconSource
        } else {
            if let oldBrandId = try container.decodeIfPresent(String.self, forKey: .brandId), !oldBrandId.isEmpty {
                iconSource = IconSource.from(displayIdentifier: oldBrandId) ?? .brandService(oldBrandId)
            } else {
                iconSource = nil
            }
        }

        reminderOffsets = try container.decodeIfPresent([Int].self, forKey: .reminderOffsets)
        status = try container.decodeIfPresent(SubscriptionStatus.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(subcategory, forKey: .subcategory)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encodeIfPresent(targetAccountId, forKey: .targetAccountId)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(startDate, forKey: .startDate)
        try container.encodeIfPresent(lastGeneratedDate, forKey: .lastGeneratedDate)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(iconSource, forKey: .iconSource)
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(status, forKey: .status)
    }
    
    /// Calculate all occurrences of this recurring transaction within a given date interval
    func occurrences(in interval: DateInterval) -> [Date] {
        guard isActive else { return [] }
        
        let calendar = Calendar.current
        let dateFormatter = DateFormatters.dateFormatter
        
        guard let start = dateFormatter.date(from: startDate) else {
            return []
        }
        
        var current = start
        var results: [Date] = []
        
        // Find the first occurrence within or after the interval's start
        while current < interval.start {
            guard let next = nextDate(after: current, calendar: calendar) else { break }
            current = next
        }
        
        // Collect all occurrences within the interval
        while current <= interval.end {
            if current >= interval.start {
                results.append(current)
            }
            guard let next = nextDate(after: current, calendar: calendar) else { break }
            current = next
        }
        
        return results
    }
    
    private func nextDate(after date: Date, calendar: Calendar) -> Date? {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum RecurringFrequency: String, Codable, CaseIterable, Hashable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"
    
    var displayName: String {
        switch self {
        case .daily:   return String(localized: "frequency.daily")
        case .weekly:  return String(localized: "frequency.weekly")
        case .monthly: return String(localized: "frequency.monthly")
        case .yearly:  return String(localized: "frequency.yearly")
        }
    }
}

struct RecurringOccurrence: Identifiable, Codable, Equatable {
    let id: String
    let seriesId: String
    let occurrenceDate: String // YYYY-MM-DD
    let transactionId: String

    nonisolated init(
        id: String = UUID().uuidString,
        seriesId: String,
        occurrenceDate: String,
        transactionId: String
    ) {
        self.id = id
        self.seriesId = seriesId
        self.occurrenceDate = occurrenceDate
        self.transactionId = transactionId
    }
}
