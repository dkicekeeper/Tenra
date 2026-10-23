//
//  FinanceToolkit.swift
//  Tenra
//
//  Executes the assistant's tools on the phone (docs/domains/assistant.md §3). The cloud
//  model never sees the database, only the results of the tools it asks for. Tool names and
//  input shapes are the contract in server/assistant/src/tools.ts.
//
//  Read tools: spending summary, period comparison, search, accounts, budgets, recurring
//  payments, insights. Heavy walks over the transactions run off the main actor on a snapshot.
//  An amount in another currency is converted to the base currency with the app's rates (a
//  `_base` field, and in every total); a rate the cache lacks is loaded first, and a currency
//  still without one is listed in `missing_rates`, never counted as zero. `convert_currency`
//  converts an amount the person asks about.
//  `forecast_balance` projects the everyday accounts to a date and gives the daily allowance.
//  `simulate_loan` prices a loan's refinancing or early repayment (LoanWhatIf) and
//  `project_savings` grows regular saving at an assumed return (SavingsProjection).
//  `draft_transactions`, `draft_budget` and `draft_recurring` file drafts (AgentDraftBook)
//  that the person saves on the confirm card; `draft_fact` files a fact to remember, change or
//  forget (AgentMemory) the same way. Savings goals and personal debts have their own read and
//  draft tools (FinanceToolkit+Plans.swift).
//

import Foundation

final class FinanceToolkit: AgentToolExecuting {
    // Internal (not private) where FinanceToolkit+Plans.swift reads them.
    let store: TransactionStore
    private weak var insights: InsightsViewModel?
    let drafts: AgentDraftBook?
    private let memory: AgentMemory?
    let goals: GoalStore?
    let debts: DebtStore?
    /// Debts are Tenra Pro: `draft_debt` asks before filing one.
    let isPro: () -> Bool
    private let learned: VoiceLearningStore
    private let suggestAccount: ((String) -> String?)?
    let now: () -> Date
    let calendar: Calendar
    /// Loads exchange rates into the cache (from the network on a miss); tests pass one that
    /// stays offline.
    private let loadRates: @MainActor (Set<String>) async -> Void

    /// - Parameters:
    ///   - drafts: where `draft_transactions` files its drafts; without it drafting answers
    ///     "not available".
    ///   - memory: the facts `draft_fact` checks a new one against; without it remembering
    ///     answers "not available".
    ///   - goals, debts: the savings goals and personal debts; without them their tools answer
    ///     "not available".
    ///   - isPro: whether the person has Tenra Pro (new debts need it).
    ///   - learned: the accounts the person confirmed per category in the voice flow.
    ///   - suggestAccount: the account the history suggests for a category (by name), as the
    ///     add-expense screen ranks them.
    ///   - loadRates: loads the rates of the given currencies into the cache.
    init(
        store: TransactionStore,
        insights: InsightsViewModel? = nil,
        drafts: AgentDraftBook? = nil,
        memory: AgentMemory? = nil,
        goals: GoalStore? = nil,
        debts: DebtStore? = nil,
        isPro: @escaping () -> Bool = { true },
        learned: VoiceLearningStore? = nil,
        suggestAccount: ((String) -> String?)? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        loadRates: @escaping @MainActor (Set<String>) async -> Void = { await TransactionConversion.loadRates($0) }
    ) {
        self.store = store
        self.insights = insights
        self.drafts = drafts
        self.memory = memory
        self.goals = goals
        self.debts = debts
        self.isPro = isPro
        self.learned = learned ?? .shared
        self.suggestAccount = suggestAccount
        self.now = now
        self.calendar = calendar
        self.loadRates = loadRates
    }

    /// Tools the server describes that this version cannot run yet.
    static let laterPhaseTools: Set<String> = []

