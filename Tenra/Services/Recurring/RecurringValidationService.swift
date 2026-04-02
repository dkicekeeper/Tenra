//
//  RecurringValidationService.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild
//

import Foundation

/// Service responsible for validating recurring series
/// Encapsulates all business rules for creating and updating recurring transactions
nonisolated class RecurringValidationService {

    // MARK: - Validation Methods

    /// Validate a recurring series before creation or update
    /// - Parameter series: The series to validate
    /// - Throws: RecurringTransactionError if validation fails
    func validate(_ series: RecurringSeries) throws {
        // Validate amount
        guard series.amount > 0 else {
            throw RecurringTransactionError.invalidAmount
        }

        // Validate start date format
        let dateFormatter = DateFormatters.dateFormatter
        guard dateFormatter.date(from: series.startDate) != nil else {
            throw RecurringTransactionError.invalidStartDate
        }

        // Validate frequency
        switch series.frequency {
        case .daily, .weekly, .monthly, .yearly:
            break
        }

        // Validate description is not empty
        guard !series.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecurringTransactionError.invalidAmount // Using generic error for now
        }

        // Validate currency
        guard !series.currency.isEmpty else {
            throw RecurringTransactionError.invalidAmount
        }

        // For subscription-specific validation
        if series.isSubscription {
            try validateSubscription(series)
        }
    }

    /// Validate subscription-specific fields
    /// - Parameter series: The subscription series to validate
    /// - Throws: RecurringTransactionError if validation fails
    private func validateSubscription(_ series: RecurringSeries) throws {
        // Subscription must have a status
        guard series.status != nil else {
            throw RecurringTransactionError.invalidAmount // Using generic error for now
        }

        // If reminderOffsets exist, validate they are positive
        if let offsets = series.reminderOffsets {
            guard offsets.allSatisfy({ $0 > 0 }) else {
                throw RecurringTransactionError.invalidAmount
            }
        }
    }

    /// Validate that a series with given ID exists in the array
    /// - Parameters:
    ///   - seriesId: The series ID to find
    ///   - series: Array of all recurring series
    /// - Returns: The found series
    /// - Throws: RecurringTransactionError.seriesNotFound if not found
    func findSeries(id seriesId: String, in series: [RecurringSeries]) throws -> RecurringSeries {
        guard let found = series.first(where: { $0.id == seriesId }) else {
            throw RecurringTransactionError.seriesNotFound(seriesId)
        }
        return found
    }

    /// Validate that a subscription with given ID exists in the array
    /// - Parameters:
    ///   - subscriptionId: The subscription ID to find
    ///   - series: Array of all recurring series
    /// - Returns: The found subscription
    /// - Throws: RecurringTransactionError.seriesNotFound if not found or not a subscription
    func findSubscription(id subscriptionId: String, in series: [RecurringSeries]) throws -> RecurringSeries {
        let found = try findSeries(id: subscriptionId, in: series)
        guard found.isSubscription else {
            throw RecurringTransactionError.seriesNotFound(subscriptionId)
        }
        return found
    }

    /// Check if series update requires regenerating future transactions
    /// - Parameters:
    ///   - oldSeries: The original series
    ///   - newSeries: The updated series
    /// - Returns: True if regeneration is needed
    func needsRegeneration(oldSeries: RecurringSeries, newSeries: RecurringSeries) -> Bool {
        return oldSeries.frequency != newSeries.frequency ||
               oldSeries.startDate != newSeries.startDate ||
               oldSeries.amount != newSeries.amount ||
               oldSeries.category != newSeries.category ||
               oldSeries.subcategory != newSeries.subcategory
    }
}
