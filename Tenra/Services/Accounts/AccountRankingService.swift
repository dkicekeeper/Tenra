//
//  AccountRankingService.swift
//  Tenra
//
//  Intelligent account ranking with recency-decayed scoring.
//

import Foundation

struct AccountRankingContext {
    let type: TransactionType
    let amount: Double?
    let category: String?
    let sourceAccountId: String?

    init(type: TransactionType, amount: Double? = nil, category: String? = nil, sourceAccountId: String? = nil) {
        self.type = type
        self.amount = amount
        self.category = category
        self.sourceAccountId = sourceAccountId
    }
}

struct RankedAccount {
    let account: Account
    let score: Double
    let reason: RankingReason
}

enum RankingReason {
    case frequentlyUsedRecently
    case frequentlyUsedForCategory
    case sufficientBalance
    case recentlyUsed
    case newAccount
    case defaultFallback
    case inactive
    case deposit
}

class AccountRankingService {

    // MARK: - Cache

    /// Bounded date cache. Date strings are stable enough that we just need to prevent
    /// unbounded growth from things like CSV import touching tens of thousands of unique dates.
    private static var parsedDatesCache: [String: Date] = [:]
    private static let parsedDatesCacheLimit: Int = 5000

    static func clearDateCache() {
        parsedDatesCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Constants

    /// Exponential decay parameters. With tau=14 days: yesterday≈0.93, week≈0.61, month≈0.12, half-year≈3e-6.
    /// Replaces step-windowed (30/90/all) counting so 5 recent uses outweigh 100 old ones.
    private enum Decay {
        static let tau: Double = 14.0
    }

    private enum ScoreModifier {
        static let recentlyUsed: Double = 5.0
        static let categoryMatch: Double = 25.0
        static let sufficientBalance: Double = 5.0
        static let newAccountBonus: Double = 20.0
        static let depositPenalty: Double = -50.0
        static let neverUsedEmptyPenalty: Double = -100.0
        static let transferSourceExclude: Double = -1000.0
    }

    private enum TimeThreshold {
        static let recentActivity: Int = 7
        static let newAccountBonus: Int = 7
        /// Within this window an account is "recent for this category" — primary signal in suggestedAccount.
        static let categoryRecencyWindow: Int = 30
        /// Dormancy penalty kicks in after this many days with no activity.
        static let dormancyStart: Int = 30
        /// Penalty per day past dormancyStart. At 60d: -60, at 90d: -120, at 180d: -300.
        static let dormancyPenaltyPerDay: Double = 2.0
    }

    /// Score-equality tolerance for the `manual order` tiebreaker.
    private static let scoreEqualityEpsilon: Double = 0.01

    // MARK: - Public

    /// `transactionsByAccount` is the pre-built index from TransactionStore.
    /// Pass `nil` to fall back to building it locally (used by call-sites that don't have access).
    static func rankAccounts(
        accounts: [Account],
        transactions: [Transaction],
        transactionsByAccount: [String: [Transaction]]? = nil,
        context: AccountRankingContext? = nil,
        balances: [String: Double] = [:]
    ) -> [Account] {
        guard !accounts.isEmpty else { return [] }

        if transactions.isEmpty && (transactionsByAccount?.isEmpty ?? true) {
            return applySmartDefaults(accounts: accounts, context: context, balances: balances)
        }

        let now = Date()

        let index: [String: [Transaction]]
        if let prebuilt = transactionsByAccount {
            index = prebuilt
        } else {
            var built: [String: [Transaction]] = [:]
            built.reserveCapacity(accounts.count)
            for transaction in transactions {
                if let id = transaction.accountId { built[id, default: []].append(transaction) }
                if let id = transaction.targetAccountId { built[id, default: []].append(transaction) }
            }
            index = built
        }

        let ranked = accounts.map { account -> RankedAccount in
            let txs = index[account.id] ?? []
            let (score, reason) = calculateScore(
                for: account,
                accountTransactions: txs,
                context: context,
                now: now,
                balances: balances
            )
            return RankedAccount(account: account, score: score, reason: reason)
        }

        return ranked.sorted(by: orderingComparator).map { $0.account }
    }

    static func suggestedAccount(
        forCategory category: String,
        accounts: [Account],
        transactions: [Transaction],
        transactionsByAccount: [String: [Transaction]]? = nil,
        amount: Double? = nil,
        balances: [String: Double] = [:]
    ) -> Account? {
        let categoryTransactions = transactions.filter {
            $0.category == category && $0.type == .expense
        }

        guard !categoryTransactions.isEmpty else {
            let context = AccountRankingContext(type: .expense, amount: amount, category: category)
            return rankAccounts(
                accounts: accounts,
                transactions: transactions,
                transactionsByAccount: transactionsByAccount,
                context: context,
                balances: balances
            ).first
        }

        let now = Date()
        var lastUsed: [String: Date] = [:]
        var decayScore: [String: Double] = [:]

        for tx in categoryTransactions {
            guard let accountId = tx.accountId,
                  let date = parseDateCached(tx.date) else { continue }

            if let existing = lastUsed[accountId] {
                if date > existing { lastUsed[accountId] = date }
            } else {
                lastUsed[accountId] = date
            }

            let days = Double(daysAgo(from: date, to: now))
            decayScore[accountId, default: 0] += exp(-days / Decay.tau)
        }

        // Primary pool: accounts that used THIS category within the recency window.
        // Falls back to all-time category history only if nothing recent exists.
        let recent = lastUsed.filter { _, date in
            daysAgo(from: date, to: now) <= TimeThreshold.categoryRecencyWindow
        }
        let pool: [(accountId: String, lastUsed: Date)] = recent.isEmpty
            ? lastUsed.map { ($0.key, $0.value) }
            : recent.map { ($0.key, $0.value) }

        let sorted = pool.sorted { a, b in
            if a.lastUsed != b.lastUsed { return a.lastUsed > b.lastUsed }
            return (decayScore[a.accountId] ?? 0) > (decayScore[b.accountId] ?? 0)
        }

        // Find first candidate that passes the balance filter.
        for entry in sorted {
            guard let account = accounts.first(where: { $0.id == entry.accountId }) else { continue }
            if let amount = amount {
                let bal = balances[account.id] ?? 0
                if bal < amount { continue }
            }
            return account
        }

        // Nothing passed balance filter → return top of pool anyway, the form will surface the warning.
        if let topId = sorted.first?.accountId,
           let account = accounts.first(where: { $0.id == topId }) {
            return account
        }

        let context = AccountRankingContext(type: .expense, amount: amount, category: category)
        return rankAccounts(
            accounts: accounts,
            transactions: transactions,
            transactionsByAccount: transactionsByAccount,
            context: context,
            balances: balances
        ).first
    }

    // MARK: - Private

    private static func calculateScore(
        for account: Account,
        accountTransactions txs: [Transaction],
        context: AccountRankingContext?,
        now: Date,
        balances: [String: Double]
    ) -> (score: Double, reason: RankingReason) {
        var score: Double = 0
        var reason: RankingReason = .defaultFallback

        var lastTxDate: Date?
        for tx in txs {
            guard let date = parseDateCached(tx.date) else { continue }
            let days = Double(daysAgo(from: date, to: now))
            score += exp(-days / Decay.tau)
            if let current = lastTxDate {
                if date > current { lastTxDate = date }
            } else {
                lastTxDate = date
            }
        }
        if score > 1.5 { reason = .frequentlyUsedRecently }

        if let last = lastTxDate, daysAgo(from: last, to: now) <= TimeThreshold.recentActivity {
            score += ScoreModifier.recentlyUsed
            if reason == .defaultFallback { reason = .recentlyUsed }
        }

        if txs.count <= 3,
           daysAgo(from: account.createdDate ?? now, to: now) <= TimeThreshold.newAccountBonus {
            score += ScoreModifier.newAccountBonus
            reason = .newAccount
        }

        if account.isDeposit { score += ScoreModifier.depositPenalty }

        let accountBalance = balances[account.id] ?? 0
        if let last = lastTxDate {
            let daysSince = daysAgo(from: last, to: now)
            if daysSince > TimeThreshold.dormancyStart {
                score -= Double(daysSince - TimeThreshold.dormancyStart) * TimeThreshold.dormancyPenaltyPerDay
                reason = .inactive
            }
        } else if accountBalance == 0 && txs.isEmpty {
            score += ScoreModifier.neverUsedEmptyPenalty
            reason = .inactive
        }

        if let context = context {
            if let category = context.category {
                let catTxs = txs.filter { $0.category == category && $0.type == context.type }
                if !catTxs.isEmpty {
                    let bonus = ScoreModifier.categoryMatch * (Double(catTxs.count) / Double(max(txs.count, 1)))
                    score += bonus
                    reason = .frequentlyUsedForCategory
                }
            }

            if context.type == .expense, let amount = context.amount, accountBalance >= amount {
                score += ScoreModifier.sufficientBalance
                if reason == .defaultFallback { reason = .sufficientBalance }
            }

            if context.type == .internalTransfer,
               let sourceId = context.sourceAccountId,
               account.id == sourceId {
                score = ScoreModifier.transferSourceExclude
            }
        }

        if account.isDeposit && score < 0 { reason = .deposit }
        return (score, reason)
    }

    /// Sort: score desc; manual `order` is a tiebreaker only when scores are within epsilon.
    /// Old behavior — `order` overriding score absolutely — was the main reason long-unused
    /// pinned accounts kept being suggested.
    private static func orderingComparator(_ a: RankedAccount, _ b: RankedAccount) -> Bool {
        if abs(a.score - b.score) > scoreEqualityEpsilon {
            return a.score > b.score
        }
        switch (a.account.order, b.account.order) {
        case let (o1?, o2?): return o1 < o2
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return a.account.name < b.account.name
        }
    }

    /// New-user fallback: no history → manual order is genuinely the best signal we have.
    private static func applySmartDefaults(
        accounts: [Account],
        context: AccountRankingContext?,
        balances: [String: Double]
    ) -> [Account] {
        return accounts.sorted { a, b in
            if let o1 = a.order, let o2 = b.order { return o1 < o2 }
            if a.order != nil { return true }
            if b.order != nil { return false }

            if a.isDeposit != b.isDeposit { return !a.isDeposit }

            let bal1 = balances[a.id] ?? 0
            let bal2 = balances[b.id] ?? 0

            if let context = context, context.type == .expense, let amount = context.amount {
                let has1 = bal1 >= amount
                let has2 = bal2 >= amount
                if has1 != has2 { return has1 }
            }

            if bal1 != bal2 { return bal1 > bal2 }
            if let d1 = a.createdDate, let d2 = b.createdDate { return d1 > d2 }
            return a.name < b.name
        }
    }

    private static func daysAgo(from date: Date, to now: Date) -> Int {
        let components = Calendar.current.dateComponents([.day], from: date, to: now)
        return abs(components.day ?? 0)
    }

    private static func parseDateCached(_ dateString: String) -> Date? {
        if let cached = parsedDatesCache[dateString] { return cached }
        guard let date = DateFormatters.dateFormatter.date(from: dateString) else { return nil }
        if parsedDatesCache.count >= parsedDatesCacheLimit {
            parsedDatesCache.removeAll(keepingCapacity: true)
        }
        parsedDatesCache[dateString] = date
        return date
    }
}
