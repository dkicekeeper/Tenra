//
//  TenraApp.swift
//  Tenra
//
//  Created by Daulet Kydrali on 06.01.2026.
//
//  Launch order:
//    1. AppDelegate.didFinishLaunching kicks off CoreDataStack.preWarm() so
//       loadPersistentStores() runs on a background queue.
//    2. .task awaits the persistentContainer, then constructs AppCoordinator and
//       awaits initializeFastPath() before publishing it. This means the first
//       MainTabView render already has accounts + categories — no empty-Home
//       flash, no opacity transition for the always-visible sections.
//

import SwiftUI
import UserNotifications

@main
struct TenraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeFilterManager = TimeFilterManager()
    @State private var coordinator: AppCoordinator? = nil

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Always present, matches the LaunchScreen background so the cross-fade
                // into MainTabView lands on a stable colour.
                AppColors.bgBase.ignoresSafeArea()

                if let coordinator {
                    Group {
                        if coordinator.needsOnboarding {
                            OnboardingFlowView(coordinator: coordinator)
                                .environment(coordinator)
                        } else {
                            MainTabView()
                                .environment(timeFilterManager)
                                .environment(coordinator)
                                .environment(coordinator.transactionStore)
                                .environment(PremiumManager.shared)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: coordinator == nil)
            .task {
                // Wait for CoreData pre-warm to finish (already started in AppDelegate).
                // If preWarm() finishes before this task runs, this await returns instantly.
                await Task.detached(priority: .userInitiated) {
                    _ = CoreDataStack.shared.persistentContainer
                }.value
                // Construct the coordinator and run the fast path BEFORE publishing it,
                // so the first MainTabView/OnboardingFlowView render already has accounts
                // + categories loaded. This removes the brief empty-Home flash and the
                // subsequent opacity transition that used to fire ~50 ms later.
                //
                // reconcileOnboardingAfterFastPath() runs inside initializeFastPath(), so
                // `needsOnboarding` is also settled before the conditional below evaluates.
                let c = AppCoordinator()
                await c.initializeFastPath()
                coordinator = c
            }
            .onChange(of: scenePhase) { _, phase in
                // Clear app icon badge whenever the app becomes active. SwiftUI's
                // scenePhase fires reliably for both cold launch and background→foreground;
                // AppDelegate's applicationDidBecomeActive can be skipped under
                // @UIApplicationDelegateAdaptor in some launch paths. Also drop
                // delivered notifications so iOS doesn't re-apply their badge.
                if phase == .active {
                    let center = UNUserNotificationCenter.current()
                    center.setBadgeCount(0)
                    center.removeAllDeliveredNotifications()

                    // Count this foreground as a session for rating-prompt eligibility.
                    RatingPromptService.shared.recordSession()

                    // Re-derive relative time-filter bounds (e.g. .thisMonth) against
                    // the current date. scenePhase fires on both cold launch and
                    // background→foreground, so this covers a new month arriving while
                    // the app was away — without it the home summary stays on last month
                    // until the user re-opens the period picker.
                    timeFilterManager.refreshRelativePresetIfNeeded()

                    // Fold any matured future-dated tx into the realized ledger and, on a
                    // day change, refresh Insights — forecast daysRemaining, period keys and
                    // the health score depend on "today" even when nothing matured. Without
                    // this, an app left foregrounded across midnight showed stale figures
                    // until the next cold launch (cache audit #7).
                    if let coordinator {
                        Task { @MainActor in
                            let dayChanged = await coordinator.transactionStore.recalculateLedgerIfDayChanged()
                            if dayChanged {
                                coordinator.insightsViewModel.invalidateAndRecompute()
                            }
                        }
                    }
                }
            }
        }
    }
}
