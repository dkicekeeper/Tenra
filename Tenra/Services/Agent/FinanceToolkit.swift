//
//  FinanceToolkit.swift
//  Tenra
//
//  Executes the assistant's tools on the phone (docs/plan-ai-assistant.md §3.1). The cloud
//  model never sees the database, only the results of the tools it asks for. Tool names and
//  input shapes are the contract in server/assistant/src/tools.ts.
//
//  Read tools: spending summary, period comparison, search, accounts, budgets, recurring
//  payments, insights. Heavy walks over the transactions run off the main actor on a snapshot.
//  `draft_transactions` and `draft_budget` file drafts (AgentDraftBook) that the person saves
//  on the confirm card. Planning (`forecast_balance`) and `draft_recurring` land later and
//  answer "not available".
//

import Foundation

final class FinanceToolkit: AgentToolExecuting {
    private let store: TransactionStore
    private weak var insights: InsightsViewModel?
    private let drafts: AgentDraftBook?
    private let learned: VoiceLearningStore
    private let suggestAccount: ((String) -> String?)?
    private let now: () -> Date
    private let calendar: Calendar

    /// - Parameters:
    ///   - drafts: where `draft_transactions` files its drafts; without it drafting answers
    ///     "not available".
    ///   - learned: the accounts the person confirmed per category in the voice flow.
    ///   - suggestAccount: the account the history suggests for a category (by name), as the
    ///     add-expense screen ranks them.
    init(
        store: TransactionStore,
        insights: InsightsViewModel? = nil,
        drafts: AgentDraftBook? = nil,
        learned: VoiceLearningStore? = nil,
        suggestAccount: ((String) -> String?)? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.insights = insights
        self.drafts = drafts
        self.learned = learned ?? .shared
        self.suggestAccount = suggestAccount
        self.now = now
        self.calendar = calendar
    }

    static let laterPhaseTools: Set<String> = ["forecast_balance", "draft_recurring"]

    func execute(name: String, input: JSONValue) async -> AgentToolOutput {
        do {
            switch name {
            case "get_spending_summary": return .success(try await spendingSummary(input))
            case "compare_periods": return .success(try await comparePeriods(input))
            case "search_transactions": return .success(try await searchTransactions(input))
            case "get_accounts": return .success(accounts())
            case "get_budgets": return .success(budgets())
            case "list_recurring": return .success(try recurring(input))
            case "get_insights": return .success(insightsResult())
            case "draft_transactions": return try await draftTransactions(input)
            case "draft_budget": return try draftBudget(input)
            case _ where Self.laterPhaseTools.contains(name):
                return .failure(Self.notYet(name))
            default:
                return .failure("Unknown tool \(name).")
            }
        } catch let error as FinanceToolError {
            return .failure(error.message)
        } catch {
            return .failure("Invalid input for \(name): \(error.localizedDescription)")
        }
    }

    private static func notYet(_ name: String) -> String {
        "\(name) is not available in this version of Tenra yet. Tell the user it is coming soon."
    }

    // MARK: - Snapshot

