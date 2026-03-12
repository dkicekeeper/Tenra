//
//  SettingsViewModel.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 1
//

import SwiftUI
import Observation

/// ViewModel for Settings screen
/// Coordinates all settings operations through specialized services
/// Follows Single Responsibility Principle with Protocol-Oriented Design
@Observable
@MainActor
final class SettingsViewModel {
    // MARK: - Observable State

    var settings: AppSettings
    var isLoading: Bool = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Wallpaper State

    var currentWallpaper: UIImage?
    var wallpaperHistory: [WallpaperHistoryItem] = []

    // MARK: - Export/Import Progress

    var exportProgress: Double = 0
    var isExporting: Bool = false

    // MARK: - Import Flow State

    var importFlowCoordinator: ImportFlowCoordinator?

    // MARK: - Dependencies (Protocol-oriented for testability)

    @ObservationIgnored private let storageService: SettingsStorageServiceProtocol
    @ObservationIgnored private let wallpaperService: WallpaperManagementServiceProtocol
    @ObservationIgnored private let resetCoordinator: DataResetCoordinatorProtocol
    @ObservationIgnored private let validationService: SettingsValidationServiceProtocol
    @ObservationIgnored private let exportCoordinator: ExportCoordinatorProtocol
    @ObservationIgnored private let importCoordinator: CSVImportCoordinatorProtocol?

    // MARK: - ViewModel References (weak to prevent retain cycles)

    @ObservationIgnored private weak var transactionsViewModel: TransactionsViewModel?
    @ObservationIgnored private weak var categoriesViewModel: CategoriesViewModel?
    @ObservationIgnored private weak var accountsViewModel: AccountsViewModel?

    // MARK: - Message Auto-Clear

