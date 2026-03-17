//
//  ContentView.swift
//  AIFinanceManager
//
//  Home screen - main entry point of the app
//  Refactored: 2026-02-01 - Full rebuild with SRP, optimized state management, and component extraction
//

import SwiftUI
import os
import ImageIO

private let cvLogger = Logger(subsystem: "AIFinanceManager", category: "ContentView")

// MARK: - HomeDestination

enum HomeDestination: Hashable {
    case history
    case subscriptions
    case loans
    case loanDetail(String) // accountId
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
            txCount: transactionStore.transactions.count,
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
    // ✨ Phase 9: Use TransactionStore instead of SubscriptionsViewModel
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
                case .subscriptions:
                    subscriptionsDestination
                case .loans:
                    LoansListView(
                        loansViewModel: coordinator.loansViewModel,
                        transactionsViewModel: viewModel,
                        balanceCoordinator: coordinator.balanceCoordinator
                    )
                    .environment(timeFilterManager)
                case .loanDetail(let accountId):
                    LoanDetailView(
                        loansViewModel: coordinator.loansViewModel,
                        transactionsViewModel: viewModel,
                        balanceCoordinator: coordinator.balanceCoordinator,
                        accountId: accountId
                    )
                    .environment(timeFilterManager)
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
            .background { wallpaperBackground }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingTimeFilter) { timeFilterSheet }
            .sheet(isPresented: $showingAddAccount) { addAccountSheet }
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

                // Phase 40: All transactions in memory — always use SummaryCalculator directly.
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
#if DEBUG
            .onChange(of: coordinator.isFastPathDone) { _, isDone in
                cvLogger.debug("⚡️ [ContentView] isFastPathDone → \(isDone)")
            }
            .onChange(of: coordinator.isFullyInitialized) { _, isInit in
                cvLogger.debug("✅ [ContentView] isFullyInitialized → \(isInit)")
            }
#endif
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                accountsSection
                    .skeletonLoading(isLoading: !coordinator.isFastPathDone) {
                        AccountsCarouselSkeleton()
                    }
                historyNavigationLink
                    .skeletonLoading(isLoading: !coordinator.isFullyInitialized) {
                        // .screenPadding() mirrors the one inside historyNavigationLink —
                        // SkeletonLoadingModifier shows skeleton XOR real content, never both.
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                subscriptionsNavigationLink
                    .skeletonLoading(isLoading: !coordinator.isFullyInitialized) {
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                loansNavigationLink
                    .skeletonLoading(isLoading: !coordinator.isFullyInitialized) {
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                categoriesSection
                    .skeletonLoading(isLoading: !coordinator.isFastPathDone) {
                        SectionCardSkeleton()
                            .screenPadding()
                    }
                errorSection
            }
            .padding(.vertical, AppSpacing.md)
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
                isEmpty: transactionStore.transactions.isEmpty,
                categoryWeights: homeState.cachedCategoryWeights,
                customCategories: coordinator.categoriesViewModel.customCategories
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var subscriptionsNavigationLink: some View {
        NavigationLink(value: HomeDestination.subscriptions) {
            SubscriptionsCardView(
                transactionStore: transactionStore,
                transactionsViewModel: viewModel
            )
        }
        .buttonStyle(.bounce)
        .screenPadding()
    }

    private var loansNavigationLink: some View {
        NavigationLink(value: HomeDestination.loans) {
            LoansCardView(
                loansViewModel: coordinator.loansViewModel,
                transactionsViewModel: viewModel
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

    private var subscriptionsDestination: some View {
        SubscriptionsListView(
            transactionStore: transactionStore,
            transactionsViewModel: viewModel,
            categoriesViewModel: categoriesViewModel
        )
        .environment(timeFilterManager)
    }

    // MARK: - Overlays & Backgrounds

    @ViewBuilder
    private var wallpaperBackground: some View {
        if let wallpaperImage = homeState.wallpaperImage {
            Image(uiImage: wallpaperImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all, edges: .all)
        }
    }

    // MARK: - Toolbar

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            timeFilterButton
        }
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
private struct AccountsCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView(height: 120, cornerRadius: AppRadius.md)
                        .frame(width: 200)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xs)
        }
        .accessibilityHidden(true)
    }
}

/// Generic section card skeleton: icon circle + 2 text lines.
/// Used for TransactionsSummaryCard, SubscriptionsCard, and QuickAdd skeletons.
private struct SectionCardSkeleton: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            SkeletonView(width: 36, height: 36, cornerRadius: AppRadius.circle)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 140, height: 14)
                SkeletonView(width: 100, height: 12, cornerRadius: AppRadius.xs)
            }
            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 72)
        // Fix #10: use design token instead of raw Color(.secondarySystemGroupedBackground)
        .background(AppColors.secondaryBackground)
        .clipShape(.rect(cornerRadius: AppRadius.md))
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(TimeFilterManager())
        .environment(AppCoordinator())
        .environment(HomePersistentState())
}
