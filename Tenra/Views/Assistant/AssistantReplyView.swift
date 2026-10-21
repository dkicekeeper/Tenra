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
//  the assistant prepared (AgentDraftBook). Text blocks are Markdown, drawn as formatted text
//  on the page (AssistantText); while the reply streams, its text shows as it is written
//  (AssistantStreamingReply).
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
            AssistantText(text)
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
        case .forecast(let source):
            if let forecast = AgentReplyData.forecast(source: source, results: results) {
                AssistantForecastCard(forecast: forecast)
            }
        case .unsupported:
            EmptyView()
        }
    }
}

// MARK: - Text

/// A text block: its Markdown as headings, paragraphs, lists and notes (AgentReplyMarkdown,
/// DesignKit's ArticleBody). A long press copies it.
struct AssistantText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ArticleBody(AgentReplyMarkdown.blocks(text), spacing: AppSpacing.sm)
            .textSelection(.enabled)
    }
}

/// The reply's text while the model writes it; the finished reply takes its place, cards and all.
struct AssistantStreamingReply: View {
    let texts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                AssistantText(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
        FormSection(header: title, style: .glass) {
            if chart.isTimeline {
                timeline
            } else {
                if kind == .donut {
                    MiniDonut(slices: DonutSlice.from(items))
                        .frame(width: AppIconSize.Tile.xxxl, height: AppIconSize.Tile.xxxl)
                        .frame(maxWidth: .infinity)
                }
                ForEach(items.prefix(Self.rowLimit)) { item in
                    CategoryBreakdownRow(item: item, currency: chart.currency)
                }
            }
        }
    }

    // MARK: Timeline

    /// Periods (months, weeks) as DesignKit's trend chart: a line when the reply asks for one,
    /// bars otherwise (a donut of periods says nothing). A tap shows a period's amount.
    @ViewBuilder
    private var timeline: some View {
        if kind == .line {
            LineChart(dataPoints: timelinePoints, series: timelineSeries, valueFormat: .currency(chart.currency))
        } else {
            BarChart(dataPoints: timelinePoints, series: timelineSeries, valueFormat: .currency(chart.currency))
        }
    }

    private static let seriesId = "value"

    private var timelinePoints: [ChartValuePoint] {
        chart.groups.map { group in
            ChartValuePoint(
                label: group.id,
                axisLabel: axisLabel(group),
                title: periodLabel(group),
                values: [Self.seriesId: group.value]
            )
        }
    }

    /// The accent; green and red around zero when a period went below it (a net flow).
    private var timelineSeries: ChartSeries<ChartValuePoint> {
        let signed = chart.groups.contains { $0.value < 0 }
        return .keyed(
            Self.seriesId,
            name: title,
            coloring: signed ? .signed(positive: AppColors.income, negative: AppColors.destructive) : .solid(AppColors.accent),
            baseline: signed ? .signed : .zero
        )
    }

    /// "2026-10" → "Oct"; a week's Monday → "13.10" (the locale's order).
    private func axisLabel(_ group: AgentReplyData.ChartGroup) -> String {
        if group.id.count == 7, let month = FastDateParser.date(from: group.id + "-01") {
            return month.formatted(.dateTime.month(.abbreviated))
        }
        if let day = FastDateParser.date(from: group.id) {
            return day.formatted(.dateTime.day().month(.defaultDigits))
        }
        return group.label
    }

