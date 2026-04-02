//
//  RecurringTransactionCoordinatorProtocol.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild
//

import Foundation

/// Protocol for coordinating all recurring transaction operations
/// Single entry point for managing recurring series and their generated transactions
@MainActor
protocol RecurringTransactionCoordinatorProtocol {

    // MARK: - Series CRUD Operations

    /// Create a new recurring series and generate initial transactions
    /// - Parameters:
    ///   - series: The recurring series to create
    /// - Throws: ValidationError if series is invalid
    func createSeries(_ series: RecurringSeries) async throws

    /// Update an existing recurring series and regenerate future transactions
    /// - Parameters:
    ///   - series: The updated recurring series
    /// - Throws: ValidationError if series is invalid or not found
    func updateSeries(_ series: RecurringSeries) async throws

    /// Stop a recurring series and delete future transactions
    /// - Parameters:
    ///   - seriesId: The ID of the series to stop
    ///   - fromDate: The date from which to stop (inclusive)
    /// - Throws: ValidationError if series not found
    func stopSeries(id seriesId: String, fromDate: String) async throws

    /// Delete a recurring series with option to keep or delete transactions
    /// - Parameters:
    ///   - seriesId: The ID of the series to delete
    ///   - deleteTransactions: If true, all transactions will be deleted. If false, transactions become regular.
    /// - Throws: ValidationError if series not found
    func deleteSeries(id seriesId: String, deleteTransactions: Bool) async throws

    // MARK: - Transaction Generation

    /// Generate transactions for all active recurring series
    /// - Parameters:
    ///   - horizonMonths: Number of months to generate ahead (default: 3)
    func generateAllTransactions(horizonMonths: Int) async

    /// Get planned transactions for display (e.g., in SubscriptionDetailView)
    /// - Parameters:
    ///   - seriesId: The ID of the series
    ///   - horizonMonths: Number of months to generate ahead
    /// - Returns: Array of planned transactions (past + future)
    func getPlannedTransactions(for seriesId: String, horizonMonths: Int) -> [Transaction]

    // MARK: - Subscription-Specific Operations

    /// Pause a subscription (sets status to paused, isActive = false)
    /// - Parameter subscriptionId: The ID of the subscription to pause
    func pauseSubscription(id subscriptionId: String) async throws

    /// Resume a paused subscription (sets status to active, isActive = true)
    /// - Parameter subscriptionId: The ID of the subscription to resume
    func resumeSubscription(id subscriptionId: String) async throws

    /// Archive a subscription (sets status to archived, isActive = false)
    /// - Parameter subscriptionId: The ID of the subscription to archive
    func archiveSubscription(id subscriptionId: String) async throws

    /// Calculate next charge date for a subscription
    /// - Parameter subscriptionId: The ID of the subscription
    /// - Returns: Next charge date or nil if not found or inactive
    func nextChargeDate(for subscriptionId: String) -> Date?
}

/// Errors that can occur during recurring transaction operations
enum RecurringTransactionError: LocalizedError {
    case seriesNotFound(String)
    case invalidFrequency
    case invalidAmount
    case invalidStartDate
    case missingAccount
    case coordinatorNotInitialized

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
        }
    }
}
