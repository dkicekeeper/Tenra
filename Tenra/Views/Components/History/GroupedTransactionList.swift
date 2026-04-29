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
    /// When non-nil, overrides `displayCurrency` for the section-header daily total currency.
    /// Used in mixed-currency contexts (LinkPaymentsView) to render the day total in the
    /// app's base currency rather than the entity's display currency.
    let summaryCurrencyOverride: String?
    /// When non-nil, replaces the default `tx.convertedAmount ?? tx.amount` summation in
    /// the section header. Should return the per-transaction amount in `summaryCurrencyOverride`.
    let summaryAmountFor: ((Transaction) -> Double)?
    let rowOverlay: (Transaction) -> Overlay

    @State private var visibleLimit: Int
    @State private var cachedSections: [DaySection] = []

    private struct DaySection: Identifiable {
        let date: String
        let displayLabel: String
        let transactions: [Transaction]
        let dayExpenseTotal: Double
        var id: String { date }
    }

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
        summaryCurrencyOverride: String? = nil,
        summaryAmountFor: ((Transaction) -> Double)? = nil,
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
        self.summaryCurrencyOverride = summaryCurrencyOverride
        self.summaryAmountFor = summaryAmountFor
        self.rowOverlay = rowOverlay
        self._visibleLimit = State(initialValue: pageSize)
    }

    private func rebuildSections() {
        let slice = Array(transactions.prefix(visibleLimit))
        let grouped = Dictionary(grouping: slice) { $0.date }
        let amountFor = summaryAmountFor
        cachedSections = grouped
            .sorted { $0.key > $1.key }
            .map { key, txs in
                let expenseTotal = txs.reduce(0.0) { acc, tx in
                    guard tx.type == .expense else { return acc }
                    if let amountFor {
                        return acc + amountFor(tx)
                    }
                    return acc + (tx.convertedAmount ?? tx.amount)
                }
                return DaySection(
                    date: key,
                    displayLabel: Self.formatDateKey(key),
                    transactions: txs,
                    dayExpenseTotal: expenseTotal
                )
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
                        .font(AppTypography.h4)
                        .foregroundStyle(.secondary)
                }
            }

            if transactions.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: String(localized: "emptyState.noTransactions", defaultValue: "No transactions"),
                    description: String(localized: "emptyState.startTracking", defaultValue: "Start tracking to see your activity here")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xxl)
            } else {
                transactionsList
            }
        }
    }

    @ViewBuilder
    private var transactionsList: some View {
        LazyVStack(spacing: AppSpacing.md, pinnedViews: []) {
                ForEach(cachedSections) { section in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            SectionHeaderView(section.displayLabel)
                            Spacer()
                            if section.dayExpenseTotal > 0,
                               let headerCurrency = summaryCurrencyOverride ?? displayCurrency {
                                FormattedAmountText(
                                    amount: section.dayExpenseTotal,
                                    currency: headerCurrency,
                                    prefix: "-",
                                    fontSize: AppTypography.bodySmall,
                                    fontWeight: .semibold,
                                    color: .gray
                                )
                            }
                        }
//                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.sm)

                        ForEach(Array(section.transactions.enumerated()), id: \.element.id) { index, transaction in
                            let sourceAccount = transaction.accountId.flatMap { accountsById[$0] }
                            let targetAccount = transaction.targetAccountId.flatMap { accountsById[$0] }
                            let style = styleHelper(transaction)
                            let rowCurrency = displayCurrency ?? transaction.currency
                            let linkedSubs = categoriesViewModel?.getSubcategoriesForTransaction(transaction.id) ?? []

                            // Inline HStack (not ZStack overlay) so the rowOverlay accessory
                            // sits beside the card's amount instead of stacking on top of it.
                            // For backward compatibility, callers that don't supply a real
                            // accessory pass `EmptyView()` — produces no visual artifact.
                            if let tapAction {
                                HStack(spacing: 0) {
                                    TransactionCardView(
                                        transaction: transaction,
                                        currency: rowCurrency,
                                        styleData: style,
                                        sourceAccount: sourceAccount,
                                        targetAccount: targetAccount,
                                        linkedSubcategories: linkedSubs
                                    )
                                    rowOverlay(transaction)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { tapAction(transaction) }
                            } else {
                                HStack(spacing: 0) {
                                    TransactionCard(
                                        transaction: transaction,
                                        currency: rowCurrency,
                                        styleData: style,
                                        sourceAccount: sourceAccount,
                                        targetAccount: targetAccount,
                                        viewModel: viewModel,
                                        categoriesViewModel: categoriesViewModel,
                                        accountsViewModel: accountsViewModel,
                                        balanceCoordinator: balanceCoordinator
                                    )
                                    rowOverlay(transaction)
                                }
                            }

                            if index < section.transactions.count - 1 {
                                Divider()
                                    .padding(.leading, AppIconSize.xxl + AppSpacing.md)
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
            // `.task(id: transactions.count)` replaces `.onAppear`: prevents re-fire on
            // back-navigation when the count is unchanged. SwiftUI cancels the previous task
            // automatically. visibleLimit reset is handled here as well.
            .task(id: transactions.count) {
                visibleLimit = pageSize
                rebuildSections()
            }
            .onChange(of: visibleLimit) { _, _ in rebuildSections() }
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
        tapAction: ((Transaction) -> Void)? = nil,
        summaryCurrencyOverride: String? = nil,
        summaryAmountFor: ((Transaction) -> Double)? = nil
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
            summaryCurrencyOverride: summaryCurrencyOverride,
            summaryAmountFor: summaryAmountFor,
            rowOverlay: { _ in EmptyView() }
        )
    }
}


// MARK: - Previews

private enum GroupedTransactionListPreviewFactory {
    static func makeSampleData() -> (transactions: [Transaction], accountsById: [String: Account]) {
        let cash = Account(id: "acc-cash", name: "Cash", currency: "KZT",
                           iconSource: .sfSymbol("banknote"), balance: 250_000)
        let card = Account(id: "acc-card", name: "Kaspi Gold", currency: "KZT",
                           iconSource: .sfSymbol("creditcard.fill"), balance: 540_000)

        let formatter = DateFormatters.dateFormatter
        let cal = Calendar.current
        let today = Date()
        func iso(_ offsetDays: Int) -> String {
            formatter.string(from: cal.date(byAdding: .day, value: offsetDays, to: today) ?? today)
        }

        let transactions: [Transaction] = [
            Transaction(id: "t1", date: iso(0), description: "Magnum",
                        amount: 12_500, currency: "KZT", type: .expense,
                        category: "Groceries", accountId: card.id),
            Transaction(id: "t2", date: iso(0), description: "Coffee",
                        amount: 1_800, currency: "KZT", type: .expense,
                        category: "Cafes", accountId: cash.id),
            Transaction(id: "t3", date: iso(-1), description: "Salary",
                        amount: 450_000, currency: "KZT", type: .income,
                        category: "Salary", accountId: card.id),
            Transaction(id: "t4", date: iso(-1), description: "Taxi",
                        amount: 2_200, currency: "KZT", type: .expense,
                        category: "Transport", accountId: card.id),
            Transaction(id: "t5", date: iso(-3), description: "Pharmacy",
                        amount: 4_300, currency: "KZT", type: .expense,
                        category: "Health", accountId: cash.id),
            Transaction(id: "t6", date: iso(-7), description: "Transfer to Cash",
                        amount: 50_000, currency: "KZT", type: .internalTransfer,
                        category: "Transfer", accountId: card.id, targetAccountId: cash.id,
                        targetCurrency: "KZT", targetAmount: 50_000)
        ]

        return (transactions, [cash.id: cash, card.id: card])
    }
}

#Preview("GroupedTransactionList") {
    let coordinator = AppCoordinator()
    let sample = GroupedTransactionListPreviewFactory.makeSampleData()

    NavigationStack {
        ScrollView {
            GroupedTransactionList(
                transactions: sample.transactions,
                displayCurrency: "KZT",
                accountsById: sample.accountsById,
                styleHelper: { _ in CategoryStyleData.fallback },
                viewModel: coordinator.transactionsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                balanceCoordinator: coordinator.balanceCoordinator
            )
            .padding()
        }
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}

#Preview("GroupedTransactionList — Empty") {
    let coordinator = AppCoordinator()

    NavigationStack {
        ScrollView {
            GroupedTransactionList(
                transactions: [],
                displayCurrency: "KZT",
                accountsById: [:],
                styleHelper: { _ in CategoryStyleData.fallback }
            )
            .padding()
        }
        .environment(coordinator)
        .environment(coordinator.transactionStore)
        .environment(TimeFilterManager())
    }
}
