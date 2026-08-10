//
//  TabViews.swift
//  Tenra
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
    @Environment(PremiumManager.self) private var premium

    @State private var showingSoftPaywall = false

    var body: some View {
        NavigationStack {
            InsightsView(insightsViewModel: coordinator.insightsViewModel)
                .environment(timeFilterManager)
                .navigationTitle(String(localized: "tab.analytics"))
                .navigationBarTitleDisplayMode(.large)
                // Aha-moment soft paywall (strategy §5): Insights is where users
                // first *see* where their money goes. Dismissible, ≥10 logged tx,
                // max 3 shows / 14-day cooldown — enforced by PremiumManager.
                .task {
                    guard premium.shouldShowSoftPaywall(
                        transactionCount: coordinator.transactionStore.transactions.count
                    ) else { return }
                    // Let the insights content render first — the paywall should
                    // interrupt a loaded aha-screen, not an empty loading state.
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { return }
                    premium.markSoftPaywallShown()
                    showingSoftPaywall = true
                }
                .paywallSheet(isPresented: $showingSoftPaywall)
        }
    }
}

// MARK: - FinancesTab

struct FinancesTab: View {
    var body: some View {
        FinancesView()
    }
}

// MARK: - VoiceTab

/// Full-screen voice recording tab.
/// VoiceInputView is embedded directly — no button trigger needed.
/// After recognition completes, pushes to VoiceInputConfirmationView.
struct VoiceTab: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PremiumManager.self) private var premium

    @State private var voiceService = VoiceInputService()
    @State private var parser: VoiceInputParser? = nil

    var body: some View {
        NavigationStack {
            if !premium.isPro {
                PremiumLockedView(
                    icon: "mic.fill",
                    title: String(localized: "premium.locked.voice.title"),
                    message: String(localized: "premium.locked.voice.message")
                )
                .navigationTitle(String(localized: "tab.voice"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
            VoiceInputView(
                voiceService: voiceService,
                parser: parser ?? VoiceInputParser(
                    categoriesViewModel: coordinator.categoriesViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    transactionsViewModel: coordinator.transactionsViewModel
                ),
                transactionsViewModel: coordinator.transactionsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                embeddedInTab: true
            )
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
}

// MARK: - OCRTab

/// Full-screen OCR / PDF import tab.
/// Shows a centred import prompt; PDFImportCoordinator handles the rest internally.
struct OCRTab: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PremiumManager.self) private var premium

    var body: some View {
        NavigationStack {
            if !premium.isPro {
                PremiumLockedView(
                    icon: "doc.viewfinder",
                    title: String(localized: "premium.locked.import.title"),
                    message: String(localized: "premium.locked.import.message")
                )
                .navigationTitle(String(localized: "tab.ocr"))
                .navigationBarTitleDisplayMode(.inline)
            } else {
            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                // Fix #11: AppIconSize.mega (64pt) instead of magic literal
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: AppIconSize.mega, weight: .light))
                    .foregroundStyle(AppColors.accent)

                VStack(spacing: AppSpacing.sm) {
                    Text(String(localized: "tab.ocr"))
                        .font(AppTypography.h3)

                    Text(String(localized: "import.tab.subtitle"))
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
}
