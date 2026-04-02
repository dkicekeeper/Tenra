//
//  ReminderOption.swift
//  AIFinanceManager
//
//  Reminder selection enum for subscriptions
//  Represents "Never" or specific days before
//

import Foundation

/// Option for reminder selection: none or specific days before
enum ReminderOption: Hashable, Codable {
    case none
    case daysBefore(Int)

    var displayName: String {
        switch self {
        case .none:
            return String(localized: "reminder.none")
        case .daysBefore(let offset):
            switch offset {
            case 1:
                return String(localized: "reminder.dayBefore.one")
            case 3:
                return String(localized: "reminder.daysBefore.3")
            case 7:
                return String(localized: "reminder.daysBefore.7")
            case 30:
                return String(localized: "reminder.daysBefore.30")
            default:
                return "За \(offset) дней"
            }
        }
    }

    /// Convert to Set<Int> for backward compatibility with existing models
    var asOffsets: Set<Int> {
        switch self {
        case .none:
            return []
        case .daysBefore(let offset):
            return [offset]
        }
    }

    /// Create from Set<Int> for backward compatibility
    static func from(offsets: Set<Int>) -> ReminderOption {
        if offsets.isEmpty {
            return .none
        } else if let first = offsets.first {
            return .daysBefore(first)
        } else {
            return .none
        }
    }

    /// Create from Array<Int> for backward compatibility
    static func from(offsets: [Int]) -> ReminderOption {
        from(offsets: Set(offsets))
    }
}
