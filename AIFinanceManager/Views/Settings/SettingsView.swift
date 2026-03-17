//
//  SettingsView.swift
//  AIFinanceManager
//
//  Created on 2024
//  Refactored: 2026-02-04 Phase 2 (CSV Migration)
//  Refactored: 2026-02-04 Phase 3 (UI Decomposition)
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Main Settings screen with modular component-based architecture
/// Follows Single Responsibility Principle with Props pattern
struct SettingsView: View {
    // MARK: - Dependencies (Observable - no wrappers needed!)

    let settingsViewModel: SettingsViewModel

    // Legacy ViewModels (navigation only)
    let transactionsViewModel: TransactionsViewModel
    let accountsViewModel: AccountsViewModel
    let categoriesViewModel: CategoriesViewModel
    // ✨ Phase 9: Use TransactionStore instead of SubscriptionsViewModel
    let transactionStore: TransactionStore
    let depositsViewModel: DepositsViewModel
    let loansViewModel: LoansViewModel

    // MARK: - State

    @State private var showingResetConfirmation = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false

    // MARK: - Body

    var body: some View {
        Group {
            if let flowCoordinator = settingsViewModel.importFlowCoordinator {
                ImportFlowSheetsContainer(
                    flowCoordinator: flowCoordinator,
                    onCancel: { settingsViewModel.cancelImportFlow() }
                ) {
                    settingsList
                }
            } else {
                settingsList
            }
        }
    }

    // MARK: - Main List

    private var settingsList: some View {
        ZStack(alignment: .top) {
            List {
                generalSection
                dataManagementSection
                exportImportSection
                experimentsSection
                dangerZoneSection
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.large)

            // Toast messages
            VStack {
                if let successMessage = settingsViewModel.successMessage {
                    MessageBanner.success(successMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }

                if let errorMessage = settingsViewModel.errorMessage {
                    MessageBanner.error(errorMessage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }

                Spacer()
            }
        }
        .alert(
            String(localized: "alert.deleteAllData.title"),
            isPresented: $showingResetConfirmation
        ) {
            Button(String(localized: "alert.deleteAllData.confirm"), role: .destructive) {
                Task {
                    await settingsViewModel.resetAllData()
                }
            }
            Button(String(localized: "alert.deleteAllData.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "alert.deleteAllData.message"))
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportActivityView(transactionsViewModel: transactionsViewModel)
        }
        .sheet(isPresented: $showingImportPicker) {
            DocumentPicker(contentTypes: [.commaSeparatedText, .text]) { url in
                Task {
                    await settingsViewModel.startImportFlow(from: url)
                }
            }
        }
        .task {
            // Load wallpaper on view appear
            await settingsViewModel.loadInitialData()
        }
    }

    // MARK: - Sections (Props-based Components)

    private var generalSection: some View {
        SettingsGeneralSection(
            selectedCurrency: settingsViewModel.settings.baseCurrency,
            availableCurrencies: AppSettings.availableCurrencies,
            onCurrencyChange: { newCurrency in
                Task { await settingsViewModel.updateBaseCurrency(newCurrency) }
            }
        ) {
            SettingsHomeBackgroundView(
                currentMode: settingsViewModel.settings.homeBackgroundMode,
                wallpaperImage: settingsViewModel.currentWallpaper,
                blurWallpaper: settingsViewModel.settings.blurWallpaper,
                onModeSelect: { newMode in
                    Task { await settingsViewModel.updateBackgroundMode(newMode) }
                },
                onPhotoChange: { newItem in
                    guard let newItem else { return }
                    guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                    guard let image = UIImage(data: data) else { return }
                    await settingsViewModel.selectWallpaper(image)
                    // Automatically switch to wallpaper mode when a photo is picked
                    await settingsViewModel.updateBackgroundMode(.wallpaper)
                },
                onWallpaperRemove: {
                    await settingsViewModel.removeWallpaper()
                },
                onBlurChange: { blur in
                    Task { await settingsViewModel.updateBlurWallpaper(blur) }
                }
            )
        }
    }

    private var dataManagementSection: some View {
        SettingsDataManagementSection {
            CategoriesManagementView(
                categoriesViewModel: categoriesViewModel,
                transactionsViewModel: transactionsViewModel
            )
        } subcategoriesDestination: {
            SubcategoriesManagementView(
                categoriesViewModel: categoriesViewModel
            )
        } accountsDestination: {
            AccountsManagementView(
                accountsViewModel: accountsViewModel,
                depositsViewModel: depositsViewModel,
                transactionsViewModel: transactionsViewModel
            )
        }
    }

    private var exportImportSection: some View {
        SettingsExportImportSection(
            onExport: {
                showingExportSheet = true
            },
            onImport: {
                showingImportPicker = true
            }
        )
    }

    private var experimentsSection: some View {
        Section {
            NavigationLink {
                ExperimentsListView()
            } label: {
                Label("Эксперименты", systemImage: "flask")
            }
            #if DEBUG
            NavigationLink {
                NotificationDebugView()
            } label: {
                Label("Notification Debug", systemImage: "bell.badge")
            }
            #endif
        }
    }

    private var dangerZoneSection: some View {
        SettingsDangerZoneSection(
            onResetData: {
                showingResetConfirmation = true
            }
        )
    }
}

// MARK: - Preview

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        SettingsView(
            settingsViewModel: coordinator.settingsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            transactionStore: coordinator.transactionStore,
            depositsViewModel: coordinator.depositsViewModel,
            loansViewModel: coordinator.loansViewModel
        )
    }
}