    private func makeSnapshot() -> FinanceSnapshot {
        var idByName: [String: String] = [:]
        var nameById: [String: String] = [:]
        for category in store.categories {
            nameById[category.id] = category.name
            if idByName[category.name] == nil { idByName[category.name] = category.id }
        }
        let moment = now()
        return FinanceSnapshot(
            transactions: store.transactions,
            baseCurrency: store.baseCurrency,
            now: moment,
            today: FastDateParser.string(from: moment),
            categoryIdByName: idByName,
            categoryNameById: nameById,
            accountNameById: Dictionary(store.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        )
    }

    // MARK: - Inputs

    private struct SpendingInput: Decodable {
        let from: String
        let to: String
        let type: String
        let categoryIds: [String]?
        let accountIds: [String]?
        let groupBy: String?

        enum CodingKeys: String, CodingKey {
            case from, to, type
            case categoryIds = "category_ids"
            case accountIds = "account_ids"
            case groupBy = "group_by"
        }
    }

    private struct PeriodInput: Decodable {
        let from: String
        let to: String
    }

    private struct CompareInput: Decodable {
        let type: String
        let current: PeriodInput
        let previous: PeriodInput
        let groupBy: String?

        enum CodingKeys: String, CodingKey {
            case type, current, previous
            case groupBy = "group_by"
        }
    }

    private struct SearchInput: Decodable {
        let query: String?
        let from: String?
        let to: String?
        let type: String?
        let categoryIds: [String]?
        let accountIds: [String]?
        let minAmount: Double?
        let maxAmount: Double?
        let sort: String?
        let limit: Int?

        enum CodingKeys: String, CodingKey {
            case query, from, to, type, sort, limit
            case categoryIds = "category_ids"
            case accountIds = "account_ids"
            case minAmount = "min_amount"
            case maxAmount = "max_amount"
        }
    }

    private struct RecurringInput: Decodable {
        let kind: String?
        let activeOnly: Bool?

        enum CodingKeys: String, CodingKey {
            case kind
            case activeOnly = "active_only"
        }
    }

    private func parseKind(_ raw: String) throws -> FinanceToolkitCompute.Kind {
        guard let kind = FinanceToolkitCompute.Kind(rawValue: raw) else {
            throw FinanceToolError(message: "type must be expense or income.")
        }
        return kind
    }

    // MARK: - Read tools

    private func spendingSummary(_ input: JSONValue) async throws -> JSONValue {
        let args = try input.decoded(as: SpendingInput.self)
        let period = try FinanceToolkitCompute.Period(from: args.from, to: args.to)
        let kind = try parseKind(args.type)
        let snapshot = makeSnapshot()
        let categoryIds = args.categoryIds, accountIds = args.accountIds, groupBy = args.groupBy ?? "none"
        return try await Task.detached(priority: .userInitiated) {
            try FinanceToolkitCompute.spendingSummary(snapshot, period: period, kind: kind, categoryIds: categoryIds, accountIds: accountIds, groupBy: groupBy)
        }.value
    }

    private func comparePeriods(_ input: JSONValue) async throws -> JSONValue {
        let args = try input.decoded(as: CompareInput.self)
        let current = try FinanceToolkitCompute.Period(from: args.current.from, to: args.current.to)
        let previous = try FinanceToolkitCompute.Period(from: args.previous.from, to: args.previous.to)
        let kind = try parseKind(args.type)
        let snapshot = makeSnapshot()
        let groupBy = args.groupBy ?? "none"
        return try await Task.detached(priority: .userInitiated) {
            try FinanceToolkitCompute.comparePeriods(snapshot, current: current, previous: previous, kind: kind, groupBy: groupBy)
        }.value
    }

    private func searchTransactions(_ input: JSONValue) async throws -> JSONValue {
        let args = try input.decoded(as: SearchInput.self)
        var query = FinanceToolkitCompute.SearchQuery()
        query.text = args.query
        if args.from != nil || args.to != nil {
            query.period = try FinanceToolkitCompute.Period(from: args.from ?? "1970-01-01", to: args.to ?? FastDateParser.string(from: now()))
        }
        query.type = args.type ?? "any"
        query.categoryIds = args.categoryIds
        query.accountIds = args.accountIds
        query.minAmount = args.minAmount
        query.maxAmount = args.maxAmount
        query.largestFirst = args.sort == "largest"
        query.limit = args.limit ?? 20
        let snapshot = makeSnapshot()
        let finalQuery = query
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.search(snapshot, finalQuery)
        }.value
    }

