//
//  TimeFilterManager.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import SwiftUI
import Observation
import os

@Observable
@MainActor
class TimeFilterManager {
    private static let logger = Logger(subsystem: "AIFinanceManager", category: "TimeFilterManager")

    var currentFilter: TimeFilter {
        didSet {
            saveToStorage()
        }
    }
    
    private let storageKey = "timeFilter"
    
    init() {
        // MIGRATION: Reset to .allTime for users who had .thisMonth as default
        // This ensures historical CSV imports are visible
        let migrationKey = "timeFilterMigrationV1"
        let needsMigration = !UserDefaults.standard.bool(forKey: migrationKey)

        if needsMigration {
            // First launch or needs migration - use .allTime
            self.currentFilter = TimeFilter(preset: .allTime)
            UserDefaults.standard.set(true, forKey: migrationKey)
            saveToStorage()
        } else if let data = UserDefaults.standard.data(forKey: storageKey) {
            // Use saved filter
            do {
                self.currentFilter = try JSONDecoder().decode(TimeFilter.self, from: data)
            } catch {
                Self.logger.warning("Failed to decode TimeFilter: \(error.localizedDescription, privacy: .public) — using .allTime")
                self.currentFilter = TimeFilter(preset: .allTime)
            }
        } else {
            // Fallback - use .allTime
            self.currentFilter = TimeFilter(preset: .allTime)
        }
    }
    
    func setFilter(_ filter: TimeFilter) {
        currentFilter = filter
    }
    
    func setPreset(_ preset: TimeFilterPreset) {
        currentFilter = TimeFilter(preset: preset)
    }
    
    func setCustomRange(start: Date, end: Date) {
        currentFilter = TimeFilter(preset: .custom, startDate: start, endDate: end)
    }
    
    private func saveToStorage() {
        do {
            let encoded = try JSONEncoder().encode(currentFilter)
            UserDefaults.standard.set(encoded, forKey: storageKey)
        } catch {
            Self.logger.warning("Failed to encode TimeFilter: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // Проверяет, попадает ли дата в текущий фильтр
    func contains(date: Date) -> Bool {
        let range = currentFilter.dateRange()
        return date >= range.start && date < range.end
    }
    
    // Проверяет, попадает ли строка даты (формат yyyy-MM-dd) в текущий фильтр
    func contains(dateString: String) -> Bool {
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else {
            return false
        }
        return contains(date: date)
    }
}
