//
//  AccountRankingService.swift
//  AIFinanceManager
//
//  Intelligent account ranking service with adaptive category-based suggestions
//

import Foundation

/// Контекст для ранжирования счетов
struct AccountRankingContext {
    let type: TransactionType
    let amount: Double?
    let category: String?
    let sourceAccountId: String? // Для переводов - исключить из списка получателей
    
    init(type: TransactionType, amount: Double? = nil, category: String? = nil, sourceAccountId: String? = nil) {
        self.type = type
        self.amount = amount
        self.category = category
        self.sourceAccountId = sourceAccountId
    }
}

/// Результат ранжирования счета
struct RankedAccount {
    let account: Account
    let score: Double
    let reason: RankingReason
}

/// Причина ранжирования (для отладки и UI подсказок)
enum RankingReason {
    case frequentlyUsedRecently        // Часто используется недавно
    case frequentlyUsedForCategory     // Часто используется для этой категории
    case sufficientBalance             // Достаточный баланс
    case recentlyUsed                  // Использовался недавно
    case newAccount                    // Новый счет (бонус)
    case defaultFallback               // По умолчанию
    case inactive                      // Неактивный
    case deposit                       // Депозит (меньший приоритет)
}

/// Сервис для интеллектуального ранжирования счетов
class AccountRankingService {

    // MARK: - Cache

    /// Cached parsed dates for performance (shared across all method calls)
    private static var parsedDatesCache: [String: Date] = [:]

