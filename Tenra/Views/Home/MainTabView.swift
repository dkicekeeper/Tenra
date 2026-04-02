//
//  MainTabView.swift
//  AIFinanceManager
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
    case settings
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

    @State private var selectedTab: AppTab = .home
    @State private var tabBarMode: TabBarMode = .normal
    /// Remembers which "real" tab was active before expanding,
    /// so we can restore it when the user taps [×].
    @State private var previousTab: AppTab = .home

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
                    String(localized: "tab.settings"),
                    systemImage: "gear",
                    value: AppTab.settings
                ) {
                    SettingsTab()
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
        .onChange(of: selectedTab) { _, new in
            handleTabSelection(new)
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

        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
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
