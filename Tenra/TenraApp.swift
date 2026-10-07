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
//    3. If the store failed to open (or the full load later fails), the window shows
//       StoreUnavailableView instead and nothing is built over the store.
//

import SwiftUI
import UserNotifications

@main
struct TenraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeFilterManager = TimeFilterManager()
    @State private var coordinator: AppCoordinator? = nil
    /// Set when the database could not be opened: the window shows only the error screen,
    /// and no coordinator exists to read, save over, back up or replace the store.
    @State private var storeFailure: StoreLoadFailure? = nil

    init() {
        // Shared design system: logo and FX hooks for DesignKit components.
        DesignKitBridge.configure()
        // The optional app lock draws in its own window above every sheet.
        AppLockService.shared.onOverlayVisibilityChange = { visible in
            AppLockWindowPresenter.shared.setVisible(visible)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Always present, matches the LaunchScreen background so the cross-fade
                // into MainTabView lands on a stable colour.
                AppColors.bgBase.ignoresSafeArea()

                if let storeFailure {
                    StoreUnavailableView(failure: storeFailure, onRetry: retryOpeningStore)
                        .transition(.opacity)
                } else if let coordinator {
                    Group {
                        if let failure = coordinator.startupFailure {
                            StoreUnavailableView(failure: failure) {
                                coordinator.retryAfterStartupFailure()
                            }
                        } else if coordinator.needsOnboarding {
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
            .animation(.easeOut(duration: AppAnimation.standard), value: coordinator == nil)
            .animation(.easeOut(duration: AppAnimation.standard), value: storeFailure == nil)
            .task {
                await bootstrap()
            }
            .onChange(of: scenePhase) { _, phase in
                AppLockService.shared.handleScenePhase(phase)

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
                if phase == .background {
                    // Ask iOS for a background insights recompute while we're away.
                    BackgroundInsightsRefresher.shared.scheduleNextRefresh()
                }
            }
        }
    }

    // MARK: - Launch

    /// Opens the store, then builds and publishes the coordinator. Also the path a successful
    /// retry from the error screen takes.
    private func bootstrap() async {
        // Wait for CoreData pre-warm to finish (already started in AppDelegate).
        // If preWarm() finishes before this task runs, this await returns instantly.
        // A store that failed to open stops the launch here: no coordinator means no
        // repository falls back to the legacy UserDefaults copy and nothing can save over,
        // back up or replace the store while the user reads the error screen.
        let failure = await Task.detached(priority: .userInitiated) {
            CoreDataStack.shared.openStoreIfNeeded()
        }.value
        if let failure {
            storeFailure = failure
            return
        }
        #if DEBUG
        // Screenshot capture mode: wipe + seed the demo dataset BEFORE the
        // coordinator exists so the normal startup path loads it as user data.
        await ScreenshotDemoSeeder.seed()
        #endif
        // Construct the coordinator and run the fast path BEFORE publishing it,
        // so the first MainTabView/OnboardingFlowView render already has accounts
        // + categories loaded. This removes the brief empty-Home flash and the
        // subsequent opacity transition that used to fire ~50 ms later.
        //
        // reconcileOnboardingAfterFastPath() runs inside initializeFastPath(), so
        // `needsOnboarding` is also settled before the conditional below evaluates.
        //
        // An App Intent can run in this same process, before or after the UI:
        // - before: the Wallet automation / Siri launched the process in the
        //   background and built a coordinator (fast path only). Adopt it, so the
        //   UI and later intents share one TransactionStore; ContentView's
        //   initialize() then runs the full load on it.
        // - after: register before the await, so the intent reuses this one.
        let c = await IntentEnvironment.shared.existingCoordinator() ?? AppCoordinator()
        IntentEnvironment.shared.register(c)
        await c.initializeFastPath() // returns at once when the intent already ran it
        coordinator = c
    }

    /// The error screen's retry: loads the store again (never touching the file) and, once it
    /// opens, continues the normal launch.
    private func retryOpeningStore() async {
        let failure = await Task.detached(priority: .userInitiated) {
            CoreDataStack.shared.retryOpeningStore()
        }.value
        if let failure {
            storeFailure = failure
            return
        }
        storeFailure = nil
        await bootstrap()
    }
}
