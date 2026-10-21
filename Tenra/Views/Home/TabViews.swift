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
        .softScrollEdges()
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
        .softScrollEdges()
    }
}

// MARK: - AssistantTab

/// The AI assistant (docs/domains/assistant.md), the action tab's page where it can run:
/// Pro, or the free allowance without it. Its home (AssistantView) owns the navigation stack,
/// each chat a page on it. The server answers only an app it can verify with App Attest, Pro or
/// not, so a device without it (the Simulator included) gets no assistant. The thread lives in
/// `AppCoordinator`, so it survives the tab changing.
struct AssistantTab: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        if !AssistantAvailability.deviceSupported {
            NavigationStack {
                EmptyState(icon: "sparkles", title: String(localized: "assistant.error.device"))
                    .navigationTitle(String(localized: "tab.assistant"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .softScrollEdges()
        } else if let assistant = coordinator.assistant() {
            AssistantView(model: assistant)
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

                // The symbol draws itself on a pale disc (DesignKit's HeroSymbol), as an
                // onboarding page's picture.
                HeroSymbol(systemImage: "doc.viewfinder", size: AppIconSize.Tile.xl * 2)

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
                    categoriesViewModel: coordinator.categoriesViewModel,
                    accountsViewModel: coordinator.accountsViewModel,
                    incomingFile: handedOverPDF,
                    onIncomingFileTaken: { _ = coordinator.consumePendingAttachment() }
                )

                Spacer()
            }
            .navigationTitle(String(localized: "tab.ocr"))
            .navigationBarTitleDisplayMode(.inline)
            }
        }
        .softScrollEdges()
    }

    /// A PDF opened in Tenra from another app while the assistant cannot take it (MainTabView
    /// brings this tab forward). Waits here while Tenra Pro is locked.
    private var handedOverPDF: URL? {
        guard !AssistantAvailability.isAvailable,
              let url = coordinator.pendingAttachment,
              url.pathExtension.lowercased() == "pdf" else { return nil }
        return url
    }
}