    func execute(name: String, input: JSONValue) async -> AgentToolOutput {
        do {
            switch name {
            case "get_spending_summary": return .success(try await spendingSummary(input))
            case "compare_periods": return .success(try await comparePeriods(input))
            case "search_transactions": return .success(try await searchTransactions(input))
            case "get_accounts": return .success(await accounts())
            case "get_budgets": return .success(budgets())
            case "list_recurring": return .success(try await recurring(input))
            case "get_insights": return .success(insightsResult())
            case "forecast_balance": return .success(try await forecastBalance(input))
            case "simulate_loan": return .success(try simulateLoan(input))
            case "project_savings": return .success(try projectSavings(input))
            case "convert_currency": return .success(try await convertCurrency(input))
            case "draft_transactions": return try await draftTransactions(input)
            case "draft_budget": return try draftBudget(input)
            case "draft_recurring": return try draftRecurring(input)
            case "draft_fact": return try await draftFact(input)
            case "get_goals": return try await goalsResult()
            case "get_debts": return try await debtsResult()
            case "draft_goal": return try await draftGoal(input)
            case "draft_goal_contribution": return try await draftGoalContribution(input)
            case "draft_debt": return try await draftDebt(input)
            case "draft_debt_repayment": return try await draftDebtRepayment(input)
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

    static func notYet(_ name: String) -> String {
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

    // MARK: - Exchange rates

    /// Loads the rates the cache lacks for `currencies`, so a tool converts an amount in
    /// another currency instead of leaving it out. A stale rate counts as present: better than
    /// waiting on the network, as on the add-transaction screen.
    func loadMissingRates(_ currencies: some Sequence<String>) async {
        let base = store.baseCurrency
        let missing = Set(currencies).filter { $0 != base && CurrencyConverter.convertSync(amount: 1, from: $0, to: base) == nil }
        guard !missing.isEmpty else { return }
        await loadRates(missing.union([base]))
    }

    /// The same for the currencies of the snapshot's transactions, gathered off the main actor.
    private func loadMissingRates(for snapshot: FinanceSnapshot) async {
        let currencies = await Task.detached(priority: .userInitiated) {
            Set(snapshot.transactions.map(\.currency))
        }.value
        await loadMissingRates(currencies)
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
        await loadMissingRates(for: snapshot)
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
        await loadMissingRates(for: snapshot)
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
        await loadMissingRates(for: snapshot)
        let finalQuery = query
        return await Task.detached(priority: .userInitiated) {
            FinanceToolkitCompute.search(snapshot, finalQuery)
        }.value
    }

    private func accounts() async -> JSONValue {
        let base = store.baseCurrency
        await loadMissingRates(store.accounts.map(\.currency))
        let rates = RateSnapshot()
        let balances = store.balanceCoordinator.balances
        var total = 0.0
        var missingRates: Set<String> = []
        var rows: [JSONValue] = []
        for account in store.accounts {
            let balance = balances[account.id] ?? account.balance
            let inBase: Double? = account.currency == base ? balance : rates.convert(balance, from: account.currency, to: base)
            let counted = !account.isLoan && account.includeInBalance
            if counted, let inBase { total += inBase }
            if counted, inBase == nil { missingRates.insert(account.currency) }
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
        return [
            "currency": .string(base),
            "total_base": .number(FinanceToolkitCompute.round2(total)),
            "accounts": .array(rows),
            "missing_rates": .array(missingRates.sorted().map(JSONValue.string)),
        ]
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

    /// `list_recurring`: every series with its amount in its own currency, the amount and the
    /// monthly cost in the base currency (`amount_base`, `monthly_base`), and the monthly total
    /// of the active expense subscriptions in the base currency. A subscription without a rate
    /// is left out of the total and its currency listed in `missing_rates`.
    private func recurring(_ input: JSONValue) async throws -> JSONValue {
        let args = try input.decoded(as: RecurringInput.self)
        let onlySubscriptions = args.kind == "subscription"
        let activeOnly = args.activeOnly ?? true
        let base = store.baseCurrency
        await loadMissingRates(store.recurringSeries.map(\.currency))
        let rates = RateSnapshot()
        var missingRates: Set<String> = []
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
            let amountBase = series.currency == base ? amount : rates.convert(amount, from: series.currency, to: base)
            let monthlyBase = amountBase.map { $0 * Self.monthlyFactor(series.frequency) }
            if series.isSubscription, series.isActive, !isIncome {
                if let monthlyBase { monthlyTotal += monthlyBase } else { missingRates.insert(series.currency) }
            }
            rows.append([
                "id": .string(series.id),
                "name": .string(series.description.isEmpty ? series.category : series.description),
                "kind": .string(series.isSubscription ? "subscription" : "regular"),
                "type": .string(isIncome ? "income" : "expense"),
                "amount": .number(FinanceToolkitCompute.round2(amount)),
                "currency": .string(series.currency),
                "amount_base": amountBase.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
                "monthly_base": monthlyBase.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
                "frequency": .string(series.frequency.rawValue),
                "next_date": next.map { JSONValue.string(FastDateParser.string(from: $0)) } ?? .null,
                "category": .string(series.category),
                "account": series.accountId.flatMap { accountNames[$0] }.map(JSONValue.string) ?? .null,
                "active": .bool(series.isActive),
            ])
        }
        return [
            "currency": .string(base),
            "items": .array(rows),
            "subscriptions_monthly_total_base": .number(FinanceToolkitCompute.round2(monthlyTotal)),
            "missing_rates": .array(missingRates.sorted().map(JSONValue.string)),
        ]
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

    // MARK: - Currency conversion

    private struct ConvertInput: Decodable {
        let amount: Double?
        let from: String
        let to: String?
    }

    /// `convert_currency`: an amount (1 by default) in another currency, the base one by
    /// default, at the rates the app converts everything with; the rate for one unit and the
    /// day the app last updated its rates. A rate the cache lacks is loaded first.
    private func convertCurrency(_ input: JSONValue) async throws -> JSONValue {
        let args = try input.decoded(as: ConvertInput.self)
        let from = args.from.uppercased()
        let to = args.to.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? store.baseCurrency
        let amount = args.amount ?? 1
        guard amount.isFinite, amount >= 0 else { throw FinanceToolError(message: "amount must be zero or more.") }
        guard from.count == 3, to.count == 3 else { throw FinanceToolError(message: "Currencies are ISO 4217 codes, such as USD.") }
        await loadMissingRates([from, to])
        guard let rate = CurrencyConverter.convertSync(amount: 1, from: from, to: to) else {
            throw FinanceToolError(message: "The app has no exchange rate between \(from) and \(to). Tell the user so.")
        }
        var result: [String: JSONValue] = [
            "currency": .string(to),
            "converted": .number(FinanceToolkitCompute.round2(amount * rate)),
            "rate": .number((rate * 1_000_000).rounded() / 1_000_000),
            "from": ["currency": .string(from), "amount": .number(FinanceToolkitCompute.round2(amount))],
        ]
        if let updated = CurrencyRateStore.shared.lastUpdated {
            result["rates_date"] = .string(FastDateParser.string(from: updated))
        }
        return .object(result)
    }

    // MARK: - Forecast

    /// A what-if change to the forecast: money in (> 0) or out (< 0) on a day.
    struct ForecastChange: Decodable {
        let label: String
        let amount: Double
        let date: String
    }

    private struct ForecastInput: Decodable {
        let until: String
        let cushion: Double?
        let accountIds: [String]?
        let extraChanges: [ForecastChange]?

        enum CodingKeys: String, CodingKey {
            case until, cushion
            case accountIds = "account_ids"
            case extraChanges = "extra_changes"
        }
    }

    struct Outflow {
        let date: String
        let label: String
        let amount: Double
        /// What it is, for its icon in "For today" (a logo, else the category's): the series,
        /// the loan account, or the planned expense's category.
        var seriesId: String? = nil
        var loanAccountId: String? = nil
        var category: String? = nil
    }

    /// What `forecast_balance` returns, typed: "For today" (Analytics, the widget) reads it too
    /// (DailyAllowance), so both say the same number.
    struct BalanceForecast {
        let currency: String
        let today: String
        let until: String
        let days: Int
        let startBalance: Double
        let outflows: [Outflow]
        let outflowTotal: Double
        let cushion: Double
        let extraTotal: Double
        let free: Double
        let dailyAllowance: Double
        let series: [(date: String, balance: Double)]
        let missingRates: Set<String>
    }

    /// The longest projection: a year and a little.
    static let forecastMaxDays = 400

    /// `forecast_balance`: the everyday accounts (regular ones counted in the balance, or
    /// `account_ids`) from today's realized balance to `until`, less what is known to go out
    /// before then: every occurrence of an active expense subscription or recurring payment,
    /// loan payments (this month's rest while unpaid, then the monthly payment on the payment
    /// day) and planned expenses not tied to a series (a series' own future occurrence is
    /// counted once, from the series). What is left after the cushion and the what-if changes,
    /// spread over the days, is the daily allowance. Amounts are in the base currency; one
    /// without a known rate is left out and its currency listed in `missing_rates`. The result
    /// has the eval simulator's shape.
    private func forecastBalance(_ input: JSONValue) async throws -> JSONValue {
        let args = try input.decoded(as: ForecastInput.self)
        let forecast = try await forecast(
            until: args.until,
            cushion: args.cushion ?? 0,
            accountIds: args.accountIds,
            extraChanges: args.extraChanges ?? []
        )
        let round = FinanceToolkitCompute.round2
        return [
            "currency": .string(forecast.currency),
            "today": .string(forecast.today),
            "until": .string(forecast.until),
            "days": .number(Double(forecast.days)),
            "start_balance": .number(round(forecast.startBalance)),
            "obligations": .array(forecast.outflows.map { outflow -> JSONValue in
                ["date": .string(outflow.date), "label": .string(outflow.label), "amount": .number(round(outflow.amount))]
            }),
            "obligations_total": .number(round(forecast.outflowTotal)),
            "cushion": .number(round(forecast.cushion)),
            "extra_changes_total": .number(round(forecast.extraTotal)),
            "free_amount": .number(round(forecast.free)),
            "daily_allowance": .number(forecast.dailyAllowance),
            "series": .array(forecast.series.map { point -> JSONValue in
                ["date": .string(point.date), "balance": .number(round(point.balance))]
            }),
            "missing_rates": .array(forecast.missingRates.sorted().map(JSONValue.string)),
        ]
    }

    /// The forecast itself (see `forecastBalance`): `until` is `yyyy-MM-dd`, after today and
    /// within `forecastMaxDays`.
    func forecast(
        until untilKey: String,
        cushion requestedCushion: Double = 0,
        accountIds requestedAccountIds: [String]? = nil,
        extraChanges: [ForecastChange] = []
    ) async throws -> BalanceForecast {
        let calendar = FastDateParser.calendar
        let moment = now()
        let todayKey = FastDateParser.string(from: moment)
        guard let today = FastDateParser.date(from: todayKey), let until = FastDateParser.date(from: untilKey) else {
            throw FinanceToolError(message: "Dates must be YYYY-MM-DD.")
        }
        guard let days = calendar.dateComponents([.day], from: today, to: until).day, days > 0 else {
            throw FinanceToolError(message: "until must be after today.")
        }
        guard days <= Self.forecastMaxDays else { throw FinanceToolError(message: "until must be within a year.") }

        let base = store.baseCurrency
        await loadMissingRates(store.accounts.map(\.currency) + store.recurringSeries.map(\.currency))
        var rates = RateSnapshot()
        var missingRates: Set<String> = []
        func inBase(_ amount: Double, _ currency: String) -> Double? {
            if currency == base { return amount }
            guard let converted = rates.convert(amount, from: currency, to: base) else {
                missingRates.insert(currency)
                return nil
            }
            return converted
        }

        // Accounts and today's balance.
        let accountsById = Dictionary(store.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let accounts: [Account]
        if let ids = requestedAccountIds, !ids.isEmpty {
            accounts = try ids.map { id in
                guard let account = accountsById[id] else { throw FinanceToolError(message: "Unknown account \(id).") }
                return account
            }
        } else {
            accounts = store.accounts.filter(\.countsForToday)
        }
        let accountIds = Set(accounts.map(\.id))
        let balances = store.balanceCoordinator.balances
        let start = accounts.reduce(0.0) { total, account in
            total + (inBase(balances[account.id] ?? account.balance, account.currency) ?? 0)
        }

        var outflows: [Outflow] = []

        // Subscriptions and recurring payments: every occurrence after today, before `until`.
        let typeByName = Dictionary(store.categories.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        for series in store.recurringSeries where series.isActive && series.targetAccountId == nil && typeByName[series.category] != .income {
            if let account = series.accountId, !accountIds.contains(account) { continue }
            guard let first = FastDateParser.date(from: series.startDate),
                  let amount = inBase(NSDecimalNumber(decimal: series.amount).doubleValue, series.currency) else { continue }
            let label = series.description.isEmpty ? series.category : series.description
            var next: Date? = first > today
                ? first
                : RecurringDateMath.firstOccurrence(after: today, start: first, frequency: series.frequency, calendar: calendar)
            var count = 0
            while let date = next, date < until, count <= Self.forecastMaxDays {
                outflows.append(Outflow(date: FastDateParser.string(from: date), label: label, amount: amount, seriesId: series.id, category: series.category))
                next = RecurringDateMath.firstOccurrence(after: date, start: first, frequency: series.frequency, calendar: calendar)
                count += 1
            }
        }

        // Loans: this month's rest while unpaid (overdue included), then a payment a month.
        for loan in store.accounts where loan.isLoan {
            guard let info = loan.loanInfo,
                  let status = LoanMonthStatusService.status(
                    loan: loan,
                    loanTransactions: store.transactionsByAccount[loan.id] ?? [],
                    today: moment,
                    rates: rates,
                    accountsById: accountsById
                  ) else { continue }
            let monthly = NSDecimalNumber(decimal: info.monthlyPayment).doubleValue
            var due = status.nextDueDate
            var amount: Double
            if case .unpaid(_, _, let left) = status { amount = left } else { amount = monthly }
            var remaining = max(1, LoanPaymentService.remainingPayments(loanInfo: info))
            while due < until, remaining > 0 {
                if amount > 0, let converted = inBase(amount, loan.currency) {
                    outflows.append(Outflow(date: FastDateParser.string(from: max(due, today)), label: loan.name, amount: converted, loanAccountId: loan.id))
                }
                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: due),
                      let nextDue = Self.paymentDay(info.paymentDay, inMonthOf: nextMonth, calendar: calendar) else { break }
                due = nextDue
                amount = monthly
                remaining -= 1
            }
        }

        // Planned expenses not tied to a series, off the main actor.
        let snapshot = makeSnapshot()
        let planned = await Task.detached(priority: .userInitiated) {
            snapshot.transactions.compactMap { transaction -> (date: String, label: String, amount: Double, currency: String, account: String, converted: Double?, category: String)? in
                guard transaction.type == .expense, transaction.recurringSeriesId == nil,
                      transaction.date > todayKey, transaction.date < untilKey,
                      let account = transaction.accountId, accountIds.contains(account) else { return nil }
                let label = transaction.description.isEmpty ? transaction.category : transaction.description
                return (transaction.date, label, transaction.amount, transaction.currency, account, transaction.convertedAmount, transaction.category)
            }
        }.value
        // A planned expense can be in a currency no account or series has (dollars on a tenge
        // card): its rate is loaded too, else the expense was left out of the forecast.
        let plannedCurrencies = Set(planned.map(\.currency)).subtracting([base])
        if !plannedCurrencies.isEmpty {
            await loadMissingRates(plannedCurrencies)
            rates = RateSnapshot()
        }
        for item in planned {
            var amount: Double?
            if item.currency == base {
                amount = item.amount
            } else if let direct = rates.convert(item.amount, from: item.currency, to: base) {
                amount = direct
            } else if let converted = item.converted, let accountCurrency = accountsById[item.account]?.currency {
                // No rate for its own currency: what it takes from its account (`convertedAmount`
                // is in the account's currency), converted from there.
                amount = inBase(converted, accountCurrency)
            } else {
                missingRates.insert(item.currency)
            }
            if let amount { outflows.append(Outflow(date: item.date, label: item.label, amount: amount, category: item.category)) }
        }
        outflows.sort { $0.date == $1.date ? $0.label < $1.label : $0.date < $1.date }

        // What if.
        let extras = extraChanges.filter { $0.date > todayKey && $0.date < untilKey }
        let cushion = max(0, requestedCushion)
        let outflowTotal = outflows.reduce(0) { $0 + $1.amount }
        let extraTotal = extras.reduce(0) { $0 + $1.amount }
        let free = start - outflowTotal - cushion + extraTotal
        let allowance = free > 0 ? (free / Double(days) * 100).rounded(.down) / 100 : 0

        var series: [(date: String, balance: Double)] = []
        var balance = start
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            let key = FastDateParser.string(from: day)
            if offset > 0 { balance -= allowance }
            balance -= outflows.filter { $0.date == key }.reduce(0) { $0 + $1.amount }
            balance += extras.filter { $0.date == key }.reduce(0) { $0 + $1.amount }
            series.append((key, balance))
        }

        return BalanceForecast(
            currency: base,
            today: todayKey,
            until: untilKey,
            days: days,
            startBalance: start,
            outflows: outflows,
            outflowTotal: outflowTotal,
            cushion: cushion,
            extraTotal: extraTotal,
            free: free,
            dailyAllowance: allowance,
            series: series,
            missingRates: missingRates
        )
    }

    /// The loan's payment day in the month of `reference`, clamped to the month's length.
    private static func paymentDay(_ day: Int, inMonthOf reference: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: reference)
        let length = calendar.range(of: .day, in: .month, for: reference)?.count ?? 30
        components.day = min(day, length)
        return calendar.date(from: components)
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

    // MARK: - Planning

    private struct SimulateLoanInput: Decodable {
        let accountId: String?
        let principal: Double?
        let ratePercent: Double?
        let monthsLeft: Int?
        let newRatePercent: Double?
        let newMonths: Int?
        let fees: Double?
        let extraMonthly: Double?
        let oneOff: Double?
        let oneOffMode: String?

        enum CodingKeys: String, CodingKey {
            case principal, fees
            case accountId = "account_id"
            case ratePercent = "rate_percent"
            case monthsLeft = "months_left"
            case newRatePercent = "new_rate_percent"
            case newMonths = "new_months"
            case extraMonthly = "extra_monthly"
            case oneOff = "one_off"
            case oneOffMode = "one_off_mode"
        }
    }

    /// A loan from the app (by account id) or one the person describes, as it runs now, and
    /// after the scenario when one is given. Amounts are in the loan's currency.
    private func simulateLoan(_ input: JSONValue) throws -> JSONValue {
        let args = try input.decoded(as: SimulateLoanInput.self)
        for (name, value) in [("rate_percent", args.ratePercent), ("new_rate_percent", args.newRatePercent)] {
            if let value, !(0...100).contains(value) { throw FinanceToolError(message: "\(name) must be from 0 to 100.") }
        }
        for (name, value) in [("months_left", args.monthsLeft), ("new_months", args.newMonths)] {
            if let value, !(1...600).contains(value) { throw FinanceToolError(message: "\(name) must be from 1 to 600.") }
        }
        for (name, value) in [("principal", args.principal), ("fees", args.fees), ("extra_monthly", args.extraMonthly), ("one_off", args.oneOff)] {
            if let value, value < 0 { throw FinanceToolError(message: "\(name) cannot be negative.") }
        }

        let current: LoanWhatIf.Plan
        let currency: String
        var name: String?
        var accountId: String?
        do {
            if let id = args.accountId, !id.isEmpty {
                guard let account = store.accounts.first(where: { $0.id == id }) else { throw FinanceToolError(message: "Unknown account \(id).") }
                guard let loan = account.loanInfo else { throw FinanceToolError(message: "Account \(id) is not a loan.") }
                guard !loan.isPaidOff else { throw FinanceToolError(message: "\(account.name) is paid off.") }
                currency = account.currency
                name = account.name
                accountId = account.id
                current = try LoanWhatIf.plan(
                    principal: NSDecimalNumber(decimal: loan.remainingPrincipal).doubleValue,
                    ratePercent: NSDecimalNumber(decimal: loan.interestRateAnnual).doubleValue,
                    payment: NSDecimalNumber(decimal: loan.monthlyPayment).doubleValue,
                    monthsLeft: LoanPaymentService.remainingPayments(loanInfo: loan)
                )
            } else {
                guard let principal = args.principal, principal > 0, let rate = args.ratePercent, let months = args.monthsLeft else {
                    throw FinanceToolError(message: "Give account_id of a loan, or principal, rate_percent and months_left.")
                }
                currency = store.baseCurrency
                current = try LoanWhatIf.plan(principal: principal, ratePercent: rate, payment: nil, monthsLeft: months)
            }
        } catch LoanWhatIf.Failure.paymentBelowInterest {
            throw FinanceToolError(message: "The loan's payment does not cover its monthly interest.")
        }

        let scenario = LoanWhatIf.Scenario(
            newRatePercent: args.newRatePercent,
            newMonths: args.newMonths,
            fees: args.fees ?? 0,
            extraMonthly: args.extraMonthly ?? 0,
            oneOff: args.oneOff ?? 0,
            oneOffReducesPayment: args.oneOffMode == "reduce_payment"
        )
        var result: [String: JSONValue] = [
            "currency": .string(currency),
            "loan": name.map(JSONValue.string) ?? .null,
            "account_id": accountId.map(JSONValue.string) ?? .null,
            "current": .object(Self.planJSON(current)),
            "scenario": .null,
        ]
        guard !scenario.isEmpty else { return .object(result) }
        let after: LoanWhatIf.Plan
        do {
            after = try LoanWhatIf.apply(scenario, to: current)
        } catch LoanWhatIf.Failure.oneOffCoversLoan {
            throw FinanceToolError(message: "one_off covers the whole loan: nothing would be left to compare.")
        } catch {
            throw FinanceToolError(message: "In this scenario the payment does not cover the monthly interest.")
        }
        var scenarioJSON = Self.planJSON(after)
        scenarioJSON["fees"] = .number(FinanceToolkitCompute.round2(scenario.fees))
        result["scenario"] = .object(scenarioJSON)
        result["interest_saved"] = .number(FinanceToolkitCompute.round2(current.totalInterest - after.totalInterest - scenario.fees))
        result["monthly_payment_change"] = .number(FinanceToolkitCompute.round2(after.monthlyPayment - current.monthlyPayment))
        result["months_saved"] = .number(Double(current.monthsLeft - after.monthsLeft))
        result["break_even_months"] = LoanWhatIf.breakEvenMonths(fees: scenario.fees, current: current, scenario: after)
            .map { JSONValue.number(Double($0)) } ?? .null
        return .object(result)
    }

    private static func planJSON(_ plan: LoanWhatIf.Plan) -> [String: JSONValue] {
        [
            "principal": .number(FinanceToolkitCompute.round2(plan.principal)),
            "rate_percent": .number(plan.ratePercent),
            "monthly_payment": .number(FinanceToolkitCompute.round2(plan.monthlyPayment)),
            "months_left": .number(Double(plan.monthsLeft)),
            "total_interest": .number(FinanceToolkitCompute.round2(plan.totalInterest)),
            "total_paid": .number(FinanceToolkitCompute.round2(plan.principal + plan.totalInterest)),
        ]
    }

    private struct ProjectSavingsInput: Decodable {
        let monthly: Double
        let years: Int
        let annualReturnPercent: Double
        let start: Double?
        let inflationPercent: Double?
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case monthly, years, start, currency
            case annualReturnPercent = "annual_return_percent"
            case inflationPercent = "inflation_percent"
        }
    }

    /// What regular saving grows to at an assumed return; a yearly series for the chart, keyed
    /// by the month each year ends.
    private func projectSavings(_ input: JSONValue) throws -> JSONValue {
        let args = try input.decoded(as: ProjectSavingsInput.self)
        let start = args.start ?? 0
        guard (1...50).contains(args.years) else { throw FinanceToolError(message: "years must be from 1 to 50.") }
        guard (-50...50).contains(args.annualReturnPercent) else { throw FinanceToolError(message: "annual_return_percent must be from -50 to 50.") }
        if let inflation = args.inflationPercent, !(-20...100).contains(inflation) {
            throw FinanceToolError(message: "inflation_percent must be from -20 to 100.")
        }
        guard args.monthly >= 0, start >= 0, args.monthly + start > 0 else {
            throw FinanceToolError(message: "monthly and start cannot be negative, and one of them must be above zero.")
        }
        let projection = SavingsProjection.project(
            start: start,
            monthly: args.monthly,
            annualReturnPercent: args.annualReturnPercent,
            years: args.years,
            inflationPercent: args.inflationPercent
        )
        let moment = now()
        let series: [JSONValue] = projection.years.map { year in
            let end = calendar.date(byAdding: .year, value: year.year, to: moment) ?? moment
            return [
                "key": .string(String(FastDateParser.string(from: end).prefix(7))),
                "total": .number(FinanceToolkitCompute.round2(year.total)),
                "contributed": .number(FinanceToolkitCompute.round2(year.contributed)),
            ]
        }
        let currency = args.currency.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? store.baseCurrency
        return [
            "currency": .string(currency),
            "years": .number(Double(args.years)),
            "monthly": .number(args.monthly),
            "start": .number(start),
            "annual_return_percent": .number(args.annualReturnPercent),
            "inflation_percent": args.inflationPercent.map(JSONValue.number) ?? .null,
            "final_amount": .number(FinanceToolkitCompute.round2(projection.finalAmount)),
            "contributed": .number(FinanceToolkitCompute.round2(projection.contributed)),
            "growth": .number(FinanceToolkitCompute.round2(projection.growth)),
            "final_amount_real": projection.finalAmountReal.map { JSONValue.number(FinanceToolkitCompute.round2($0)) } ?? .null,
            "series": .array(series),
        ]
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

    private struct DraftRecurringInput: Decodable {
        let kind: String
        let name: String
        let amount: Double
        let currency: String?
        let frequency: String
        let nextDate: String
        let category: String?
        let account: String?

        enum CodingKeys: String, CodingKey {
            case kind, name, amount, currency, frequency, category, account
            case nextDate = "next_date"
        }
    }

    /// `draft_recurring`: a subscription or a regular payment as the series it will become,
    /// starting on its next charge, saved through `SubscriptionCreationService` like the
    /// subscription screen saves. The account is the one named, else the one the history
    /// suggests for the category, else the first everyday account (marked as guessed).
    private func draftRecurring(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_recurring")) }
        let args = try input.decoded(as: DraftRecurringInput.self)
        let name = args.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinanceToolError(message: "name is required.") }
        guard args.amount.isFinite, args.amount > 0 else { throw FinanceToolError(message: "amount must be positive.") }
        let kind: RecurringSeriesKind
        switch args.kind {
        case "subscription": kind = .subscription
        case "regular": kind = .generic
        default: throw FinanceToolError(message: "kind must be subscription or regular.")
        }
        guard let frequency = RecurringFrequency(rawValue: args.frequency) else {
            throw FinanceToolError(message: "frequency must be daily, weekly, monthly, quarterly or yearly.")
        }
        let todayKey = FastDateParser.string(from: now())
        guard let start = FastDateParser.date(from: args.nextDate), let today = FastDateParser.date(from: todayKey) else {
            throw FinanceToolError(message: "next_date must be YYYY-MM-DD.")
        }
        guard args.nextDate >= todayKey else { throw FinanceToolError(message: "next_date cannot be in the past.") }
        guard let days = FastDateParser.calendar.dateComponents([.day], from: today, to: start).day, days <= 366 else {
            throw FinanceToolError(message: "next_date must be within a year.")
        }

        // A subscription is an expense; a regular payment may be income too (a salary).
        let candidates = store.categories.filter { kind == .generic || $0.type == .expense }
        guard let reference = args.category, !reference.isEmpty else {
            throw FinanceToolError(message: "Give a category id or name from <app_context>.")
        }
        guard let category = candidates.first(where: { $0.id == reference })
            ?? candidates.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown category \(reference). Use a category id from <app_context>.")
        }

        let everyday = store.accounts.filter { !$0.isLoan && !$0.isDeposit }
        var guessed: [JSONValue] = []
        let account: Account
        if let reference = args.account, !reference.isEmpty {
            guard let named = resolveAccount(reference, in: everyday) else { throw FinanceToolError(message: "Unknown account \(reference).") }
            account = named
        } else if let suggested = suggestAccount?(category.name).flatMap({ id in everyday.first { $0.id == id } }) ?? everyday.first {
            account = suggested
            guessed.append("account")
        } else {
            throw FinanceToolError(message: "There is no everyday account to pay from.")
        }

        let currency = args.currency.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? account.currency
        let amount = Decimal(string: String(FinanceToolkitCompute.round2(args.amount))) ?? Decimal(args.amount)
        let series = RecurringSeries(
            amount: amount,
            currency: currency,
            category: category.name,
            // A subscription's name doubles as its subcategory, as on the subscription screen.
            subcategory: kind == .subscription ? name : nil,
            description: name,
            accountId: account.id,
            frequency: frequency,
            startDate: args.nextDate,
            kind: kind,
            status: kind == .subscription ? .active : nil
        )
        let id = drafts.add([.recurring(AgentRecurringDraft(series: series, accountGuessed: !guessed.isEmpty))])
        return .success([
            "draft_id": .string(id),
            "kind": .string(args.kind),
            "name": .string(name),
            "amount": .number(FinanceToolkitCompute.round2(args.amount)),
            "currency": .string(currency),
            "frequency": .string(frequency.rawValue),
            "next_date": .string(args.nextDate),
            "category_id": .string(category.id),
            "category": .string(category.name),
            "account_id": .string(account.id),
            "account": .string(account.name),
            "guessed": .array(guessed),
            "saved": false,
        ])
    }

    private struct DraftFactInput: Decodable {
        let text: String?
        let replaces: String?
    }

    /// `draft_fact`: a fact about the person's money to remember across chats, or a change to
    /// or the removal of a remembered one (`replaces`, its id from `<app_context>`; no text
    /// forgets it). Checked against the facts now: not empty, not too long, not remembered
    /// already, room for a new one.
    private func draftFact(_ input: JSONValue) async throws -> AgentToolOutput {
        guard let drafts, let memory else { return .failure(Self.notYet("draft_fact")) }
        let args = try input.decoded(as: DraftFactInput.self)
        await memory.load()
        let replaces = args.replaces.flatMap { $0.isEmpty ? nil : $0 }
        let text = args.text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let fact: AgentFactDraft
        do {
            fact = try memory.validated(text: text, replacing: replaces)
        } catch let error as AgentMemoryError {
            throw FinanceToolError(message: Self.message(for: error))
        }
        let id = drafts.add([.fact(fact)])
        let action = fact.text == nil ? "forget" : (fact.replaces == nil ? "remember" : "change")
        return .success([
            "draft_id": .string(id),
            "action": .string(action),
            "text": fact.text.map(JSONValue.string) ?? .null,
            "replaces": fact.replaces.map { JSONValue.string($0.id) } ?? .null,
            "previous_text": fact.replaces.map { JSONValue.string($0.text) } ?? .null,
            "saved": false,
        ])
    }

    private static func message(for error: AgentMemoryError) -> String {
        switch error {
        case .empty: "Give the fact's text, or replaces with the id of the fact to forget."
        case .tooLong: "Keep a fact under \(AgentMemory.maxLength) characters: one short sentence."
        case .full: "The memory is full (\(AgentMemory.limit) facts). Offer to change or forget one of the facts in <app_context>."
        case .duplicate(let id): "This is remembered already as \(id)."
        case .unknown(let id): "There is no fact \(id). Use a fact id from <app_context>."
        }
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

    /// FastPath (AgentFastPath): the parser's operations resolved as `draft_transactions`
    /// resolves them; nil when one cannot be drafted, so the message goes to the model. The
    /// parser always picks an account: one the message does not name is marked as guessed.
    func fastPathOperations(for operations: [ParsedOperation], message: String) async -> [AgentDraftOperation]? {
        let lowered = message.lowercased()
        var drafted: [AgentDraftOperation] = []
        for operation in operations {
            var result = makeDraft(operation, conversion: .cachedOnly)
            if case .failure(.needsFXConversion(let amount, let from, let to)) = result {
                let converted = await CurrencyConverter.convert(amount: amount, from: from, to: to)
                result = makeDraft(operation, conversion: .provided(converted))
            }
            guard case .success(var draft) = result else { return nil }
            let account = store.accounts.first(where: { $0.id == draft.accountId })
            if !Self.message(lowered, names: account),
               !draft.warnings.contains(.accountInferred) {
                draft.warnings.append(.accountInferred)
            }
            drafted.append(.single(draft))
        }
        return drafted
    }

    /// Whether the message names the account: a word of its name, three letters or more.
    private static func message(_ lowered: String, names account: Account?) -> Bool {
        guard let account else { return false }
        let words: [Substring] = account.name.lowercased().split { (character: Character) -> Bool in
            !character.isLetter && !character.isNumber
        }
        for word in words where word.count >= 3 && lowered.contains(word) {
            return true
        }
        return false
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
    func resolveAccount(_ reference: String, in accounts: [Account]) -> Account? {
        if let byId = accounts.first(where: { $0.id == reference }) { return byId }
        let name = reference.lowercased()
        return accounts.first { $0.name.lowercased() == name }
    }

    /// What the draft will write, for the model to describe and point the confirm block at, and
    /// what an edited draft holds now (`<draft_status>`, AssistantViewModel).
    func describe(_ operation: AgentDraftOperation) -> JSONValue {
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
        case .recurring(let recurring):
            let series = recurring.series
            return [
                "type": .string(series.kind == .subscription ? "subscription" : "regular"),
                "name": .string(series.description),
                "amount": .number(NSDecimalNumber(decimal: series.amount).doubleValue),
                "currency": .string(series.currency),
                "frequency": .string(series.frequency.rawValue),
                "next_date": .string(series.startDate),
                "category": .string(series.category),
                "account_id": series.accountId.map(JSONValue.string) ?? .null,
                "account": series.accountId.flatMap(accountName).map(JSONValue.string) ?? .null,
            ]
        case .fact(let fact):
            return [
                "type": "fact",
                "text": fact.text.map(JSONValue.string) ?? .null,
                "replaces": fact.replaces.map { JSONValue.string($0.id) } ?? .null,
            ]
        case .goal, .goalContribution, .debt, .debtRepayment:
            return describePlan(operation)
        }
    }
}
