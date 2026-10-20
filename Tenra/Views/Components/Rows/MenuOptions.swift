//
//  MenuOptions.swift
//  Tenra
//
//  The options of Tenra's menu rows (frequency, recurring, loan type, reminder), for DesignKit's
//  `UniversalRow(accessory: .menu(_:options:))` (7.0.0; convenience inits on its MenuPickerRow
//  before). The row itself lives in DesignKit.
//

import SwiftUI

extension RecurringFrequency {
    /// Every frequency, for a subscription's menu row.
    static var menuOptions: [(label: String, value: RecurringFrequency)] {
        allCases.map { (label: $0.displayName, value: $0) }
    }
}

extension RecurringOption {
    /// "Never" and every frequency, for a transaction's recurring row.
    static var menuOptions: [(label: String, value: RecurringOption)] {
        [(label: String(localized: "recurring.never"), value: .never)]
            + RecurringFrequency.allCases.map { (label: $0.displayName, value: .frequency($0)) }
    }
}

extension LoanType {
    /// Annuity ("Credit") or installment, with `LoanTypeBadge`'s short labels so the same wording
    /// surfaces in the edit form and the loan list.
    static var menuOptions: [(label: String, value: LoanType)] {
        [
            (label: String(localized: "loan.typeAnnuityShort", defaultValue: "Credit"), value: .annuity),
            (label: String(localized: "loan.typeInstallmentShort", defaultValue: "Installment"), value: .installment),
        ]
    }
}

extension ReminderOption {
    /// "None" and the standard reminders, for a subscription's reminder row.
    static var menuOptions: [(label: String, value: ReminderOption)] {
        [
            (label: String(localized: "reminder.none"), value: .none),
            (label: String(localized: "reminder.dayBefore.one"), value: .daysBefore(1)),
            (label: String(localized: "reminder.daysBefore.3"), value: .daysBefore(3)),
            (label: String(localized: "reminder.daysBefore.7"), value: .daysBefore(7)),
            (label: String(localized: "reminder.daysBefore.30"), value: .daysBefore(30)),
        ]
    }
}

// MARK: - RecurringOption Enum

/// Option for recurring transactions: never or specific frequency
enum RecurringOption: Hashable {
    case never
    case frequency(RecurringFrequency)

    var displayName: String {
        switch self {
        case .never:
            return String(localized: "recurring.never")
        case .frequency(let freq):
            return freq.displayName
        }
    }
}
