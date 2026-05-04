//
//  TenraApp.swift
//  Tenra
//
//  Created by Daulet Kydrali on 06.01.2026.
//
//  Phase 31: coordinator made optional — created only after CoreData pre-warm
//  completes so persistentContainer.loadPersistentStores() never blocks MainActor.
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
            Group {
                if let coordinator {
                    if coordinator.needsOnboarding {
                        OnboardingFlowView(coordinator: coordinator)
                            .environment(coordinator)
                    } else {
                        MainTabView()
                            .environment(timeFilterManager)
                            .environment(coordinator)
                            .environment(coordinator.transactionStore)
                    }
                } else {
                    // System launch screen is still visible — show matching background
                    // so there is no flash when coordinator becomes ready.
                    AppColors.backgroundPrimary.ignoresSafeArea()
                }
            }
            .task {
                // Wait for CoreData pre-warm to finish (already started in AppDelegate).
                // If preWarm() finishes before this task runs, this await returns instantly.
                await Task.detached(priority: .userInitiated) {
                    _ = CoreDataStack.shared.persistentContainer
                }.value
                // Now safe to create AppCoordinator — persistentContainer is already open.
                coordinator = AppCoordinator()
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
                }
            }
        }
    }
}