    private func accounts() -> JSONValue {
        let base = store.baseCurrency
        let rates = RateSnapshot()
        let balances = store.balanceCoordinator.balances
        var total = 0.0
        var rows: [JSONValue] = []
        for account in store.accounts {
            let balance = balances[account.id] ?? account.balance
            let inBase: Double? = account.currency == base ? balance : rates.convert(balance, from: account.currency, to: base)
            let counted = !account.isLoan && account.includeInBalance
            if counted, let inBase { total += inBase }
            var row: [String: JSONValue] = [
                "id": .string(account.id),
                "name": .string(account.name),
                "kind": .string(account.isLoan ? "loan" : account.isDeposit ? "deposit" : "regular"),
                "currency": .string(account.currency),
                "balance": .number(FinanceToolkitCompute.round2(balance)),
                "balance_base": inBase.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
                "counted_in_total": .bool(counted),
            ]
            if let loan = account.loanInfo {
                row["remaining_principal"] = .number(FinanceToolkitCompute.round2(NSDecimalNumber(decimal: loan.remainingPrincipal).doubleValue))
            }
            rows.append(.object(row))
        }
        return ["currency": .string(base), "total_base": .number(FinanceToolkitCompute.round2(total)), "accounts": .array(rows)]
    }

    private func budgets() -> JSONValue {
        let service = CategoryBudgetService(store: store)
        let today = calendar.startOfDay(for: now())
        var rows: [JSONValue] = []
        for category in store.categories where category.type == .expense && category.budgetAmount != nil {
            guard let progress = service.budgetProgress(for: category) else { continue }
            let start = service.budgetPeriodStart(for: category)
            let component: Calendar.Component = switch category.budgetPeriod {
            case .weekly: .weekOfYear
            case .monthly: .month
            case .yearly: .year
            }
            let end = calendar.date(byAdding: component, value: 1, to: start)
            let daysLeft = end.flatMap { calendar.dateComponents([.day], from: today, to: $0).day }.map { max(0, $0) }
            rows.append([
                "category_id": .string(category.id),
                "category": .string(category.name),
                "period": .string(category.budgetPeriod.rawValue),
                "period_start": .string(FastDateParser.string(from: start)),
                "limit": .number(FinanceToolkitCompute.round2(progress.budgetAmount)),
                "spent": .number(FinanceToolkitCompute.round2(progress.spent)),
                "remaining": .number(FinanceToolkitCompute.round2(progress.remaining)),
                "percent": .number(FinanceToolkitCompute.round2(progress.percentage)),
                "over_budget": .bool(progress.isOverBudget),
                "days_left": daysLeft.map { JSONValue.number(Double($0)) } ?? .null,
            ])
        }
        return ["currency": .string(store.baseCurrency), "budgets": .array(rows)]
    }

