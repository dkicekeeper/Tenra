//
//  TransactionPaginationManager.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Observation

/// Manages pagination for large transaction lists
/// Loads transactions incrementally to improve performance
/// ✅ MIGRATED 2026-02-12: Now using @Observable instead of ObservableObject
@Observable
@MainActor
class TransactionPaginationManager {
    // MARK: - Observable Properties

    /// Currently visible date sections with their transactions
    private(set) var visibleSections: [String] = []

    /// Grouped transactions by date key
    private(set) var groupedTransactions: [String: [Transaction]] = [:]

    /// Whether there are more sections to load
    private(set) var hasMore = true

    /// Whether currently loading more data
    private(set) var isLoadingMore = false

    // MARK: - Private Properties

    /// All available date keys in sorted order
    private var allSortedKeys: [String] = []

    /// All grouped transactions (source of truth)
    private var allGroupedTransactions: [String: [Transaction]] = [:]

    /// Number of date sections to load per page
    private let sectionsPerPage = 10

    /// Current page index
    private var currentPage = 0

    // MARK: - Initialization

    init() {
    }

    // MARK: - Public Methods

    /// Initialize pagination with grouped transactions
    /// - Parameters:
    ///   - grouped: Dictionary of date keys to transactions
    ///   - sortedKeys: Array of date keys in display order
    func initialize(grouped: [String: [Transaction]], sortedKeys: [String]) {

        self.allGroupedTransactions = grouped
        self.allSortedKeys = sortedKeys
        self.currentPage = 0
        self.visibleSections = []
        self.groupedTransactions = [:]
        self.hasMore = !sortedKeys.isEmpty

        // Load first page immediately
        loadNextPage()
    }

    /// Load the next page of transaction sections
    func loadNextPage() {
        guard hasMore && !isLoadingMore else {
            return
        }

        isLoadingMore = true

        // Calculate range for next page
        let startIndex = currentPage * sectionsPerPage
        let endIndex = min(startIndex + sectionsPerPage, allSortedKeys.count)

        guard startIndex < allSortedKeys.count else {
            hasMore = false
            isLoadingMore = false
            return
        }

        // Get next batch of sections
        let newSections = Array(allSortedKeys[startIndex..<endIndex])

        // Add new sections to visible list
        visibleSections.append(contentsOf: newSections)

        // Add corresponding transactions to grouped dictionary
        for section in newSections {
            if let transactions = allGroupedTransactions[section] {
                groupedTransactions[section] = transactions
            }
        }

        // Update state
        currentPage += 1
        hasMore = endIndex < allSortedKeys.count
        isLoadingMore = false

    }

    /// Reset pagination to initial state
    func reset() {
        currentPage = 0
        visibleSections = []
        groupedTransactions = [:]
        hasMore = !allSortedKeys.isEmpty
        isLoadingMore = false
    }

    /// Check if should load more when reaching a specific section
    /// - Parameter sectionKey: The date key of the section
    /// - Returns: True if this is near the end and should trigger loading
    func shouldLoadMore(for sectionKey: String) -> Bool {
        // Load more when reaching the last 3 visible sections
        guard let index = visibleSections.firstIndex(of: sectionKey) else {
            return false
        }

        let triggerIndex = max(0, visibleSections.count - 3)
        let shouldLoad = index >= triggerIndex && hasMore && !isLoadingMore

        return shouldLoad
    }
}
