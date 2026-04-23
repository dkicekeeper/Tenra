//
//  GroupedTransactionList.swift
//  Tenra
//
//  Shared date-grouped transaction list used by all entity-detail screens
//  and by LinkPaymentsView. Pure renderer — caller owns data & filtering.
//

import SwiftUI

struct GroupedTransactionList<Overlay: View>: View {
    let transactions: [Transaction]
    let displayCurrency: String?
    let accountsById: [String: Account]
    let styleHelper: (Transaction) -> CategoryStyleData
    let pageSize: Int
    let showCountBadge: Bool
    let viewModel: TransactionsViewModel?
    let categoriesViewModel: CategoriesViewModel?
    let accountsViewModel: AccountsViewModel?
    let balanceCoordinator: BalanceCoordinator?
    /// When non-nil, replaces the default row tap (open edit sheet) with the provided closure.
    /// Used by selection UIs like `LinkPaymentsView` to toggle selection on tap.
    let tapAction: ((Transaction) -> Void)?
    let rowOverlay: (Transaction) -> Overlay

    @State private var visibleLimit: Int
    @State private var cachedSections: [(date: String, displayLabel: String, transactions: [Transaction])] = []

    init(
        transactions: [Transaction],
        displayCurrency: String? = nil,
        accountsById: [String: Account],
        styleHelper: @escaping (Transaction) -> CategoryStyleData,
        pageSize: Int = 100,
        showCountBadge: Bool = true,
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        tapAction: ((Transaction) -> Void)? = nil,
        @ViewBuilder rowOverlay: @escaping (Transaction) -> Overlay
    ) {
        self.transactions = transactions
        self.displayCurrency = displayCurrency
        self.accountsById = accountsById
        self.styleHelper = styleHelper
        self.pageSize = pageSize
        self.showCountBadge = showCountBadge
        self.viewModel = viewModel
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.balanceCoordinator = balanceCoordinator
        self.tapAction = tapAction
        self.rowOverlay = rowOverlay
        self._visibleLimit = State(initialValue: pageSize)
    }

    private func rebuildSections() {
        let slice = Array(transactions.prefix(visibleLimit))
        let grouped = Dictionary(grouping: slice) { $0.date }
        cachedSections = grouped
            .sorted { $0.key > $1.key }
            .map { key, txs in
                (date: key, displayLabel: Self.formatDateKey(key), transactions: txs)
            }
    }

    private static func formatDateKey(_ isoDate: String) -> String {
        guard let date = DateFormatters.dateFormatter.date(from: isoDate) else { return isoDate }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "date.today", defaultValue: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "date.yesterday", defaultValue: "Yesterday") }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return DateFormatters.displayDateFormatter.string(from: date)
        }
        return DateFormatters.displayDateWithYearFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(String(localized: "history.section.title", defaultValue: "History"))
                    .font(AppTypography.h4)
                Spacer()
                if showCountBadge, !transactions.isEmpty {
                    Text("\(transactions.count)")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(cachedSections, id: \.date) { section in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        DateSectionHeaderView(dateKey: section.displayLabel)
                            .padding(.top, AppSpacing.sm)

                        ForEach(section.transactions) { transaction in
                            let sourceAccount = transaction.accountId.flatMap { accountsById[$0] }
                            let targetAccount = transaction.targetAccountId.flatMap { accountsById[$0] }
                            let style = styleHelper(transaction)
                            let rowCurrency = displayCurrency ?? transaction.currency

                            ZStack {
                                TransactionCard(
                                    transaction: transaction,
                                    currency: rowCurrency,
                                    styleData: style,
                                    sourceAccount: sourceAccount,
                                    targetAccount: targetAccount,
                                    viewModel: viewModel,
                                    categoriesViewModel: categoriesViewModel,
                                    accountsViewModel: accountsViewModel,
                                    balanceCoordinator: balanceCoordinator,
                                    tapAction: tapAction.map { outer in { outer(transaction) } }
                                )
                                rowOverlay(transaction)
                            }
                        }
                    }
                }

                if visibleLimit < transactions.count {
                    ProgressView()
                        .padding(.vertical, AppSpacing.md)
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            visibleLimit = min(visibleLimit + pageSize, transactions.count)
                        }
                }
            }
            .onAppear { rebuildSections() }
            .onChange(of: transactions.count) { _, _ in
                visibleLimit = pageSize
                rebuildSections()
            }
            .onChange(of: visibleLimit) { _, _ in rebuildSections() }
        }
    }
}

// MARK: - EmptyView Overlay Overload
//
// When callers don't need a per-row overlay, Swift can't infer the Overlay generic
// from the default parameter alone. This overload allows calling without the
// rowOverlay closure and pins Overlay to EmptyView.
extension GroupedTransactionList where Overlay == EmptyView {
    init(
        transactions: [Transaction],
        displayCurrency: String? = nil,
        accountsById: [String: Account],
        styleHelper: @escaping (Transaction) -> CategoryStyleData,
        pageSize: Int = 100,
        showCountBadge: Bool = true,
        viewModel: TransactionsViewModel? = nil,
        categoriesViewModel: CategoriesViewModel? = nil,
        accountsViewModel: AccountsViewModel? = nil,
        balanceCoordinator: BalanceCoordinator? = nil,
        tapAction: ((Transaction) -> Void)? = nil
    ) {
        self.init(
            transactions: transactions,
            displayCurrency: displayCurrency,
            accountsById: accountsById,
            styleHelper: styleHelper,
            pageSize: pageSize,
            showCountBadge: showCountBadge,
            viewModel: viewModel,
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            balanceCoordinator: balanceCoordinator,
            tapAction: tapAction,
            rowOverlay: { _ in EmptyView() }
        )
    }
}
