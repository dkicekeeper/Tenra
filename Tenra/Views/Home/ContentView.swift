//
//  ContentView.swift
//  Tenra
//
//  Home screen - main entry point of the app
//  Refactored: 2026-02-01 - Full rebuild with SRP, optimized state management, and component extraction
//

import SwiftUI
import ImageIO

// MARK: - HomeDestination

enum HomeDestination: Hashable {
    case history
}

// MARK: - ContentView (Home Screen)

/// Main home screen displaying accounts, analytics, subscriptions, and quick actions
/// Single responsibility: Home screen UI orchestration
struct ContentView: View {
    // MARK: - Environment (Modern @Observable with @Environment)
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(TimeFilterManager.self) private var timeFilterManager
    /// Persistent UI state injected from MainTabView — survives tab-bar reconstruction.
    @Environment(HomePersistentState.self) private var homeState

    // MARK: - State
    @State private var navigationPath = NavigationPath()
    @Namespace private var accountNamespace
    @State private var showingTimeFilter = false
    @State private var showingAddAccount = false
    @State private var showingSettings = false

    // MARK: - Summary Trigger
    // Equatable snapshot of every input that drives the summary card.
    // .task(id: summaryTrigger) restarts automatically whenever this changes.
    private struct SummaryTrigger: Equatable {
        let txCount: Int
        let filterName: String  // displayName proxy — avoids Equatable requirement on TimeFilter
        let isImporting: Bool
        let isFullyInitialized: Bool
    }
    private var summaryTrigger: SummaryTrigger {
        SummaryTrigger(
            // Read the Observable mirror, not transactions.count — the latter would
            // subscribe ContentView's body to the full 19k-element array and re-eval
            // body on every micro-mutation.
            txCount: transactionStore.transactionsCount,
            filterName: timeFilterManager.currentFilter.displayName,
            isImporting: transactionStore.isImporting,
            isFullyInitialized: coordinator.isFullyInitialized
        )
    }

