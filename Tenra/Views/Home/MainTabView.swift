//
//  MainTabView.swift
//  Tenra
//
//  Root tab bar using the iOS 26 Tab API.
//
//  Mechanic (Apple Music style):
//  • Normal mode  → Home | Analytics | Settings | [+]
//  • Expanded mode → Voice | Import | [×]
//
//  Tapping [+] animates the bar into "expanded" mode and switches
//  to Voice tab. Tapping [×] restores the original three tabs.
//

import SwiftUI

// MARK: - AppTab

/// All possible tab identifiers, including the action pseudo-tab.
enum AppTab: String, Hashable {
    case home
    case analytics
    case finances
    case voice
    case ocr
    /// The action pseudo-tab — never "selected" in a navigation sense.
    case plusAction
}

// MARK: - TabBarMode

enum TabBarMode {
    case normal
    case expanded
}

// MARK: - MainTabView

struct MainTabView: View {

    // MARK: State

    @Environment(AppCoordinator.self) private var coordinator

    /// Rating-prompt coordinator (singleton). Observed so `shouldShowSurvey` drives the sheet.
    @State private var ratingPrompt = RatingPromptService.shared

    @State private var selectedTab: AppTab = .home
    @State private var tabBarMode: TabBarMode = .normal
    /// Remembers which "real" tab was active before expanding,
    /// so we can restore it when the user taps [×].
    @State private var previousTab: AppTab = .home

    /// Stable, TabView-owned control of the tab bar's visibility. Pushed views
    /// (e.g. `TransactionAddModal`) toggle `isHidden` instead of relying on a
    /// transient `.toolbar(.hidden, for: .tabBar)` whose restore races the view's
    /// teardown. See `TabBarVisibility` for the full rationale.
    @State private var tabBarVisibility = TabBarVisibility()

    /// Home screen UI state that must survive ContentView recreation.
    /// ContentView is destroyed when tab-bar mode toggles (conditional Tab declarations).
    /// Storing state here keeps it alive and passes it down via @Environment.
    @State private var homeState = HomePersistentState()

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {
            if tabBarMode == .normal {
                // ── Normal mode tabs ──────────────────────────────────────

                Tab(
                    String(localized: "tab.home"),
                    systemImage: "house",
                    value: AppTab.home
                ) {
                    HomeTab()
                        .environment(homeState)
                }

                Tab(
                    String(localized: "tab.analytics"),
                    systemImage: "chart.bar",
                    value: AppTab.analytics
                ) {
                    AnalyticsTab()
                }

                Tab(
                    String(localized: "tab.finances"),
                    systemImage: "wallet.bifold",
                    value: AppTab.finances
                ) {
                    FinancesTab()
                }
            } else {
                // ── Expanded mode tabs ────────────────────────────────────

                Tab(
                    String(localized: "tab.voice"),
                    systemImage: "waveform",
                    value: AppTab.voice
                ) {
                    VoiceTab()
                }

                Tab(
                    String(localized: "tab.ocr"),
                    systemImage: "doc.viewfinder",
                    value: AppTab.ocr
                ) {
                    OCRTab()
                }
            }

            // ── Action tab — visually separated (like Search in Apple Music) ─
            Tab(value: AppTab.plusAction, role: .search) {
                // Content is never shown — tap is intercepted in onChange
                Color.clear.ignoresSafeArea()
            } label: {
                PlusTabLabel(isExpanded: tabBarMode == .expanded)
            }
        }
        // `.automatic` (not `.visible`) is the default so pushed views that hide
        // the bar via their own per-destination modifier (CloudBackupsView,
        // LinkPaymentsView, AccountActionView) keep working; only an explicit
        // `isHidden` forces `.hidden` from this stable owner.
        .toolbar(tabBarVisibility.isHidden ? .hidden : .automatic, for: .tabBar)
        .environment(tabBarVisibility)
        .onChange(of: selectedTab) { _, new in
            handleTabSelection(new)
        }
        // Warm-launch path: notification arrives while the app is already running.
        // We update the coordinator; the .onChange(initial:) below switches the tab.
        .onReceive(
            NotificationCenter.default.publisher(for: .subscriptionNotificationTapped)
        ) { notification in
            guard let seriesId = notification.userInfo?["seriesId"] as? String else { return }
            coordinator.setPendingSubscription(seriesId: seriesId)
        }
        // Single source of truth for "switch to Finances tab when a deep-link is pending".
        // `initial: true` covers cold-launch: AppCoordinator.init() has already loaded the
        // stashed seriesId from AppDelegate by the time this view first appears.
        .onChange(of: coordinator.pendingSubscriptionSeriesId, initial: true) { _, new in
            guard new != nil else { return }
            if tabBarMode == .expanded {
                tabBarMode = .normal
            }
            selectedTab = .finances
            previousTab = .finances
        }
        // Insight signal notification tap → Analytics tab (audit 2026-07).
        .onReceive(
            NotificationCenter.default.publisher(for: .insightSignalNotificationTapped)
        ) { _ in
            if tabBarMode == .expanded {
                tabBarMode = .normal
            }
            selectedTab = .analytics
            previousTab = .analytics
        }
        // Rating pre-prompt survey. Fired by RatingPromptService at a success moment.
        .sheet(isPresented: $ratingPrompt.shouldShowSurvey) {
            RatingSurveyView()
        }
    }

    // MARK: - Tap Handling

    private func handleTabSelection(_ tab: AppTab) {
        guard tab == .plusAction else {
            // Regular navigation tap — remember it for restore
            if tabBarMode == .normal {
                previousTab = tab
            }
            return
        }

        // User tapped + or ×
        HapticManager.light()

        withAnimation(AppAnimation.contentSpring) {
            if tabBarMode == .normal {
                tabBarMode = .expanded
                selectedTab = .voice          // Default expanded selection
            } else {
                tabBarMode = .normal
                selectedTab = previousTab     // Restore previous tab
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environment(TimeFilterManager())
        .environment(AppCoordinator())
}