    /// Each group as a breakdown item: a category keeps its own icon and colour, a loan payment
    /// or deposit interest (no `CustomCategory`) the system style Insights gives them, a merchant
    /// takes the accent.
    private var items: [CategoryBreakdownItem] {
        let categories = coordinator.transactionStore.categories
        let total = chart.groups.reduce(0) { $0 + max($1.value, 0) }
        return chart.groups.map { group in
            let category = categories.first { $0.id == group.id }
            let synthetic = category == nil ? InsightsService.syntheticCategoryStyle(for: group.id) : nil
            return CategoryBreakdownItem(
                id: group.id,
                categoryName: category?.name ?? periodLabel(group),
                amount: group.value,
                percentage: total > 0 ? group.value / total * 100 : 0,
                color: category.map { Color(hex: $0.colorHex) } ?? synthetic?.color ?? AppColors.accent,
                iconSource: category?.iconSource ?? synthetic?.icon,
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
            FormSection(header: title, style: .glass) {
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

// MARK: - Forecast

/// "How much a day until payday": the allowance with what is free behind it, the balance day
/// by day under it, and what goes out before the date.
private struct AssistantForecastCard: View {
    let forecast: AgentReplyData.Forecast

    @Environment(\.amountsHidden) private var amountsHidden

    private static let obligationLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            MetricCard(
                title: String(format: String(localized: "assistant.forecast.perDay"), untilText),
                subtitle: String(
                    format: String(localized: "assistant.forecast.free"),
                    amountsHidden
                        ? Formatting.hiddenAmount(currency: forecast.currency)
                        : Formatting.formatCurrencySmart(forecast.freeAmount, currency: forecast.currency)
                ),
                value: .amount(forecast.dailyAllowance, currency: forecast.currency),
                chartPlacement: .bottom
            ) {
                Sparkline(values: forecast.balance.groups.map(\.value), markExtremes: true)
                    .accessibilityLabel(String(localized: "assistant.forecast.balance"))
            }
            if !forecast.obligations.isEmpty {
                FormSection(header: String(format: String(localized: "assistant.forecast.obligations"), untilText), style: .glass) {
                    ForEach(Array(forecast.obligations.prefix(Self.obligationLimit).enumerated()), id: \.offset) { _, obligation in
                        UniversalRow(
                            label(obligation),
                            config: .info,
                            accessory: .amount(obligation.amount, currency: forecast.currency)
                        )
                    }
                }
            }
        }
    }

    private var untilText: String {
        FastDateParser.date(from: forecast.until)?.formatted(.dateTime.day().month(.wide)) ?? forecast.until
    }

    private func label(_ obligation: AgentReplyData.Forecast.Obligation) -> String {
        let day = FastDateParser.date(from: obligation.date)?.formatted(.dateTime.day().month(.abbreviated)) ?? obligation.date
        return "\(obligation.label) · \(day)"
    }
}

// MARK: - Confirm

/// A draft to save (plan §1, "do"): its operations as they will look in the history (a budget
/// as its new limit next to the old one, a subscription as its name, frequency and first
/// charge, a fact to remember as its text, a goal as its name and target, a debt as who and
/// how much, money towards a goal or back on a debt as the amount), what Tenra guessed, Save;
/// once saved, Undo. Nothing is written before Save. Until then a tap on an income or an
/// expense opens it in the voice confirmation form (AgentDraftEditor).
private struct AssistantDraftCard: View {
    @Environment(AppCoordinator.self) private var coordinator

    let book: AgentDraftBook
    let draft: AgentDraft

    /// An operation open in the form.
    private struct Editing: Identifiable {
        let index: Int
        let operation: ParsedOperation
        var id: Int { index }
    }

    @State private var editing: Editing?
    /// Why the last edit did not apply.
    @State private var editError: String?

    var body: some View {
        let store = coordinator.transactionStore
        let state = book.states[draft.id] ?? .pending
        FormSection(style: .glass) {
            ForEach(Array(draft.operations.enumerated()), id: \.offset) { index, operation in
                if let preview = Self.preview(operation, id: "\(draft.id)-\(index)") {
                    let row = TransactionCardView(
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
                    if case .single(let single) = operation, state == .pending || state == .failed {
                        Button {
                            editError = nil
                            editing = Editing(
                                index: index,
                                operation: AgentDraftEditor.operation(from: single, subcategories: coordinator.categoriesViewModel.subcategories)
                            )
                        } label: {
                            row
                        }
                        .buttonStyle(.bounce)
                        .accessibilityHint(String(localized: "assistant.draft.editHint"))
                    } else {
                        row
                    }
                } else if case .budget(let budget) = operation {
                    budgetRows(budget, store: store)
                } else if case .recurring(let recurring) = operation {
                    recurringRow(recurring.series)
                } else if case .fact(let fact) = operation {
                    factRow(fact)
                } else if case .goal(let goal) = operation {
                    goalRow(goal, store: store)
                } else if case .goalContribution(let goalId, let contribution) = operation {
                    contributionRow(goalId: goalId, contribution)
                } else if case .debt(let debt) = operation {
                    debtRow(debt)
                } else if case .debtRepayment(let debtId, let repayment) = operation {
                    repaymentRow(debtId: debtId, repayment)
                }
            }
            if state == .pending {
                ForEach(guesses, id: \.self) { guess in
                    InlineStatusText(message: guess, type: .warning)
                }
                // A guess is what an edit fixes: say where.
                if !guesses.isEmpty, draft.operations.contains(where: { if case .single = $0 { true } else { false } }) {
                    InlineStatusText(message: String(localized: "assistant.draft.editTip"), type: .info)
                }
                if let editError {
                    InlineStatusText(message: editError, type: .error)
                }
            }
            footer(state)
        }
        .animation(AppAnimation.smooth, value: state)
        .sheet(item: $editing) { target in
            VoiceInputConfirmationView(
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel,
                parsedOperation: target.operation,
                originalText: target.operation.note,
                editsDate: true,
                onUpdate: { updated in
                    Task { await apply(updated, at: target.index) }
                }
            )
            .environment(coordinator.transactionStore)
        }
    }

    /// The form's operation, resolved again, in place of the one the assistant drafted.
    private func apply(_ operation: ParsedOperation, at index: Int) async {
        let store = coordinator.transactionStore
        let result = await AgentDraftEditor.draft(
            from: operation,
            accounts: store.accounts,
            categories: store.categories,
            subcategories: coordinator.categoriesViewModel.subcategories,
            learned: .shared,
            convert: { await CurrencyConverter.convert(amount: $0, from: $1, to: $2) }
        )
        switch result {
        case .success(let edited):
            if book.replace(draft.id, at: index, with: .single(edited)) {
                editError = nil
            }
        case .failure(let issue):
            editError = AgentDraftEditor.message(for: issue)
            HapticManager.error()
        }
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
        UniversalRow(
            "\(name) · \(Self.periodName(budget.period))",
            icon: "gauge.with.dots.needle.50percent",
            config: .info,
            accessory: .amount(budget.amount, currency: store.baseCurrency)
        )
        if let previous = budget.previousAmount {
            UniversalRow(
                "\(String(localized: "assistant.draft.budgetWas")) · \(Self.periodName(budget.previousPeriod))",
                config: .info,
                accessory: .amount(previous, currency: store.baseCurrency)
            )
        }
    }

    /// The subscription or regular payment: its name, how often, the first charge, the amount.
    private func recurringRow(_ series: RecurringSeries) -> some View {
        let first = FastDateParser.date(from: series.startDate)?.formatted(.dateTime.day().month(.abbreviated)) ?? series.startDate
        return UniversalRow(
            "\(series.description) · \(series.frequency.displayName) · \(first)",
            icon: series.kind == .subscription ? "repeat.circle" : "repeat",
            config: .info,
            accessory: .amount(NSDecimalNumber(decimal: series.amount).doubleValue, currency: series.currency)
        )
    }

    /// A fact to remember: its text, and what it replaces or that it goes.
    private func factRow(_ fact: AgentFactDraft) -> some View {
        let note: String
        if fact.text == nil {
            note = String(localized: "assistant.fact.forget")
        } else if let before = fact.replaces {
            note = String(format: String(localized: "assistant.fact.was"), before.text)
        } else {
            note = String(localized: "assistant.fact.remember")
        }
        return ItemRow(
            fact.text ?? fact.replaces?.text ?? "",
            meta: [MetaLine([.text(note)])],
            leading: .symbol(fact.text == nil ? "eraser" : "brain"),
            style: .large
        )
        .accessibilityElement(children: .combine)
    }

    /// A new goal: its name, the deadline and the account it follows, the target.
    private func goalRow(_ goal: SavingsGoal, store: TransactionStore) -> some View {
        var parts = [goal.name]
        if let deadline = goal.deadline { parts.append(DateFormatters.displayDateOmittingCurrentYear(deadline)) }
        if let accountId = goal.linkedAccountId, let account = store.accountById[accountId] { parts.append(account.name) }
        return UniversalRow(
            parts.joined(separator: " · "),
            icon: "target",
            config: .info,
            accessory: .amount(goal.targetAmount, currency: goal.currency)
        )
    }

    /// Money towards a goal: the goal and the day, the amount.
    private func contributionRow(goalId: String, _ contribution: GoalContribution) -> some View {
        let goal = coordinator.goalStore.goal(id: goalId)
        let day = DateFormatters.displayDateOmittingCurrentYear(contribution.date)
        return UniversalRow(
            "\(goal?.name ?? "") · \(day)",
            icon: "plus.circle",
            config: .info,
            accessory: .amount(contribution.amount, currency: goal?.currency ?? "")
        )
    }

    /// A new debt: who, which way and by when, the amount.
    private func debtRow(_ debt: PersonalDebt) -> some View {
        var parts = [
            debt.person,
            debt.direction == .owedToMe ? String(localized: "debt.section.owedToMe") : String(localized: "debt.section.iOwe"),
        ]
        if let due = debt.dueDate { parts.append(DateFormatters.displayDateOmittingCurrentYear(due)) }
        return UniversalRow(
            parts.joined(separator: " · "),
            icon: debt.direction == .owedToMe ? "arrow.down.left.circle" : "arrow.up.right.circle",
            config: .info,
            accessory: .amount(debt.amount, currency: debt.currency)
        )
    }

    /// Money back on a debt: who and the day, the amount.
    private func repaymentRow(debtId: String, _ repayment: DebtRepayment) -> some View {
        let debt = coordinator.debtStore.debt(id: debtId)
        let day = DateFormatters.displayDateOmittingCurrentYear(repayment.date)
        return UniversalRow(
            "\(debt?.person ?? "") · \(day)",
            icon: "arrow.uturn.down",
            config: .info,
            accessory: .amount(repayment.amount, currency: debt?.currency ?? "")
        )
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
        let recurringGuessed = draft.operations.contains { operation in
            if case .recurring(let recurring) = operation { return recurring.accountGuessed }
            return false
        }
        var lines: [String] = []
        if warnings.contains(.accountInferred) || recurringGuessed {
            lines.append(String(localized: "assistant.draft.accountGuessed"))
        }
        if warnings.contains(where: { if case .categorySubstituted = $0 { true } else { false } }) {
            lines.append(String(localized: "assistant.draft.categoryGuessed"))
        }
        return lines
    }

    /// The operation as the transaction it will become, for the row; nil for a budget, a
    /// recurring payment, a fact, a goal or a debt, which have rows of their own.
    private static func preview(_ operation: AgentDraftOperation, id: String) -> Transaction? {
        switch operation {
        case .budget, .recurring, .fact, .goal, .goalContribution, .debt, .debtRepayment:
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

/// A row into one of the app's screens, pushed on the assistant's stack: a standard row (it
/// pads itself) in a card, in the accent, with the chevron of a push outside a List.
private struct AssistantOpenLink: View {
    let route: AssistantRoute
    let label: String

    var body: some View {
        NavigationLink(value: route) {
            UniversalRow(
                config: .standard,
                leadingIcon: .sfSymbol(route.systemImage, color: AppColors.accent, size: AppIconSize.lg),
                title: label,
                titleColor: AppColors.accent
            ) {
                DisclosureChevron()
            }
            .contentShape(Rectangle())
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}
