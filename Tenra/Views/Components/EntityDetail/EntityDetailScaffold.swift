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
    let navigationTitle: String

    init(
        navigationTitle: String = "",
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
                hero.screenPadding()

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
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
        .toolbar {
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
                Button(role: primaryAction.role, action: primaryAction.action) {
                    actionLabel(primaryAction)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if let secondaryAction {
                Button(role: secondaryAction.role, action: secondaryAction.action) {
                    actionLabel(secondaryAction)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ cfg: ActionConfig) -> some View {
        HStack(spacing: AppSpacing.xs) {
            if let systemImage = cfg.systemImage {
                Image(systemName: systemImage)
            }
            Text(cfg.title)
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

// MARK: - Convenience overloads for optional generic slots
//
// Swift can't infer the CustomSections / HistoryOverlay generics from default
// parameters alone. These overloads let callers omit either slot cleanly by
// pinning the generic to EmptyView.

extension EntityDetailScaffold where CustomSections == EmptyView, HistoryOverlay == EmptyView {
    init(
        navigationTitle: String = "",
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
