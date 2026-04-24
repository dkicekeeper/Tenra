//
//  EntityDetailScaffold.swift
//  Tenra
//
//  Common container for Subscription / Account / Category / Deposit / Loan detail screens.
//  Layout: Hero -> Actions -> Info rows -> Custom sections -> History.
//  Caller provides the hero, custom sections, and toolbar menu content via @ViewBuilder slots.
//

import SwiftUI

struct EntityDetailScaffold<Hero: View, CustomSections: View, MenuContent: View, HistoryOverlay: View>: View {
    let hero: Hero
    let primaryAction: ActionConfig?
    let secondaryAction: ActionConfig?
    let infoRows: [InfoRowConfig]
    let customSections: CustomSections
    let transactions: [Transaction]
    let historyCurrency: String?
    let accountsById: [String: Account]
    let styleHelper: (Transaction) -> CategoryStyleData
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel?
    let balanceCoordinator: BalanceCoordinator?
    let historyRowOverlay: (Transaction) -> HistoryOverlay
    let toolbarMenu: MenuContent
    /// Title shown in the nav bar AFTER the hero scrolls out of view.
    let navigationTitle: String
    /// Optional subtitle shown under `navigationTitle` in the nav bar once the hero scrolls out.
    let navigationSubtitle: String?

    /// Tracks whether the hero has scrolled past the nav bar. Drives the inline
    /// title/subtitle fade-in inside `.toolbar(.principal)`.
    @State private var isNavTitleVisible: Bool = false

