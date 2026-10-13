//
//  AssistantReplyView.swift
//  Tenra
//
//  One assistant reply: its blocks top to bottom as the app's own cards and rows
//  (docs/plan-ai-assistant.md §3.3). Figures come from the tool results by reference
//  (AgentReplyData); lists resolve back to the app's models by id, so a transaction is a
//  `TransactionCardView`, a budget a `BudgetProgressRow`, a subscription a `SubscriptionCard`
//  and an insight an `InsightsCardView`, exactly as everywhere else in the app. A block whose
//  reference does not resolve is left out. An `open` block is a way into the app's own screen
//  (AssistantDestinationView); a `confirm` block is the draft card, where the person saves what
//  the assistant prepared (AgentDraftBook).
//

import SwiftUI

struct AssistantReplyView: View {
    let reply: AgentReply
    let results: [String: JSONValue]
    var drafts: AgentDraftBook?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ForEach(Array(reply.blocks.enumerated()), id: \.offset) { index, block in
                AssistantBlockView(block: block, results: results, drafts: drafts)
                    .cascadeIn(index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssistantBlockView: View {
    let block: AgentBlock
    let results: [String: JSONValue]
    let drafts: AgentDraftBook?

    var body: some View {
        switch block {
        case .text(let text):
            MessageBubble(text, role: .incoming)
        case .metric(let label, let source, let path, let trendPath):
            if let metric = AgentReplyData.metric(label: label, source: source, path: path, trendPath: trendPath, results: results) {
                AssistantMetricCard(metric: metric)
            }
        case .chart(let kind, let title, let source, let path):
            if let chart = AgentReplyData.chart(source: source, path: path, results: results) {
                AssistantChartCard(kind: kind, title: title, chart: chart)
            }
        case .transactions(let title, let source):
            AssistantTransactionsCard(title: title, ids: AgentReplyData.transactionIds(source: source, results: results))
        case .budgets(let source, let categoryIds):
            AssistantBudgetsList(categoryIds: AgentReplyData.budgetCategoryIds(source: source, only: categoryIds, results: results))
        case .recurring(let source):
            AssistantRecurringList(ids: AgentReplyData.recurringIds(source: source, results: results))
        case .insight(_, let insightId):
            AssistantInsightCard(insightId: insightId)
        case .open(let destination, let targetId, let label):
            if let route = AssistantRoute(destination: destination, targetId: targetId) {
                AssistantOpenLink(route: route, label: label)
            }
        case .confirm(let draftId):
            if let drafts, let draft = drafts.drafts[draftId] {
                AssistantDraftCard(book: drafts, draft: draft)
            }
        case .forecast, .unsupported:
            // Planning arrives in a later phase (plan §5).
            EmptyView()
        }
    }
}

// MARK: - Metric

private struct AssistantMetricCard: View {
    let metric: AgentReplyData.Metric

    var body: some View {
        MetricCard(title: metric.label, subtitle: "", value: value, unit: unit, trend: trend)
    }

    private var value: MetricCardValue {
        switch metric.value {
        case .amount(let amount, let currency): .amount(amount, currency: currency)
        case .percent(let percent): .text(percent.formatted(.number.precision(.fractionLength(0...1))))
        case .count(let count): .text(count.formatted(.number.precision(.fractionLength(0))))
        }
    }

    private var unit: String? {
        if case .percent = metric.value { return "%" }
        return nil
    }

    private var trend: MetricCardTrend? {
        guard let change = metric.changePercent else { return nil }
        let direction: TrendBadge.Direction = change > 0 ? .up : change < 0 ? .down : .flat
        // Spending that grows is bad news: red up, green down.
        let color: Color? = metric.isExpense
            ? (change > 0 ? AppColors.destructive : change < 0 ? AppColors.income : nil)
            : nil
        return MetricCardTrend(direction: direction, changePercent: change, color: color)
    }
}

// MARK: - Chart

private struct AssistantChartCard: View {
    @Environment(AppCoordinator.self) private var coordinator

    let kind: AgentChartKind
    let title: String
    let chart: AgentReplyData.Chart

    private static let rowLimit = 6

    var body: some View {
        AssistantCard(title: title) {
            if kind == .donut && !chart.isTimeline {
                MiniDonut(slices: DonutSlice.from(items))
                    .frame(width: AppIconSize.Tile.xxxl, height: AppIconSize.Tile.xxxl)
                    .frame(maxWidth: .infinity)
            }
            ForEach(items.prefix(Self.rowLimit)) { item in
                CategoryBreakdownRow(item: item, currency: chart.currency)
            }
        }
    }

    /// Each group as a breakdown item: a category keeps its own icon and colour, a merchant or
    /// a period takes the accent.
    private var items: [CategoryBreakdownItem] {
        let categories = coordinator.transactionStore.categories
        let total = chart.groups.reduce(0) { $0 + max($1.value, 0) }
        return chart.groups.map { group in
            let category = categories.first { $0.id == group.id }
            return CategoryBreakdownItem(
                id: group.id,
                categoryName: category?.name ?? periodLabel(group),
                amount: group.value,
                percentage: total > 0 ? group.value / total * 100 : 0,
                color: category.map { Color(hex: $0.colorHex) } ?? AppColors.accent,
                iconSource: category?.iconSource,
                subcategories: []
            )
        }
    }

    /// "2026-10" → "October 2026"; a week's Monday → "13 October"; anything else as it is.
    private func periodLabel(_ group: AgentReplyData.ChartGroup) -> String {
        guard chart.isTimeline else { return group.label }
        if group.id.count == 7, let month = FastDateParser.date(from: group.id + "-01") {
            return month.formatted(.dateTime.month(.wide).year())
        }
        if let day = FastDateParser.date(from: group.id) {
            return day.formatted(.dateTime.day().month(.wide))
        }
        return group.label
    }
}

// MARK: - Lists

private struct AssistantTransactionsCard: View {
    @Environment(AppCoordinator.self) private var coordinator

    let title: String?
    let ids: [String]

    private static let rowLimit = 8

    var body: some View {
        let store = coordinator.transactionStore
        let transactions = ids.prefix(Self.rowLimit).compactMap { store.transactionById[$0] }
        if !transactions.isEmpty {
            AssistantCard(title: title) {
                ForEach(transactions) { transaction in
                    TransactionCardView(
                        transaction: transaction,
                        currency: transaction.currency,
                        styleData: CategoryStyleHelper.cached(
                            category: transaction.category,
                            type: transaction.type,
                            customCategories: store.categories
                        ),
                        sourceAccount: transaction.accountId.flatMap { store.accountById[$0] },
                        targetAccount: transaction.targetAccountId.flatMap { store.accountById[$0] }
                    )
                }
            }
        }
    }
}

private struct AssistantBudgetsList: View {
    @Environment(AppCoordinator.self) private var coordinator

    let categoryIds: [String]

    var body: some View {
        let store = coordinator.transactionStore
        let service = CategoryBudgetService(store: store)
        VStack(spacing: AppSpacing.md) {
            ForEach(categoryIds, id: \.self) { id in
                if let category = store.categories.first(where: { $0.id == id }),
                   let progress = service.budgetProgress(for: category) {
                    BudgetProgressRow(
                        item: BudgetInsightItem(
                            id: category.id,
                            categoryName: category.name,
                            budgetAmount: progress.budgetAmount,
                            spent: progress.spent,
                            percentage: progress.percentage,
                            isOverBudget: progress.isOverBudget,
                            color: Color(hex: category.colorHex),
                            daysRemaining: daysRemaining(category, service: service),
                            projectedSpend: progress.spent,
                            iconSource: category.iconSource
                        ),
                        currency: store.baseCurrency
                    )
                }
            }
        }
    }

    private func daysRemaining(_ category: CustomCategory, service: CategoryBudgetService) -> Int {
        let calendar = Calendar.current
        let start = service.budgetPeriodStart(for: category)
        let component: Calendar.Component = switch category.budgetPeriod {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        guard let end = calendar.date(byAdding: component, value: 1, to: start) else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: end).day ?? 0)
    }
}

private struct AssistantRecurringList: View {
    @Environment(AppCoordinator.self) private var coordinator

    let ids: [String]

    private static let rowLimit = 8

    var body: some View {
        let store = coordinator.transactionStore
        let series = ids.prefix(Self.rowLimit).compactMap { id in store.recurringSeries.first { $0.id == id } }
        VStack(spacing: AppSpacing.md) {
            ForEach(series) { item in
                SubscriptionCard(
                    subscription: item,
                    nextChargeDate: store.nextChargeDate(for: item.id),
                    baseCurrency: store.baseCurrency
                )
            }
        }
    }
}

private struct AssistantInsightCard: View {
    @Environment(AppCoordinator.self) private var coordinator

    let insightId: String

    var body: some View {
        if let insight = coordinator.insightsViewModel.insights.first(where: { $0.id == insightId }) {
            InsightsCardView(insight: insight)
        }
    }
}

// MARK: - Confirm

/// A draft to save (plan §1, "do"): its operations as they will look in the history (a budget
/// as its new limit next to the old one), what Tenra guessed, Save; once saved, Undo. Nothing
/// is written before Save.
private struct AssistantDraftCard: View {
    @Environment(AppCoordinator.self) private var coordinator

    let book: AgentDraftBook
    let draft: AgentDraft

    var body: some View {
        let store = coordinator.transactionStore
        let state = book.states[draft.id] ?? .pending
        AssistantCard(title: nil) {
            ForEach(Array(draft.operations.enumerated()), id: \.offset) { index, operation in
                if let preview = Self.preview(operation, id: "\(draft.id)-\(index)") {
                    TransactionCardView(
                        transaction: preview,
                        currency: preview.currency,
                        styleData: CategoryStyleHelper.cached(
                            category: preview.category,
                            type: preview.type,
                            customCategories: store.categories
                        ),
                        sourceAccount: preview.accountId.flatMap { store.accountById[$0] },
                        targetAccount: preview.targetAccountId.flatMap { store.accountById[$0] }
                    )
                } else if case .budget(let budget) = operation {
                    budgetRows(budget, store: store)
                }
            }
            if state == .pending {
                ForEach(guesses, id: \.self) { guess in
                    InlineStatusText(message: guess, type: .warning)
                }
            }
            footer(state)
        }
        .animation(AppAnimation.smooth, value: state)
    }

    @ViewBuilder
    private func footer(_ state: AgentDraftState) -> some View {
        switch state {
        case .pending, .saving:
            DSButton(
                String(localized: "assistant.draft.save"),
                systemImage: "checkmark",
                fullWidth: true,
                isLoading: state == .saving
            ) {
                Task {
                    await book.save(draft.id)
                    if case .saved? = book.states[draft.id] { HapticManager.success() } else { HapticManager.error() }
                }
            }
        case .saved:
            HStack {
                InlineStatusText(message: String(localized: "assistant.draft.saved"), type: .success)
                Spacer()
                DSButton(String(localized: "assistant.draft.undo"), appearance: .flat, size: .small) {
                    Task { await book.undo(draft.id) }
                }
            }
        case .undone:
            InlineStatusText(message: String(localized: "assistant.draft.undone"), type: .info)
        case .failed:
            InlineStatusText(message: String(localized: "assistant.draft.failed"), type: .error)
            DSButton(String(localized: "assistant.draft.save"), systemImage: "arrow.clockwise", fullWidth: true) {
                Task { await book.save(draft.id) }
            }
        }
    }

    /// The new limit, and the one it replaces.
    @ViewBuilder
    private func budgetRows(_ budget: AgentBudgetDraft, store: TransactionStore) -> some View {
        let name = store.categories.first { $0.id == budget.categoryId }?.name ?? ""
        InfoRow(
            icon: "gauge.with.dots.needle.50percent",
            label: "\(name) · \(Self.periodName(budget.period))",
            amount: budget.amount,
            currency: store.baseCurrency
        )
        if let previous = budget.previousAmount {
            InfoRow(
                label: "\(String(localized: "assistant.draft.budgetWas")) · \(Self.periodName(budget.previousPeriod))",
                amount: previous,
                currency: store.baseCurrency
            )
        }
    }

    private static func periodName(_ period: CustomCategory.BudgetPeriod) -> String {
        switch period {
        case .weekly: String(localized: "budget.weekly")
        case .monthly: String(localized: "budget.monthly")
        case .yearly: String(localized: "yearly")
        }
    }

    /// What Tenra filled in itself, for the person to check before saving.
    private var guesses: [String] {
        let warnings = draft.operations.flatMap { operation -> [DraftWarning] in
            if case .single(let single) = operation { return single.warnings }
            return []
        }
        var lines: [String] = []
        if warnings.contains(.accountInferred) {
            lines.append(String(localized: "assistant.draft.accountGuessed"))
        }
        if warnings.contains(where: { if case .categorySubstituted = $0 { true } else { false } }) {
            lines.append(String(localized: "assistant.draft.categoryGuessed"))
        }
        return lines
    }

    /// The operation as the transaction it will become, for the row; nil for a budget.
    private static func preview(_ operation: AgentDraftOperation, id: String) -> Transaction? {
        switch operation {
        case .budget:
            return nil
        case .single(let draft):
            return Transaction(
                id: id,
                date: FastDateParser.string(from: draft.date),
                description: draft.note,
                amount: draft.amount,
                currency: draft.currency,
                convertedAmount: draft.convertedAmount,
                type: draft.type,
                category: draft.categoryName,
                accountId: draft.accountId
            )
        case .transfer(let transfer):
            return Transaction(
                id: id,
                date: FastDateParser.string(from: transfer.date),
                description: transfer.note,
                amount: transfer.amount,
                currency: transfer.currency,
                convertedAmount: transfer.conversion.convertedAmount,
                type: .internalTransfer,
                category: TransactionType.transferCategoryName,
                accountId: transfer.fromAccountId,
                targetAccountId: transfer.toAccountId,
                targetCurrency: transfer.conversion.targetCurrency,
                targetAmount: transfer.conversion.targetAmount
            )
        }
    }
}

// MARK: - Open

/// A row into one of the app's screens, pushed on the assistant's stack.
private struct AssistantOpenLink: View {
    let route: AssistantRoute
    let label: String

    var body: some View {
        NavigationLink(value: route) {
            ActionRowLabel(label, systemImage: route.systemImage)
                .padding(.horizontal, AppSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Container

/// Rows in a card under an optional header, as the insight detail lists lay them out.
private struct AssistantCard<Rows: View>: View {
    let title: String?
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let title, !title.isEmpty {
                SectionHeader(title)
            }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                rows()
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}