    /// Clear date cache (call when date format changes or memory pressure)
    static func clearDateCache() {
        parsedDatesCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Constants
    
    /// Веса для разных периодов времени
    private enum TimeWeight {
        static let last30Days: Double = 3.0
        static let last90Days: Double = 2.0
        static let allTime: Double = 1.0
    }
    
    /// Бонусы и штрафы
    private enum ScoreModifier {
        static let recentlyUsed: Double = 10.0           // Использовался на этой неделе
        static let categoryMatch: Double = 25.0          // Часто используется для этой категории
        static let sufficientBalance: Double = 5.0       // Достаточный баланс для расхода
        static let newAccountBonus: Double = 20.0        // Новый счет (первые 7 дней)
        static let depositPenalty: Double = -50.0        // Депозит (менее удобен)
        static let inactivePenalty: Double = -100.0      // Неактивный счет
        static let transferSourceExclude: Double = -1000.0 // Исключить source account при переводе
    }
    
    /// Временные пороги (в днях)
    private enum TimeThreshold {
        static let recentActivity: Int = 7
        static let newAccountBonus: Int = 7
        static let inactivityPenalty: Int = 180
    }
    
    // MARK: - Public Methods
    
    /// Ранжировать счета с учетом контекста
    /// - Parameters:
    ///   - accounts: Список счетов для ранжирования
    ///   - transactions: История транзакций
    ///   - context: Контекст транзакции (опционально)
    ///   - balances: Словарь текущих балансов счетов [accountId: balance]
    /// - Returns: Отсортированный список счетов
    static func rankAccounts(
        accounts: [Account],
        transactions: [Transaction],
        context: AccountRankingContext? = nil,
        balances: [String: Double] = [:]
    ) -> [Account] {

        guard !accounts.isEmpty else { return [] }


        let now = Date()

        // Если нет транзакций - используем smart defaults
        if transactions.isEmpty {
            return applySmartDefaults(accounts: accounts, context: context, balances: balances)
        }

        #if DEBUG
        _ = CFAbsoluteTimeGetCurrent()
        #endif

        // ✅ PERFORMANCE: Pre-group транзакции по accountId (O(n) вместо O(n*m))
        var transactionsByAccount: [String: [Transaction]] = [:]
        for transaction in transactions {
            if let accountId = transaction.accountId {
                transactionsByAccount[accountId, default: []].append(transaction)
            }
            if let targetAccountId = transaction.targetAccountId {
                transactionsByAccount[targetAccountId, default: []].append(transaction)
            }
        }


        #if DEBUG
        _ = CFAbsoluteTimeGetCurrent()
        #endif

        // Ранжируем каждый счет
        let rankedAccounts = accounts.map { account -> RankedAccount in
            let accountTransactions = transactionsByAccount[account.id] ?? []
            let (score, reason) = calculateScore(
                for: account,
                accountTransactions: accountTransactions,
                context: context,
                now: now,
                balances: balances
            )
            return RankedAccount(account: account, score: score, reason: reason)
        }


        #if DEBUG
        _ = CFAbsoluteTimeGetCurrent()
        #endif

        // Сортируем: сначала по manual order, затем по score
        let result = rankedAccounts
            .sorted { ranked1, ranked2 in
                // 1. PRIORITY: Manual order (if both have order, sort by order)
                if let order1 = ranked1.account.order, let order2 = ranked2.account.order {
                    return order1 < order2
                }
                // If only one has order, it goes first
                if ranked1.account.order != nil {
                    return true
                }
                if ranked2.account.order != nil {
                    return false
                }
                // 2. Sort by intelligent score (for accounts without manual order)
                return ranked1.score > ranked2.score
            }
            .map { $0.account }


        return result
    }
    
    /// Получить рекомендуемый счет для категории (адаптивное автоподставление)
    /// - Parameters:
    ///   - category: Категория транзакции
    ///   - accounts: Список доступных счетов
    ///   - transactions: История транзакций
    ///   - amount: Сумма транзакции (опционально)
    ///   - balances: Словарь текущих балансов счетов
    /// - Returns: Рекомендуемый счет или nil
    static func suggestedAccount(
        forCategory category: String,
        accounts: [Account],
        transactions: [Transaction],
        amount: Double? = nil,
        balances: [String: Double] = [:]
    ) -> Account? {
        
        // Находим счет, наиболее часто используемый для этой категории
        let categoryTransactions = transactions.filter { 
            $0.category == category && $0.type == .expense 
        }
        
        guard !categoryTransactions.isEmpty else {
            // Если нет истории для категории - используем общее ранжирование
            let context = AccountRankingContext(type: .expense, amount: amount, category: category)
            return rankAccounts(accounts: accounts, transactions: transactions, context: context).first
        }
        
        // Подсчитываем частоту использования каждого счета для этой категории
        var accountFrequency: [String: Int] = [:]
        var accountLastUsed: [String: Date] = [:]
        
        for transaction in categoryTransactions {
            guard let accountId = transaction.accountId else { continue }

            accountFrequency[accountId, default: 0] += 1

            // ✅ PERFORMANCE: Use cached date parsing (50-100x faster)
            if let transactionDate = parseDateCached(transaction.date) {
                if let existing = accountLastUsed[accountId] {
                    if transactionDate > existing {
                        accountLastUsed[accountId] = transactionDate
                    }
                } else {
                    accountLastUsed[accountId] = transactionDate
                }
            }
        }
        
        // Находим счет с максимальной частотой
        let sortedAccounts = accountFrequency
            .sorted { entry1, entry2 in
                if entry1.value != entry2.value {
                    return entry1.value > entry2.value
                }
                // При равной частоте - по дате последнего использования
                let date1 = accountLastUsed[entry1.key] ?? Date.distantPast
                let date2 = accountLastUsed[entry2.key] ?? Date.distantPast
                return date1 > date2
            }
        
        // Проверяем, что рекомендуемый счет все еще существует и активен
        if let topAccountId = sortedAccounts.first?.key,
           let account = accounts.first(where: { $0.id == topAccountId }) {

            // Проверяем баланс, если указана сумма
            if let amount = amount {
                let accountBalance = balances[account.id] ?? 0
                if accountBalance < amount {
                    // Ищем следующий подходящий счет с достаточным балансом
                    for (accountId, _) in sortedAccounts {
                        if let account = accounts.first(where: { $0.id == accountId }) {
                            let balance = balances[account.id] ?? 0
                            if balance >= amount {
                                return account
                            }
                        }
                    }
                }
            }

            return account
        }

        // Fallback - общее ранжирование
        let context = AccountRankingContext(type: .expense, amount: amount, category: category)
        return rankAccounts(accounts: accounts, transactions: transactions, context: context, balances: balances).first
    }
    
    // MARK: - Private Methods
    
    /// Рассчитать score для счета
    private static func calculateScore(
        for account: Account,
        accountTransactions: [Transaction],
        context: AccountRankingContext?,
        now: Date,
        balances: [String: Double]
    ) -> (score: Double, reason: RankingReason) {

        var score: Double = 0
        var primaryReason: RankingReason = .defaultFallback
        
        // 2. Подсчет транзакций по периодам
        let last30Count = countTransactions(accountTransactions, withinDays: 30, from: now)
        let last90Count = countTransactions(accountTransactions, withinDays: 90, from: now)
        let allTimeCount = accountTransactions.count
        
        // 3. Взвешенный расчет базового score
        let baseScore = Double(last30Count) * TimeWeight.last30Days +
                       Double(last90Count) * TimeWeight.last90Days +
                       Double(allTimeCount) * TimeWeight.allTime
        
        score += baseScore
        
        if baseScore > 20 {
            primaryReason = .frequentlyUsedRecently
        }
        
        // 4. Бонус за недавнее использование (на этой неделе)
        // ✅ PERFORMANCE: Use cached date parsing
        if let lastDate = accountTransactions.map({ $0.date }).compactMap({ parseDateCached($0) }).max(),
           daysAgo(from: lastDate, to: now) <= TimeThreshold.recentActivity {
            score += ScoreModifier.recentlyUsed
            if primaryReason == .defaultFallback {
                primaryReason = .recentlyUsed
            }
        }
        
        // 5. Бонус для новых счетов (первые 7 дней)
        if allTimeCount <= 3, daysAgo(from: account.createdDate ?? now, to: now) <= TimeThreshold.newAccountBonus {
            score += ScoreModifier.newAccountBonus
            primaryReason = .newAccount
        }
        
        // 6. Штраф для депозитов
        if account.isDeposit {
            score += ScoreModifier.depositPenalty
            if score < 0 {
                primaryReason = .deposit
            }
        }
        
        // 7. Штраф для неактивных счетов
        // ✅ PERFORMANCE: Use cached date parsing
        let accountBalance = balances[account.id] ?? 0
        if let lastDate = accountTransactions.map({ $0.date }).compactMap({ parseDateCached($0) }).max() {
            if daysAgo(from: lastDate, to: now) > TimeThreshold.inactivityPenalty && accountBalance == 0 {
                score += ScoreModifier.inactivePenalty
                primaryReason = .inactive
            }
        } else if accountBalance == 0 && allTimeCount == 0 {
            // Счет никогда не использовался и баланс нулевой
            score += ScoreModifier.inactivePenalty
            primaryReason = .inactive
        }
        
        // 8. Контекстные модификаторы
        if let context = context {
            // 8a. Бонус за соответствие категории (адаптивная логика)
            if let category = context.category {
                let categoryTransactions = accountTransactions.filter {
                    $0.category == category && $0.type == context.type
                }
                
                if !categoryTransactions.isEmpty {
                    let categoryBonus = ScoreModifier.categoryMatch * (Double(categoryTransactions.count) / Double(max(allTimeCount, 1)))
                    score += categoryBonus
                    primaryReason = .frequentlyUsedForCategory
                }
            }
            
            // 8b. Бонус за достаточный баланс при расходе
            if context.type == .expense, let amount = context.amount {
                if accountBalance >= amount {
                    score += ScoreModifier.sufficientBalance
                    if primaryReason == .defaultFallback {
                        primaryReason = .sufficientBalance
                    }
                }
            }
            
            // 8c. Исключаем source account при переводе
            if context.type == .internalTransfer, let sourceId = context.sourceAccountId, account.id == sourceId {
                score = ScoreModifier.transferSourceExclude
            }
        }
        
        return (score, primaryReason)
    }
    
    /// Smart defaults для новых пользователей (без истории транзакций)
    private static func applySmartDefaults(
        accounts: [Account],
        context: AccountRankingContext?,
        balances: [String: Double]
    ) -> [Account] {

        return accounts.sorted { account1, account2 in
            // 0. PRIORITY: Manual order (if both have order, sort by order)
            if let order1 = account1.order, let order2 = account2.order {
                return order1 < order2
            }
            // If only one has order, it goes first
            if account1.order != nil {
                return true
            }
            if account2.order != nil {
                return false
            }

            // 1. Обычные счета выше депозитов (for accounts without manual order)
            if account1.isDeposit != account2.isDeposit {
                return !account1.isDeposit
            }

            let balance1 = balances[account1.id] ?? 0
            let balance2 = balances[account2.id] ?? 0

            // 2. При расходе - счета с балансом выше
            if let context = context, context.type == .expense, let amount = context.amount {
                let has1 = balance1 >= amount
                let has2 = balance2 >= amount
                if has1 != has2 {
                    return has1
                }
            }

            // 3. По балансу (больше = выше)
            if balance1 != balance2 {
                return balance1 > balance2
            }

            // 4. По дате создания (новее = выше)
            if let date1 = account1.createdDate, let date2 = account2.createdDate {
                return date1 > date2
            }

            // 5. По алфавиту
            return account1.name < account2.name
        }
    }
    
    /// Подсчет транзакций за N дней
    private static func countTransactions(
        _ transactions: [Transaction],
        withinDays days: Int,
        from now: Date
    ) -> Int {
        return transactions.filter { transaction in
            // ✅ PERFORMANCE: Use cached date parsing (50-100x faster)
            guard let date = parseDateCached(transaction.date) else {
                return false
            }
            return daysAgo(from: date, to: now) <= days
        }.count
    }
    
    /// Количество дней между датами
    private static func daysAgo(from date: Date, to now: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: date, to: now)
        return abs(components.day ?? 0)
    }

    /// Parse date with caching (50-100x faster for repeated date strings)
    private static func parseDateCached(_ dateString: String) -> Date? {
        // Check cache first
        if let cached = parsedDatesCache[dateString] {
            return cached
        }

        // Parse and cache
        if let date = DateFormatters.dateFormatter.date(from: dateString) {
            parsedDatesCache[dateString] = date
            return date
        }

        return nil
    }
}

