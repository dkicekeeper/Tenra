//
//  TabViews.swift
//  AIFinanceManager
//
//  NavigationStack wrappers for each tab in MainTabView.
//  Each wrapper owns its NavigationStack so navigation state
//  is independent per tab (standard iOS tab bar pattern).
//

import SwiftUI

// MARK: - HomeTab

struct HomeTab: View {
    var body: some View {
        ContentView()
    }
}

// MARK: - AnalyticsTab

struct AnalyticsTab: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager

    var body: some View {
        NavigationStack {
            InsightsView(insightsViewModel: coordinator.insightsViewModel)
                .environment(timeFilterManager)
                .navigationTitle(String(localized: "tab.analytics"))
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - SettingsTab

struct SettingsTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
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
}

// MARK: - VoiceTab

/// Full-screen voice recording tab.
/// VoiceInputView is embedded directly — no button trigger needed.
/// After recognition completes, pushes to VoiceInputConfirmationView.
struct VoiceTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var voiceService = VoiceInputService()
    @State private var parsedOperation: ParsedOperation? = nil

    // Fix #5: stored as @State so a single VoiceInputParser instance is created for the
    // VoiceTab lifetime and reused across body re-evaluations. The previous computed var
    // created a new parser on every body call (potentially 60×/s during animations).
    // Optional because @Environment is unavailable at @State init time; set once in .task.
    @State private var parser: VoiceInputParser? = nil

    var body: some View {
        NavigationStack {
            VoiceInputView(
                voiceService: voiceService,
                onComplete: { transcribedText in
                    guard let p = parser else { return }
                    let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    parsedOperation = p.parse(trimmed)
                },
                // Fallback creates a parser only on the first frame (before .task fires).
                // From the second frame onward the stored @State parser is used instead.
                parser: parser ?? VoiceInputParser(
                    categoriesViewModel: coordinator.categoriesViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    transactionsViewModel: coordinator.transactionsViewModel
                ),
                embeddedInTab: true
            )
            .navigationDestination(item: $parsedOperation) { parsed in
                VoiceInputConfirmationView(
                    transactionsViewModel: coordinator.transactionsViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel,
                    parsedOperation: parsed,
                    originalText: voiceService.getFinalText()
                )
            }
            .task {
                if parser == nil {
                    parser = VoiceInputParser(
                        categoriesViewModel: coordinator.categoriesViewModel,
                        accountsViewModel: coordinator.accountsViewModel,
                        transactionsViewModel: coordinator.transactionsViewModel
                    )
                }
                voiceService.categoriesViewModel = coordinator.categoriesViewModel
                voiceService.accountsViewModel = coordinator.accountsViewModel
            }
        }
    }
}

// MARK: - OCRTab

/// Full-screen OCR / PDF import tab.
/// Shows a centred import prompt; PDFImportCoordinator handles the rest internally.
struct OCRTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                // Fix #11: AppIconSize.mega (64pt) instead of magic literal
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: AppIconSize.mega, weight: .light))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: AppSpacing.sm) {
                    Text(String(localized: "tab.ocr"))
                        .font(AppTypography.h3)

                    Text(String(localized: "accessibility.importStatementHint"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxxl)
                }

                // PDFImportCoordinator renders the import button + manages all sheets
                PDFImportCoordinator(
                    transactionsViewModel: coordinator.transactionsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel
                )

                Spacer()
            }
            .navigationTitle(String(localized: "tab.ocr"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