    @ObservationIgnored private var messageClearTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        storageService: SettingsStorageServiceProtocol,
        wallpaperService: WallpaperManagementServiceProtocol,
        resetCoordinator: DataResetCoordinatorProtocol,
        validationService: SettingsValidationServiceProtocol,
        exportCoordinator: ExportCoordinatorProtocol,
        importCoordinator: CSVImportCoordinatorProtocol? = nil,
        transactionsViewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        initialSettings: AppSettings? = nil
    ) {
        self.storageService = storageService
        self.wallpaperService = wallpaperService
        self.resetCoordinator = resetCoordinator
        self.validationService = validationService
        self.exportCoordinator = exportCoordinator
        self.importCoordinator = importCoordinator
        self.transactionsViewModel = transactionsViewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.settings = initialSettings ?? AppSettings.makeDefault()
    }

    // MARK: - Lifecycle

    /// Load settings and wallpaper on initialization
    func loadInitialData() async {
        await loadSettings()
        await loadCurrentWallpaper()
        await loadWallpaperHistory()
    }

    // MARK: - Settings Operations

    /// Update base currency
    func updateBaseCurrency(_ currency: String) async {

        do {
            // Validate currency
            try validationService.validateCurrency(currency)

            // Update settings
            settings.baseCurrency = currency

            // Save to storage
            try await storageService.saveSettings(settings)

            await showSuccess(String(localized: "success.settings.currencyUpdated", defaultValue: "Currency updated successfully"))

        } catch {
            await showError(error.localizedDescription)
        }
    }

    /// Select new wallpaper
    func selectWallpaper(_ image: UIImage) async {

        await setLoading(true)

        do {
            // Remove old wallpaper if exists
            if let oldFileName = settings.wallpaperImageName {
                try? await wallpaperService.removeWallpaper(named: oldFileName)
            }

            // Save new wallpaper
            let fileName = try await wallpaperService.saveWallpaper(image)

            // Update settings
            settings.wallpaperImageName = fileName

            // Save to storage
            try await storageService.saveSettings(settings)

            // Update current wallpaper
            currentWallpaper = image

            // Reload history
            await loadWallpaperHistory()

            await showSuccess(String(localized: "success.settings.wallpaperUpdated", defaultValue: "Wallpaper updated successfully"))

        } catch {
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    /// Remove current wallpaper
    func removeWallpaper() async {

        guard let fileName = settings.wallpaperImageName else {
            return
        }

        await setLoading(true)

        do {
            // Remove file
            try await wallpaperService.removeWallpaper(named: fileName)

            // Update settings
            settings.wallpaperImageName = nil

            // Save to storage
            try await storageService.saveSettings(settings)

            // Clear current wallpaper
            currentWallpaper = nil

            await showSuccess(String(localized: "success.settings.wallpaperRemoved", defaultValue: "Wallpaper removed successfully"))

        } catch {
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    // MARK: - Export/Import Operations

    /// Export all data to CSV
    func exportAllData() async -> URL? {

        isExporting = true
        exportProgress = 0

        do {
            let fileURL = try await exportCoordinator.exportAllData()

            exportProgress = 1.0

            await showSuccess(String(localized: "success.export.completed", defaultValue: "Data exported successfully"))


            isExporting = false
            return fileURL
        } catch {
            await showError(error.localizedDescription)
            isExporting = false
            return nil
        }
    }

    /// Start CSV import flow
    /// - Parameter url: URL of CSV file to import
    func startImportFlow(from url: URL) async {

        guard let transactionsViewModel = transactionsViewModel,
              let categoriesViewModel = categoriesViewModel else {
            await showError(String(localized: "error.import.viewModelsNotAvailable", defaultValue: "Required view models not available"))
            return
        }

        // Create flow coordinator (it will create CSVImportCoordinator lazily)
        let flowCoordinator = ImportFlowCoordinator(
            transactionsViewModel: transactionsViewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel
        )

        importFlowCoordinator = flowCoordinator

        // Start import
        await flowCoordinator.startImport(from: url)
    }

    /// Cancel import flow
    func cancelImportFlow() {
        importFlowCoordinator?.cancel()
        importFlowCoordinator = nil
    }

    // MARK: - Dangerous Operations

    /// Reset all application data
    func resetAllData() async {

        await setLoading(true)

        do {
            try await resetCoordinator.resetAllData()

            // Add haptic feedback for successful reset
            await MainActor.run {
                HapticManager.success()
            }

            await showSuccess(String(localized: "success.reset.completed", defaultValue: "All data has been reset"))

        } catch {
            await MainActor.run {
                HapticManager.error()
            }
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    /// Recalculate all account balances
    func recalculateBalances() async {

        await setLoading(true)

        do {
            try await resetCoordinator.recalculateAllBalances()

            // Add haptic feedback for successful recalculation
            await MainActor.run {
                HapticManager.success()
            }

            await showSuccess(String(localized: "success.recalculation.completed", defaultValue: "Balances recalculated successfully"))

        } catch {
            await MainActor.run {
                HapticManager.error()
            }
            await showError(error.localizedDescription)
        }

        await setLoading(false)
    }

    // MARK: - Private Helpers

    private func loadSettings() async {
        do {
            settings = try await storageService.loadSettings()

        } catch {

            // Use default on error
            settings = AppSettings.makeDefault()
        }
    }

    private func loadCurrentWallpaper() async {
        guard let fileName = settings.wallpaperImageName else {
            currentWallpaper = nil
            return
        }

        do {
            currentWallpaper = try await wallpaperService.loadWallpaper(named: fileName)

        } catch {

            // Clear invalid wallpaper reference
            settings.wallpaperImageName = nil
            try? await storageService.saveSettings(settings)
            currentWallpaper = nil
        }
    }

    private func loadWallpaperHistory() async {
        wallpaperHistory = await wallpaperService.getWallpaperHistory()
    }

    private func setLoading(_ loading: Bool) async {
        isLoading = loading
    }

    private func showError(_ message: String) async {
        errorMessage = message
        successMessage = nil

        // Auto-clear after 5 seconds (cancel previous to avoid race)
        messageClearTask?.cancel()
        messageClearTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if self.errorMessage == message {
                self.errorMessage = nil
            }
        }
    }

    private func showSuccess(_ message: String) async {
        successMessage = message
        errorMessage = nil

        // Auto-clear after 3 seconds (cancel previous to avoid race)
        messageClearTask?.cancel()
        messageClearTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if self.successMessage == message {
                self.successMessage = nil
            }
        }
    }
}