    // Thread-safe because it is only accessed from @MainActor context (.task body).
    @MainActor
    private static let summaryDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        return df
    }()

    // MARK: - Computed ViewModels (from coordinator)
    private var viewModel: TransactionsViewModel {
        coordinator.transactionsViewModel
    }
    private var accountsViewModel: AccountsViewModel {
        coordinator.accountsViewModel
    }
    private var categoriesViewModel: CategoriesViewModel {
        coordinator.categoriesViewModel
    }
    private var transactionStore: TransactionStore {
        coordinator.transactionStore
    }

    // MARK: - Body
    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainContent
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeDestination.self) { dest in
                switch dest {
                case .history:
                    historyDestination
                }
            }
            .navigationDestination(for: Account.self) { account in
                AccountActionView(
                    transactionsViewModel: viewModel,
                    accountsViewModel: accountsViewModel,
                    account: account,
                    namespace: accountNamespace,
                    categoriesViewModel: categoriesViewModel
                )
                .environment(timeFilterManager)
                .navigationTransition(.zoom(sourceID: account.id, in: accountNamespace))
            }
            .background { homeBackground }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingTimeFilter) { timeFilterSheet }
            .sheet(isPresented: $showingAddAccount) { addAccountSheet }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .task {
                await coordinator.initializeFastPath()
                await coordinator.initialize()
            }
            // Reactive summary
            // Fires whenever transactions count, active filter, import state, or
            // initialization state changes. SwiftUI cancels the previous task and
            // starts a new one automatically — no manual task tracking needed.
            .task(id: summaryTrigger) {
                guard !transactionStore.isImporting else { return }
                // Debounce rapid count changes during initial data load.
                // When isFullyInitialized flips true the trigger fires immediately
                // (skip sleep so the summary card is ready the moment skeleton lifts).
                if !coordinator.isFullyInitialized {
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }
                }
                // Capture Sendable value-type snapshots on @MainActor before leaving.
                let snapshot     = Array(transactionStore.transactions)
                let filterRange  = timeFilterManager.currentFilter.dateRange()
                let filterStart  = filterRange.start
                let filterEnd    = filterRange.end
                let currency     = viewModel.appSettings.baseCurrency

                // Both summary and category weights are computed in one Task.detached so the
                // transactions array is iterated only twice on the same background thread.
                let (summary, categoryWeights) = await Task.detached(priority: .userInitiated) {
                    let s = SummaryCalculator.compute(
                        transactions: snapshot,
                        filterStart: filterStart,
                        filterEnd: filterEnd,
                        baseCurrency: currency
                    )
                    let w = SummaryCalculator.computeTopExpenseWeights(
                        transactions: snapshot,
                        filterStart: filterStart,
                        filterEnd: filterEnd,
                        baseCurrency: currency
                    )
                    return (s, w)
                }.value

                guard !Task.isCancelled else { return }
                homeState.cachedSummary = summary
                homeState.cachedCategoryWeights = categoryWeights
            }
            // Reactive wallpaper
            // Fires when wallpaperImageName changes. Skips re-appear when the image
            // for the current name is already loaded in homeState.
            .task(id: viewModel.appSettings.wallpaperImageName) {
                let targetName = viewModel.appSettings.wallpaperImageName
                // Same name already loaded → nothing to do (handles back-navigation).
                guard homeState.wallpaperImageName != targetName else { return }
                homeState.wallpaperImage = nil
                homeState.wallpaperImageName = nil
                guard let name = targetName else { return }

                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                let screenSize  = windowScene?.screen.bounds.size ?? CGSize(width: 390, height: 844)
                let scale       = windowScene?.screen.scale ?? 3.0
                let fileURL     = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

                let image = await Task.detached(priority: .userInitiated) {
                    ContentView.downsampleWallpaper(at: fileURL, screenSize: screenSize, scale: scale)
                }.value

                guard !Task.isCancelled else { return }
                homeState.wallpaperImage     = image
                homeState.wallpaperImageName = name
            }
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Sections are gated by `if` — not `.contentReveal` opacity — so SwiftUI
                // doesn't pay the cost of evaluating their bodies, laying them out, and
                // rendering glass effects during the first render before data is ready.
                // Profiling showed the initial ContentView render was blocking MainActor
                // for ~2.4 s, which delayed fastPath's `await` from delivering accounts
                // and prevented the user from interacting with anything for ~6 s total.
                if coordinator.isFastPathDone {
                    accountsSection
                        .transition(.opacity)
                }
                if coordinator.isFullyInitialized {
                    historyNavigationLink
                        .transition(.opacity)
                }
                if coordinator.isFastPathDone {
                    categoriesSection
                        .transition(.opacity)
                }
                errorSection
            }
            .padding(.vertical, AppSpacing.md)
            .animation(AppAnimation.contentRevealAnimation, value: coordinator.isFastPathDone)
            .animation(AppAnimation.contentRevealAnimation, value: coordinator.isFullyInitialized)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountsSection: some View {
        let nonLoanAccounts = accountsViewModel.accounts.filter { !$0.isLoan }
        if nonLoanAccounts.isEmpty {
            EmptyCardView(
                sectionTitle: String(localized: "accounts.title"),
                emptyTitle: String(localized: "emptyState.noAccounts"),
                action: { showingAddAccount = true }
            )
            .screenPadding()
        } else {
            AccountsCarousel(
                accounts: nonLoanAccounts,
                balanceCoordinator: coordinator.balanceCoordinator,
                namespace: accountNamespace
            )
        }
    }

    private var historyNavigationLink: some View {
        NavigationLink(value: HomeDestination.history) {
            TransactionsSummaryCard(
                summary: homeState.cachedSummary,
                currency: viewModel.appSettings.baseCurrency,
                // Use the Observable count mirror so this navlink doesn't subscribe
                // to the full transactions array (any tx mutation would otherwise
                // dirty the entire summary navlink).
                isEmpty: transactionStore.transactionsCount == 0
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var categoriesSection: some View {
        TransactionCategoryPickerView(
            transactionsViewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionStore: coordinator.transactionStore,
            timeFilterManager: timeFilterManager
        )
        .screenPadding()
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            InlineStatusText(message: error, type: .error)
                .screenPadding()
        }
    }

    // MARK: - Destinations

    private var historyDestination: some View {
        HistoryView(
            transactionsViewModel: viewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            paginationController: coordinator.transactionPaginationController,
            initialCategory: nil
        )
        .environment(timeFilterManager)
    }

    // MARK: - Overlays & Backgrounds

    /// Renders the correct full-screen background based on the user's chosen mode.
    @ViewBuilder
    private var homeBackground: some View {
        switch viewModel.appSettings.homeBackgroundMode {
        case .none:
            // No background — system default
            EmptyView()

        case .gradient:
            // Category orbs fill the full screen behind all Liquid Glass cards.
            // Opacity is user-configurable in Settings (default 0.35) so that the
            // glass layer remains legible at conservative values but can be dialed up.
            CategoryGradientBackground(
                weights: homeState.cachedCategoryWeights,
                customCategories: coordinator.categoriesViewModel.customCategories
            )
            .opacity(viewModel.appSettings.homeBackgroundOpacity)
            .ignoresSafeArea(.all, edges: .all)
            .animation(AppAnimation.gentleSpring, value: homeState.cachedCategoryWeights)

        case .wallpaper:
            if let wallpaperImage = homeState.wallpaperImage {
                Image(uiImage: wallpaperImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: viewModel.appSettings.blurWallpaper ? 20 : 0, opaque: true)
                    .ignoresSafeArea(.all, edges: .all)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            timeFilterButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            HapticManager.light()
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(String(localized: "settings.title"))
    }

    private var timeFilterButton: some View {
        Button(action: {
            HapticManager.light()
            showingTimeFilter = true
        }) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "calendar")
                Text(timeFilterManager.currentFilter.displayName)
                    .font(AppTypography.bodySmall)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(String(localized: "accessibility.calendar"))
        .accessibilityHint(String(localized: "accessibility.calendarHint"))
    }

    // MARK: - Sheets

    private var timeFilterSheet: some View {
        TimeFilterView(filterManager: timeFilterManager)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    private var addAccountSheet: some View {
        AccountEditView(
            accountsViewModel: accountsViewModel,
            transactionsViewModel: viewModel,
            account: nil,
            onSave: handleAccountSave,
            onCancel: {
                showingAddAccount = false
            }
        )
    }

    private var settingsSheet: some View {
        NavigationStack {
            SettingsView(
                settingsViewModel: coordinator.settingsViewModel,
                transactionsViewModel: viewModel,
                accountsViewModel: accountsViewModel,
                categoriesViewModel: categoriesViewModel,
                transactionStore: transactionStore,
                depositsViewModel: coordinator.depositsViewModel,
                loansViewModel: coordinator.loansViewModel,
                cloudSyncViewModel: coordinator.cloudSyncViewModel
            )
        }
    }

    /// Decodes `fileURL` into a UIImage downsampled to `screenSize × scale` pixels.
    /// Returns nil if the file cannot be read or decoded.
    private nonisolated static func downsampleWallpaper(
        at fileURL: URL,
        screenSize: CGSize,
        scale: CGFloat
    ) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let maxPixelDimension = max(screenSize.width, screenSize.height) * scale
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Event Handlers

    private func handleAccountSave(_ account: Account) {
        HapticManager.success()
        Task {
            await accountsViewModel.addAccount(
                name: account.name,
                initialBalance: account.initialBalance ?? 0,
                currency: account.currency,
                iconSource: account.iconSource
            )
            showingAddAccount = false
        }
    }

    // MARK: - Reactive Updates
    // Summary and wallpaper update via .task(id:) — SwiftUI manages cancellation
    // and restart automatically. No manual task tracking or onChange chains needed.
}

// MARK: - Skeleton Components

/// Accounts carousel skeleton: 3 cards (200×120) in horizontal scroll.
// MARK: - Preview

#Preview {
    let coordinator = AppCoordinator()
    ContentView()
        .environment(TimeFilterManager())
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(HomePersistentState())
}