    init(
        navigationTitle: String = "",
        navigationSubtitle: String? = nil,
        primaryAction: ActionConfig? = nil,
        secondaryAction: ActionConfig? = nil,
        infoRows: [InfoRowConfig] = [],
        transactions: [Transaction] = [],
        historyCurrency: String? = nil,
        accountsById: [String: Account] = [:],
        styleHelper: @escaping (Transaction) -> CategoryStyleData = { _ in
            CategoryStyleData.fallback
        },
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder customSections: () -> CustomSections,
        @ViewBuilder historyRowOverlay: @escaping (Transaction) -> HistoryOverlay,
        @ViewBuilder toolbarMenu: () -> MenuContent
    ) {
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.infoRows = infoRows
        self.hero = hero()
        self.customSections = customSections()
        self.transactions = transactions
        self.historyCurrency = historyCurrency
        self.accountsById = accountsById
        self.styleHelper = styleHelper
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.balanceCoordinator = balanceCoordinator
        self.historyRowOverlay = historyRowOverlay
        self.toolbarMenu = toolbarMenu()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                hero
                    .screenPadding()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HeroMaxYPreferenceKey.self,
                                value: proxy.frame(in: .named(entityDetailScrollSpace)).maxY
                            )
                        }
                    )

                if primaryAction != nil || secondaryAction != nil {
                    actionsBar.screenPadding()
                }

                if !infoRows.isEmpty {
                    infoRowsCard.screenPadding()
                }

                customSections

                if !transactions.isEmpty {
                    GroupedTransactionList(
                        transactions: transactions,
                        displayCurrency: historyCurrency,
                        accountsById: accountsById,
                        styleHelper: styleHelper,
                        viewModel: viewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel,
                        balanceCoordinator: balanceCoordinator,
                        rowOverlay: historyRowOverlay
                    )
                    .screenPadding()
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .coordinateSpace(.named(entityDetailScrollSpace))
        .onPreferenceChange(HeroMaxYPreferenceKey.self) { maxY in
            let shouldShow = maxY < entityDetailNavTitleThreshold
            guard shouldShow != isNavTitleVisible else { return }
            withAnimation(.smooth(duration: 0.2)) {
                isNavTitleVisible = shouldShow
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isNavTitleVisible, !navigationTitle.isEmpty {
                    VStack(spacing: 2) {
                        Text(navigationTitle)
                            .font(AppTypography.bodyEmphasis)
                            .lineLimit(1)
                        if let navigationSubtitle, !navigationSubtitle.isEmpty {
                            Text(navigationSubtitle)
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .transition(.opacity)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    toolbarMenu
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }


    @ViewBuilder
    private var actionsBar: some View {
        HStack(spacing: AppSpacing.md) {
            if let primaryAction {
                EntityActionButton(
                    title: primaryAction.title,
                    systemImage: primaryAction.systemImage,
                    role: primaryAction.role,
                    action: primaryAction.action
                )
            }
            if let secondaryAction {
                EntityActionButton(
                    title: secondaryAction.title,
                    systemImage: secondaryAction.systemImage,
                    role: secondaryAction.role,
                    action: secondaryAction.action
                )
            }
        }
    }

    @ViewBuilder
    private var infoRowsCard: some View {
        VStack(spacing: 0) {
            ForEach(infoRows) { row in
                UniversalRow(
                    config: .info,
                    leadingIcon: row.icon.map {
                        .sfSymbol($0, color: row.iconColor, size: AppIconSize.lg)
                    }
                ) {
                    HStack {
                        Text(row.label)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(row.value)
                            .font(AppTypography.bodyEmphasis)
                    }
                } trailing: {
                    row.trailing ?? AnyView(EmptyView())
                }
                if row.id != infoRows.last?.id {
                    Divider().padding(.leading, AppSpacing.lg)
                }
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

// MARK: - Scroll Tracking

/// Named coordinate space for the scaffold's ScrollView — hero measures its bottom here.
private let entityDetailScrollSpace = "entityDetailScroll"
/// When hero's `maxY` in scroll space falls below this value, the inline nav title fades in.
/// ~40pt accounts for the top safe area / nav bar so the title replaces the hero as it exits.
private let entityDetailNavTitleThreshold: CGFloat = 40

private struct HeroMaxYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Convenience overloads for optional generic slots
//
// Swift can't infer the CustomSections / HistoryOverlay generics from default
// parameters alone. These overloads let callers omit either slot cleanly by
// pinning the generic to EmptyView.

extension EntityDetailScaffold where CustomSections == EmptyView, HistoryOverlay == EmptyView {
    init(
        navigationTitle: String = "",
        navigationSubtitle: String? = nil,
        primaryAction: ActionConfig? = nil,
        secondaryAction: ActionConfig? = nil,
        infoRows: [InfoRowConfig] = [],
        transactions: [Transaction] = [],
        historyCurrency: String? = nil,
        accountsById: [String: Account] = [:],
        styleHelper: @escaping (Transaction) -> CategoryStyleData = { _ in
            CategoryStyleData.fallback
        },
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder toolbarMenu: () -> MenuContent
    ) {
        self.init(
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            infoRows: infoRows,
            transactions: transactions,
            historyCurrency: historyCurrency,
            accountsById: accountsById,
            styleHelper: styleHelper,
            viewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: balanceCoordinator,
            hero: hero,
            customSections: { EmptyView() },
            historyRowOverlay: { _ in EmptyView() },
            toolbarMenu: toolbarMenu
        )
    }
}

extension EntityDetailScaffold where CustomSections == EmptyView {
    init(
        navigationTitle: String = "",
        navigationSubtitle: String? = nil,
        primaryAction: ActionConfig? = nil,
        secondaryAction: ActionConfig? = nil,
        infoRows: [InfoRowConfig] = [],
        transactions: [Transaction] = [],
        historyCurrency: String? = nil,
        accountsById: [String: Account] = [:],
        styleHelper: @escaping (Transaction) -> CategoryStyleData = { _ in
            CategoryStyleData.fallback
        },
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder historyRowOverlay: @escaping (Transaction) -> HistoryOverlay,
        @ViewBuilder toolbarMenu: () -> MenuContent
    ) {
        self.init(
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            infoRows: infoRows,
            transactions: transactions,
            historyCurrency: historyCurrency,
            accountsById: accountsById,
            styleHelper: styleHelper,
            viewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: balanceCoordinator,
            hero: hero,
            customSections: { EmptyView() },
            historyRowOverlay: historyRowOverlay,
            toolbarMenu: toolbarMenu
        )
    }
}

extension EntityDetailScaffold where HistoryOverlay == EmptyView {
    init(
        navigationTitle: String = "",
        navigationSubtitle: String? = nil,
        primaryAction: ActionConfig? = nil,
        secondaryAction: ActionConfig? = nil,
        infoRows: [InfoRowConfig] = [],
        transactions: [Transaction] = [],
        historyCurrency: String? = nil,
        accountsById: [String: Account] = [:],
        styleHelper: @escaping (Transaction) -> CategoryStyleData = { _ in
            CategoryStyleData.fallback
        },
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder customSections: () -> CustomSections,
        @ViewBuilder toolbarMenu: () -> MenuContent
    ) {
        self.init(
            navigationTitle: navigationTitle,
            navigationSubtitle: navigationSubtitle,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            infoRows: infoRows,
            transactions: transactions,
            historyCurrency: historyCurrency,
            accountsById: accountsById,
            styleHelper: styleHelper,
            viewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: balanceCoordinator,
            hero: hero,
            customSections: customSections,
            historyRowOverlay: { _ in EmptyView() },
            toolbarMenu: toolbarMenu
        )
    }
}


// MARK: - Previews

#Preview("EntityDetailScaffold") {
    let coordinator = AppCoordinator()

    NavigationStack {
        EntityDetailScaffold(
            navigationTitle: "Sample Entity",
            primaryAction: ActionConfig(title: "Add", systemImage: "plus") {},
            secondaryAction: ActionConfig(title: "Edit", systemImage: "pencil") {},
            infoRows: [
                InfoRowConfig(icon: "calendar", label: "Created", value: "Jan 1, 2026"),
                InfoRowConfig(icon: "number", label: "Transactions", value: "42"),
                InfoRowConfig(icon: "arrow.up.circle", label: "Income", value: "250 000 ₸", iconColor: .green),
                InfoRowConfig(icon: "arrow.down.circle", label: "Expense", value: "80 000 ₸", iconColor: .red)
            ],
            transactions: [],
            historyCurrency: "KZT",
            viewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            balanceCoordinator: coordinator.balanceCoordinator,
            hero: {
                HeroSection(
                    icon: .sfSymbol("star.fill"),
                    title: "Sample Entity",
                    primaryAmount: 170_000,
                    primaryCurrency: "KZT"
                )
            },
            toolbarMenu: {
                Button("Delete", role: .destructive) {}
            }
        )
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}
