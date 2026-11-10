//
//  RecurringTransactionError.swift
//  Tenra
//
//  Why a recurring series could not be saved (RecurringValidationService). It lived beside
//  RecurringTransactionCoordinatorProtocol, which nothing conformed to.
//

import Foundation

/// Errors that can occur during recurring transaction operations
enum RecurringTransactionError: LocalizedError {
    case seriesNotFound(String)
    case invalidFrequency
    case invalidAmount
    case invalidStartDate
    case missingAccount
    case coordinatorNotInitialized
    case emptyDescription
    case emptyCurrency
    case missingSubscriptionStatus
    case invalidReminderOffsets

    var errorDescription: String? {
        switch self {
        case .seriesNotFound(let id):
            return String(localized: "recurring.error.seriesNotFound") + " (ID: \(id))"
        case .invalidFrequency:
            return String(localized: "recurring.error.invalidFrequency")
        case .invalidAmount:
            return String(localized: "recurring.error.invalidAmount")
        case .invalidStartDate:
            return String(localized: "recurring.error.invalidStartDate")
        case .missingAccount:
            return String(localized: "recurring.error.missingAccount")
        case .coordinatorNotInitialized:
            return "Recurring coordinator is not initialized"
        case .emptyDescription:
            return String(localized: "recurring.error.emptyDescription")
        case .emptyCurrency:
            return String(localized: "recurring.error.emptyCurrency")
        case .missingSubscriptionStatus:
            return String(localized: "recurring.error.missingSubscriptionStatus")
        case .invalidReminderOffsets:
            return String(localized: "recurring.error.invalidReminderOffsets")
        }
    }
}
