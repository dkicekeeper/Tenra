//
//  HistoryFilterCoordinator.swift
//  AIFinanceManager
//
//  Created on 2026-01-27
//  Part of Phase 2: HistoryView Decomposition
//
//  Manages all filter state and debouncing logic for HistoryView.
//  Extracted to follow Single Responsibility Principle.
//

import Foundation
import SwiftUI
import Observation

/// Coordinates filter state and debouncing for HistoryView
/// Handles search text, account filter, and debouncing logic
/// ✅ MIGRATED 2026-02-12: Now using @Observable instead of ObservableObject
@Observable
@MainActor
class HistoryFilterCoordinator {

    // MARK: - Observable Properties

    /// Currently selected account filter (nil = all accounts)
    var selectedAccountFilter: String?

    /// Current search text (user input)
    var searchText: String = ""

    /// Debounced search text (used for actual filtering)
    var debouncedSearchText: String = ""

    /// Whether search is currently active
    var isSearchActive: Bool = false

    /// Whether account filter sheet is shown
    var showingAccountFilter: Bool = false

    /// Whether category filter sheet is shown
    var showingCategoryFilter: Bool = false

    // MARK: - Private Properties

    /// Task for debouncing search input
    private var searchTask: Task<Void, Never>?

    /// Search debounce delay in nanoseconds (300ms)
    private let searchDebounceDelay: Duration = .milliseconds(300)

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Debounces search input: waits 300 ms of inactivity before writing `debouncedSearchText`.
    /// `searchText` is already set by the binding before this method is called — no reassignment needed.
    /// - Parameter text: New search text (matches the current `searchText` value)
    func applySearch(_ text: String) {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(for: self.searchDebounceDelay)
            guard !Task.isCancelled else { return }

            if self.searchText == text {
                self.debouncedSearchText = text
            }
        }
    }

    /// Fires haptic for account filter change.
    /// The actual `selectedAccountFilter` mutation is done by the binding in
    /// `HistoryFilterSection` before this method is called — no reassignment needed.
    func applyAccountFilter() {
        HapticManager.selection()
    }

    /// Apply category filter change.
    /// Filter forwarding is handled synchronously by HistoryView's onChange handler
    /// via `applyFiltersToController()` — no debounce task needed here.
    func applyCategoryFilterChange() {
        HapticManager.selection()
    }

    /// Reset all filters to default state
    func reset() {
        selectedAccountFilter = nil
        searchText = ""
        debouncedSearchText = ""
        isSearchActive = false
        showingAccountFilter = false
        showingCategoryFilter = false

        // Cancel pending tasks
        searchTask?.cancel()
    }

    /// Set initial account filter (from navigation)
    /// - Parameter accountId: Account ID to set
    func setInitialAccountFilter(_ accountId: String?) {
        if let accountId = accountId, selectedAccountFilter != accountId {
            selectedAccountFilter = accountId
        }
    }

    // MARK: - Debug Helpers

    #if DEBUG
    /// Get current filter state for debugging
    func getFilterState() -> [String: Any] {
        return [
            "selectedAccount": selectedAccountFilter ?? "all",
            "searchText": searchText,
            "debouncedSearchText": debouncedSearchText,
            "isSearchActive": isSearchActive,
            "showingCategoryFilter": showingCategoryFilter
        ]
    }

    /// Check if any filters are active
    var hasActiveFilters: Bool {
        return selectedAccountFilter != nil ||
               !debouncedSearchText.isEmpty
    }
    #endif
}