    private func recurring(_ input: JSONValue) throws -> JSONValue {
        let args = try input.decoded(as: RecurringInput.self)
        let onlySubscriptions = args.kind == "subscription"
        let activeOnly = args.activeOnly ?? true
        let base = store.baseCurrency
        let rates = RateSnapshot()
        let today = now()
        let typeByName = Dictionary(store.categories.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        let accountNames = Dictionary(store.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var monthlyTotal = 0.0
        var rows: [JSONValue] = []
        for series in store.recurringSeries {
            if onlySubscriptions && !series.isSubscription { continue }
            if activeOnly && !series.isActive { continue }
            let amount = NSDecimalNumber(decimal: series.amount).doubleValue
            let isIncome = typeByName[series.category] == .income
            let next: Date? = series.isSubscription
                ? store.nextChargeDate(for: series.id)
                : FastDateParser.date(from: series.startDate).flatMap {
                    RecurringDateMath.firstOccurrence(after: today, start: $0, frequency: series.frequency, calendar: calendar)
                }
            if series.isSubscription, series.isActive, !isIncome {
                let monthly = amount * Self.monthlyFactor(series.frequency)
                monthlyTotal += series.currency == base ? monthly : (rates.convert(monthly, from: series.currency, to: base) ?? 0)
            }
            rows.append([
                "id": .string(series.id),
                "name": .string(series.description.isEmpty ? series.category : series.description),
                "kind": .string(series.isSubscription ? "subscription" : "regular"),
                "type": .string(isIncome ? "income" : "expense"),
                "amount": .number(FinanceToolkitCompute.round2(amount)),
                "currency": .string(series.currency),
                "frequency": .string(series.frequency.rawValue),
                "next_date": next.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "category": .string(series.category),
                "account": series.accountId.flatMap { accountNames[$0] }.map(JSONValue.string) ?? .null,
                "active": .bool(series.isActive),
            ])
        }
        return ["currency": .string(base), "items": .array(rows), "subscriptions_monthly_total_base": .number(FinanceToolkitCompute.round2(monthlyTotal))]
    }

    static func monthlyFactor(_ frequency: RecurringFrequency) -> Double {
        switch frequency {
        case .daily: return 30.4
        case .weekly: return 52.0 / 12.0
        case .monthly: return 1
        case .quarterly: return 1.0 / 3.0
        case .yearly: return 1.0 / 12.0
        }
    }

    private func insightsResult() -> JSONValue {
        guard let insights else { return ["available": false] }
        var result: [String: JSONValue] = [:]
        if let health = insights.healthScore {
            result["health_score"] = [
                "score": .number(Double(health.score)),
                "grade": .string(health.grade),
                "components": [
                    "savings": .number(Double(health.savingsRateScore)),
                    "budgets": .number(Double(health.budgetAdherenceScore)),
                    "recurring": .number(Double(health.recurringRatioScore)),
                    "cushion": .number(Double(health.emergencyFundScore)),
                    "cashflow": .number(Double(health.cashflowScore)),
                ],
            ]
        }
        result["insights"] = .array(insights.insights.prefix(20).map { insight in
            [
                "id": .string(insight.id),
                "type": .string(String(describing: insight.type)),
                "title": .string(insight.title),
                "subtitle": .string(insight.subtitle),
                "severity": .string(String(describing: insight.severity)),
                "value": .number(insight.metric.value),
                "unit": insight.metric.unit.map(JSONValue.string) ?? .null,
            ]
        })
        let available = insights.healthScore != nil || !insights.insights.isEmpty
        result["available"] = .bool(available)
        if !available { result["note"] = "Insights are still being computed. Answer from the other tools." }
        return .object(result)
    }

    // MARK: - Drafts

    private struct DraftItemInput: Decodable {
        let type: String
        let amount: Double
        let currency: String?
        let category: String?
        let account: String?
        let toAccount: String?
        let date: String?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case type, amount, currency, category, account, date, note
            case toAccount = "to_account"
        }
    }

    private struct DraftTransactionsInput: Decodable {
        let items: [DraftItemInput]
    }

    /// `draft_transactions`: resolves each operation the way the voice and Siri paths do
    /// (`TransactionDraftService.makeDraft`) and files the ones that resolved as one draft.
    /// An operation that cannot be drafted (no amount, no account, no exchange rate) comes
    /// back under `skipped` with the reason. The result has the shape the eval simulates
    /// (server/assistant/eval/simulator.ts), plus `guessed` for what the phone filled in.
    private func draftTransactions(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_transactions")) }
        let args = try input.decoded(as: DraftTransactionsInput.self)
        guard !args.items.isEmpty else { throw FinanceToolError(message: "items must not be empty.") }
        var operations: [AgentDraftOperation] = []
        var items: [JSONValue] = []
        var skipped: [JSONValue] = []
        for (index, item) in args.items.enumerated() {
            switch await draftOperation(item) {
            case .success(let operation):
                operations.append(operation)
                items.append(describe(operation))
            case .failure(let error):
                skipped.append(["index": .number(Double(index)), "reason": .string(error.message)])
            }
        }
        guard !operations.isEmpty else {
            let reasons = skipped.compactMap { $0["reason"]?.stringValue }.joined(separator: "; ")
            return .failure("Nothing could be drafted: \(reasons). Ask the user for what is missing.")
        }
        let id = drafts.add(operations)
        return .success(["draft_id": .string(id), "items": .array(items), "skipped": .array(skipped), "saved": false])
    }

    private struct DraftBudgetInput: Decodable {
        let category: String
        let amount: Double
        let period: String
    }

    /// `draft_budget`: a new or changed budget of an expense category, by id or name, in the
    /// base currency (budgets are kept in it). The previous limit goes back with the draft, for
    /// the model and for Undo.
    private func draftBudget(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_budget")) }
        let args = try input.decoded(as: DraftBudgetInput.self)
        let expenses = store.categories.filter { $0.type == .expense }
        let name = args.category.lowercased()
        guard let category = expenses.first(where: { $0.id == args.category }) ?? expenses.first(where: { $0.name.lowercased() == name }) else {
            throw FinanceToolError(message: "Unknown expense category \(args.category). Use a category id from <app_context>.")
        }
        guard args.amount.isFinite, args.amount > 0 else { throw FinanceToolError(message: "amount must be positive.") }
        guard let period = CustomCategory.BudgetPeriod(rawValue: args.period) else {
            throw FinanceToolError(message: "period must be weekly, monthly or yearly.")
        }
        let budget = AgentBudgetDraft(
            categoryId: category.id,
            amount: args.amount,
            period: period,
            previousAmount: category.budgetAmount,
            previousPeriod: category.budgetPeriod
        )
        let id = drafts.add([.budget(budget)])
        return .success([
            "draft_id": .string(id),
            "category_id": .string(category.id),
            "category": .string(category.name),
            "amount": .number(FinanceToolkitCompute.round2(args.amount)),
            "currency": .string(store.baseCurrency),
            "period": .string(period.rawValue),
            "previous_limit": category.budgetAmount.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
            "previous_period": category.budgetAmount == nil ? .null : .string(category.budgetPeriod.rawValue),
            "saved": false,
        ])
    }

    private func draftOperation(_ item: DraftItemInput) async -> Result<AgentDraftOperation, FinanceToolError> {
        guard item.amount.isFinite, item.amount > 0 else { return .failure(FinanceToolError(message: "amount must be positive")) }
        let date = item.date.flatMap { FastDateParser.date(from: $0) } ?? now()
        let note = item.note ?? ""
        let currency = item.currency.map { $0.uppercased() }
        switch item.type {
        case "expense", "income":
            let operation = ParsedOperation(
                type: item.type == "income" ? .income : .expense,
                amount: Decimal(string: String(item.amount)) ?? Decimal(item.amount),
                currencyCode: currency,
                date: date,
                accountId: item.account.flatMap { resolveAccount($0, in: store.accounts) }?.id,
                categoryName: item.category.map { name in store.categories.first { $0.id == name }?.name ?? name },
                note: note
            )
            var result = makeDraft(operation, conversion: .cachedOnly)
            // The person is in the app: a missing cached rate is worth a network request.
            if case .failure(.needsFXConversion(let amount, let from, let to)) = result {
                let converted = await CurrencyConverter.convert(amount: amount, from: from, to: to)
                result = makeDraft(operation, conversion: .provided(converted))
            }
            switch result {
            case .success(let draft):
                return .success(.single(draft))
            case .failure(.missingAmount):
                return .failure(FinanceToolError(message: "amount must be positive"))
            case .failure(.noEligibleAccount):
                return .failure(FinanceToolError(message: "the user has no regular account to record it on"))
            case .failure(.needsFXConversion(_, let from, let to)):
                return .failure(FinanceToolError(message: "no exchange rate from \(from) to \(to)"))
            }
        case "transfer":
            let eligible = store.accounts.filter { !$0.isLoan && !$0.isDeposit }
            guard let from = item.account.flatMap({ resolveAccount($0, in: eligible) }),
                  let to = item.toAccount.flatMap({ resolveAccount($0, in: eligible) }),
                  from.id != to.id else {
                return .failure(FinanceToolError(message: "a transfer needs two different regular accounts in account and to_account"))
            }
            let currency = currency ?? from.currency
            func fields() -> TransactionConversion? {
                TransactionConversion.transfer(
                    amount: item.amount,
                    currency: currency,
                    sourceCurrency: from.currency,
                    targetCurrency: to.currency,
                    convert: TransactionConversion.cachedRate
                )
            }
            var conversion = fields()
            if conversion == nil {
                await TransactionConversion.loadRates([currency, from.currency, to.currency])
                conversion = fields()
            }
            guard let conversion else {
                return .failure(FinanceToolError(message: "no exchange rate for \(currency)"))
            }
            return .success(.transfer(AgentTransferDraft(
                fromAccountId: from.id,
                toAccountId: to.id,
                amount: item.amount,
                currency: currency,
                conversion: conversion,
                date: date,
                note: note
            )))
        default:
            return .failure(FinanceToolError(message: "type must be expense, income or transfer"))
        }
    }

    private func makeDraft(_ operation: ParsedOperation, conversion: ConversionPolicy) -> Result<TransactionDraft, DraftIssue> {
        TransactionDraftService.makeDraft(
            from: operation,
            accounts: store.accounts,
            categories: store.categories,
            learned: learned,
            conversion: conversion,
            suggestAccount: suggestAccount
        )
    }

    /// An account by id, else by name ignoring case: the model has the ids, a person may
    /// name the account.
    private func resolveAccount(_ reference: String, in accounts: [Account]) -> Account? {
        if let byId = accounts.first(where: { $0.id == reference }) { return byId }
        let name = reference.lowercased()
        return accounts.first { $0.name.lowercased() == name }
    }

    /// What the draft will write, for the model to describe and point the confirm block at.
    private func describe(_ operation: AgentDraftOperation) -> JSONValue {
        func accountName(_ id: String) -> String? { store.accounts.first { $0.id == id }?.name }
        switch operation {
        case .single(let draft):
            var guessed: [JSONValue] = []
            if draft.warnings.contains(.accountInferred) { guessed.append("account") }
            if draft.warnings.contains(where: { if case .categorySubstituted = $0 { true } else { false } }) { guessed.append("category") }
            let categoryId = store.categories.first { $0.name == draft.categoryName && $0.type == draft.type }?.id
            return [
                "type": .string(draft.type == .income ? "income" : "expense"),
                "amount": .number(FinanceToolkitCompute.round2(draft.amount)),
                "currency": .string(draft.currency),
                "category_id": categoryId.map(JSONValue.string) ?? .null,
                "category": draft.categoryName.isEmpty ? .null : .string(draft.categoryName),
                "account_id": .string(draft.accountId),
                "account": accountName(draft.accountId).map(JSONValue.string) ?? .null,
                "date": .string(FastDateParser.string(from: draft.date)),
                "note": draft.note.isEmpty ? .null : .string(draft.note),
                "guessed": .array(guessed),
            ]
        case .transfer(let transfer):
            return [
                "type": "transfer",
                "amount": .number(FinanceToolkitCompute.round2(transfer.amount)),
                "currency": .string(transfer.currency),
                "account_id": .string(transfer.fromAccountId),
                "account": accountName(transfer.fromAccountId).map(JSONValue.string) ?? .null,
                "to_account_id": .string(transfer.toAccountId),
                "to_account": accountName(transfer.toAccountId).map(JSONValue.string) ?? .null,
                "date": .string(FastDateParser.string(from: transfer.date)),
                "note": transfer.note.isEmpty ? .null : .string(transfer.note),
                "guessed": [],
            ]
        case .budget(let budget):
            return [
                "type": "budget",
                "category_id": .string(budget.categoryId),
                "amount": .number(FinanceToolkitCompute.round2(budget.amount)),
                "period": .string(budget.period.rawValue),
            ]
        }
    }
}
