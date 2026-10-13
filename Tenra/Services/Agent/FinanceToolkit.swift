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
//  Planning (`forecast_balance`) and drafts land in later phases and answer "not available".
//

import Foundation

final class FinanceToolkit: AgentToolExecuting {
    private let store: TransactionStore
    private weak var insights: InsightsViewModel?
    private let now: () -> Date
    private let calendar: Calendar

    init(store: TransactionStore, insights: InsightsViewModel? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.store = store
        self.insights = insights
        self.now = now
        self.calendar = calendar
    }

    static let laterPhaseTools: Set<String> = ["forecast_balance", "draft_transactions", "draft_budget", "draft_recurring"]

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
            case _ where Self.laterPhaseTools.contains(name):
                return .failure("\(name) is not available in this version of Tenra yet. Tell the user it is coming soon.")
            default:
                return .failure("Unknown tool \(name).")
            }
        } catch let error as FinanceToolError {
            return .failure(error.message)
        } catch {
            return .failure("Invalid input for \(name): \(error.localizedDescription)")
        }
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
}
